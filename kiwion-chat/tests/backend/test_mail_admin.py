"""Admin "Почта" page: SMTP settings in the DB, encrypted password, diagnostics, test mail, resend codes."""
import base64
import socket
import socketserver
import threading

import pytest

from conftest import register, solve_pow
from kiwion_backend.db import MailLog, Setting


class FakeSMTP(socketserver.StreamRequestHandler):
    """Minimal SMTP server: EHLO, AUTH PLAIN, MAIL/RCPT/DATA. Stores delivered messages."""
    inbox: list = []
    password = "app-password-123"

    def w(self, line):
        self.wfile.write((line + "\r\n").encode())

    def handle(self):
        self.w("220 fake.smtp ready")
        authed = False
        rcpt, data_mode, buf = [], False, []
        for raw in self.rfile:
            line = raw.decode().rstrip("\r\n")
            if data_mode:
                if line == ".":
                    FakeSMTP.inbox.append({"rcpt": rcpt, "data": "\n".join(buf)})
                    data_mode, buf = False, []
                    self.w("250 queued")
                else:
                    buf.append(line)
                continue
            cmd = line.split(" ")[0].upper()
            if cmd in ("EHLO", "HELO"):
                self.w("250-fake.smtp")
                self.w("250 AUTH PLAIN")
            elif cmd == "AUTH":
                creds = base64.b64decode(line.split(" ")[2]).split(b"\0")
                if creds[-1].decode() == FakeSMTP.password:
                    authed = True
                    self.w("235 ok")
                else:
                    self.w("535 bad credentials")
            elif cmd == "MAIL":
                self.w("250 ok" if authed else "530 auth required")
            elif cmd == "RCPT":
                rcpt.append(line.split(":", 1)[1].strip("<> "))
                self.w("250 ok")
            elif cmd == "DATA":
                data_mode = True
                self.w("354 go")
            elif cmd == "QUIT":
                self.w("221 bye")
                return
            else:
                self.w("250 ok")


@pytest.fixture
def smtp_server():
    FakeSMTP.inbox = []
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), FakeSMTP)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield srv.server_address[1]
    srv.shutdown()
    srv.server_close()


def configure(client, admin, port, password="app-password-123", **extra):
    body = {"mode": "smtp", "host": "127.0.0.1", "port": port, "security": "none",
            "user": "kiwi@kiwion.dev", "sender": "Kiwion Chat <kiwi@kiwion.dev>", "password": password, **extra}
    r = client.put("/api/admin/mail", json=body, headers=admin)
    assert r.status_code == 200, r.text
    return r.json()


def test_mail_settings_password_is_encrypted_and_never_returned(client, smtp_server):
    admin = register(client, "admin@kiwion.dev")
    state = configure(client, admin, smtp_server)
    assert state["config"]["source"] == "admin" and state["config"]["has_password"] is True
    assert "app-password-123" not in client.get("/api/admin/mail", headers=admin).text
    with client.kiwion.db.SessionLocal() as s:
        raw = " ".join(r.value for r in s.query(Setting).all())
    assert "app-password-123" not in raw     # stored encrypted
    # keeping the password: omitted field does not erase it
    state = configure(client, admin, smtp_server, password=None)
    assert state["config"]["has_password"] is True


def test_check_and_test_mail_and_signup_codes_go_through_admin_smtp(client, smtp_server):
    admin = register(client, "admin@kiwion.dev")
    configure(client, admin, smtp_server)
    chk = client.post("/api/admin/mail/check", headers=admin).json()
    assert chk["ok"], chk
    assert [s["step"] for s in chk["steps"]][:4] == ["DNS", "Порт", "TLS", "Вход"]

    r = client.post("/api/admin/mail/test", json={"to": "me@kiwion.dev"}, headers=admin).json()
    assert r["ok"], r
    assert FakeSMTP.inbox[-1]["rcpt"] == ["me@kiwion.dev"]

    # a new user's verification code is delivered by the SMTP configured in the admin panel
    body = {"email": "newbie@kiwion.dev", "password": "kiwi12345", "pow": solve_pow(client)}
    assert client.post("/api/auth/register", json=body).status_code == 201
    assert any(m["rcpt"] == ["newbie@kiwion.dev"] for m in FakeSMTP.inbox)

    log = client.get("/api/admin/mail", headers=admin).json()["log"]
    assert log[0]["status"] == "sent" and log[0]["to"].startswith("n***")   # recipient masked

    # admin can resend the code to an unverified user
    uid = client.get("/api/admin/users?q=newbie", headers=admin).json()["users"][0]["id"]
    n = len(FakeSMTP.inbox)
    r = client.post(f"/api/admin/users/{uid}/resend-verification", headers=admin).json()
    assert r["ok"] and len(FakeSMTP.inbox) == n + 1


def test_check_explains_wrong_password_and_blocked_port(client, smtp_server):
    admin = register(client, "admin@kiwion.dev")
    configure(client, admin, smtp_server, password="wrong")
    chk = client.post("/api/admin/mail/check", headers=admin).json()
    assert not chk["ok"] and chk["steps"][-1]["step"] == "Вход" and "пароль приложения" in chk["steps"][-1]["hint"]
    r = client.post("/api/admin/mail/test", json={"to": "me@kiwion.dev"}, headers=admin).json()
    assert r["ok"] is False
    with client.kiwion.db.SessionLocal() as s:
        assert s.query(MailLog).filter_by(status="failed").count() >= 1

    s_ = socket.socket(); s_.bind(("127.0.0.1", 0)); closed = s_.getsockname()[1]; s_.close()
    configure(client, admin, closed)
    chk = client.post("/api/admin/mail/check", headers=admin).json()
    port_step = next(s for s in chk["steps"] if s["step"] == "Порт")
    assert port_step["ok"] is False and "хостинг" in port_step["hint"]


def test_mail_admin_requires_admin(client):
    u = register(client, "plain@kiwion.dev")
    for m, path in [("get", "/api/admin/mail"), ("post", "/api/admin/mail/check"), ("post", "/api/admin/mail/test")]:
        assert getattr(client, m)(path, headers=u, **({"json": {"to": "a@kiwion.dev"}} if m == "post" else {})).status_code == 403
    assert client.put("/api/admin/mail", json={"mode": "smtp", "host": "x"}, headers=u).status_code == 403


def test_env_mode_switch_back(client, smtp_server):
    admin = register(client, "admin@kiwion.dev")
    configure(client, admin, smtp_server)
    st = client.put("/api/admin/mail", json={"mode": "env"}, headers=admin).json()
    assert st["config"]["source"] == "env" and st["config"]["mode"] == "file"
