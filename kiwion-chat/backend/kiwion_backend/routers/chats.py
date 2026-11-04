"""Chats, messages and streaming generation (Server-Sent Events)."""
from __future__ import annotations

import asyncio
import json
import logging
import time

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session as DBSession

from kiwion_shared.messages import MODEL_OFFLINE_RU, OVERLOADED_RU

from ..db import Chat, Message, User, utcnow
from ..deps import AppState, api_error, get_db, log_error, rate_limit, state, verified_user
from ..inference_client import InferenceOverloaded, InferenceUnavailable
from ..usage import can_chat, chat_quota, record_chat_usage

router = APIRouter(prefix="/api/chats", tags=["chats"])
log = logging.getLogger("kiwion.chats")
HISTORY_LIMIT = 40


class ChatCreate(BaseModel):
    title: str | None = Field(default=None, max_length=120)


class ChatRename(BaseModel):
    title: str = Field(min_length=1, max_length=120)


class MessageIn(BaseModel):
    content: str = Field(min_length=1, max_length=32000)
    temperature: float | None = Field(default=None, ge=0, le=1.5)


def _iso(d):
    return d.isoformat() + "Z" if d else None


def chat_out(c: Chat, db: DBSession | None = None) -> dict:
    out = {"id": c.id, "title": c.title, "created_at": _iso(c.created_at), "updated_at": _iso(c.updated_at)}
    if db is not None:
        out["message_count"] = db.scalar(select(func.count(Message.id)).where(Message.chat_id == c.id))
    return out


def msg_out(m: Message) -> dict:
    return {"id": m.id, "role": m.role, "content": m.content, "status": m.status, "seq": m.seq,
            "prompt_tokens": m.prompt_tokens, "completion_tokens": m.completion_tokens,
            "created_at": _iso(m.created_at), "edited_at": _iso(m.edited_at)}


def _own_chat(db: DBSession, user: User, chat_id: str) -> Chat:
    chat = db.get(Chat, chat_id)
    if chat is None or chat.user_id != user.id:  # never reveal other users' chats
        raise api_error(404, "not_found", "Чат не найден")
    return chat


@router.get("")
def list_chats(user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    rows = db.scalars(select(Chat).where(Chat.user_id == user.id).order_by(Chat.updated_at.desc()).limit(500)).all()
    return [chat_out(c) for c in rows]


@router.post("", status_code=201, dependencies=[Depends(rate_limit("newchat", 60, 60))])
def create_chat(body: ChatCreate, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    chat = Chat(user_id=user.id, title=(body.title or "Новый чат").strip()[:120] or "Новый чат")
    db.add(chat)
    db.commit()
    return chat_out(chat)


@router.get("/{chat_id}")
def get_chat(chat_id: str, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    chat = _own_chat(db, user, chat_id)
    return {**chat_out(chat), "messages": [msg_out(m) for m in chat.messages]}


@router.patch("/{chat_id}")
def rename_chat(chat_id: str, body: ChatRename, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    chat = _own_chat(db, user, chat_id)
    chat.title = body.title.strip()
    chat.updated_at = utcnow()
    db.commit()
    return chat_out(chat)


@router.delete("/{chat_id}")
def delete_chat(chat_id: str, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    chat = _own_chat(db, user, chat_id)
    db.delete(chat)
    db.commit()
    return {"ok": True}


@router.delete("")
def delete_all_chats(user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    n = db.query(Chat).filter(Chat.user_id == user.id).delete()
    db.commit()
    return {"ok": True, "deleted": n}


@router.post("/{chat_id}/stop")
def stop_generation(chat_id: str, request: Request, user: User = Depends(verified_user),
                    db: DBSession = Depends(get_db)):
    _own_chat(db, user, chat_id)
    state(request).active_streams.setdefault(("stop", chat_id), True)
    return {"ok": True}


# ------------------------------------------------------------------ generation
def _history(chat: Chat, upto_seq: int | None = None) -> list[dict]:
    msgs = [m for m in chat.messages if (upto_seq is None or m.seq <= upto_seq)
            and m.status != "error" and m.content.strip()]
    return [{"role": m.role, "content": m.content} for m in msgs][-HISTORY_LIMIT:]


def _preflight(st: AppState, db: DBSession, user: User, content_len: int = 0):
    cfg = st.store.all()
    if cfg["maintenance_mode"]:
        raise api_error(503, "maintenance", cfg["maintenance_message"])
    if not cfg["chat_enabled"]:
        raise api_error(503, "chat_disabled", "Чат временно отключён администратором")
    if content_len > cfg["max_message_chars"]:
        raise api_error(400, "too_long", f"Сообщение длиннее {cfg['max_message_chars']} символов")
    if not can_chat(db, user, cfg):
        raise api_error(429, "quota_exceeded", "Дневной лимит токенов исчерпан. Он обновится завтра, "
                        "а бонусные токены можно получить за приглашения друзей 🥝",
                        quota=chat_quota(db, user, cfg))
    key = ("user", user.id)
    if st.active_streams.get(key, 0) >= st.settings.max_concurrent_streams_per_user:
        raise api_error(429, "busy", "Дождитесь окончания текущего ответа")
    return cfg


async def _open_stream(st: AppState, history: list[dict], cfg: dict, temperature: float | None, chat_id: str):
    st.active_streams.pop(("stop", chat_id), None)   # forget stale stop requests from a previous answer
    agen = st.inference.generate(history, max_tokens=cfg["max_tokens_per_reply"],
                                 temperature=0.7 if temperature is None else temperature,
                                 system_prompt=cfg["system_prompt"])
    try:
        first = await agen.__anext__()
    except InferenceOverloaded:
        await agen.aclose()
        return None, JSONResponse(status_code=503, content={"detail": {"code": "overloaded", "message": OVERLOADED_RU}})
    except (InferenceUnavailable, StopAsyncIteration) as e:
        await agen.aclose()
        log_error(st, f"inference unavailable: {e}", source="inference")
        return None, JSONResponse(status_code=503, content={"detail": {"code": "model_unavailable",
                                                                       "message": MODEL_OFFLINE_RU}})
    return (first, agen), None


def _sse(obj: dict) -> str:
    return "data: " + json.dumps(obj, ensure_ascii=False) + "\n\n"


def _stream(st: AppState, user_id: int, chat_id: str, assistant_id: str, first: dict, agen, meta: dict):
    async def gen():
        key = ("user", user_id)
        stop_key = ("stop", chat_id)   # cleared in _open_stream; a stop pressed early must not be lost
        st.active_streams[key] = st.active_streams.get(key, 0) + 1
        buf: list[str] = []
        status, prompt_t, completion_t = "streaming", 0, 0
        started = time.monotonic()
        last_save = started
        try:
            yield _sse({"type": "meta", **meta})
            ev = first
            while True:
                t = ev.get("type")
                if t == "queued":
                    yield _sse({"type": "queued", "position": ev.get("position", 0)})
                elif t == "start":
                    yield _sse({"type": "start"})
                elif t == "token":
                    buf.append(ev["text"])
                    yield _sse({"type": "token", "text": ev["text"]})
                elif t == "done":
                    prompt_t, completion_t = ev.get("prompt_tokens", 0), ev.get("completion_tokens", 0)
                    status = "complete"
                    break
                if st.active_streams.pop(stop_key, None):
                    status = "stopped"
                    break
                if time.monotonic() - last_save > 3:  # periodic checkpoint for crash safety
                    last_save = time.monotonic()
                    _save(st, assistant_id, "".join(buf), "streaming", 0, 0)
                try:
                    ev = await agen.__anext__()
                except StopAsyncIteration:
                    status = "complete" if status == "streaming" else status
                    break
        except InferenceOverloaded:
            status = "error"
            yield _sse({"type": "error", "code": "overloaded", "message": OVERLOADED_RU})
        except InferenceUnavailable as e:
            status = "error"
            log_error(st, f"generation failed: {e}", source="inference")
            yield _sse({"type": "error", "code": "model_unavailable", "message": MODEL_OFFLINE_RU})
        except asyncio.CancelledError:
            status = "stopped"
            raise
        finally:
            await agen.aclose()
            if status == "streaming":
                status = "stopped"
            if status == "error" and buf:
                status = "stopped"
            if completion_t == 0 and buf:
                completion_t = max(1, len("".join(buf)) // 4)
            msg = _save(st, assistant_id, "".join(buf), status, prompt_t, completion_t,
                        user_id=user_id, latency_ms=int((time.monotonic() - started) * 1000))
            st.active_streams[key] = max(0, st.active_streams.get(key, 1) - 1)
        yield _sse({"type": "done", "message": msg})
    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


def _save(st: AppState, message_id: str, content: str, status: str, prompt_t: int, completion_t: int,
          user_id: int | None = None, latency_ms: int = 0) -> dict | None:
    with st.db.SessionLocal() as s:
        m = s.get(Message, message_id)
        if m is None:  # chat deleted while streaming
            return None
        m.content = content
        m.status = status if (content or status != "complete") else "error"
        m.prompt_tokens, m.completion_tokens = prompt_t, completion_t
        chat = s.get(Chat, m.chat_id)
        chat.updated_at = utcnow()
        if user_id is not None and (prompt_t or completion_t):
            user = s.get(User, user_id)
            record_chat_usage(s, user, prompt_t, completion_t, latency_ms,
                              "ok" if status == "complete" else status, st.store.all())
        s.commit()
        return msg_out(m)


def _next_seq(db: DBSession, chat_id: str) -> int:
    return (db.scalar(select(func.max(Message.seq)).where(Message.chat_id == chat_id)) or 0) + 1


@router.post("/{chat_id}/messages", dependencies=[Depends(rate_limit("send", 30, 60, by="user"))])
async def send_message(chat_id: str, body: MessageIn, request: Request,
                       user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    st = state(request)
    chat = _own_chat(db, user, chat_id)
    cfg = _preflight(st, db, user, len(body.content))
    content = body.content.strip()
    history = _history(chat) + [{"role": "user", "content": content}]
    opened, err = await _open_stream(st, history, cfg, body.temperature, chat.id)
    if err:
        return err  # nothing was written: the client keeps the user's text
    seq = _next_seq(db, chat.id)
    um = Message(chat_id=chat.id, seq=seq, role="user", content=content)
    am = Message(chat_id=chat.id, seq=seq + 1, role="assistant", content="", status="streaming")
    db.add_all([um, am])
    if chat.title == "Новый чат" and seq == 1:
        chat.title = (content.splitlines()[0][:60] or "Новый чат").strip()
    chat.updated_at = utcnow()
    db.commit()
    return _stream(st, user.id, chat.id, am.id, *opened,
                   meta={"user_message": msg_out(um), "assistant_message_id": am.id, "chat": chat_out(chat)})


@router.post("/{chat_id}/regenerate", dependencies=[Depends(rate_limit("send", 30, 60, by="user"))])
async def regenerate(chat_id: str, request: Request, user: User = Depends(verified_user),
                     db: DBSession = Depends(get_db)):
    st = state(request)
    chat = _own_chat(db, user, chat_id)
    cfg = _preflight(st, db, user)
    msgs = list(chat.messages)
    last_user = next((m for m in reversed(msgs) if m.role == "user"), None)
    if last_user is None:
        raise api_error(400, "nothing_to_regenerate", "Нет сообщения для повторной генерации")
    history = _history(chat, upto_seq=last_user.seq)
    opened, err = await _open_stream(st, history, cfg, None, chat.id)
    if err:
        return err
    for m in msgs:
        if m.seq > last_user.seq:
            db.delete(m)
    am = Message(chat_id=chat.id, seq=last_user.seq + 1, role="assistant", content="", status="streaming")
    db.add(am)
    chat.updated_at = utcnow()
    db.commit()
    return _stream(st, user.id, chat.id, am.id, *opened,
                   meta={"user_message": msg_out(last_user), "assistant_message_id": am.id,
                         "chat": chat_out(chat), "replaced_after_seq": last_user.seq})


@router.put("/{chat_id}/messages/{message_id}", dependencies=[Depends(rate_limit("send", 30, 60, by="user"))])
async def edit_message(chat_id: str, message_id: str, body: MessageIn, request: Request,
                       user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    st = state(request)
    chat = _own_chat(db, user, chat_id)
    target = db.get(Message, message_id)
    if target is None or target.chat_id != chat.id or target.role != "user":
        raise api_error(404, "not_found", "Сообщение не найдено")
    cfg = _preflight(st, db, user, len(body.content))
    content = body.content.strip()
    history = _history(chat, upto_seq=target.seq - 1) + [{"role": "user", "content": content}]
    opened, err = await _open_stream(st, history, cfg, body.temperature, chat.id)
    if err:
        return err
    for m in list(chat.messages):
        if m.seq > target.seq:
            db.delete(m)
    target.content = content
    target.edited_at = utcnow()
    am = Message(chat_id=chat.id, seq=target.seq + 1, role="assistant", content="", status="streaming")
    db.add(am)
    chat.updated_at = utcnow()
    db.commit()
    return _stream(st, user.id, chat.id, am.id, *opened,
                   meta={"user_message": msg_out(target), "assistant_message_id": am.id,
                         "chat": chat_out(chat), "replaced_after_seq": target.seq - 1})
