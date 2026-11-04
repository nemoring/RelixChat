"""Kiwion Inference HTTP API (internal — only the backend talks to it).

Endpoints
  GET  /health        unauthenticated liveness: {"status": "ok" | "loading" | "error"}
  GET  /v1/status     signed: engine + queue statistics
  POST /v1/generate   signed: NDJSON stream of events
                      {"type":"queued","position":N}
                      {"type":"start"}
                      {"type":"token","text":"..."}
                      {"type":"done","prompt_tokens":..,"completion_tokens":..,"finish_reason":..}
                      {"type":"error","code":"...","message":"..."}
                      503 {"error":"overloaded"} when the waiting list is full.
"""
from __future__ import annotations

import asyncio
import json
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field

from kiwion_shared.prompt import trim_history, with_default_system
from kiwion_shared.signing import NonceCache, verify_request
from kiwion_shared.version import __version__

from .config import InferenceConfig
from .engine import BaseEngine, EngineUnavailable, make_engine
from .queue import AdmissionQueue, Overloaded, QueueTimeout

log = logging.getLogger("kiwion.inference")


class Msg(BaseModel):
    role: str = Field(pattern="^(system|user|assistant)$")
    content: str = Field(max_length=32000)


class GenerateRequest(BaseModel):
    messages: list[Msg] = Field(min_length=1, max_length=200)
    max_tokens: int = Field(default=512, ge=1, le=4096)
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    top_p: float = Field(default=0.9, gt=0.0, le=1.0)
    stop: list[str] = Field(default_factory=list, max_length=4)
    seed: int | None = None
    system_prompt: str | None = None
    use_default_system: bool = True


def create_app(cfg: InferenceConfig | None = None, engine: BaseEngine | None = None) -> FastAPI:
    cfg = cfg or InferenceConfig()
    cfg.validate()
    engine = engine or make_engine(cfg)
    queue = AdmissionQueue(cfg.parallel, cfg.max_queue, cfg.queue_timeout)
    nonces = NonceCache()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await engine.start()
        yield
        await engine.stop()

    app = FastAPI(title="Kiwion Inference", version=__version__, lifespan=lifespan,
                  docs_url=None, redoc_url=None, openapi_url=None)
    app.state.engine = engine
    app.state.queue = queue
    app.state.cfg = cfg

    @app.middleware("http")
    async def auth(request: Request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        if cfg.secret:
            body = await request.body()
            ok, reason = verify_request(cfg.secret, request.headers, request.method,
                                        request.url.path, body, nonces)
            if not ok:
                log.warning("rejected unsigned/invalid request from %s: %s",
                            request.client.host if request.client else "?", reason)
                return JSONResponse({"error": "unauthorized"}, status_code=401)
        return await call_next(request)

    @app.get("/health")
    async def health():
        status = {"ready": "ok"}.get(engine.state, engine.state)
        return JSONResponse({"status": status}, status_code=200 if status == "ok" else 503)

    @app.get("/v1/status")
    async def status():
        return {"version": __version__, **engine.info(), "queue": queue.stats()}

    @app.get("/v1/models")
    async def models():
        ident = cfg.identity()
        return {"data": [{"id": ident["id"], "name": ident["name"], "context_length": cfg.ctx_size,
                          "engine": engine.name, "state": engine.state}]}

    @app.post("/v1/generate")
    async def generate(req: GenerateRequest, request: Request):
        if engine.state != "ready":
            return JSONResponse({"error": "model_unavailable", "message": engine.error or engine.state},
                                status_code=503)
        try:
            ticket = queue.reserve()
        except Overloaded:
            return JSONResponse({"error": "overloaded"}, status_code=503)

        messages = [m.model_dump() for m in req.messages]
        if req.use_default_system:
            messages = with_default_system(messages, req.system_prompt) if req.system_prompt \
                else with_default_system(messages)
        max_tokens = min(req.max_tokens, cfg.max_tokens_cap)
        messages = trim_history(messages, max(256, cfg.ctx_size - max_tokens - 16))
        try:
            prompt = await engine.render(messages)
        except EngineUnavailable as e:
            await queue.cancel(ticket)
            return JSONResponse({"error": "model_unavailable", "message": str(e)}, status_code=503)

        async def stream():
            events: asyncio.Queue = asyncio.Queue()

            async def on_pos(pos: int):
                await events.put({"type": "queued", "position": pos})

            acquire = asyncio.create_task(queue.acquire(ticket, on_pos))
            try:
                while not acquire.done():
                    get = asyncio.create_task(events.get())
                    done, _ = await asyncio.wait({acquire, get}, return_when=asyncio.FIRST_COMPLETED)
                    if get in done:
                        yield json.dumps(get.result()) + "\n"
                    else:
                        get.cancel()
                acquire.result()
            except QueueTimeout:
                yield json.dumps({"type": "error", "code": "overloaded", "message": "queue timeout"}) + "\n"
                return
            except asyncio.CancelledError:
                acquire.cancel()
                await queue.cancel(ticket)
                raise
            try:
                yield json.dumps({"type": "start"}) + "\n"
                async for ev in engine.generate(prompt, max_tokens, req.temperature, req.top_p,
                                                req.stop, req.seed):
                    yield json.dumps(ev, ensure_ascii=False) + "\n"
            except EngineUnavailable as e:
                log.error("generation failed: %s", e)
                yield json.dumps({"type": "error", "code": "model_unavailable", "message": str(e)}) + "\n"
            finally:
                await queue.release()

        return StreamingResponse(stream(), media_type="application/x-ndjson",
                                 headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})

    return app
