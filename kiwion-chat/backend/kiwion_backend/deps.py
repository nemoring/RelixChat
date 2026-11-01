"""Shared FastAPI dependencies and application state."""
from __future__ import annotations

import datetime as dt
import logging
from dataclasses import dataclass, field

from fastapi import Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session as DBSession

from kiwion_shared.redact import redact

from .config import Settings
from .db import ApiKey, Database, ErrorLog, Session, User, utcnow
from .inference_client import InferenceClient
from .mailer import Mailer
from .security import ProofOfWork, RateLimiter, client_ip, token_hash
from .settings_store import SettingsStore

log = logging.getLogger("kiwion.backend")


@dataclass
class AppState:
    settings: Settings
    db: Database
    store: SettingsStore
    limiter: RateLimiter
    pow: ProofOfWork
    mailer: Mailer
    inference: InferenceClient
    active_streams: dict = field(default_factory=dict)  # user_id -> count


def state(request: Request) -> AppState:
    return request.app.state.kiwion


def get_db(request: Request):
    st: AppState = request.app.state.kiwion
    s = st.db.SessionLocal()
    try:
        yield s
    finally:
        s.close()


def api_error(status: int, code: str, message: str, **extra) -> HTTPException:
    return HTTPException(status_code=status, detail={"code": code, "message": message, **extra})


def ip_of(request: Request) -> str:
    return client_ip(request, state(request).settings.trusted_proxies)


def rate_limit(name: str, limit: int, window: float, by: str = "ip"):
    def dep(request: Request):
        st = state(request)
        key = f"{name}:{ip_of(request)}"
        if by == "user" and getattr(request.state, "user_id", None):
            key = f"{name}:u{request.state.user_id}"
        ok, retry = st.limiter.hit(key, limit, window)
        if not ok:
            raise api_error(429, "rate_limited", "Слишком много запросов. Попробуйте чуть позже.",
                            retry_after=int(retry) + 1)
    return dep


def _bearer(request: Request) -> str | None:
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return None


def current_session(request: Request, db: DBSession = Depends(get_db)) -> Session:
    st = state(request)
    token = _bearer(request)
    if not token or not token.startswith("kws_"):
        raise api_error(401, "unauthorized", "Требуется вход в аккаунт")
    sess = db.scalar(select(Session).where(Session.token_hash == token_hash(token, st.settings.secret_key)))
    if sess is None or sess.expires_at < utcnow():
        raise api_error(401, "unauthorized", "Сессия истекла. Войдите снова.")
    user = db.get(User, sess.user_id)
    if user is None:
        raise api_error(401, "unauthorized", "Аккаунт не найден")
    if user.is_banned:
        raise api_error(403, "banned", f"Аккаунт заблокирован. {user.ban_reason}".strip())
    now = utcnow()
    if now - sess.last_seen_at > dt.timedelta(minutes=5):
        sess.last_seen_at = now
        sess.ip = ip_of(request)
        db.commit()
    request.state.user_id = user.id
    return sess


def current_user(sess: Session = Depends(current_session), db: DBSession = Depends(get_db)) -> User:
    return db.get(User, sess.user_id)


def verified_user(user: User = Depends(current_user)) -> User:
    if not user.is_verified:
        raise api_error(403, "email_not_verified", "Подтвердите email, чтобы пользоваться чатом")
    return user


def admin_user(user: User = Depends(current_user)) -> User:
    if user.role != "admin":
        raise api_error(403, "forbidden", "Недостаточно прав")
    return user


def api_key_auth(request: Request, db: DBSession = Depends(get_db)) -> ApiKey:
    st = state(request)
    token = _bearer(request) or request.headers.get("x-api-key")
    if not token or not token.startswith("kw-"):
        raise HTTPException(401, detail={"error": {"message": "Invalid API key", "type": "invalid_request_error",
                                                   "code": "invalid_api_key"}})
    key = db.scalar(select(ApiKey).where(ApiKey.key_hash == token_hash(token, st.settings.secret_key)))
    if key is None or key.revoked_at is not None:
        raise HTTPException(401, detail={"error": {"message": "Invalid or revoked API key",
                                                   "type": "invalid_request_error", "code": "invalid_api_key"}})
    user = db.get(User, key.user_id)
    if user is None or user.is_banned or not user.is_verified:
        raise HTTPException(403, detail={"error": {"message": "Account is not allowed to use the API",
                                                   "type": "permission_error", "code": "account_disabled"}})
    return key


def log_error(st: AppState, message: str, source: str = "backend", path: str = "", level: str = "error") -> None:
    msg = redact(message)[:4000]
    log.error("%s: %s", source, msg)
    try:
        with st.db.SessionLocal() as s:
            s.add(ErrorLog(level=level, source=source, path=path[:255], message=msg))
            s.commit()
    except Exception:  # pragma: no cover
        log.exception("failed to persist error log")
