"""Token quotas and usage accounting."""
from __future__ import annotations

import datetime as dt

from sqlalchemy import func, select
from sqlalchemy.orm import Session as DBSession

from .db import ApiKey, UsageEvent, User, utcnow


def day_start() -> dt.datetime:
    now = utcnow()
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def tokens_used_today(s: DBSession, user_id: int | None = None, api_key_id: str | None = None,
                      source: str | None = None) -> int:
    q = select(func.coalesce(func.sum(UsageEvent.prompt_tokens + UsageEvent.completion_tokens), 0)) \
        .where(UsageEvent.created_at >= day_start())
    if user_id is not None:
        q = q.where(UsageEvent.user_id == user_id)
    if api_key_id is not None:
        q = q.where(UsageEvent.api_key_id == api_key_id)
    if source is not None:
        q = q.where(UsageEvent.source == source)
    return int(s.scalar(q) or 0)


def user_daily_limit(user: User, cfg: dict) -> int:
    return user.daily_token_limit if user.daily_token_limit is not None else cfg["free_daily_tokens"]


def chat_quota(s: DBSession, user: User, cfg: dict) -> dict:
    used = tokens_used_today(s, user_id=user.id, source="chat")
    limit = user_daily_limit(user, cfg)
    return {"used_today": used, "daily_limit": limit, "bonus_tokens": user.bonus_tokens or 0,
            "remaining": max(0, limit - used) + (user.bonus_tokens or 0)}


def can_chat(s: DBSession, user: User, cfg: dict) -> bool:
    return chat_quota(s, user, cfg)["remaining"] > 0


def record_chat_usage(s: DBSession, user: User, prompt_tokens: int, completion_tokens: int,
                      latency_ms: int, status: str, cfg: dict) -> None:
    used_before = tokens_used_today(s, user_id=user.id, source="chat")
    limit = user_daily_limit(user, cfg)
    total = prompt_tokens + completion_tokens
    over = max(0, used_before + total - max(limit, used_before))
    if over and user.bonus_tokens:
        user.bonus_tokens = max(0, user.bonus_tokens - over)
    s.add(UsageEvent(user_id=user.id, source="chat", status=status, prompt_tokens=prompt_tokens,
                     completion_tokens=completion_tokens, latency_ms=latency_ms))


def api_key_limits(key: ApiKey, cfg: dict) -> tuple[int, int]:
    rpm = key.rpm_limit if key.rpm_limit is not None else cfg["api_default_rpm"]
    daily = key.daily_token_limit if key.daily_token_limit is not None else cfg["api_default_daily_tokens"]
    return rpm, daily
