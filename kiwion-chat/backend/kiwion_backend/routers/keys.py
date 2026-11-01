"""API key management for the Developer API (keys are stored only as hashes)."""
from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session as DBSession

from ..db import ApiKey, UsageEvent, User, utcnow
from ..deps import api_error, get_db, rate_limit, state, verified_user
from ..security import new_token, token_hash
from ..usage import api_key_limits, tokens_used_today

router = APIRouter(prefix="/api/keys", tags=["developer"])


class KeyCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)


def key_out(k: ApiKey, cfg: dict, db: DBSession) -> dict:
    rpm, daily = api_key_limits(k, cfg)
    return {"id": k.id, "name": k.name, "prefix": k.prefix, "created_at": k.created_at.isoformat() + "Z",
            "last_used_at": k.last_used_at.isoformat() + "Z" if k.last_used_at else None,
            "revoked": k.revoked_at is not None, "rpm_limit": rpm, "daily_token_limit": daily,
            "tokens_today": tokens_used_today(db, api_key_id=k.id)}


@router.get("")
def list_keys(request: Request, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    cfg = state(request).store.all()
    keys = db.scalars(select(ApiKey).where(ApiKey.user_id == user.id).order_by(ApiKey.created_at.desc())).all()
    return [key_out(k, cfg, db) for k in keys]


@router.post("", status_code=201, dependencies=[Depends(rate_limit("newkey", 10, 3600))])
def create_key(body: KeyCreate, request: Request, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    st = state(request)
    cfg = st.store.all()
    if not cfg["api_enabled"]:
        raise api_error(503, "api_disabled", "Developer API временно отключён")
    active = db.scalar(select(func.count(ApiKey.id)).where(ApiKey.user_id == user.id, ApiKey.revoked_at.is_(None))) or 0
    if active >= cfg["api_max_keys_per_user"]:
        raise api_error(400, "too_many_keys", f"Максимум {cfg['api_max_keys_per_user']} активных ключей")
    secret = new_token("kw-", 32)
    k = ApiKey(user_id=user.id, name=body.name.strip(), prefix=secret[:10],
               key_hash=token_hash(secret, st.settings.secret_key))
    db.add(k)
    db.commit()
    # The full key is returned exactly once.
    return {**key_out(k, cfg, db), "key": secret,
            "warning": "Сохраните ключ сейчас — позже его нельзя будет посмотреть"}


@router.post("/{key_id}/revoke")
def revoke_key(key_id: str, request: Request, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    k = db.get(ApiKey, key_id)
    if k is None or k.user_id != user.id:
        raise api_error(404, "not_found", "Ключ не найден")
    if k.revoked_at is None:
        k.revoked_at = utcnow()
        db.commit()
    return key_out(k, state(request).store.all(), db)


@router.delete("/{key_id}")
def delete_key(key_id: str, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    k = db.get(ApiKey, key_id)
    if k is None or k.user_id != user.id:
        raise api_error(404, "not_found", "Ключ не найден")
    db.delete(k)
    db.commit()
    return {"ok": True}


@router.get("/usage")
def usage(days: int = 14, user: User = Depends(verified_user), db: DBSession = Depends(get_db)):
    days = max(1, min(days, 90))
    since = (utcnow() - dt.timedelta(days=days - 1)).replace(hour=0, minute=0, second=0, microsecond=0)
    day = func.date(UsageEvent.created_at)
    rows = db.execute(select(day, UsageEvent.api_key_id, func.count(UsageEvent.id),
                             func.sum(UsageEvent.prompt_tokens), func.sum(UsageEvent.completion_tokens),
                             func.sum(UsageEvent.latency_ms))
                      .where(UsageEvent.user_id == user.id, UsageEvent.source == "api", UsageEvent.created_at >= since)
                      .group_by(day, UsageEvent.api_key_id).order_by(day)).all()
    errors = db.scalar(select(func.count(UsageEvent.id)).where(
        UsageEvent.user_id == user.id, UsageEvent.source == "api", UsageEvent.created_at >= since,
        UsageEvent.status != "ok")) or 0
    out = [{"date": str(d), "key_id": k, "requests": n, "prompt_tokens": int(p or 0),
            "completion_tokens": int(c or 0), "avg_latency_ms": int((lat or 0) / n) if n else 0}
           for d, k, n, p, c, lat in rows]
    return {"days": days, "rows": out,
            "totals": {"requests": sum(r["requests"] for r in out),
                       "prompt_tokens": sum(r["prompt_tokens"] for r in out),
                       "completion_tokens": sum(r["completion_tokens"] for r in out),
                       "errors": errors}}
