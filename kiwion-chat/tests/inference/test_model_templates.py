"""Any GGUF chat model: name/id from the file name, prompt from the model's own chat template."""
import json
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import SECRET
from kiwion_inference.app import create_app
from kiwion_inference.config import PROJECT_ROOT, InferenceConfig
from kiwion_shared.models import identify, is_olmo
from kiwion_shared.signing import sign_request

BIN = PROJECT_ROOT / "third_party/llama.cpp/build/bin/llama-server"
GEMMA = PROJECT_ROOT / "models/tiny-gemma-3-4b-test.gguf"


@pytest.mark.parametrize("fname,name,ident", [
    ("olmo-2-1b-instruct-Q4_K_M.gguf", "OLMo 2 1B Instruct", "olmo-2-1b-instruct"),
    ("gemma-3-4b-it-Q4_K_M.gguf", "Gemma 3 4B", "gemma-3-4b"),
    ("google_gemma-3-4b-it-qat-Q4_0.gguf", "Gemma 3 4B", "gemma-3-4b"),
    ("Qwen3-4B-Q4_K_M.gguf", "Qwen3 4B", "qwen3-4b"),
    ("my-custom-model-Q5_K_M.gguf", "my custom model", "my-custom-model"),
])
def test_identify(fname, name, ident):
    got = identify("/models/" + fname)
    assert got["name"] == name and got["id"] == ident


def test_overrides_and_template_choice():
    assert identify("x/gemma-3-4b-it-Q4_K_M.gguf", name="Kiwi Brain", model_id="kiwi")["name"] == "Kiwi Brain"
    cfg = InferenceConfig()
    cfg.model_path, cfg.prompt_format = "m/gemma-3-4b-it-Q4_K_M.gguf", "auto"
    assert not cfg.uses_olmo_template()
    cfg.model_path = "m/olmo-2-1b-instruct-Q4_K_M.gguf"
    assert cfg.uses_olmo_template() and is_olmo(cfg.model_path)
    cfg.prompt_format = "model"
    assert not cfg.uses_olmo_template()


@pytest.mark.skipif(not (BIN.exists() and GEMMA.exists()), reason="llama-server or tiny gemma-template GGUF missing")
def test_gemma_style_template_end_to_end(tmp_path, monkeypatch):
    monkeypatch.setenv("KIWION_LOG_DIR", str(tmp_path))
    cfg = InferenceConfig()
    cfg.engine, cfg.secret, cfg.model_path = "llamacpp", SECRET, str(GEMMA)
    cfg.llama_server_bin, cfg.llama_port, cfg.threads, cfg.ctx_size = str(BIN), 18392, 2, 1024
    app = create_app(cfg)
    with TestClient(app) as c:
        for _ in range(120):
            if c.get("/health").status_code == 200:
                break
            time.sleep(0.25)
        st = c.get("/v1/status", headers=sign_request(SECRET, "GET", "/v1/status")).json()
        assert st["model_name"] == "Gemma 3 4B" and st["model"] == "gemma-3-4b" and st["prompt_format"] == "model"
        prompt = c.portal.call(app.state.engine.render, [{"role": "system", "content": "Be kind"},
                                                         {"role": "user", "content": "hello"}])
        assert "<start_of_turn>user\nBe kind\n\nhello<end_of_turn>" in prompt and prompt.endswith("<start_of_turn>model\n")
        assert "<|user|>" not in prompt
        body = json.dumps({"messages": [{"role": "user", "content": "hello kiwi"}], "max_tokens": 12}).encode()
        r = c.post("/v1/generate", content=body, headers={**sign_request(SECRET, "POST", "/v1/generate", body),
                                                           "Content-Type": "application/json"})
        ev = [json.loads(l) for l in r.text.splitlines()]
        assert ev[-1]["type"] == "done" and ev[-1]["completion_tokens"] == 12
        models = c.get("/v1/models", headers=sign_request(SECRET, "GET", "/v1/models")).json()["data"]
        assert models[0]["id"] == "gemma-3-4b"
