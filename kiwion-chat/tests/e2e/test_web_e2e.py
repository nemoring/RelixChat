"""Browser end-to-end test of the main user journey (Playwright + Chromium).

Starts a real backend and a real inference service (mock engine, so it runs
without model weights) as subprocesses and drives the web UI:
splash → register (proof-of-work) → e-mail verification link → chat streaming →
stop → regenerate → rename → settings → API key → referral → easter egg → logout.
Set KIWION_E2E_SHOTS=/some/dir to save screenshots.
"""
import email
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

import httpx
import pytest

pw = pytest.importorskip("playwright.sync_api")
ROOT = Path(__file__).resolve().parents[2]


def launch(p):
    exe = os.getenv("KIWION_CHROMIUM") or ("/opt/pw-browsers/chromium" if Path("/opt/pw-browsers/chromium").exists() else None)
    try:
        return p.chromium.launch()
    except Exception:
        if not exe:
            raise
        return p.chromium.launch(executable_path=exe, args=["--no-sandbox"])


def wait_js(page, expr, timeout=10):
    """Poll a JS expression (wait_for_function needs eval, which our CSP forbids)."""
    end = time.time() + timeout
    while time.time() < end:
        if page.evaluate(expr):
            return
        page.wait_for_timeout(100)
    raise AssertionError(f"timeout waiting for {expr}")


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


@pytest.fixture(scope="module")
def server(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("e2e")
    bport, iport = free_port(), free_port()
    env = {**os.environ, "KIWION_INFERENCE_SECRET": "e" * 64, "KIWION_ENGINE": "mock", "KIWION_MOCK_DELAY": "0.06",
           "KIWION_INFERENCE_PORT": str(iport), "KIWION_INFERENCE_URL": f"http://127.0.0.1:{iport}",
           "KIWION_PORT": str(bport), "KIWION_PUBLIC_URL": f"http://127.0.0.1:{bport}",
           "KIWION_DATABASE_URL": f"sqlite:///{tmp / 'db.sqlite'}", "KIWION_OUTBOX_DIR": str(tmp / "outbox"),
           "KIWION_POW_DIFFICULTY": "10", "KIWION_ADMIN_EMAILS": "boss@kiwion.dev", "KIWION_LOG_DIR": str(tmp), "KIWION_SECRET_KEY": "q" * 48,
           "PYTHONPATH": os.pathsep.join(str(ROOT / d) for d in ("shared", "backend", "inference", "cli"))}
    procs = [subprocess.Popen([sys.executable, "-m", m], env=env, cwd=ROOT, stdout=open(tmp / f"{m}.log", "wb"),
                              stderr=subprocess.STDOUT) for m in ("kiwion_inference", "kiwion_backend")]
    base = f"http://127.0.0.1:{bport}"
    for _ in range(100):
        try:
            if httpx.get(base + "/api/model/status", timeout=1).json()["state"] == "online":
                break
        except Exception:
            pass
        time.sleep(0.2)
    yield {"base": base, "outbox": tmp / "outbox"}
    for p in procs:
        p.terminate()
        p.wait(10)


def verify_link(outbox: Path, addr: str) -> str:
    for _ in range(50):
        files = sorted(outbox.glob(f"*_{addr}.eml"))
        if files:
            msg = email.message_from_bytes(files[-1].read_bytes())
            text = next(p.get_payload(decode=True).decode() for p in msg.walk() if p.get_content_type() == "text/plain")
            return re.search(r"(http\S+#/verify\?token=\S+)", text).group(1)
        time.sleep(0.1)
    raise AssertionError("verification mail not found")


def test_main_user_journey(server):
    shots = os.getenv("KIWION_E2E_SHOTS")
    shot = (lambda page, name: page.screenshot(path=f"{shots}/{name}.png")) if shots else (lambda *a: None)
    with pw.sync_playwright() as p:
        browser = launch(p)
        page = browser.new_page(viewport={"width": 1280, "height": 820})
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(server["base"] + "/?ref=NOPE#/register")
        page.wait_for_selector("#f")
        shot(page, "01-register")
        page.fill("#name", "Kiwi Tester")
        page.fill("#email", "e2e@kiwion.dev")
        page.fill("#pw", "kiwi12345")
        page.click("button[type=submit]")
        page.wait_for_url("**#/verify-pending")
        shot(page, "02-verify-pending")
        page.goto(verify_link(server["outbox"], "e2e@kiwion.dev"))
        page.wait_for_selector("#composer", timeout=15000)
        shot(page, "03-empty-chat")
        page.wait_for_selector("#model-pill.ok")

        # streaming answer with markdown + code highlighting
        page.fill("#input", "Привет, киви!")
        page.keyboard.press("Enter")
        page.wait_for_selector(".msg.user >> text=Привет, киви!")
        page.wait_for_selector(".msg.assistant pre code.hljs", timeout=15000)
        page.wait_for_selector("#send[aria-label='Отправить']", timeout=15000)
        shot(page, "04-answer")
        assert "Привет, киви!" in page.inner_text(".msg.assistant .md")
        assert page.inner_text(".msg.assistant .ai-note") == "Kiwion — это ИИ, и он может ошибаться"
        assert "может ошибаться" not in page.inner_text(".msg.assistant .md")   # not part of the answer text
        assert page.locator(".chat-item.active .title").inner_text() == "Привет, киви!"

        # stop generation keeps the partial answer
        page.fill("#input", "длинный ответ " * 30)
        page.keyboard.press("Enter")
        page.wait_for_selector("#send[aria-label='Остановить']")
        page.wait_for_timeout(500)
        page.click("#send")
        page.wait_for_selector(".status-note >> text=Генерация остановлена", timeout=10000)

        # regenerate the last answer
        page.click(".msg.last [data-act=regen]")
        page.wait_for_selector("#send[aria-label='Остановить']")
        page.wait_for_selector("#send[aria-label='Отправить']", timeout=20000)
        assert page.locator(".msg").count() == 4

        # history survives a reload (auto-restore) and the draft is kept
        page.fill("#input", "черновик сообщения")
        page.reload()
        page.wait_for_selector(".msg.assistant")
        assert page.locator(".msg").count() == 4
        assert page.input_value("#input") == "черновик сообщения"

        # settings: api key, referrals, theme, easter egg
        page.goto(server["base"] + "/#/settings/api")
        page.fill("#kname", "e2e key")
        page.click("#kcreate")
        key = page.inner_text("#newkey .keybox")
        assert key.startswith("kw-")
        r = httpx.post(server["base"] + "/v1/chat/completions", headers={"Authorization": f"Bearer {key}"},
                       json={"messages": [{"role": "user", "content": "api works"}]}, timeout=30)
        assert "api works" in r.json()["choices"][0]["message"]["content"]
        shot(page, "05-api-keys")
        page.goto(server["base"] + "/#/settings/referrals")
        page.wait_for_selector("#reflink")
        assert "ref=KIWI" in page.inner_text("#reflink")
        page.goto(server["base"] + "/#/settings/appearance")
        page.click("[data-theme=dark]")
        assert page.evaluate("document.documentElement.dataset.theme") == "dark"
        page.goto(server["base"] + "/#/settings/about")
        row = page.locator("#version-row")
        for _ in range(4):
            row.click()
        assert page.locator(".kiwi-egg").count() == 0          # 4 taps are not enough
        page.wait_for_timeout(1700)                            # pause > 1.5 s resets the counter
        for _ in range(4):
            row.click()
        assert page.locator(".kiwi-egg").count() == 0
        row.click()                                            # 5th quick tap
        page.wait_for_selector(".kiwi-egg .egg-title")
        page.wait_for_selector(".kiwi-egg .egg-pet.show", timeout=15000)
        shot(page, "06-easter-egg")
        page.click(".egg-pet")
        wait_js(page, "() => getComputedStyle(document.querySelector('.egg-happy')).opacity > 0.9")
        shot(page, "07-kiwi-happy")
        page.click(".egg-close")
        assert page.locator(".kiwi-egg").count() == 0
        row.click()                                            # UI not blocked after closing; works again
        for _ in range(4):
            row.click()
        page.wait_for_selector(".kiwi-egg")
        page.keyboard.press("Escape")
        assert page.locator(".kiwi-egg").count() == 0

        # mobile layout
        page.set_viewport_size({"width": 390, "height": 800})
        page.goto(server["base"] + "/#/chat")
        page.wait_for_selector(".msg.assistant")
        shot(page, "08-mobile")
        page.click("#menu")
        page.wait_for_selector(".app.nav-open")

        page.goto(server["base"] + "/launch")
        wait_js(page, "() => document.getElementById('s').textContent !== '--'")
        shot(page, "09-launch")
        browser.close()
        assert not errors, errors


def test_overload_message_and_text_preserved(server):
    """Saturate the queue directly on the inference node, then send from the UI."""
    with pw.sync_playwright() as p:
        browser = launch(p)
        page = browser.new_page()
        page.route("**/api/chats/*/messages", lambda route: route.fulfill(
            status=503, content_type="application/json",
            body='{"detail":{"code":"overloaded","message":"busy"}}'))
        page.goto(server["base"] + "/#/login")
        page.fill("#email", "e2e@kiwion.dev")
        page.fill("#pw", "kiwi12345")
        page.click("button[type=submit]")
        page.wait_for_selector("#composer")
        page.goto(server["base"] + "/#/chat")
        page.wait_for_selector("#composer")
        page.fill("#input", "мой важный вопрос")
        page.keyboard.press("Enter")
        page.wait_for_selector(".toast >> text=Птичка киви немного устала")
        assert page.input_value("#input") == "мой важный вопрос"
        browser.close()


def test_admin_panel(server):
    from kiwion_backend.security import ProofOfWork
    base = server["base"]
    ch = httpx.get(base + "/api/auth/challenge").json()
    r = httpx.post(base + "/api/auth/register", json={"email": "boss@kiwion.dev", "password": "kiwi12345",
                   "pow": {"challenge": ch["challenge"], "nonce": ProofOfWork.solve(ch["challenge"], ch["difficulty"])}})
    assert r.status_code == 201
    httpx.post(base + "/api/auth/verify", json={"token": re.search(r"token=(\S+)", verify_link(server["outbox"], "boss@kiwion.dev")).group(1)})
    shots = os.getenv("KIWION_E2E_SHOTS")
    with pw.sync_playwright() as p:
        browser = launch(p)
        page = browser.new_page(viewport={"width": 1280, "height": 860})
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        # a regular user is refused
        page.goto(base + "/admin/")
        page.fill("#email", "e2e@kiwion.dev"); page.fill("#pw", "kiwi12345"); page.click("button[type=submit]")
        page.wait_for_selector("text=нет прав администратора")
        page.fill("#email", "boss@kiwion.dev"); page.fill("#pw", "kiwi12345"); page.click("button[type=submit]")
        page.wait_for_selector("h1 >> text=Обзор")
        if shots:
            page.screenshot(path=f"{shots}/10-admin.png")
        for hash_, title in [("inference", "Модель и очередь"), ("users", "Пользователи"), ("referrals", "Рефералы"),
                             ("settings", "Лимиты и доступность"), ("mail", "Почта"), ("errors", "Системные ошибки"),
                             ("audit", "Журнал")]:
            page.goto(f"{base}/admin/#/{hash_}")
            page.wait_for_selector(f"h1 >> text={title}")
        # mail page: Gmail preset, save, diagnostics, test mail in file mode
        page.goto(f"{base}/admin/#/mail")
        page.wait_for_selector("#mf")
        page.click("[data-preset=gmail]")
        assert page.input_value("[name=host]") == "smtp.gmail.com" and page.input_value("[name=port]") == "465"
        assert "пароль приложения" in page.inner_text("#phint")
        page.fill("[name=user]", "kiwion.bot@gmail.com")
        page.fill("[name=password]", "abcd efgh ijkl mnop")
        assert page.input_value("[name=sender]") == "Kiwion Chat <kiwion.bot@gmail.com>"   # follows the login
        page.click("#mf button[type=submit]")
        page.wait_for_selector("[name=password][placeholder^='сохранён']")
        assert page.input_value("[name=sender]") == "Kiwion Chat <kiwion.bot@gmail.com>"
        if shots:
            page.screenshot(path=f"{shots}/11-admin-mail.png", full_page=True)
        page.select_option("[name=mode]", "file")
        page.click("#mf button[type=submit]")
        page.wait_for_selector(".notice.warn >> text=не уходят на почту")   # page re-rendered in file mode
        page.fill("#mto", "boss@kiwion.dev")
        page.click("#mtest")
        page.wait_for_selector("#mres >> text=Режим «файл»")
        page.goto(f"{base}/admin/#/users")
        page.wait_for_selector("h1 >> text=Пользователи")

        page.goto(f"{base}/admin/#/settings")
        page.wait_for_selector("[name=registration_open]")
        assert page.locator("[name=smtp_host]").count() == 0     # mail settings live on their own page
        assert "LANGUAGE RULES" in page.input_value("[name=system_prompt]")      # editable system prompt
        page.uncheck("[name=registration_open]")
        page.click("#sf button[type=submit]")
        page.wait_for_selector(".toast >> text=Настройки сохранены")
        assert httpx.get(base + "/api/config/public").json()["registration_open"] is False
        page.check("[name=registration_open]")
        page.click("#sf button[type=submit]")
        page.wait_for_timeout(300)
        browser.close()
        assert not errors, errors
