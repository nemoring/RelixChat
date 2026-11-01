"""Admin API — every route requires role=admin."""
from __future__ import annotations

import datetime as dt
import json

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session as DBSession

from ..db import (ApiKey, AuditLog, Chat, ErrorLog, Message, Referral, Session, UsageEvent, User,
                  utcnow)
from ..deps import admin_user, api_error, get_db, state
from ..referrals import admin_decide
from ..security import mask_email

router = APIRouter(prefix="/api/admin", tags=["admin"], dependencies=[Depends(admin_user)])


def audit(db: DBSession, admin: User, action: str, target: str = "", details: dict | None = None):
    db.add(AuditLog(admin_id=admin.id, action=action, target=target,
                    details=json.dumps(details or {}, ensure_ascii=False)))


def _iso(d):
    return d.isoformat() + "Z" if d else None


@router.get("/stats")
async def stats(request: Request, db: DBSession = Depends(get_db)):
    st = state(request)
    now = utcnow()
    d1, d7 = now - dt.timedelta(days=1), now - dt.timedelta(days=7)
    day = func.date(User.created_at)
    regs = db.execute(select(day, func.count(User.id)).where(User.created_at >= now - dt.timedelta(days=30))
                      .group_by(day).order_by(day)).all()
    uday = func.date(UsageEvent.created_at)
    tokens = db.execute(select(uday, UsageEvent.source, func.sum(UsageEvent.prompt_tokens),
                               func.sum(UsageEvent.completion_tokens), func.count(UsageEvent.id))
                        .where(UsageEvent.created_at >= now - dt.timedelta(days=14))
                        .group_by(uday, UsageEvent.source).order_by(uday)).all()
    inf = await st.inference.status(max_age=1)
    return {
        "users_total": db.scalar(select(func.count(User.id))),
        "users_verified": db.scalar(select(func.count(User.id)).where(User.is_verified.is_(True))),
        "users_banned": db.scalar(select(func.count(User.id)).where(User.is_banned.is_(True))),
        "registrations_24h": db.scalar(select(func.count(User.id)).where(User.created_at >= d1)),
        "registrations_7d": db.scalar(select(func.count(User.id)).where(User.created_at >= d7)),
        "registrations_by_day": [{"date": str(d), "count": n} for d, n in regs],
        "chats_total": db.scalar(select(func.count(Chat.id))),
        "active_chats_24h": db.scalar(select(func.count(Chat.id)).where(Chat.updated_at >= d1)),
        "messages_24h": db.scalar(select(func.count(Message.id)).where(Message.created_at >= d1)),
        "active_sessions": db.scalar(select(func.count(Session.id)).where(Session.last_seen_at >= d1)),
        "api_keys_active": db.scalar(select(func.count(ApiKey.id)).where(ApiKey.revoked_at.is_(None))),
        "tokens_24h": int(db.scalar(select(func.coalesce(func.sum(UsageEvent.prompt_tokens + UsageEvent.completion_tokens), 0))
                                    .where(UsageEvent.created_at >= d1)) or 0),
        "tokens_by_day": [{"date": str(d), "source": s, "prompt_tokens": int(p or 0), "completion_tokens": int(c or 0),
                           "requests": n} for d, s, p, c, n in tokens],
        "errors_24h": db.scalar(select(func.count(ErrorLog.id)).where(ErrorLog.created_at >= d1)),
        "referrals_review": db.scalar(select(func.count(Referral.id)).where(Referral.status == "review")),
        "active_streams": sum(v for k, v in st.active_streams.items() if k[0] == "user"),
        "inference": inf,
    }


@router.get("/inference")
async def inference_status(request: Request):
    return await state(request).inference.status(max_age=0)


@router.get("/users")
def users(q: str = "", page: int = 1, per_page: int = 50, status: str = "", db: DBSession = Depends(get_db)):
    per_page = max(1, min(per_page, 200))
    stmt = select(User)
    if q:
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(or_(User.email.like(like), User.display_name.like(like), User.referral_code == q.strip().upper()))
    if status == "banned":
        stmt = stmt.where(User.is_banned.is_(True))
    elif status == "unverified":
        stmt = stmt.where(User.is_verified.is_(False))
    elif status == "admin":
        stmt = stmt.where(User.role == "admin")
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(User.created_at.desc()).offset((page - 1) * per_page).limit(per_page)).all()
    return {"total": total, "page": page, "per_page": per_page, "users": [_user_row(db, u) for u in rows]}


def _user_row(db: DBSession, u: User) -> dict:
    return {"id": u.id, "email": u.email, "display_name": u.display_name, "role": u.role,
            "is_verified": u.is_verified, "is_banned": u.is_banned, "ban_reason": u.ban_reason,
            "created_at": _iso(u.created_at), "last_login_at": _iso(u.last_login_at),
            "daily_token_limit": u.daily_token_limit, "bonus_tokens": u.bonus_tokens,
            "discount_percent": u.discount_percent, "signup_ip": u.signup_ip,
            "referral_code": u.referral_code, "referred_by_id": u.referred_by_id,
            "chats": db.scalar(select(func.count(Chat.id)).where(Chat.user_id == u.id))}


class UserPatch(BaseModel):
    is_banned: bool | None = None
    ban_reason: str | None = Field(default=None, max_length=255)
    daily_token_limit: int | None = Field(default=None, ge=-1, le=10**8)  # -1 = reset to default
    bonus_tokens: int | None = Field(default=None, ge=0, le=10**8)
    role: str | None = Field(default=None, pattern="^(user|admin)$")
    is_verified: bool | None = None


@router.patch("/users/{user_id}")
def patch_user(user_id: int, body: UserPatch, request: Request, admin: User = Depends(admin_user),
               db: DBSession = Depends(get_db)):
    u = db.get(User, user_id)
    if u is None:
        raise api_error(404, "not_found", "Пользователь не найден")
    if u.id == admin.id and (body.is_banned or body.role == "user"):
        raise api_error(400, "self_lockout", "Нельзя заблокировать или разжаловать самого себя")
    changes = body.model_dump(exclude_none=True)
    if body.is_banned is not None:
        u.is_banned = body.is_banned
        u.ban_reason = (body.ban_reason or "") if body.is_banned else ""
        if body.is_banned:
            db.query(Session).filter(Session.user_id == u.id).delete()
            db.query(ApiKey).filter(ApiKey.user_id == u.id, ApiKey.revoked_at.is_(None)).update({"revoked_at": utcnow()})
    if body.daily_token_limit is not None:
        u.daily_token_limit = None if body.daily_token_limit < 0 else body.daily_token_limit
    if body.bonus_tokens is not None:
        u.bonus_tokens = body.bonus_tokens
    if body.role is not None:
        u.role = body.role
    if body.is_verified is not None:
        u.is_verified = body.is_verified
    audit(db, admin, "user.update", f"user:{u.id}", changes)
    db.commit()
    return _user_row(db, u)


@router.get("/errors")
def errors(limit: int = 100, source: str = "", db: DBSession = Depends(get_db)):
    stmt = select(ErrorLog)
    if source:
        stmt = stmt.where(ErrorLog.source == source)
    rows = db.scalars(stmt.order_by(ErrorLog.id.desc()).limit(max(1, min(limit, 500)))).all()
    return [{"id": e.id, "created_at": _iso(e.created_at), "level": e.level, "source": e.source,
             "path": e.path, "message": e.message} for e in rows]


@router.delete("/errors")
def clear_errors(admin: User = Depends(admin_user), db: DBSession = Depends(get_db)):
    n = db.query(ErrorLog).delete()
    audit(db, admin, "errors.clear", "", {"deleted": n})
    db.commit()
    return {"ok": True, "deleted": n}


@router.get("/settings")
def get_settings(request: Request):
    return state(request).store.all()


@router.put("/settings")
def put_settings(changes: dict, request: Request, admin: User = Depends(admin_user), db: DBSession = Depends(get_db)):
    try:
        out = state(request).store.update(changes)
    except ValueError as e:
        raise api_error(400, "bad_setting", str(e))
    audit(db, admin, "settings.update", "", changes)
    db.commit()
    return out


@router.get("/referrals")
def referrals(status: str = "", limit: int = 200, db: DBSession = Depends(get_db)):
    stmt = select(Referral)
    if status:
        stmt = stmt.where(Referral.status == status)
    rows = db.scalars(stmt.order_by(Referral.id.desc()).limit(max(1, min(limit, 1000)))).all()
    out = []
    for r in rows:
        a, b = db.get(User, r.referrer_id), db.get(User, r.invitee_id)
        out.append({"id": r.id, "status": r.status, "risk_score": r.risk_score,
                    "risk_reasons": json.loads(r.risk_reasons or "[]"), "created_at": _iso(r.created_at),
                    "decided_at": _iso(r.decided_at),
                    "referrer": {"id": a.id, "email": a.email} if a else None,
                    "invitee": {"id": b.id, "email": b.email, "verified": b.is_verified,
                                "signup_ip": b.signup_ip} if b else None})
    return out


class Decision(BaseModel):
    approve: bool


@router.post("/referrals/{ref_id}/decision")
def decide(ref_id: int, body: Decision, request: Request, admin: User = Depends(admin_user),
           db: DBSession = Depends(get_db)):
    r = db.get(Referral, ref_id)
    if r is None:
        raise api_error(404, "not_found", "Приглашение не найдено")
    admin_decide(db, r, body.approve, state(request).store.all())
    audit(db, admin, "referral.decision", f"referral:{r.id}", {"approve": body.approve})
    db.commit()
    return {"id": r.id, "status": r.status}


@router.get("/audit")
def audit_log(limit: int = 100, db: DBSession = Depends(get_db)):
    rows = db.scalars(select(AuditLog).order_by(AuditLog.id.desc()).limit(max(1, min(limit, 500)))).all()
    out = []
    for r in rows:
        a = db.get(User, r.admin_id) if r.admin_id else None
        out.append({"id": r.id, "created_at": _iso(r.created_at), "admin": mask_email(a.email) if a else None,
                    "action": r.action, "target": r.target, "details": json.loads(r.details or "{}")})
    return out
