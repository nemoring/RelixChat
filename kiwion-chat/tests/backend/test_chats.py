import httpx
import pytest
from fastapi.testclient import TestClient

from conftest import register, sse_events
from kiwion_backend.app import create_app
from kiwion_backend.inference_client import InferenceClient
from kiwion_shared.messages import OVERLOADED_RU


def test_chat_crud_and_streaming(client):
    h = register(client, "chat@kiwion.dev")
    chat = client.post("/api/chats", json={}, headers=h).json()
    r = client.post(f"/api/chats/{chat['id']}/messages", json={"content": "Привет, киви!"}, headers=h)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/event-stream")
    ev = sse_events(r.text)
    types = [e["type"] for e in ev]
    assert types[0] == "meta" and "token" in types and types[-1] == "done"
    text = "".join(e["text"] for e in ev if e["type"] == "token")
    assert "Привет, киви!" in text
    done = ev[-1]["message"]
    assert done["status"] == "complete" and done["completion_tokens"] > 0

    full = client.get(f"/api/chats/{chat['id']}", headers=h).json()
    assert full["title"] == "Привет, киви!"
    assert [m["role"] for m in full["messages"]] == ["user", "assistant"]
    assert full["messages"][1]["content"] == text

    # rename + list
    client.patch(f"/api/chats/{chat['id']}", json={"title": "Киви-чат"}, headers=h)
    assert client.get("/api/chats", headers=h).json()[0]["title"] == "Киви-чат"

    # regenerate replaces the last answer
    r = client.post(f"/api/chats/{chat['id']}/regenerate", headers=h)
    assert sse_events(r.text)[-1]["message"]["status"] == "complete"
    msgs = client.get(f"/api/chats/{chat['id']}", headers=h).json()["messages"]
    assert len(msgs) == 2

    # edit the user message -> history after it is replaced
    uid = msgs[0]["id"]
    r = client.put(f"/api/chats/{chat['id']}/messages/{uid}", json={"content": "Как дела?"}, headers=h)
    assert "Как дела?" in "".join(e.get("text", "") for e in sse_events(r.text))
    msgs = client.get(f"/api/chats/{chat['id']}", headers=h).json()["messages"]
    assert msgs[0]["content"] == "Как дела?" and msgs[0]["edited_at"] and len(msgs) == 2

    # usage is accounted
    me = client.get("/api/account/me", headers=h).json()
    assert me["quota"]["used_today"] > 0

    assert client.delete(f"/api/chats/{chat['id']}", headers=h).status_code == 200
    assert client.get(f"/api/chats/{chat['id']}", headers=h).status_code == 404


def test_users_cannot_access_each_others_chats(client):
    a = register(client, "alice@kiwion.dev")
    b = register(client, "bob@kiwion.dev")
    chat = client.post("/api/chats", json={"title": "secret"}, headers=a).json()
    assert client.get(f"/api/chats/{chat['id']}", headers=b).status_code == 404
    assert client.patch(f"/api/chats/{chat['id']}", json={"title": "x"}, headers=b).status_code == 404
    assert client.delete(f"/api/chats/{chat['id']}", headers=b).status_code == 404
    assert client.post(f"/api/chats/{chat['id']}/messages", json={"content": "hi"}, headers=b).status_code == 404
    assert client.get("/api/chats", headers=b).json() == []


class Always503(httpx.AsyncBaseTransport):
    def __init__(self, body):
        self.body = body

    async def handle_async_request(self, request):
        return httpx.Response(503, json=self.body)


@pytest.mark.parametrize("body,code", [({"error": "overloaded"}, "overloaded"),
                                       ({"error": "model_unavailable", "message": "loading"}, "model_unavailable")])
def test_overload_keeps_history_untouched(settings, body, code):
    inf = InferenceClient(settings, transport=Always503(body))
    with TestClient(create_app(settings, inference=inf)) as c:
        c.outbox = __import__("pathlib").Path(settings.outbox_dir)
        h = register(c, "busy@kiwion.dev")
        chat = c.post("/api/chats", json={}, headers=h).json()
        r = c.post(f"/api/chats/{chat['id']}/messages", json={"content": "очень важный текст"}, headers=h)
        assert r.status_code == 503
        assert r.json()["detail"]["code"] == code
        if code == "overloaded":
            assert r.json()["detail"]["message"] == OVERLOADED_RU
        # nothing was stored -> the client keeps the typed text and can resend
        assert c.get(f"/api/chats/{chat['id']}", headers=h).json()["messages"] == []


def test_quota_exceeded(client):
    h = register(client, "quota@kiwion.dev")
    client.kiwion.store.update({"free_daily_tokens": 1})
    chat = client.post("/api/chats", json={}, headers=h).json()
    client.post(f"/api/chats/{chat['id']}/messages", json={"content": "first"}, headers=h)
    r = client.post(f"/api/chats/{chat['id']}/messages", json={"content": "second"}, headers=h)
    assert r.status_code == 429 and r.json()["detail"]["code"] == "quota_exceeded"


def test_maintenance_mode(client):
    h = register(client, "mnt@kiwion.dev")
    chat = client.post("/api/chats", json={}, headers=h).json()
    client.kiwion.store.update({"maintenance_mode": True})
    r = client.post(f"/api/chats/{chat['id']}/messages", json={"content": "hi"}, headers=h)
    assert r.status_code == 503 and r.json()["detail"]["code"] == "maintenance"
    assert client.get("/api/config/public").json()["maintenance"] is True


def test_model_status_public(client):
    s = client.get("/api/model/status").json()
    assert s["state"] == "online" and s["engine"] == "mock"


def test_method_override_for_android(client):
    h = register(client, "andr@kiwion.dev")
    chat = client.post("/api/chats", json={}, headers=h).json()
    r = client.post(f"/api/chats/{chat['id']}", json={"title": "via override"},
                    headers={**h, "X-HTTP-Method-Override": "PATCH"})
    assert r.status_code == 200 and r.json()["title"] == "via override"


def test_stop_requested_before_stream_starts_is_honoured(client):
    h = register(client, "earlystop@kiwion.dev")
    chat = client.post("/api/chats", json={}, headers=h).json()
    st = client.kiwion
    orig = st.inference.generate

    def generate_then_stop(*a, **kw):
        # the user presses "stop" while the backend is still connecting to the model
        st.active_streams[("stop", chat["id"])] = True   # what POST /api/chats/{id}/stop does
        return orig(*a, **kw)

    st.inference.generate = generate_then_stop
    r = client.post(f"/api/chats/{chat['id']}/messages", json={"content": "stop me early"}, headers=h)
    st.inference.generate = orig
    assert sse_events(r.text)[-1]["message"]["status"] == "stopped"
