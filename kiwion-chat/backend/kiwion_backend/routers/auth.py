from __future__ import annotations

import datetime as dt
import logging
import secrets
import string

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session as DBSession

from ..db import DeviceSighting, EmailToken, Referral, Session, User, utcnow
from ..deps import (AppState, api_error, current_session, current_user, get_db, ip_of, log_error,
                    rate_limit, state)
from ..referrals import attach_referral, evaluate_referral
from ..security import (hash_password, is_disposable, new_token, normalize_email,
                        password_needs_rehash, token_hash, validate_password_strength, verify_password)

router = APIRouter(prefix="/api/auth", tags=["auth"])
log = logging.getLogger("kiwion.auth")


class PowSolution(BaseModel):
    challenge: str = Field(max_length=128)
    nonce: str = Field(max_length=64)


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(default="", max_length=64)
    referral_code: str | None = Field(default=None, max_length=16)
    device_id: str = Field(default="", max_length=64, pattern=r"^[A-Za-z0-9\-_]*$")
    device_name: str = Field(default="", max_length=128)
    pow: PowSolution | None = None
    accept_terms: bool = True


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)
    device_id: str = Field(default="", max_length=64, pattern=r"^[A-Za-z0-9\-_]*$")
    device_name: str = Field(default="", max_length=128)


class TokenIn(BaseModel):
    token: str = Field(min_length=10, max_length=200)


class ForgotIn(BaseModel):
    email: EmailStr


class ResetIn(BaseModel):
    token: str = Field(min_length=10, max_length=200)
    new_password: str = Field(min_length=8, max_length=128)


def _referral_code(db: DBSession) -> str:
    alphabet = string.ascii_uppercase + string.digits
    alphabet = "".join(c for c in alphabet if c not in "0O1I")
    while True:
        code = "KIWI" + "".join(secrets.choice(alphabet) for _ in range(6))
        if not db.scalar(select(User.id).where(User.referral_code == code)):
            return code


def _issue_email_token(db: DBSession, st: AppState, user: User, kind: str, hours: float) -> str:
    db.query(EmailToken).filter(EmailToken.user_id == user.id, EmailToken.kind == kind,
                                EmailToken.used_at.is_(None)).delete()
    token = new_token(nbytes=24)
    db.add(EmailToken(user_id=user.id, kind=kind, token_hash=token_hash(token, st.settings.secret_key),
                      expires_at=utcnow() + dt.timedelta(hours=hours)))
    return token


def create_session(db: DBSession, st: AppState, user: User, request: Request,
                   device_id: str, device_name: str) -> tuple[str, Session]:
    token = new_token("kws_", 32)
    sess = Session(user_id=user.id, token_hash=token_hash(token, st.settings.secret_key),
                   device_id=device_id, device_name=device_name or _device_from_ua(request),
                   user_agent=request.headers.get("user-agent", "")[:255], ip=ip_of(request),
                   expires_at=utcnow() + dt.timedelta(days=st.settings.session_days))
    db.add(sess)
    return token, sess


def _device_from_ua(request: Request) -> str:
    ua = request.headers.get("user-agent", "")
    for name in ("KiwionAndroid", "Android", "iPhone", "Windows", "Macintosh", "Linux", "kiwion-cli"):
        if name in ua:
            return {"KiwionAndroid": "Kiwion для Android", "Macintosh": "Mac", "kiwion-cli": "Kiwion CLI"}.get(name, name)
    return "Браузер"


def _send_mail_safe(st: AppState, fn, *args):
    try:
        fn(*args)
    except Exception as e:
        log_error(st, f"mail delivery failed: {e}", source="mail")


@router.get("/challenge", dependencies=[Depends(rate_limit("challenge", 30, 60))])
def challenge(request: Request):
    return state(request).pow.issue()


@router.post("/register", status_code=201, dependencies=[Depends(rate_limit("register", 10, 3600))])
def register(body: RegisterIn, request: Request, background: BackgroundTasks, db: DBSession = Depends(get_db)):
    st = state(request)
    cfg = st.store.all()
    if cfg["maintenance_mode"] or not cfg["registration_open"]:
        raise api_error(503, "registration_closed", "Регистрация временно закрыта")
    if not body.accept_terms:
        raise api_error(400, "terms_required", "Необходимо принять условия использования")
    if not body.pow or not st.pow.verify(body.pow.challenge, body.pow.nonce):
        raise api_error(400, "bad_pow", "Проверка защиты от ботов не пройдена. Обновите страницу и попробуйте снова.")
    ip = ip_of(request)
    ok, _ = st.limiter.hit(f"signup-ip:{ip}", cfg["signups_per_ip_per_hour"], 3600)
    if not ok:
        raise api_error(429, "rate_limited", "С этого адреса слишком много регистраций. Попробуйте позже.")
    email = body.email.strip().lower()
    if is_disposable(email):
        raise api_error(400, "disposable_email", "Временные почтовые адреса не поддерживаются")
    if err := validate_password_strength(body.password):
        raise api_error(400, "weak_password", err)
    if body.device_id:
        n_dev = db.scalar(select(func.count(func.distinct(DeviceSighting.user_id))).where(
            DeviceSighting.device_id == body.device_id, DeviceSighting.event == "signup")) or 0
        if n_dev >= cfg["max_accounts_per_device"]:
            raise api_error(429, "device_limit", "С этого устройства создано слишком много аккаунтов")
    if db.scalar(select(User.id).where(User.email == email)):
        raise api_error(409, "email_taken", "Аккаунт с таким email уже существует")
    norm = normalize_email(email)
    alias_count = db.scalar(select(func.count(User.id)).where(User.email_normalized == norm)) or 0
    if alias_count >= 1:
        raise api_error(409, "email_taken", "Аккаунт с этим адресом (или его псевдонимом) уже существует")

    user = User(email=email, email_normalized=norm, password_hash=hash_password(body.password),
                display_name=(body.display_name or email.split("@")[0])[:64].strip(),
                referral_code=_referral_code(db), signup_ip=ip, signup_device_id=body.device_id,
                role="admin" if email in st.settings.admin_emails else "user")
    db.add(user)
    db.flush()
    attach_referral(db, user, body.referral_code)
    db.add(DeviceSighting(device_id=body.device_id, user_id=user.id, ip=ip, event="signup"))
    token = _issue_email_token(db, st, user, "verify", 48)
    session_token, _ = create_session(db, st, user, request, body.device_id, body.device_name)
    db.commit()
    background.add_task(_send_mail_safe, st, st.mailer.send_verification, email, token)
    return {"token": session_token, "user": user_out(user, cfg, db),
            "message": "Мы отправили письмо для подтверждения email"}


@router.post("/verify", dependencies=[Depends(rate_limit("verify", 20, 600))])
def verify(body: TokenIn, request: Request, db: DBSession = Depends(get_db)):
    st = state(request)
    et = db.scalar(select(EmailToken).where(EmailToken.token_hash == token_hash(body.token, st.settings.secret_key),
                                            EmailToken.kind == "verify"))
    if et is None or et.used_at is not None or et.expires_at < utcnow():
        raise api_error(400, "bad_token", "Ссылка недействительна или устарела")
    user = db.get(User, et.user_id)
    et.used_at = utcnow()
    if not user.is_verified:
        user.is_verified = True
        user.verified_at = utcnow()
        db.flush()
        ref = db.scalar(select(Referral).where(Referral.invitee_id == user.id))
        if ref:
            evaluate_referral(db, ref, st.store.all())
    db.commit()
    return {"ok": True, "message": "Email подтверждён! Добро пожаловать в Kiwion Chat 🥝"}


@router.post("/resend-verification", dependencies=[Depends(rate_limit("resend", 3, 600))])
def resend(request: Request, background: BackgroundTasks, user: User = Depends(current_user),
           db: DBSession = Depends(get_db)):
    st = state(request)
    if user.is_verified:
        return {"ok": True, "message": "Email уже подтверждён"}
    token = _issue_email_token(db, st, user, "verify", 48)
    db.commit()
    background.add_task(_send_mail_safe, st, st.mailer.send_verification, user.email, token)
    return {"ok": True, "message": "Письмо отправлено повторно"}


@router.post("/login", dependencies=[Depends(rate_limit("login", 20, 300))])
def login(body: LoginIn, request: Request, db: DBSession = Depends(get_db)):
    st = state(request)
    email = body.email.strip().lower()
    if st.limiter.count(f"login-fail:{email}", 900) >= 8:
        raise api_error(429, "locked", "Слишком много неудачных попыток. Попробуйте через 15 минут.")
    user = db.scalar(select(User).where(User.email == email))
    if not verify_password(user.password_hash if user else None, body.password):
        st.limiter.hit(f"login-fail:{email}", 1000, 900)
        raise api_error(401, "bad_credentials", "Неверный email или пароль")
    if user.is_banned:
        raise api_error(403, "banned", f"Аккаунт заблокирован. {user.ban_reason}".strip())
    if password_needs_rehash(user.password_hash):
        user.password_hash = hash_password(body.password)
    user.last_login_at = utcnow()
    db.add(DeviceSighting(device_id=body.device_id, user_id=user.id, ip=ip_of(request), event="login"))
    token, _ = create_session(db, st, user, request, body.device_id, body.device_name)
    db.commit()
    return {"token": token, "user": user_out(user, st.store.all(), db)}


@router.post("/logout")
def logout(sess: Session = Depends(current_session), db: DBSession = Depends(get_db)):
    db.delete(db.get(Session, sess.id))
    db.commit()
    return {"ok": True}


@router.post("/forgot", dependencies=[Depends(rate_limit("forgot", 5, 900))])
def forgot(body: ForgotIn, request: Request, background: BackgroundTasks, db: DBSession = Depends(get_db)):
    st = state(request)
    user = db.scalar(select(User).where(User.email == body.email.strip().lower()))
    if user and not user.is_banned:
        token = _issue_email_token(db, st, user, "reset", 1)
        db.commit()
        background.add_task(_send_mail_safe, st, st.mailer.send_reset, user.email, token)
    # Same answer whether the account exists or not (no user enumeration).
    return {"ok": True, "message": "Если аккаунт существует, мы отправили письмо со ссылкой"}


@router.post("/reset", dependencies=[Depends(rate_limit("reset", 10, 900))])
def reset(body: ResetIn, request: Request, db: DBSession = Depends(get_db)):
    st = state(request)
    et = db.scalar(select(EmailToken).where(EmailToken.token_hash == token_hash(body.token, st.settings.secret_key),
                                            EmailToken.kind == "reset"))
    if et is None or et.used_at is not None or et.expires_at < utcnow():
        raise api_error(400, "bad_token", "Ссылка недействительна или устарела")
    if err := validate_password_strength(body.new_password):
        raise api_error(400, "weak_password", err)
    user = db.get(User, et.user_id)
    user.password_hash = hash_password(body.new_password)
    et.used_at = utcnow()
    if not user.is_verified:  # the reset link proves mailbox ownership
        user.is_verified, user.verified_at = True, utcnow()
    db.query(Session).filter(Session.user_id == user.id).delete()
    db.commit()
    return {"ok": True, "message": "Пароль изменён. Войдите с новым паролем."}


def user_out(user: User, cfg: dict, db: DBSession | None = None) -> dict:
    from ..usage import chat_quota
    out = {
        "id": user.id, "email": user.email, "display_name": user.display_name, "role": user.role,
        "is_verified": user.is_verified, "created_at": user.created_at.isoformat() + "Z",
        "referral_code": user.referral_code, "bonus_tokens": user.bonus_tokens,
        "discount_percent": user.discount_percent, "theme": user.theme,
    }
    if db is not None:
        out["quota"] = chat_quota(db, user, cfg)
    return out
