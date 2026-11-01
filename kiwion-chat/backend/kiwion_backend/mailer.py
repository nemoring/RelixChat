"""Outgoing e-mail. smtp in production; file/console modes for development and tests."""
from __future__ import annotations

import logging
import smtplib
import ssl
import time
from email.message import EmailMessage
from pathlib import Path

from .config import Settings

log = logging.getLogger("kiwion.mail")


class Mailer:
    def __init__(self, settings: Settings):
        self.s = settings

    def send(self, to: str, subject: str, text: str, html: str | None = None) -> None:
        msg = EmailMessage()
        msg["From"] = self.s.mail_from
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        if html:
            msg.add_alternative(html, subtype="html")
        mode = self.s.mail_mode
        try:
            if mode == "smtp":
                ctx = ssl.create_default_context()
                if self.s.smtp_port == 465:
                    with smtplib.SMTP_SSL(self.s.smtp_host, self.s.smtp_port, context=ctx, timeout=20) as smtp:
                        self._login_send(smtp, msg)
                else:
                    with smtplib.SMTP(self.s.smtp_host, self.s.smtp_port, timeout=20) as smtp:
                        if self.s.smtp_starttls:
                            smtp.starttls(context=ctx)
                        self._login_send(smtp, msg)
            elif mode == "file":
                out = Path(self.s.outbox_dir)
                out.mkdir(parents=True, exist_ok=True)
                safe_to = "".join(c if c.isalnum() or c in "@.-_" else "_" for c in to)
                (out / f"{time.time_ns()}_{safe_to}.eml").write_bytes(bytes(msg))
                log.info("mail to %s stored in outbox (%s)", to, subject)
            else:
                log.info("MAIL to=%s subject=%s\n%s", to, subject, text)
        except Exception as e:  # never break signup because SMTP is down; it is logged
            log.error("failed to send mail to %s: %s", to, e)
            raise

    def _login_send(self, smtp, msg):
        if self.s.smtp_user:
            smtp.login(self.s.smtp_user, self.s.smtp_password)
        smtp.send_message(msg)

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
                  f"Здравствуйте!\n\nПодтвердите адрес для Kiwion Chat: {link}\n\nСсылка действует 48 часов.\nКод подтверждения: {token}\n",
                  self._wrap("Подтверждение email", "Нажмите кнопку, чтобы подтвердить адрес. Ссылка действует 48 часов.",
                             link, "Подтвердить email"))

    def send_reset(self, to: str, token: str) -> None:
        link = f"{self.s.public_url}/#/reset?token={token}"
        self.send(to, "Восстановление пароля — Kiwion Chat",
                  f"Чтобы задать новый пароль, откройте: {link}\n\nСсылка действует 1 час.\nКод: {token}\n",
                  self._wrap("Восстановление пароля", "Ссылка для смены пароля действует 1 час.", link, "Задать новый пароль"))
