from __future__ import annotations

import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _bool(name: str, default: bool = False) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


def _list(name: str) -> list[str]:
    return [x.strip() for x in os.getenv(name, "").split(",") if x.strip()]


@dataclass
class Settings:
    env: str = field(default_factory=lambda: os.getenv("KIWION_ENV", "development"))
    host: str = field(default_factory=lambda: os.getenv("KIWION_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: int(os.getenv("KIWION_PORT", "8080")))
    public_url: str = field(default_factory=lambda: os.getenv("KIWION_PUBLIC_URL", "http://127.0.0.1:8080").rstrip("/"))
    database_url: str = field(default_factory=lambda: os.getenv(
        "KIWION_DATABASE_URL", f"sqlite:///{PROJECT_ROOT / 'data' / 'kiwion.db'}"))
    secret_key: str = field(default_factory=lambda: os.getenv("KIWION_SECRET_KEY", ""))
    inference_url: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_URL", "http://127.0.0.1:8090").rstrip("/"))
    inference_secret: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_SECRET", ""))
    inference_ca_cert: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_CA_CERT", ""))
    inference_client_cert: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_CLIENT_CERT", ""))
    inference_client_key: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_CLIENT_KEY", ""))
    mail_mode: str = field(default_factory=lambda: os.getenv("KIWION_MAIL_MODE", "file"))  # smtp | file | console
    mail_from: str = field(default_factory=lambda: os.getenv("KIWION_MAIL_FROM", "Kiwion Chat <no-reply@kiwion.local>"))
    smtp_host: str = field(default_factory=lambda: os.getenv("KIWION_SMTP_HOST", ""))
    smtp_port: int = field(default_factory=lambda: int(os.getenv("KIWION_SMTP_PORT", "587")))
    smtp_user: str = field(default_factory=lambda: os.getenv("KIWION_SMTP_USER", ""))
    smtp_password: str = field(default_factory=lambda: os.getenv("KIWION_SMTP_PASSWORD", ""))
    smtp_starttls: bool = field(default_factory=lambda: _bool("KIWION_SMTP_STARTTLS", True))
    outbox_dir: str = field(default_factory=lambda: os.getenv("KIWION_OUTBOX_DIR", str(PROJECT_ROOT / "data" / "outbox")))
    launch_at: str = field(default_factory=lambda: os.getenv("KIWION_LAUNCH_AT", "2027-01-15T12:00:00+03:00"))
    https: bool = field(default_factory=lambda: _bool("KIWION_HTTPS"))
    trusted_proxies: list[str] = field(default_factory=lambda: _list("KIWION_TRUSTED_PROXIES"))
    cors_origins: list[str] = field(default_factory=lambda: _list("KIWION_CORS_ORIGINS"))
    admin_emails: list[str] = field(default_factory=lambda: [e.lower() for e in _list("KIWION_ADMIN_EMAILS")])
    pow_difficulty: int = field(default_factory=lambda: int(os.getenv("KIWION_POW_DIFFICULTY", "16")))
    session_days: int = field(default_factory=lambda: int(os.getenv("KIWION_SESSION_DAYS", "30")))
    max_concurrent_streams_per_user: int = field(default_factory=lambda: int(os.getenv("KIWION_MAX_STREAMS_PER_USER", "1")))
    serve_static: bool = field(default_factory=lambda: _bool("KIWION_SERVE_STATIC", True))
    log_level: str = field(default_factory=lambda: os.getenv("KIWION_LOG_LEVEL", "INFO"))

    def __post_init__(self):
        if not self.secret_key:
            if self.env == "production":
                raise SystemExit("KIWION_SECRET_KEY must be set in production")
            self.secret_key = _dev_secret()
        if self.env == "production":
            if len(self.secret_key) < 32:
                raise SystemExit("KIWION_SECRET_KEY must be at least 32 characters")
            if not self.inference_secret:
                raise SystemExit("KIWION_INFERENCE_SECRET must be set in production")

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


def _dev_secret() -> str:
    """Persist a random dev secret so sessions survive restarts in development."""
    p = PROJECT_ROOT / "data" / ".dev_secret"
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        if p.exists():
            return p.read_text().strip()
        s = secrets.token_urlsafe(48)
        p.write_text(s)
        os.chmod(p, 0o600)
        return s
    except OSError:
        return secrets.token_urlsafe(48)


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings


def set_settings(s: Settings) -> None:
    global _settings
    _settings = s
