from __future__ import annotations

import hashlib
import hmac
import ipaddress
import re
import secrets
import threading
import time
from collections import defaultdict, deque

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

# Argon2id with moderate parameters: safe, but light enough for a cheap VPS.
_ph = PasswordHasher(time_cost=3, memory_cost=64 * 1024, parallelism=2)
_DUMMY_HASH = _ph.hash("kiwion-dummy-password")


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _ph.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    try:
        return _ph.check_needs_rehash(password_hash)
    except InvalidHashError:
        return True


def validate_password_strength(password: str) -> str | None:
    if len(password) < 8:
        return "Пароль должен содержать минимум 8 символов"
    if len(password) > 128:
        return "Пароль слишком длинный"
    if not re.search(r"[A-Za-zА-Яа-яЁё]", password) or not re.search(r"\d", password):
        return "Пароль должен содержать буквы и цифры"
    return None


def new_token(prefix: str = "", nbytes: int = 32) -> str:
    return prefix + secrets.token_urlsafe(nbytes)


def token_hash(token: str, pepper: str = "") -> str:
    """Hash for high-entropy tokens (sessions, API keys, email links).

    Tokens carry >=256 bits of randomness, so a keyed SHA-256 is sufficient and
    allows O(1) lookup; a slow KDF is only needed for low-entropy passwords.
    """
    return hmac.new(pepper.encode(), token.encode(), hashlib.sha256).hexdigest()


def normalize_email(email: str) -> str:
    """Canonical form used to detect duplicate accounts (gmail dots, +tags)."""
    email = email.strip().lower()
    local, _, domain = email.partition("@")
    local = local.split("+", 1)[0]
    if domain in ("gmail.com", "googlemail.com"):
        local = local.replace(".", "")
        domain = "gmail.com"
    return f"{local}@{domain}"


DISPOSABLE_DOMAINS = {
    "mailinator.com", "10minutemail.com", "guerrillamail.com", "tempmail.com", "temp-mail.org",
    "yopmail.com", "trashmail.com", "sharklasers.com", "getnada.com", "dispostable.com",
    "maildrop.cc", "fakeinbox.com", "throwawaymail.com", "mintemail.com", "mohmal.com",
    "emailondeck.com", "tempail.com", "moakt.com", "mailnesia.com", "spamgourmet.com",
}


def is_disposable(email: str) -> bool:
    return email.rsplit("@", 1)[-1].lower() in DISPOSABLE_DOMAINS


def mask_email(email: str) -> str:
    local, _, domain = email.partition("@")
    if len(local) <= 2:
        return local[:1] + "*@" + domain
    return local[0] + "*" * (len(local) - 2) + local[-1] + "@" + domain


# ---------------------------------------------------------------- proof of work
class ProofOfWork:
    """Stateless hashcash challenge: makes mass automated registrations expensive.

    challenge = f"{ts}.{random}.{hmac(ts.random)}"; the client must find a nonce
    such that sha256(f"{challenge}:{nonce}") starts with `difficulty` zero bits.
    """

    def __init__(self, secret: str, difficulty: int, ttl: int = 600):
        self.secret = secret.encode()
        self.difficulty = difficulty
        self.ttl = ttl
        self._used: dict[str, float] = {}
        self._lock = threading.Lock()

    def issue(self) -> dict:
        ts = str(int(time.time()))
        rnd = secrets.token_hex(8)
        mac = hmac.new(self.secret, f"{ts}.{rnd}".encode(), hashlib.sha256).hexdigest()[:16]
        return {"challenge": f"{ts}.{rnd}.{mac}", "difficulty": self.difficulty, "expires_in": self.ttl}

    @staticmethod
    def leading_zero_bits(digest: bytes) -> int:
        bits = 0
        for b in digest:
            if b == 0:
                bits += 8
                continue
            bits += 8 - b.bit_length()
            break
        return bits

    def verify(self, challenge: str, nonce: str) -> bool:
        if self.difficulty <= 0:
            return True
        try:
            ts, rnd, mac = challenge.split(".")
            ts_i = int(ts)
        except ValueError:
            return False
        good = hmac.new(self.secret, f"{ts}.{rnd}".encode(), hashlib.sha256).hexdigest()[:16]
        if not hmac.compare_digest(good, mac) or time.time() - ts_i > self.ttl or len(nonce) > 64:
            return False
        digest = hashlib.sha256(f"{challenge}:{nonce}".encode()).digest()
        if self.leading_zero_bits(digest) < self.difficulty:
            return False
        with self._lock:
            now = time.time()
            self._used = {c: t for c, t in self._used.items() if now - t < self.ttl}
            if challenge in self._used:
                return False
            self._used[challenge] = now
        return True

    @staticmethod
    def solve(challenge: str, difficulty: int) -> str:
        """Reference solver (used by tests and the CLI)."""
        n = 0
        while True:
            d = hashlib.sha256(f"{challenge}:{n}".encode()).digest()
            if ProofOfWork.leading_zero_bits(d) >= difficulty:
                return str(n)
            n += 1


# ---------------------------------------------------------------- rate limiting
class RateLimiter:
    """In-memory sliding-window limiter (per process).

    For multiple backend workers put the limits in Redis or terminate at the
    reverse proxy; a single uvicorn worker is the recommended VPS setup.
    """

    def __init__(self):
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str, limit: int, window: float) -> tuple[bool, float]:
        now = time.monotonic()
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] > window:
                q.popleft()
            if len(q) >= limit:
                return False, window - (now - q[0])
            q.append(now)
            if len(self._hits) > 50000:
                for k in [k for k, v in self._hits.items() if not v][:10000]:
                    del self._hits[k]
            return True, 0.0

    def count(self, key: str, window: float) -> int:
        now = time.monotonic()
        with self._lock:
            q = self._hits.get(key) or deque()
            return sum(1 for t in q if now - t <= window)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


def client_ip(request, trusted_proxies: list[str]) -> str:
    peer = request.client.host if request.client else ""
    if trusted_proxies and _ip_in(peer, trusted_proxies):
        fwd = request.headers.get("x-forwarded-for", "")
        if fwd:
            return fwd.split(",")[0].strip()[:64]
        real = request.headers.get("x-real-ip")
        if real:
            return real.strip()[:64]
    return peer[:64]


def _ip_in(ip: str, nets: list[str]) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    for n in nets:
        try:
            if addr in ipaddress.ip_network(n, strict=False):
                return True
        except ValueError:
            continue
    return False


def ip_subnet(ip: str) -> str:
    """/24 for IPv4, /64 for IPv6 — used as a *weak* fraud signal only."""
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return ip
    prefix = 24 if addr.version == 4 else 64
    return str(ipaddress.ip_network(f"{ip}/{prefix}", strict=False))
