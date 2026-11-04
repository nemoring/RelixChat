"""Client for the Kiwion Inference service (signed HMAC requests over TLS/WireGuard)."""
from __future__ import annotations

import json
import logging
import ssl
import time
from typing import AsyncIterator

import httpx

from kiwion_shared.signing import sign_request

from .config import Settings

log = logging.getLogger("kiwion.inference_client")


class InferenceOverloaded(Exception):
    pass


class InferenceUnavailable(Exception):
    pass


class InferenceClient:
    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None):
        self.s = settings
        verify: bool | ssl.SSLContext = True
        if settings.inference_ca_cert or settings.inference_client_cert:
            ctx = ssl.create_default_context(cafile=settings.inference_ca_cert or None)
            if settings.inference_client_cert:
                ctx.load_cert_chain(settings.inference_client_cert, settings.inference_client_key or None)
            verify = ctx
        self.client = httpx.AsyncClient(
            base_url=settings.inference_url, verify=verify, transport=transport,
            timeout=httpx.Timeout(connect=5, read=300, write=30, pool=30))
        self._status_cache: tuple[float, dict] | None = None

    def _headers(self, method: str, path: str, body: bytes) -> dict:
        h = {"Content-Type": "application/json"}
        if self.s.inference_secret:
            h.update(sign_request(self.s.inference_secret, method, path, body))
        return h

    async def status(self, max_age: float = 2.0) -> dict:
        now = time.monotonic()
        if self._status_cache and now - self._status_cache[0] < max_age:
            return self._status_cache[1]
        try:
            r = await self.client.get("/v1/status", headers=self._headers("GET", "/v1/status", b""), timeout=5)
            r.raise_for_status()
            data = r.json()
            data["reachable"] = True
        except Exception as e:
            data = {"reachable": False, "state": "offline", "error": type(e).__name__,
                    "queue": {"active": 0, "waiting": 0, "max_queue": 0, "parallel": 0}}
        self._status_cache = (now, data)
        return data

    async def model_identity(self) -> dict:
        """Name / API id / licence of the model the inference node is serving (cached via status())."""
        from kiwion_shared.version import MODEL_DISPLAY_NAME, MODEL_ID
        s = await self.status()
        return {"name": s.get("model_name") or MODEL_DISPLAY_NAME, "id": s.get("model") or MODEL_ID,
                "license": s.get("model_license") or ""}

    async def generate(self, messages: list[dict], max_tokens: int, temperature: float = 0.7,
                       top_p: float = 0.9, stop: list[str] | None = None, seed: int | None = None,
                       system_prompt: str | None = None) -> AsyncIterator[dict]:
        payload = {"messages": messages, "max_tokens": max_tokens, "temperature": temperature,
                   "top_p": top_p, "stop": stop or [], "seed": seed}
        if system_prompt is not None:
            payload["system_prompt"] = system_prompt
        body = json.dumps(payload).encode()
        try:
            req = self.client.build_request("POST", "/v1/generate", content=body,
                                            headers=self._headers("POST", "/v1/generate", body))
            r = await self.client.send(req, stream=True)
        except httpx.HTTPError as e:
            raise InferenceUnavailable(f"inference unreachable: {type(e).__name__}") from e
        try:
            if r.status_code == 503:
                data = {}
                try:
                    data = json.loads(await r.aread())
                except ValueError:
                    pass
                if data.get("error") == "overloaded":
                    raise InferenceOverloaded()
                raise InferenceUnavailable(data.get("message") or "model unavailable")
            if r.status_code != 200:
                raise InferenceUnavailable(f"inference returned HTTP {r.status_code}")
            async for line in r.aiter_lines():
                if not line.strip():
                    continue
                ev = json.loads(line)
                if ev.get("type") == "error":
                    if ev.get("code") == "overloaded":
                        raise InferenceOverloaded()
                    raise InferenceUnavailable(ev.get("message", "generation failed"))
                yield ev
        except httpx.HTTPError as e:
            raise InferenceUnavailable(f"inference stream broken: {type(e).__name__}") from e
        finally:
            await r.aclose()

    async def aclose(self):
        await self.client.aclose()
