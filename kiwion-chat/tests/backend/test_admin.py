from conftest import register


def test_regular_user_cannot_use_admin(client):
    h = register(client, "user@kiwion.dev")
    for method, path in [("get", "/api/admin/stats"), ("get", "/api/admin/users"), ("get", "/api/admin/settings"),
                         ("put", "/api/admin/settings"), ("get", "/api/admin/errors"), ("patch", "/api/admin/users/1")]:
        kwargs = {"json": {}} if method in ("put", "patch") else {}
        r = getattr(client, method)(path, headers=h, **kwargs)
        assert r.status_code == 403, (path, r.text)
    assert client.get("/api/admin/stats").status_code == 401


def test_admin_dashboard_and_controls(client):
    admin = register(client, "admin@kiwion.dev")
    u = register(client, "victim@kiwion.dev")
    stats = client.get("/api/admin/stats", headers=admin).json()
    assert stats["users_total"] == 2 and stats["inference"]["engine"] == "mock"
    users = client.get("/api/admin/users?q=victim", headers=admin).json()
    assert users["total"] == 1
    uid = users["users"][0]["id"]
    # limits
    r = client.patch(f"/api/admin/users/{uid}", json={"daily_token_limit": 123}, headers=admin)
    assert r.json()["daily_token_limit"] == 123
    assert client.get("/api/account/me", headers=u).json()["quota"]["daily_limit"] == 123
    # ban -> sessions revoked
    client.patch(f"/api/admin/users/{uid}", json={"is_banned": True, "ban_reason": "spam"}, headers=admin)
    assert client.get("/api/account/me", headers=u).status_code == 401
    r = client.post("/api/auth/login", json={"email": "victim@kiwion.dev", "password": "kiwi12345"})
    assert r.status_code == 403 and "spam" in r.json()["detail"]["message"]
    # settings / availability
    s = client.put("/api/admin/settings", json={"registration_open": False}, headers=admin).json()
    assert s["registration_open"] is False
    assert client.put("/api/admin/settings", json={"bogus": 1}, headers=admin).status_code == 400
    assert client.put("/api/admin/settings", json={"free_daily_tokens": "lots"}, headers=admin).status_code == 400
    assert client.get("/api/config/public").json()["registration_open"] is False
    audit = client.get("/api/admin/audit", headers=admin).json()
    assert {a["action"] for a in audit} >= {"user.update", "settings.update"}
    # admin cannot lock themselves out
    me = client.get("/api/account/me", headers=admin).json()
    assert client.patch(f"/api/admin/users/{me['id']}", json={"is_banned": True}, headers=admin).status_code == 400


def test_errors_are_logged_without_secrets(client):
    admin = register(client, "admin@kiwion.dev")
    from kiwion_backend.deps import log_error
    log_error(client.kiwion, 'boom Authorization: Bearer kws_abcdefghijklmnop password="hunter22" key kw-1234567890abc')
    errs = client.get("/api/admin/errors", headers=admin).json()
    msg = errs[0]["message"]
    assert "kws_abcdefghijklmnop" not in msg and "hunter22" not in msg and "kw-1234567890abc" not in msg
    assert "[REDACTED]" in msg
