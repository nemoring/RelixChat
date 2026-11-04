"""Admin-editable system prompt (incl. the language rules) reaches the model."""
import json

import httpx
from fastapi.testclient import TestClient

from conftest import make_inference_app, register, sse_events
from kiwion_backend.app import create_app
from kiwion_backend.inference_client import InferenceClient
from kiwion_shared.prompt import DEFAULT_SYSTEM_PROMPT


class Recording(httpx.AsyncBaseTransport):
    """Passes requests to the inference app and remembers /v1/generate bodies."""
    def __init__(self, app):
        self.inner = httpx.ASGITransport(app=app)
        self.bodies = []

    async def handle_async_request(self, request):
        if request.url.path == "/v1/generate":
            self.bodies.append(json.loads(await request.aread()))
        return await self.inner.handle_async_request(request)


def make_client(settings):
    rec = Recording(make_inference_app())
    c = TestClient(create_app(settings, inference=InferenceClient(settings, transport=rec)))
    c.__enter__()
    from pathlib import Path
    c.outbox = Path(settings.outbox_dir)
    c.kiwion = c.app.state.kiwion
    return c, rec


def test_default_prompt_has_language_rules():
    assert "LANGUAGE RULES" in DEFAULT_SYSTEM_PROMPT
    assert "If the user writes in Russian, respond entirely in Russian." in DEFAULT_SYSTEM_PROMPT
    assert "Do not add English follow-up questions to Russian answers." in DEFAULT_SYSTEM_PROMPT


def test_chat_uses_configured_prompt_and_admin_can_change_it(settings):
    c, rec = make_client(settings)
    admin = register(c, "admin@kiwion.dev")
    assert c.get("/api/admin/settings", headers=admin).json()["system_prompt"] == DEFAULT_SYSTEM_PROMPT
    chat = c.post("/api/chats", json={}, headers=admin).json()
    sse_events(c.post(f"/api/chats/{chat['id']}/messages", json={"content": "Привет"}, headers=admin).text)
    assert rec.bodies[-1]["system_prompt"] == DEFAULT_SYSTEM_PROMPT

    custom = "Ты — киви. Отвечай только по-русски.\n" + "x" * 1500   # longer than ordinary settings
    assert c.put("/api/admin/settings", json={"system_prompt": custom}, headers=admin).status_code == 200
    sse_events(c.post(f"/api/chats/{chat['id']}/messages", json={"content": "Ещё"}, headers=admin).text)
    assert rec.bodies[-1]["system_prompt"] == custom

    # empty = back to the default; too long is rejected
    assert c.put("/api/admin/settings", json={"system_prompt": "  "}, headers=admin).json()["system_prompt"] == DEFAULT_SYSTEM_PROMPT
    assert c.put("/api/admin/settings", json={"system_prompt": "y" * 9000}, headers=admin).status_code == 400
    c.__exit__(None, None, None)


def test_developer_api_system_message_wins(settings):
    c, rec = make_client(settings)
    h = register(c, "dev@kiwion.dev")
    key = c.post("/api/keys", json={"name": "k"}, headers=h).json()["key"]
    auth = {"Authorization": f"Bearer {key}"}
    c.post("/v1/chat/completions", headers=auth, json={"messages": [{"role": "user", "content": "hi"}]})
    assert rec.bodies[-1]["system_prompt"] == DEFAULT_SYSTEM_PROMPT
    c.post("/v1/chat/completions", headers=auth, json={"messages": [{"role": "system", "content": "Be a pirate"},
                                                                    {"role": "user", "content": "hi"}]})
    assert rec.bodies[-1].get("system_prompt") is None
    assert rec.bodies[-1]["messages"][0] == {"role": "system", "content": "Be a pirate"}
    c.__exit__(None, None, None)
