from __future__ import annotations

import json

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session as DBSession

from ..db import Referral, ReferralReward, Session, User
from ..deps import api_error, current_session, current_user, get_db, rate_limit, state
from ..security import hash_password, mask_email, validate_password_strength, verify_password
from .auth import user_out

router = APIRouter(prefix="/api/account", tags=["account"])


class ProfileIn(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=64)
    theme: str | None = Field(default=None, pattern="^(system|light|dark)$")


class PasswordIn(BaseModel):
    old_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class DeleteIn(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    confirm: str = Field(pattern="^(DELETE|УДАЛИТЬ)$")


@router.get("/me")
def me(request: Request, user: User = Depends(current_user), db: DBSession = Depends(get_db)):
    return user_out(user, state(request).store.all(), db)


@router.patch("/me")
def update_me(body: ProfileIn, request: Request, user: User = Depends(current_user), db: DBSession = Depends(get_db)):
    if body.display_name is not None:
        user.display_name = body.display_name.strip()
    if body.theme is not None:
        user.theme = body.theme
    db.commit()
    return user_out(user, state(request).store.all(), db)


@router.post("/password", dependencies=[Depends(rate_limit("chpass", 10, 900))])
def change_password(body: PasswordIn, sess: Session = Depends(current_session),
                    user: User = Depends(current_user), db: DBSession = Depends(get_db)):
    if not verify_password(user.password_hash, body.old_password):
        raise api_error(400, "bad_password", "Текущий пароль указан неверно")
    if err := validate_password_strength(body.new_password):
        raise api_error(400, "weak_password", err)
    user.password_hash = hash_password(body.new_password)
    # sign out every other device
    db.query(Session).filter(Session.user_id == user.id, Session.id != sess.id).delete()
    db.commit()
    return {"ok": True, "message": "Пароль изменён, остальные устройства отключены"}


@router.get("/sessions")
def sessions(sess: Session = Depends(current_session), db: DBSession = Depends(get_db)):
    rows = db.scalars(select(Session).where(Session.user_id == sess.user_id).order_by(Session.last_seen_at.desc())).all()
    return [{"id": r.id, "device_name": r.device_name, "user_agent": r.user_agent, "ip": r.ip,
             "created_at": r.created_at.isoformat() + "Z", "last_seen_at": r.last_seen_at.isoformat() + "Z",
             "current": r.id == sess.id} for r in rows]


@router.delete("/sessions/{session_id}")
def revoke_session(session_id: str, sess: Session = Depends(current_session), db: DBSession = Depends(get_db)):
    target = db.get(Session, session_id)
    if target is None or target.user_id != sess.user_id:  # user isolation
        raise api_error(404, "not_found", "Сессия не найдена")
    db.delete(target)
    db.commit()
    return {"ok": True}


@router.delete("/sessions")
def revoke_other_sessions(sess: Session = Depends(current_session), db: DBSession = Depends(get_db)):
    n = db.query(Session).filter(Session.user_id == sess.user_id, Session.id != sess.id).delete()
    db.commit()
    return {"ok": True, "revoked": n}


@router.post("/delete", dependencies=[Depends(rate_limit("delacc", 5, 900))])
def delete_account(body: DeleteIn, user: User = Depends(current_user), db: DBSession = Depends(get_db)):
    if not verify_password(user.password_hash, body.password):
        raise api_error(400, "bad_password", "Пароль указан неверно")
    db.delete(user)  # cascades: sessions, chats, messages, api keys, usage, referral rows
    db.commit()
    return {"ok": True, "message": "Аккаунт и все данные удалены"}


@router.get("/referrals")
def referrals(request: Request, user: User = Depends(current_user), db: DBSession = Depends(get_db)):
    st = state(request)
    cfg = st.store.all()
    refs = db.scalars(select(Referral).where(Referral.referrer_id == user.id).order_by(Referral.created_at.desc())).all()
    invites = []
    for r in refs:
        invitee = db.get(User, r.invitee_id)
        invites.append({"id": r.id, "invitee": mask_email(invitee.email) if invitee else "удалён",
                        "status": r.status, "created_at": r.created_at.isoformat() + "Z",
                        "email_verified": bool(invitee and invitee.is_verified)})
    rewards = db.scalars(select(ReferralReward).where(ReferralReward.user_id == user.id)
                         .order_by(ReferralReward.created_at.desc())).all()
    return {
        "code": user.referral_code,
        "link": f"{st.settings.public_url}/?ref={user.referral_code}#/register",
        "enabled": cfg["referral_enabled"],
        "rewards_config": {"referrer_bonus_tokens": cfg["referral_referrer_bonus_tokens"],
                           "invitee_bonus_tokens": cfg["referral_invitee_bonus_tokens"],
                           "discount_percent": cfg["referral_discount_percent"],
                           "discount_cap": cfg["referral_discount_cap"]},
        "stats": {"total": len(refs), "confirmed": sum(r.status == "confirmed" for r in refs),
                  "pending": sum(r.status in ("pending", "review") for r in refs)},
        "bonus_tokens": user.bonus_tokens, "discount_percent": user.discount_percent,
        "invites": invites,
        "rewards": [{"kind": w.kind, "amount": w.amount, "note": w.note,
                     "created_at": w.created_at.isoformat() + "Z"} for w in rewards],
    }
