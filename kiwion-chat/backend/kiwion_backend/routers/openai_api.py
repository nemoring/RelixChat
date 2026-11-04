"""OpenAI-compatible Developer API: /v1/models and /v1/chat/completions (incl. streaming)."""
from __future__ import annotations

import json
import time
import uuid

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session as DBSession

from kiwion_shared.messages import OVERLOADED_EN
from kiwion_shared.version import MODEL_ID

from ..db import ApiKey, UsageEvent, utcnow
from ..deps import get_db, log_error, state, api_key_auth
from ..inference_client import InferenceOverloaded, InferenceUnavailable
from ..usage import api_key_limits, tokens_used_today

router = APIRouter(prefix="/v1", tags=["openai-compatible"])
# "kiwion" always means "the model this server runs"; the served model's own id is accepted too
GENERIC_ALIASES = {"kiwion", "kiwion-chat", "default"}
OLMO_ALIASES = {MODEL_ID, "olmo-2-0425-1b-instruct", "olmo2-1b-instruct"}


def accepted_models(model_id: str) -> set[str]:
    out = GENERIC_ALIASES | {model_id}
    if model_id.startswith("olmo"):
        out |= OLMO_ALIASES
    return out


def oai_error(status: int, message: str, type_: str, code: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"message": message, "type": type_, "code": code}})


class ChatMessage(BaseModel):
    role: str = Field(pattern="^(system|user|assistant|developer)$")
    content: str | list = Field(default="")
    name: str | None = None


class StreamOptions(BaseModel):
    include_usage: bool = False


class ChatCompletionRequest(BaseModel):
    model: str = "kiwion"
    messages: list[ChatMessage] = Field(min_length=1, max_length=200)
    max_tokens: int | None = Field(default=None, ge=1, le=4096)
    max_completion_tokens: int | None = Field(default=None, ge=1, le=4096)
    temperature: float = Field(default=0.7, ge=0, le=2)
    top_p: float = Field(default=0.9, gt=0, le=1)
    stream: bool = False
    stream_options: StreamOptions | None = None
    stop: str | list[str] | None = None
    seed: int | None = None
    n: int = Field(default=1, ge=1, le=1)
    user: str | None = Field(default=None, max_length=128)


def _text(content) -> str:
    if isinstance(content, str):
        return content
    parts = []
    for p in content or []:
        if isinstance(p, dict) and p.get("type") == "text":
            parts.append(str(p.get("text", "")))
    return "\n".join(parts)


@router.get("/models")
async def models(request: Request, key: ApiKey = Depends(api_key_auth)):
    m = await state(request).inference.model_identity()
    return {"object": "list", "data": [{"id": m["id"], "object": "model", "created": 1714521600,
                                        "owned_by": "kiwion", "name": m["name"]}]}


@router.post("/chat/completions")
async def chat_completions(body: ChatCompletionRequest, request: Request,
                           key: ApiKey = Depends(api_key_auth), db: DBSession = Depends(get_db)):
    st = state(request)
    cfg = st.store.all()
    if cfg["maintenance_mode"] or not cfg["api_enabled"]:
        return oai_error(503, "Kiwion API is temporarily unavailable", "server_error", "service_unavailable")
    served = (await st.inference.model_identity())["id"]
    if body.model not in accepted_models(served):
        return oai_error(404, f"The model '{body.model}' does not exist. Use '{served}' or 'kiwion'.",
                         "invalid_request_error", "model_not_found")
    rpm, daily = api_key_limits(key, cfg)
    ok, retry = st.limiter.hit(f"apikey:{key.id}", rpm, 60)
    if not ok:
        r = oai_error(429, f"Rate limit reached: {rpm} requests per minute", "rate_limit_error", "rate_limit_exceeded")
        r.headers["Retry-After"] = str(int(retry) + 1)
        return r
    if tokens_used_today(db, api_key_id=key.id) >= daily:
        return oai_error(429, f"Daily token quota exceeded ({daily} tokens)", "insufficient_quota", "insufficient_quota")

    messages = []
    for m in body.messages:
        role = "system" if m.role == "developer" else m.role
        messages.append({"role": role, "content": _text(m.content)[:32000]})
    has_system = any(m["role"] == "system" for m in messages)
    stop = [body.stop] if isinstance(body.stop, str) else (body.stop or [])
    max_tokens = min(body.max_completion_tokens or body.max_tokens or 512, 1024)
    key_id, user_id = key.id, key.user_id
    key.last_used_at = utcnow()
    db.commit()

    agen = st.inference.generate(messages, max_tokens=max_tokens, temperature=body.temperature, top_p=body.top_p,
                                 stop=stop[:4], seed=body.seed, system_prompt=None if has_system else cfg["system_prompt"])
    started = time.monotonic()
    try:
        first = await agen.__anext__()
    except InferenceOverloaded:
        await agen.aclose()
        _record(st, user_id, key_id, 0, 0, 0, "overloaded")
        return oai_error(503, OVERLOADED_EN, "server_error", "overloaded")
    except (InferenceUnavailable, StopAsyncIteration) as e:
        await agen.aclose()
        log_error(st, f"api inference unavailable: {e}", source="inference")
        _record(st, user_id, key_id, 0, 0, 0, "error")
        return oai_error(503, "The model is currently unavailable", "server_error", "model_unavailable")

    cid = "chatcmpl-" + uuid.uuid4().hex[:24]
    created = int(time.time())

    async def events():
        ev = first
        while True:
            yield ev
            try:
                ev = await agen.__anext__()
            except StopAsyncIteration:
                return

    if not body.stream:
        text, usage, finish = [], {"prompt_tokens": 0, "completion_tokens": 0}, "stop"
        status = "ok"
        try:
            async for ev in events():
                if ev["type"] == "token":
                    text.append(ev["text"])
                elif ev["type"] == "done":
                    usage = {"prompt_tokens": ev["prompt_tokens"], "completion_tokens": ev["completion_tokens"]}
                    finish = ev.get("finish_reason", "stop")
        except (InferenceOverloaded, InferenceUnavailable) as e:
            status = "error"
            log_error(st, f"api generation failed: {e}", source="inference")
            return oai_error(503, "Generation failed", "server_error", "model_unavailable")
        finally:
            await agen.aclose()
            _record(st, user_id, key_id, usage["prompt_tokens"], usage["completion_tokens"],
                    int((time.monotonic() - started) * 1000), status)
        return {
            "id": cid, "object": "chat.completion", "created": created, "model": served,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": "".join(text)},
                         "finish_reason": finish, "logprobs": None}],
            "usage": {**usage, "total_tokens": usage["prompt_tokens"] + usage["completion_tokens"]},
            "system_fingerprint": "kiwion-llamacpp",
        }

    include_usage = bool(body.stream_options and body.stream_options.include_usage)

    def chunk(delta: dict, finish=None, usage=None) -> str:
        obj = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": served,
               "system_fingerprint": "kiwion-llamacpp",
               "choices": [{"index": 0, "delta": delta, "finish_reason": finish, "logprobs": None}]}
        if usage is not None:
            obj["choices"] = []
            obj["usage"] = usage
        return "data: " + json.dumps(obj, ensure_ascii=False) + "\n\n"

    async def sse():
        usage = {"prompt_tokens": 0, "completion_tokens": 0}
        status, n_chars = "ok", 0
        try:
            yield chunk({"role": "assistant", "content": ""})
            async for ev in events():
                if ev["type"] == "token":
                    n_chars += len(ev["text"])
                    yield chunk({"content": ev["text"]})
                elif ev["type"] == "done":
                    usage = {"prompt_tokens": ev["prompt_tokens"], "completion_tokens": ev["completion_tokens"]}
                    yield chunk({}, finish=ev.get("finish_reason", "stop"))
            if include_usage:
                yield chunk({}, usage={**usage, "total_tokens": usage["prompt_tokens"] + usage["completion_tokens"]})
            yield "data: [DONE]\n\n"
        except (InferenceOverloaded, InferenceUnavailable) as e:
            status = "error"
            log_error(st, f"api stream failed: {e}", source="inference")
            yield "data: " + json.dumps({"error": {"message": "Generation failed", "type": "server_error",
                                                   "code": "model_unavailable"}}) + "\n\n"
        finally:
            await agen.aclose()
            if not usage["completion_tokens"] and n_chars:
                usage["completion_tokens"] = max(1, n_chars // 4)
            _record(st, user_id, key_id, usage["prompt_tokens"], usage["completion_tokens"],
                    int((time.monotonic() - started) * 1000), status)

    return StreamingResponse(sse(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


def _record(st, user_id, key_id, p, c, latency, status):
    with st.db.SessionLocal() as s:
        s.add(UsageEvent(user_id=user_id, api_key_id=key_id, source="api", status=status,
                         prompt_tokens=p, completion_tokens=c, latency_ms=latency))
        s.commit()
