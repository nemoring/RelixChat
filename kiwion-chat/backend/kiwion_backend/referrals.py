"""Referral program with anti-fraud scoring.

Decisions are based on a weighted risk score. A shared IP address is only a weak
signal (families, offices, mobile carriers and campus NAT share IPs), so it can
never reject a referral on its own — strong signals are the same device,
self-invites by e-mail alias, invitation cycles and abnormal velocity.
"""
from __future__ import annotations

import datetime as dt
import json
import logging

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DBSession

from .db import DeviceSighting, Referral, ReferralReward, User, utcnow
from .security import ip_subnet, is_disposable

log = logging.getLogger("kiwion.referrals")

WEIGHTS = {
    "self_invite": 100,
    "invite_cycle": 100,
    "same_device_as_referrer": 60,
    "device_many_accounts": 40,
    "chain_same_device": 40,
    "velocity": 50,
    "disposable_email": 30,
    "subnet_cluster": 20,
    "fresh_referrer_chain": 15,
    "same_ip_as_referrer": 15,
    "same_subnet_as_referrer": 5,
}


def attach_referral(s: DBSession, invitee: User, code: str | None) -> Referral | None:
    if not code:
        return None
    referrer = s.scalar(select(User).where(User.referral_code == code.strip().upper()))
    if referrer is None:
        return None
    ref = Referral(referrer_id=referrer.id, invitee_id=invitee.id, status="pending")
    invitee.referred_by_id = referrer.id
    if referrer.id == invitee.id or referrer.email_normalized == invitee.email_normalized:
        ref.status = "rejected"
        ref.risk_score = WEIGHTS["self_invite"]
        ref.risk_reasons = json.dumps(["self_invite"])
        ref.decided_at = utcnow()
    s.add(ref)
    return ref


def _user_devices(s: DBSession, user_id: int) -> set[str]:
    return {d for (d,) in s.execute(select(DeviceSighting.device_id).where(
        DeviceSighting.user_id == user_id, DeviceSighting.device_id != "")).all()}


def _user_ips(s: DBSession, user_id: int) -> set[str]:
    return {ip for (ip,) in s.execute(select(DeviceSighting.ip).where(
        DeviceSighting.user_id == user_id, DeviceSighting.ip != "")).all()}


def _ancestors(s: DBSession, user: User, depth: int = 10) -> list[User]:
    out, cur, seen = [], user, set()
    while cur.referred_by_id and len(out) < depth and cur.referred_by_id not in seen:
        seen.add(cur.referred_by_id)
        cur = s.get(User, cur.referred_by_id)
        if cur is None:
            break
        out.append(cur)
    return out


def score_referral(s: DBSession, ref: Referral, cfg: dict) -> tuple[int, list[str]]:
    referrer = s.get(User, ref.referrer_id)
    invitee = s.get(User, ref.invitee_id)
    reasons: list[str] = []

    if referrer.email_normalized == invitee.email_normalized:
        reasons.append("self_invite")
    if any(a.id == invitee.id for a in _ancestors(s, referrer)):
        reasons.append("invite_cycle")

    invitee_devices = _user_devices(s, invitee.id) | ({invitee.signup_device_id} if invitee.signup_device_id else set())
    referrer_devices = _user_devices(s, referrer.id)
    if invitee_devices & referrer_devices:
        reasons.append("same_device_as_referrer")
    for dev in invitee_devices:
        n_accounts = s.scalar(select(func.count(func.distinct(DeviceSighting.user_id)))
                              .where(DeviceSighting.device_id == dev)) or 0
        if n_accounts > cfg["max_accounts_per_device"]:
            reasons.append("device_many_accounts")
            break
    # chain check: someone up the referrer's chain registered from the invitee's device
    for anc in _ancestors(s, referrer, depth=5):
        if invitee_devices & (_user_devices(s, anc.id) | {anc.signup_device_id}):
            reasons.append("chain_same_device")
            break
    if referrer.referred_by_id and referrer.created_at and \
            utcnow() - referrer.created_at < dt.timedelta(hours=1):
        reasons.append("fresh_referrer_chain")

    since = utcnow() - dt.timedelta(hours=24)
    confirmed_today = s.scalar(select(func.count(Referral.id)).where(
        Referral.referrer_id == referrer.id, Referral.status == "confirmed",
        Referral.decided_at >= since)) or 0
    if confirmed_today >= cfg["referral_max_confirmed_per_day"]:
        reasons.append("velocity")

    if is_disposable(invitee.email):
        reasons.append("disposable_email")

    referrer_ips = _user_ips(s, referrer.id)
    if invitee.signup_ip and invitee.signup_ip in referrer_ips:
        reasons.append("same_ip_as_referrer")
    elif invitee.signup_ip and ip_subnet(invitee.signup_ip) in {ip_subnet(i) for i in referrer_ips}:
        reasons.append("same_subnet_as_referrer")

    if invitee.signup_ip:
        subnet = ip_subnet(invitee.signup_ip)
        recent = s.execute(select(User.signup_ip).join(Referral, Referral.invitee_id == User.id).where(
            Referral.referrer_id == referrer.id, Referral.created_at >= since, User.id != invitee.id)).all()
        if sum(1 for (ip,) in recent if ip and ip_subnet(ip) == subnet) >= 3:
            reasons.append("subnet_cluster")

    score = sum(WEIGHTS[r] for r in reasons)
    return score, reasons


def evaluate_referral(s: DBSession, ref: Referral, cfg: dict) -> Referral:
    """Called when the invitee confirms the e-mail. Idempotent."""
    if ref.status != "pending":
        return ref
    invitee = s.get(User, ref.invitee_id)
    referrer = s.get(User, ref.referrer_id)
    if not invitee or not invitee.is_verified:
        return ref
    if not cfg["referral_enabled"]:
        return ref
    if referrer is None or referrer.is_banned:
        ref.status, ref.decided_at = "rejected", utcnow()
        ref.risk_reasons = json.dumps(["referrer_banned"])
        return ref
    score, reasons = score_referral(s, ref, cfg)
    ref.risk_score = score
    ref.risk_reasons = json.dumps(reasons)
    ref.decided_at = utcnow()
    if score >= cfg["referral_reject_threshold"]:
        ref.status = "rejected"
    elif score >= cfg["referral_review_threshold"]:
        ref.status = "review"
    else:
        ref.status = "confirmed"
        grant_rewards(s, ref, cfg)
    log.info("referral %s -> %s score=%s reasons=%s", ref.id, ref.status, score, reasons)
    return ref


def _grant(s: DBSession, ref: Referral, user: User, kind: str, amount: int, note: str, cfg: dict) -> bool:
    if amount <= 0:
        return False
    exists = s.scalar(select(ReferralReward.id).where(
        ReferralReward.referral_id == ref.id, ReferralReward.user_id == user.id, ReferralReward.kind == kind))
    if exists:
        return False
    if kind == "discount":
        new_val = min(cfg["referral_discount_cap"], (user.discount_percent or 0) + amount)
        amount = new_val - (user.discount_percent or 0)
        if amount <= 0:
            return False
    try:
        with s.begin_nested():
            s.add(ReferralReward(referral_id=ref.id, user_id=user.id, kind=kind, amount=amount, note=note))
            s.flush()
    except IntegrityError:  # concurrent double-grant is blocked by the unique constraint
        return False
    if kind == "bonus_tokens":
        user.bonus_tokens = (user.bonus_tokens or 0) + amount
    else:
        user.discount_percent = (user.discount_percent or 0) + amount
    return True


def grant_rewards(s: DBSession, ref: Referral, cfg: dict) -> None:
    referrer = s.get(User, ref.referrer_id)
    invitee = s.get(User, ref.invitee_id)
    _grant(s, ref, referrer, "bonus_tokens", cfg["referral_referrer_bonus_tokens"],
           f"Приглашение пользователя #{invitee.id}", cfg)
    _grant(s, ref, referrer, "discount", cfg["referral_discount_percent"],
           f"Скидка за приглашение #{invitee.id}", cfg)
    _grant(s, ref, invitee, "bonus_tokens", cfg["referral_invitee_bonus_tokens"],
           "Бонус за регистрацию по приглашению", cfg)


def admin_decide(s: DBSession, ref: Referral, approve: bool, cfg: dict) -> Referral:
    if ref.status in ("confirmed",):
        return ref
    ref.decided_at = utcnow()
    if approve:
        ref.status = "confirmed"
        grant_rewards(s, ref, cfg)
    else:
        ref.status = "rejected"
    return ref
