from conftest import last_token, register, solve_pow


def test_register_requires_pow(client):
    r = client.post("/api/auth/register", json={"email": "a@kiwion.dev", "password": "kiwi12345"})
    assert r.status_code == 400 and r.json()["detail"]["code"] == "bad_pow"


def test_pow_cannot_be_reused(client):
    pow_ = solve_pow(client)
    r1 = client.post("/api/auth/register", json={"email": "a1@kiwion.dev", "password": "kiwi12345", "pow": pow_})
    r2 = client.post("/api/auth/register", json={"email": "a2@kiwion.dev", "password": "kiwi12345", "pow": pow_})
    assert r1.status_code == 201 and r2.status_code == 400


def test_full_account_flow(client):
    h = register(client, "kiwi@kiwion.dev", verify=False)
    me = client.get("/api/account/me", headers=h).json()
    assert me["is_verified"] is False and me["referral_code"].startswith("KIWI")
    # chats need a verified email
    assert client.get("/api/chats", headers=h).json()["detail"]["code"] == "email_not_verified"
    assert client.post("/api/auth/verify", json={"token": last_token(client, "kiwi@kiwion.dev")}).status_code == 200
    assert client.get("/api/chats", headers=h).status_code == 200
    # verification link is single-use
    assert client.post("/api/auth/verify", json={"token": last_token(client, "kiwi@kiwion.dev")}).status_code == 400

    r = client.post("/api/auth/login", json={"email": "kiwi@kiwion.dev", "password": "kiwi12345", "device_name": "Phone"})
    assert r.status_code == 200
    h2 = {"Authorization": "Bearer " + r.json()["token"]}
    sessions = client.get("/api/account/sessions", headers=h).json()
    assert len(sessions) == 2
    other = next(s for s in sessions if not s["current"])
    assert client.delete(f"/api/account/sessions/{other['id']}", headers=h).status_code == 200
    assert client.get("/api/account/me", headers=h2).status_code == 401

    r = client.patch("/api/account/me", json={"display_name": "Fluffy", "theme": "dark"}, headers=h)
    assert r.json()["display_name"] == "Fluffy" and r.json()["theme"] == "dark"


def test_password_is_hashed_with_argon2(client):
    register(client, "hash@kiwion.dev")
    from kiwion_backend.db import User
    with client.kiwion.db.SessionLocal() as s:
        u = s.query(User).filter_by(email="hash@kiwion.dev").one()
        assert u.password_hash.startswith("$argon2id$") and "kiwi12345" not in u.password_hash


def test_login_errors_and_lockout(client):
    register(client, "lock@kiwion.dev")
    for _ in range(8):
        r = client.post("/api/auth/login", json={"email": "lock@kiwion.dev", "password": "wrong-pass1"})
        assert r.status_code == 401
    r = client.post("/api/auth/login", json={"email": "lock@kiwion.dev", "password": "kiwi12345"})
    assert r.status_code == 429 and r.json()["detail"]["code"] == "locked"


def test_password_reset_flow(client):
    h = register(client, "reset@kiwion.dev")
    r = client.post("/api/auth/forgot", json={"email": "reset@kiwion.dev"})
    assert r.status_code == 200
    # unknown e-mail gets the same answer (no enumeration)
    assert client.post("/api/auth/forgot", json={"email": "nobody@kiwion.dev"}).json() == r.json()
    token = last_token(client, "reset@kiwion.dev", kind="reset")
    assert client.post("/api/auth/reset", json={"token": token, "new_password": "short"}).status_code == 422
    assert client.post("/api/auth/reset", json={"token": token, "new_password": "newkiwi777"}).status_code == 200
    assert client.get("/api/account/me", headers=h).status_code == 401  # all sessions revoked
    assert client.post("/api/auth/login", json={"email": "reset@kiwion.dev", "password": "newkiwi777"}).status_code == 200


def test_duplicate_and_alias_emails_rejected(client):
    register(client, "john.doe@gmail.com", verify=False)
    body = {"email": "johndoe+spam@gmail.com", "password": "kiwi12345", "pow": solve_pow(client)}
    r = client.post("/api/auth/register", json=body)
    assert r.status_code == 409


def test_disposable_and_weak_password(client):
    r = client.post("/api/auth/register", json={"email": "x@mailinator.com", "password": "kiwi12345", "pow": solve_pow(client)})
    assert r.json()["detail"]["code"] == "disposable_email"
    r = client.post("/api/auth/register", json={"email": "x@kiwion.dev", "password": "onlyletters", "pow": solve_pow(client)})
    assert r.json()["detail"]["code"] == "weak_password"


def test_device_account_limit(client):
    for i in range(3):
        body = {"email": f"d{i}@kiwion.dev", "password": "kiwi12345", "device_id": "same-device", "pow": solve_pow(client)}
        assert client.post("/api/auth/register", json=body).status_code == 201
    body = {"email": "d9@kiwion.dev", "password": "kiwi12345", "device_id": "same-device", "pow": solve_pow(client)}
    r = client.post("/api/auth/register", json=body)
    assert r.status_code == 429 and r.json()["detail"]["code"] == "device_limit"


def test_delete_account(client):
    h = register(client, "del@kiwion.dev")
    chat = client.post("/api/chats", json={}, headers=h).json()
    assert client.post("/api/account/delete", json={"password": "bad", "confirm": "DELETE"}, headers=h).status_code == 400
    assert client.post("/api/account/delete", json={"password": "kiwi12345", "confirm": "DELETE"}, headers=h).status_code == 200
    assert client.get("/api/account/me", headers=h).status_code == 401
    from kiwion_backend.db import Chat
    with client.kiwion.db.SessionLocal() as s:
        assert s.get(Chat, chat["id"]) is None


def test_security_headers_and_sql_injection(client):
    r = client.get("/api/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    r = client.post("/api/auth/login", json={"email": "a@b.c' OR '1'='1", "password": "x"})
    assert r.status_code == 422
    r = client.post("/api/auth/login", json={"email": "admin@kiwion.dev", "password": "' OR 1=1 --"})
    assert r.status_code == 401
