"""HMAC request signing between Kiwion Backend and Kiwion Inference.

Every request from the backend carries:
    X-Kiwion-Timestamp: unix seconds
    X-Kiwion-Nonce:     random hex
    X-Kiwion-Signature: hex(HMAC-SHA256(secret, f"{ts}\n{nonce}\n{METHOD}\n{path}\n{sha256(body)}"))

The inference server rejects requests whose timestamp is outside the allowed
skew window, whose nonce was already seen (replay), or whose signature does not
match. This works on top of TLS / WireGuard, so the inference node can be safely
exposed only to the backend.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time

MAX_SKEW_SECONDS = 60


def _digest(secret: str, ts: str, nonce: str, method: str, path: str, body: bytes) -> str:
    body_hash = hashlib.sha256(body or b"").hexdigest()
    msg = f"{ts}\n{nonce}\n{method.upper()}\n{path}\n{body_hash}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()


def sign_request(secret: str, method: str, path: str, body: bytes = b"") -> dict[str, str]:
    ts = str(int(time.time()))
    nonce = secrets.token_hex(16)
    return {
        "X-Kiwion-Timestamp": ts,
        "X-Kiwion-Nonce": nonce,
        "X-Kiwion-Signature": _digest(secret, ts, nonce, method, path, body),
    }


class NonceCache:
    def __init__(self, ttl: int = MAX_SKEW_SECONDS * 2):
        self.ttl = ttl
        self._seen: dict[str, float] = {}
        self._lock = threading.Lock()

    def check_and_add(self, nonce: str) -> bool:
        now = time.time()
        with self._lock:
            if len(self._seen) > 10000:
                self._seen = {n: t for n, t in self._seen.items() if now - t < self.ttl}
            if nonce in self._seen and now - self._seen[nonce] < self.ttl:
                return False
            self._seen[nonce] = now
            return True


def verify_request(secret: str, headers, method: str, path: str, body: bytes,
                   nonces: NonceCache | None = None) -> tuple[bool, str]:
    ts = headers.get("x-kiwion-timestamp") or headers.get("X-Kiwion-Timestamp")
    nonce = headers.get("x-kiwion-nonce") or headers.get("X-Kiwion-Nonce")
    sig = headers.get("x-kiwion-signature") or headers.get("X-Kiwion-Signature")
    if not (ts and nonce and sig):
        return False, "missing signature headers"
    try:
        ts_i = int(ts)
    except ValueError:
        return False, "bad timestamp"
    if abs(time.time() - ts_i) > MAX_SKEW_SECONDS:
        return False, "timestamp outside allowed window"
    expected = _digest(secret, ts, nonce, method, path, body)
    if not hmac.compare_digest(expected, sig):
        return False, "bad signature"
    if nonces is not None and not nonces.check_and_add(nonce):
        return False, "replayed nonce"
    return True, "ok"
