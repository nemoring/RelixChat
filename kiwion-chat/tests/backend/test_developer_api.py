import json

from conftest import register, sse_events


def make_key(client, h, name="test"):
    r = client.post("/api/keys", json={"name": name}, headers=h)
    assert r.status_code == 201, r.text
    return r.json()


def test_key_lifecycle_and_hash_storage(client):
    h = register(client, "dev@kiwion.dev")
    k = make_key(client, h)
    assert k["key"].startswith("kw-") and k["prefix"] == k["key"][:10]
    listed = client.get("/api/keys", headers=h).json()
    assert "key" not in listed[0]  # never shown again
    from kiwion_backend.db import ApiKey
    with client.kiwion.db.SessionLocal() as s:
        row = s.get(ApiKey, k["id"])
        assert row.key_hash != k["key"] and k["key"] not in row.key_hash and len(row.key_hash) == 64
    auth = {"Authorization": f"Bearer {k['key']}"}
    assert client.get("/v1/models", headers=auth).json()["data"][0]["id"] == "olmo-2-1b-instruct"
    client.post(f"/api/keys/{k['id']}/revoke", headers=h)
    r = client.get("/v1/models", headers=auth)
    assert r.status_code == 401 and r.json()["error"]["code"] == "invalid_api_key"


def test_chat_completions_non_stream(client):
    h = register(client, "oa@kiwion.dev")
    k = make_key(client, h)
    r = client.post("/v1/chat/completions", headers={"Authorization": f"Bearer {k['key']}"},
                    json={"model": "olmo-2-1b-instruct", "messages": [{"role": "user", "content": "Hello kiwi"}]})
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["object"] == "chat.completion" and d["choices"][0]["message"]["role"] == "assistant"
    assert "Hello kiwi" in d["choices"][0]["message"]["content"]
    assert d["usage"]["total_tokens"] == d["usage"]["prompt_tokens"] + d["usage"]["completion_tokens"] > 0
    usage = client.get("/api/keys/usage", headers=h).json()
    assert usage["totals"]["requests"] == 1 and usage["totals"]["completion_tokens"] > 0


def test_chat_completions_stream_openai_format(client):
    h = register(client, "oas@kiwion.dev")
    k = make_key(client, h)
    r = client.post("/v1/chat/completions", headers={"Authorization": f"Bearer {k['key']}"},
                    json={"model": "olmo-2-1b-instruct", "stream": True, "stream_options": {"include_usage": True},
                          "messages": [{"role": "system", "content": "be brief"}, {"role": "user", "content": "Stream me"}]})
    ev = sse_events(r.text)
    assert ev[-1] == "[DONE]"
    chunks = ev[:-1]
    assert chunks[0]["choices"][0]["delta"]["role"] == "assistant"
    assert all(c["object"] == "chat.completion.chunk" for c in chunks)
    text = "".join(c["choices"][0]["delta"].get("content", "") for c in chunks if c["choices"])
    assert "Stream me" in text
    assert any(c["choices"] and c["choices"][0]["finish_reason"] == "stop" for c in chunks)
    assert chunks[-1]["usage"]["completion_tokens"] > 0


def test_openai_sdk_style_errors(client):
    h = register(client, "oae@kiwion.dev")
    k = make_key(client, h)
    auth = {"Authorization": f"Bearer {k['key']}"}
    r = client.post("/v1/chat/completions", headers=auth, json={"model": "gpt-4", "messages": [{"role": "user", "content": "x"}]})
    assert r.status_code == 404 and r.json()["error"]["code"] == "model_not_found"
    r = client.post("/v1/chat/completions", headers=auth, json={"messages": []})
    assert r.status_code == 400 and r.json()["error"]["type"] == "invalid_request_error"
    assert client.post("/v1/chat/completions", json={"messages": [{"role": "user", "content": "x"}]}).status_code == 401


def test_per_key_rate_limit_and_quota(client):
    h = register(client, "lim@kiwion.dev")
    k = make_key(client, h)
    from kiwion_backend.db import ApiKey
    with client.kiwion.db.SessionLocal() as s:
        row = s.get(ApiKey, k["id"])
        row.rpm_limit = 2
        s.commit()
    auth = {"Authorization": f"Bearer {k['key']}"}
    body = {"messages": [{"role": "user", "content": "x"}], "max_tokens": 4}
    assert client.post("/v1/chat/completions", headers=auth, json=body).status_code == 200
    assert client.post("/v1/chat/completions", headers=auth, json=body).status_code == 200
    r = client.post("/v1/chat/completions", headers=auth, json=body)
    assert r.status_code == 429 and r.json()["error"]["code"] == "rate_limit_exceeded"
    with client.kiwion.db.SessionLocal() as s:
        row = s.get(ApiKey, k["id"])
        row.rpm_limit, row.daily_token_limit = 100, 1
        s.commit()
    r = client.post("/v1/chat/completions", headers=auth, json=body)
    assert r.status_code == 429 and r.json()["error"]["code"] == "insufficient_quota"


def test_key_isolation(client):
    a = register(client, "ka@kiwion.dev")
    b = register(client, "kb@kiwion.dev")
    k = make_key(client, a)
    assert client.post(f"/api/keys/{k['id']}/revoke", headers=b).status_code == 404
    assert client.delete(f"/api/keys/{k['id']}", headers=b).status_code == 404


def test_unverified_cannot_create_keys(client):
    h = register(client, "unv@kiwion.dev", verify=False)
    assert client.post("/api/keys", json={"name": "x"}, headers=h).status_code == 403
