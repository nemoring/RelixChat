"""Admin-editable runtime settings stored in the database (with defaults)."""
from __future__ import annotations

import json
import threading
import time

from .db import Setting

DEFAULTS: dict = {
    "maintenance_mode": False,
    "maintenance_message": "Kiwion Chat на техническом обслуживании. Птичка киви скоро вернётся 🥝",
    "registration_open": True,
    "chat_enabled": True,
    "api_enabled": True,
    "free_daily_tokens": 30000,
    "max_tokens_per_reply": 512,
    "max_message_chars": 8000,
    "api_default_rpm": 20,
    "api_default_daily_tokens": 50000,
    "api_max_keys_per_user": 5,
    "referral_enabled": True,
    "referral_referrer_bonus_tokens": 15000,
    "referral_invitee_bonus_tokens": 5000,
    "referral_discount_percent": 5,
    "referral_discount_cap": 30,
    "referral_max_confirmed_per_day": 10,
    "referral_review_threshold": 40,
    "referral_reject_threshold": 80,
    "max_accounts_per_device": 3,
    "signups_per_ip_per_hour": 5,
    # e-mail (edited on the admin "Почта" page). mail_mode "" = use the values from .env
    "mail_mode": "",
    "smtp_host": "",
    "smtp_port": 465,
    "smtp_security": "ssl",
    "smtp_user": "",
    "mail_from": "",
}
MAIL_KEYS = ("mail_mode", "smtp_host", "smtp_port", "smtp_security", "smtp_user", "mail_from")

_TYPES = {k: type(v) for k, v in DEFAULTS.items()}


class SettingsStore:
    def __init__(self, session_factory, ttl: float = 5.0, secret_key: str = ""):
        self._sf = session_factory
        self._fernet = None
        if secret_key:
            import base64
            import hashlib
            from cryptography.fernet import Fernet
            self._fernet = Fernet(base64.urlsafe_b64encode(hashlib.sha256(("kiwion-settings:" + secret_key).encode()).digest()))
        self._cache: dict | None = None
        self._ts = 0.0
        self._ttl = ttl
        self._lock = threading.Lock()

    def all(self) -> dict:
        with self._lock:
            if self._cache is not None and time.monotonic() - self._ts < self._ttl:
                return dict(self._cache)
        data = dict(DEFAULTS)
        with self._sf() as s:
            for row in s.query(Setting).all():
                if row.key in DEFAULTS:
                    try:
                        data[row.key] = json.loads(row.value)
                    except ValueError:
                        pass
        with self._lock:
            self._cache, self._ts = data, time.monotonic()
        return dict(data)

    def get(self, key: str):
        return self.all()[key]

    def update(self, changes: dict) -> dict:
        clean = {}
        for k, v in changes.items():
            if k not in DEFAULTS:
                raise ValueError(f"unknown setting: {k}")
            t = _TYPES[k]
            if t is bool and not isinstance(v, bool):
                raise ValueError(f"{k} must be boolean")
            if t is int:
                if isinstance(v, bool) or not isinstance(v, int) or v < 0 or v > 10**9:
                    raise ValueError(f"{k} must be a non-negative integer")
            if t is str:
                if not isinstance(v, str) or len(v) > 500:
                    raise ValueError(f"{k} must be a string up to 500 chars")
            clean[k] = v
        with self._sf() as s:
            for k, v in clean.items():
                row = s.get(Setting, k)
                if row:
                    row.value = json.dumps(v)
                else:
                    s.add(Setting(key=k, value=json.dumps(v)))
            s.commit()
        with self._lock:
            self._cache = None
        return self.all()

    # --- encrypted secrets (e.g. SMTP password): stored encrypted, never returned by the API
    def set_secret(self, key: str, value: str | None) -> None:
        name = "secret:" + key
        with self._sf() as s:
            row = s.get(Setting, name)
            if not value:
                if row:
                    s.delete(row)
            else:
                token = self._fernet.encrypt(value.encode()).decode()
                if row:
                    row.value = token
                else:
                    s.add(Setting(key=name, value=token))
            s.commit()

    def get_secret(self, key: str) -> str:
        with self._sf() as s:
            row = s.get(Setting, "secret:" + key)
            if not row or not self._fernet:
                return ""
            try:
                return self._fernet.decrypt(row.value.encode()).decode()
            except Exception:
                return ""
