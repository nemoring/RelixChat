import json
import re
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from kiwion_backend.app import create_app
from kiwion_backend.config import Settings
from kiwion_backend.inference_client import InferenceClient
from kiwion_backend.security import ProofOfWork
from kiwion_inference.app import create_app as create_inference_app
from kiwion_inference.config import InferenceConfig

SECRET = "x" * 48


def make_inference_app(**overrides):
    cfg = InferenceConfig()
    cfg.engine = "mock"
    cfg.secret = SECRET
    cfg.mock_delay = 0
    for k, v in overrides.items():
        setattr(cfg, k, v)
    app = create_inference_app(cfg)
    app.state.engine.state = "ready"
    return app


@pytest.fixture
def settings(tmp_path):
    s = Settings()
    s.env = "test"
    s.database_url = f"sqlite:///{tmp_path / 'test.db'}"
    s.secret_key = "s" * 48
    s.inference_secret = SECRET
    s.inference_url = "http://inference"
    s.mail_mode = "file"
    s.outbox_dir = str(tmp_path / "outbox")
    s.pow_difficulty = 4
    s.admin_emails = ["admin@kiwion.dev"]
    s.serve_static = True
    return s


@pytest.fixture
def inference_app():
    return make_inference_app()


@pytest.fixture
def client(settings, inference_app):
    inf = InferenceClient(settings, transport=httpx.ASGITransport(app=inference_app))
    app = create_app(settings, inference=inf)
    with TestClient(app) as c:
        c.kiwion = app.state.kiwion
        c.outbox = Path(settings.outbox_dir)
        yield c


def solve_pow(client):
    ch = client.get("/api/auth/challenge").json()
    return {"challenge": ch["challenge"], "nonce": ProofOfWork.solve(ch["challenge"], ch["difficulty"])}


def last_token(client, email, kind="verify"):
    files = sorted(client.outbox.glob(f"*_{email}.eml"))
    assert files, f"no mail for {email}"
    import email
    msg = email.message_from_bytes(files[-1].read_bytes())
    text = next(part.get_payload(decode=True).decode() for part in msg.walk()
                if part.get_content_type() == "text/plain")
    m = re.search(r"#/" + ("verify" if kind == "verify" else "reset") + r"\?token=([A-Za-z0-9_\-]+)", text)
    assert m, text
    return m.group(1)


def register(client, email, password="kiwi12345", verify=True, ref=None, device="dev-" , ip=None):
    body = {"email": email, "password": password, "display_name": email.split("@")[0],
            "device_id": device + re.sub(r"[^A-Za-z0-9]", "", email.split("@")[0]), "pow": solve_pow(client)}
    if ref:
        body["referral_code"] = ref
    headers = {"x-forwarded-for": ip} if ip else {}
    r = client.post("/api/auth/register", json=body, headers=headers)
    assert r.status_code == 201, r.text
    token = r.json()["token"]
    if verify:
        v = client.post("/api/auth/verify", json={"token": last_token(client, email)})
        assert v.status_code == 200, v.text
    return {"Authorization": f"Bearer {token}"}


def sse_events(text):
    out = []
    for block in text.split("\n\n"):
        if block.startswith("data: "):
            payload = block[6:]
            out.append(payload if payload == "[DONE]" else json.loads(payload))
    return out
