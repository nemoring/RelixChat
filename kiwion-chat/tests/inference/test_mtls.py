"""Backend ↔ inference over mutual TLS + HMAC, using certificates from scripts/gen_certs.sh."""
import asyncio
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = pytest.mark.skipif(not shutil.which("openssl"), reason="openssl missing")


def test_mutual_tls_and_signature(tmp_path):
    env = {**os.environ, "KIWION_CERTS_DIR": str(tmp_path)}
    subprocess.run(["bash", str(ROOT / "scripts/gen_certs.sh"), "localhost", "127.0.0.1"], env=env, check=True, capture_output=True)
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    secret = "t" * 48
    proc = subprocess.Popen([sys.executable, "-m", "kiwion_inference"], cwd=tmp_path, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, env={
        **os.environ, "KIWION_ENGINE": "mock", "KIWION_INFERENCE_SECRET": secret, "KIWION_INFERENCE_PORT": str(port),
        "KIWION_INFERENCE_SSL_CERT": "inference.crt", "KIWION_INFERENCE_SSL_KEY": "inference.key",
        "KIWION_INFERENCE_SSL_CLIENT_CA": "ca.crt",
        "PYTHONPATH": os.pathsep.join(str(ROOT / d) for d in ("shared", "inference"))})
    try:
        from kiwion_backend.config import Settings
        from kiwion_backend.inference_client import InferenceClient
        st = Settings()
        st.inference_url, st.inference_secret = f"https://localhost:{port}", secret
        st.inference_ca_cert = str(tmp_path / "ca.crt")
        st.inference_client_cert, st.inference_client_key = str(tmp_path / "backend.crt"), str(tmp_path / "backend.key")

        async def run():
            c = InferenceClient(st)
            for _ in range(50):
                info = await c.status(max_age=0)
                if info.get("state") == "ready":
                    break
                await asyncio.sleep(0.2)
            assert info["state"] == "ready"
            events = [e async for e in c.generate([{"role": "user", "content": "secure kiwi"}], 30)]
            await c.aclose()
            return events

        events = asyncio.run(run())
        assert "secure kiwi" in "".join(e.get("text", "") for e in events)
        with pytest.raises(httpx.HTTPError):  # no client certificate -> handshake refused
            httpx.get(f"https://localhost:{port}/health", verify=str(tmp_path / "ca.crt"), timeout=5)
        with pytest.raises(httpx.HTTPError):  # plain http is not served
            httpx.get(f"http://localhost:{port}/health", timeout=5)
    finally:
        proc.terminate()
        proc.wait(10)
