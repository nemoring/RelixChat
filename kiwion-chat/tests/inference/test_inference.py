import asyncio
import json

import pytest
from fastapi.testclient import TestClient

from conftest import SECRET, make_inference_app
from kiwion_inference.queue import AdmissionQueue, Overloaded
from kiwion_shared.prompt import render_olmo2, trim_history
from kiwion_shared.signing import NonceCache, sign_request, verify_request


def signed(method, path, body=b""):
    return {**sign_request(SECRET, method, path, body), "Content-Type": "application/json"}


def test_olmo2_template_matches_reference():
    msgs = [{"role": "system", "content": "S"}, {"role": "user", "content": "U1"},
            {"role": "assistant", "content": "A1"}, {"role": "user", "content": "U2"}]
    assert render_olmo2(msgs) == ("<|endoftext|><|system|>\nS\n<|user|>\nU1\n<|assistant|>\nA1<|endoftext|>\n"
                                  "<|user|>\nU2\n<|assistant|>\n")


def test_trim_history_keeps_system_and_latest():
    msgs = [{"role": "system", "content": "s"}] + [{"role": "user", "content": "x" * 400} for _ in range(10)]
    out = trim_history(msgs, 300)
    assert out[0]["role"] == "system" and len(out) < len(msgs) and out[-1] is msgs[-1]


def test_signature_replay_and_tamper():
    body = b'{"a":1}'
    h = sign_request(SECRET, "POST", "/v1/generate", body)
    cache = NonceCache()
    assert verify_request(SECRET, h, "POST", "/v1/generate", body, cache)[0]
    assert verify_request(SECRET, h, "POST", "/v1/generate", body, cache) == (False, "replayed nonce")
    h2 = sign_request(SECRET, "POST", "/v1/generate", body)
    assert not verify_request(SECRET, h2, "POST", "/v1/generate", b'{"a":2}')[0]
    assert not verify_request("y" * 48, h2, "POST", "/v1/generate", body)[0]


def test_unsigned_requests_rejected():
    with TestClient(make_inference_app()) as c:
        assert c.get("/health").json()["status"] == "ok"
        assert c.get("/v1/status").status_code == 401
        assert c.get("/v1/status", headers=signed("GET", "/v1/status")).json()["engine"] == "mock"


def test_generate_stream_events():
    with TestClient(make_inference_app()) as c:
        body = json.dumps({"messages": [{"role": "user", "content": "kiwi?"}], "max_tokens": 50}).encode()
        r = c.post("/v1/generate", content=body, headers=signed("POST", "/v1/generate", body))
        ev = [json.loads(l) for l in r.text.splitlines()]
        assert ev[0]["type"] == "start" and ev[-1]["type"] == "done"
        assert "kiwi?" in "".join(e.get("text", "") for e in ev)


def test_secret_required():
    from kiwion_inference.config import InferenceConfig
    cfg = InferenceConfig()
    cfg.secret, cfg.insecure_dev = "", False
    with pytest.raises(SystemExit):
        cfg.validate()
    cfg.secret = "short"
    with pytest.raises(SystemExit):
        cfg.validate()


async def test_queue_fifo_and_overload():
    q = AdmissionQueue(parallel=1, max_queue=2, timeout=5)
    t1 = q.reserve()
    await q.acquire(t1)
    t2, t3 = q.reserve(), q.reserve()
    with pytest.raises(Overloaded):
        q.reserve()
    positions = []

    async def waiter(t):
        async def on_pos(p):
            positions.append((t, p))
        await q.acquire(t, on_pos)
        return t

    w2 = asyncio.create_task(waiter(t2))
    w3 = asyncio.create_task(waiter(t3))
    await asyncio.sleep(0.05)
    assert (t2, 1) in positions and (t3, 2) in positions
    await q.release()
    assert await asyncio.wait_for(w2, 1) == t2
    assert not w3.done()
    await q.release()
    assert await asyncio.wait_for(w3, 1) == t3
    await q.release()
    assert q.stats()["total_rejected"] == 1 and q.active == 0


async def test_queue_cancel_frees_place():
    q = AdmissionQueue(parallel=1, max_queue=1, timeout=5)
    t1 = q.reserve()
    await q.acquire(t1)
    t2 = q.reserve()
    task = asyncio.create_task(q.acquire(t2))
    await asyncio.sleep(0.02)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert q.waiting == 0
    q.reserve()  # place is free again


def test_overloaded_http_503():
    app = make_inference_app(parallel=1, max_queue=0)
    with TestClient(app) as c:
        app.state.queue.active = 1  # simulate a running generation
        body = json.dumps({"messages": [{"role": "user", "content": "x"}]}).encode()
        r = c.post("/v1/generate", content=body, headers=signed("POST", "/v1/generate", body))
        assert r.status_code == 503 and r.json()["error"] == "overloaded"
