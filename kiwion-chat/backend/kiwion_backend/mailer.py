"""Outgoing e-mail.

The SMTP settings come from the admin panel ("Почта") when configured there, otherwise from .env.
Modes: smtp (real delivery), file (writes .eml to data/outbox — development), console (log only).
Every message is recorded in mail_logs (recipient masked) so admins can see delivery problems.
"""
from __future__ import annotations

import logging
import smtplib
import socket
import ssl
import time
from dataclasses import dataclass
from email.message import EmailMessage
from email.utils import parseaddr
from pathlib import Path

from .config import Settings

log = logging.getLogger("kiwion.mail")


@dataclass
class MailConfig:
    mode: str            # smtp | file | console
    host: str
    port: int
    security: str        # ssl | starttls | none
    user: str
    password: str
    sender: str
    source: str          # admin | env


PRESETS = {
    "gmail": {"smtp_host": "smtp.gmail.com", "smtp_port": 465, "smtp_security": "ssl",
              "hint": "Нужна двухэтапная проверка и «пароль приложения» (myaccount.google.com/apppasswords). Отправитель = ваш адрес Gmail. Лимит ≈ 500 писем в сутки."},
    "yandex": {"smtp_host": "smtp.yandex.ru", "smtp_port": 465, "smtp_security": "ssl",
               "hint": "Создайте пароль приложения в Яндекс ID → Безопасность и включите доступ почтовых программ. Отправитель = ваш адрес Яндекса."},
    "mailru": {"smtp_host": "smtp.mail.ru", "smtp_port": 465, "smtp_security": "ssl",
               "hint": "Нужен пароль для внешнего приложения (настройки безопасности Mail.ru). Отправитель = ваш адрес Mail.ru."},
}


def mask(addr: str) -> str:
    local, _, domain = addr.partition("@")
    return (local[:1] + "***" + local[-1:] if len(local) > 2 else local[:1] + "***") + "@" + domain


class Mailer:
    def __init__(self, settings: Settings, store=None, session_factory=None):
        self.s = settings
        self.store = store
        self.sf = session_factory

    def config(self) -> MailConfig:
        if self.store is not None:
            c = self.store.all()
            if c.get("mail_mode"):
                return MailConfig(mode=c["mail_mode"], host=c["smtp_host"], port=int(c["smtp_port"]),
                                  security=c["smtp_security"], user=c["smtp_user"],
                                  password=self.store.get_secret("smtp_password"),
                                  sender=c["mail_from"] or c["smtp_user"], source="admin")
        security = "ssl" if self.s.smtp_port == 465 else ("starttls" if self.s.smtp_starttls else "none")
        return MailConfig(mode=self.s.mail_mode, host=self.s.smtp_host, port=self.s.smtp_port, security=security,
                          user=self.s.smtp_user, password=self.s.smtp_password, sender=self.s.mail_from, source="env")

    def _record(self, to: str, subject: str, status: str, error: str = "") -> None:
        if self.sf is None:
            return
        try:
            from .db import MailLog
            with self.sf() as s:
                s.add(MailLog(to_masked=mask(to), subject=subject[:200], status=status, error=error[:1000]))
                s.commit()
        except Exception:  # pragma: no cover - logging must never break sending
            log.exception("failed to record mail log")

    @staticmethod
    def _connect(cfg: MailConfig, timeout: float = 20):
        ctx = ssl.create_default_context()
        if cfg.security == "ssl":
            return smtplib.SMTP_SSL(cfg.host, cfg.port, context=ctx, timeout=timeout)
        smtp = smtplib.SMTP(cfg.host, cfg.port, timeout=timeout)
        if cfg.security == "starttls":
            smtp.starttls(context=ctx)
        return smtp

    def send(self, to: str, subject: str, text: str, html: str | None = None) -> None:
        cfg = self.config()
        msg = EmailMessage()
        msg["From"] = cfg.sender or self.s.mail_from
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        if html:
            msg.add_alternative(html, subtype="html")
        try:
            if cfg.mode == "smtp":
                if not cfg.host:
                    raise RuntimeError("SMTP не настроен: укажите сервер в админ-панели → Почта")
                with self._connect(cfg) as smtp:
                    if cfg.user:
                        smtp.login(cfg.user, cfg.password)
                    smtp.send_message(msg)
                self._record(to, subject, "sent")
                log.info("mail sent to %s (%s)", mask(to), subject)
            elif cfg.mode == "file":
                out = Path(self.s.outbox_dir)
                out.mkdir(parents=True, exist_ok=True)
                safe_to = "".join(c if c.isalnum() or c in "@.-_" else "_" for c in to)
                (out / f"{time.time_ns()}_{safe_to}.eml").write_bytes(bytes(msg))
                self._record(to, subject, "stored")
                log.info("mail to %s stored in outbox (%s)", to, subject)
            else:
                self._record(to, subject, "logged")
                log.info("MAIL to=%s subject=%s\n%s", to, subject, text)
        except Exception as e:
            self._record(to, subject, "failed", f"{type(e).__name__}: {e}")
            log.error("failed to send mail to %s: %s", mask(to), e)
            raise

    # --- diagnostics for the admin panel -------------------------------------
    def check(self) -> list[dict]:
        """Step-by-step SMTP diagnostics with human hints (DNS → TCP → TLS → login)."""
        cfg = self.config()
        steps: list[dict] = []

        def step(name, ok, msg, hint=""):
            steps.append({"step": name, "ok": ok, "message": msg, "hint": hint})
            return ok

        if cfg.mode != "smtp":
            step("Режим", False, f"Сейчас режим «{cfg.mode}»: письма не уходят на почту",
                 "Выберите режим SMTP и сохраните настройки.")
            return steps
        if not cfg.host:
            step("Сервер", False, "Не указан SMTP-сервер", "Выберите шаблон (Gmail/Яндекс) или впишите сервер.")
            return steps
        try:
            ip = socket.gethostbyname(cfg.host)
            step("DNS", True, f"{cfg.host} → {ip}")
        except OSError as e:
            step("DNS", False, f"Имя {cfg.host} не найдено: {e}", "Проверьте адрес SMTP-сервера.")
            return steps
        try:
            with socket.create_connection((cfg.host, cfg.port), timeout=8):
                pass
            step("Порт", True, f"Порт {cfg.port} доступен")
        except OSError as e:
            other = 587 if cfg.port == 465 else 465
            step("Порт", False, f"Нет соединения с {cfg.host}:{cfg.port} ({type(e).__name__})",
                 f"Скорее всего, хостинг блокирует исходящий порт {cfg.port}. Попробуйте порт {other} "
                 f"или попросите поддержку хостинга открыть исходящие порты 465/587.")
            return steps
        try:
            with self._connect(cfg, timeout=15) as smtp:
                step("TLS", True, "Защищённое соединение установлено" if cfg.security != "none" else "Соединение без шифрования")
                if cfg.user:
                    try:
                        smtp.login(cfg.user, cfg.password)
                        step("Вход", True, f"Вход как {cfg.user} выполнен")
                    except smtplib.SMTPAuthenticationError as e:
                        step("Вход", False, f"Сервер отклонил логин/пароль ({e.smtp_code})",
                             "Нужен «пароль приложения», а не обычный пароль от почты. Проверьте, что логин — полный адрес.")
                        return steps
                else:
                    step("Вход", True, "Без авторизации")
        except (ssl.SSLError, smtplib.SMTPException, OSError) as e:
            hint = "Для порта 465 выберите SSL, для 587 — STARTTLS." if isinstance(e, (ssl.SSLError, smtplib.SMTPServerDisconnected)) else ""
            step("TLS", False, f"Ошибка соединения: {type(e).__name__}: {e}", hint)
            return steps
        sender = parseaddr(cfg.sender)[1]
        if cfg.user and sender and sender.lower() != cfg.user.lower():
            step("Отправитель", True, f"Отправитель {sender} отличается от логина",
                 "Gmail и Яндекс заменят отправителя на адрес логина — лучше указать тот же адрес.")
        return steps

    # --- templates -------------------------------------------------------
    def _wrap(self, title: str, body: str, link: str, button: str) -> str:
        return f"""<!doctype html><html><body style="font-family:system-ui,sans-serif;background:#f3f7ef;padding:24px">
<div style="max-width:520px;margin:auto;background:#fff;border-radius:16px;padding:28px">
<h2 style="color:#2f7d32;margin-top:0">🥝 Kiwion Chat</h2><h3>{title}</h3><p>{body}</p>
<p><a href="{link}" style="display:inline-block;background:#4caf50;color:#fff;padding:12px 20px;border-radius:12px;text-decoration:none">{button}</a></p>
<p style="color:#777;font-size:12px">Если кнопка не работает, откройте ссылку: {link}<br>Если вы не запрашивали это письмо — просто проигнорируйте его.</p>
<p style="color:#777;font-size:12px">Kiwion Chat · Kiwi_Fuzzy</p></div></body></html>"""

    def send_verification(self, to: str, token: str) -> None:
        link = f"{self.s.public_url}/#/verify?token={token}"
        self.send(to, "Подтвердите email — Kiwion Chat",
                  f"Здравствуйте!\n\nПодтвердите адрес для Kiwion Chat: {link}\n\nСсылка действует 48 часов.\n"
                  f"Код подтверждения (для приложения): {token}\n",
                  self._wrap("Подтверждение email", "Нажмите кнопку, чтобы подтвердить адрес. Ссылка действует 48 часов."
                             f"<br><br>Код для приложения:<br><b style='font-family:monospace;font-size:15px'>{token}</b>",
                             link, "Подтвердить email"))

    def send_reset(self, to: str, token: str) -> None:
        link = f"{self.s.public_url}/#/reset?token={token}"
        self.send(to, "Восстановление пароля — Kiwion Chat",
                  f"Чтобы задать новый пароль, откройте: {link}\n\nСсылка действует 1 час.\nКод: {token}\n",
                  self._wrap("Восстановление пароля", "Ссылка для смены пароля действует 1 час."
                             f"<br><br>Код для приложения:<br><b style='font-family:monospace;font-size:15px'>{token}</b>",
                             link, "Задать новый пароль"))

    def send_test(self, to: str) -> None:
        self.send(to, "Тестовое письмо — Kiwion Chat",
                  "Если вы читаете это письмо, отправка почты из Kiwion Chat настроена правильно 🥝\n",
                  self._wrap("Почта работает!", "Если вы читаете это письмо, отправка почты из Kiwion Chat настроена правильно 🥝",
                             self.s.public_url, "Открыть Kiwion Chat"))
