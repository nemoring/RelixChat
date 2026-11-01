"""Real llama.cpp integration test (llama-server + tiny OLMo2-architecture GGUF).

Skipped automatically when llama-server or the test model is not present.
Build them with: scripts/build_llamacpp.sh && python scripts/make_tiny_test_model.py
"""
import json
import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import SECRET
from kiwion_inference.app import create_app
from kiwion_inference.config import PROJECT_ROOT, InferenceConfig
from kiwion_shared.signing import sign_request

BIN = PROJECT_ROOT / "third_party/llama.cpp/build/bin/llama-server"
MODEL = Path(os.getenv("KIWION_TEST_GGUF", PROJECT_ROOT / "models/tiny-olmo2-test.gguf"))

pytestmark = pytest.mark.skipif(not (BIN.exists() and MODEL.exists()), reason="llama-server or test GGUF missing")


def test_llamacpp_engine_end_to_end(tmp_path, monkeypatch):
    monkeypatch.setenv("KIWION_LOG_DIR", str(tmp_path))
    cfg = InferenceConfig()
    cfg.engine, cfg.secret, cfg.model_path = "llamacpp", SECRET, str(MODEL)
    cfg.llama_server_bin, cfg.llama_port, cfg.threads, cfg.ctx_size = str(BIN), 18391, 2, 1024
    app = create_app(cfg)
    with TestClient(app) as c:
        import time
        for _ in range(120):
            if c.get("/health").status_code == 200:
                break
            time.sleep(0.25)
        assert c.get("/health").json()["status"] == "ok", app.state.engine.error
        body = json.dumps({"messages": [{"role": "user", "content": "hello kiwi"}], "max_tokens": 16,
                           "temperature": 0}).encode()
        h = {**sign_request(SECRET, "POST", "/v1/generate", body), "Content-Type": "application/json"}
        r = c.post("/v1/generate", content=body, headers=h)
        ev = [json.loads(l) for l in r.text.splitlines()]
        assert ev[0]["type"] == "start" and ev[-1]["type"] == "done"
        assert ev[-1]["completion_tokens"] == 16 and ev[-1]["prompt_tokens"] > 10
        assert sum(1 for e in ev if e["type"] == "token") >= 1
        st = c.get("/v1/status", headers=sign_request(SECRET, "GET", "/v1/status")).json()
        assert st["engine"] == "llamacpp" and st["total_completion_tokens"] == 16
    assert app.state.engine.proc is None  # llama-server was stopped with the service
