"""Log redaction: never write passwords, bearer tokens or API keys to logs."""
from __future__ import annotations

import logging
import re

_PATTERNS = [
    (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._\-~+/=]+"), r"\1[REDACTED]"),
    (re.compile(r"\bkw-[A-Za-z0-9_\-]{8,}"), "kw-[REDACTED]"),
    (re.compile(r"\bkws_[A-Za-z0-9_\-]{8,}"), "kws_[REDACTED]"),
    (re.compile(r'(?i)("?(?:password|new_password|old_password|token|secret|api_key|refresh_token)"?\s*[:=]\s*)("[^"]*"|\S+)'),
     r'\1"[REDACTED]"'),
]


def redact(text: str) -> str:
    for pat, repl in _PATTERNS:
        text = pat.sub(repl, text)
    return text


class RedactingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:
            return True
        record.msg = redact(msg)
        record.args = ()
        return True


def install_redaction(logger: logging.Logger | None = None) -> None:
    target = logger or logging.getLogger()
    f = RedactingFilter()
    target.addFilter(f)
    for h in target.handlers:
        h.addFilter(f)
