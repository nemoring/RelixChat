import json

from conftest import register, solve_pow
from kiwion_backend.db import Referral, ReferralReward, User
from kiwion_backend.referrals import grant_rewards


def code_of(client, h):
    return client.get("/api/account/me", headers=h).json()["referral_code"]


def referral_for(client, email):
    with client.kiwion.db.SessionLocal() as s:
        u = s.query(User).filter_by(email=email).one()
        return s.query(Referral).filter_by(invitee_id=u.id).one()


def test_clean_referral_confirmed_and_rewarded(client):
    a = register(client, "ref@kiwion.dev", ip="10.1.1.1")
    b = register(client, "friend@kiwion.dev", ref=code_of(client, a), ip="10.9.9.9")
    r = referral_for(client, "friend@kiwion.dev")
    assert r.status == "confirmed", r.risk_reasons
    data = client.get("/api/account/referrals", headers=a).json()
    assert data["stats"]["confirmed"] == 1 and data["bonus_tokens"] == 15000 and data["discount_percent"] == 5
    assert data["invites"][0]["invitee"].startswith("f") and "*" in data["invites"][0]["invitee"]
    assert {w["kind"] for w in data["rewards"]} == {"bonus_tokens", "discount"}
    assert client.get("/api/account/me", headers=b).json()["bonus_tokens"] == 5000


def test_referral_waits_for_email_verification(client):
    a = register(client, "w1@kiwion.dev")
    register(client, "w2@kiwion.dev", ref=code_of(client, a), verify=False)
    assert referral_for(client, "w2@kiwion.dev").status == "pending"
    assert client.get("/api/account/me", headers=a).json()["bonus_tokens"] == 0


def test_shared_ip_alone_is_not_fraud(client):
    a = register(client, "home1@kiwion.dev", ip="203.0.113.5")
    register(client, "home2@kiwion.dev", ref=code_of(client, a), ip="203.0.113.5")
    r = referral_for(client, "home2@kiwion.dev")
    assert r.status == "confirmed"
    assert "same_ip_as_referrer" in json.loads(r.risk_reasons)


def test_same_device_goes_to_review_or_reject(client):
    a = register(client, "dev1@kiwion.dev", device="shared")
    # same device id as the referrer
    body = {"email": "dev2@kiwion.dev", "password": "kiwi12345", "device_id": "shareddev1",
            "referral_code": code_of(client, a), "pow": solve_pow(client)}
    assert client.post("/api/auth/register", json=body).status_code == 201
    from conftest import last_token
    client.post("/api/auth/verify", json={"token": last_token(client, "dev2@kiwion.dev")})
    r = referral_for(client, "dev2@kiwion.dev")
    assert r.status in ("review", "rejected")
    assert "same_device_as_referrer" in json.loads(r.risk_reasons)
    assert client.get("/api/account/me", headers=a).json()["bonus_tokens"] == 0


def test_rewards_cannot_be_granted_twice(client):
    a = register(client, "twice@kiwion.dev")
    register(client, "twice2@kiwion.dev", ref=code_of(client, a))
    cfg = client.kiwion.store.all()
    with client.kiwion.db.SessionLocal() as s:
        u = s.query(User).filter_by(email="twice2@kiwion.dev").one()
        ref = s.query(Referral).filter_by(invitee_id=u.id).one()
        grant_rewards(s, ref, cfg)
        grant_rewards(s, ref, cfg)
        s.commit()
        assert s.query(ReferralReward).filter_by(referral_id=ref.id).count() == 3
    assert client.get("/api/account/me", headers=a).json()["bonus_tokens"] == 15000


def test_velocity_limit(client):
    client.kiwion.store.update({"referral_max_confirmed_per_day": 2, "max_accounts_per_device": 10})
    a = register(client, "vel@kiwion.dev")
    code = code_of(client, a)
    for i in range(3):
        register(client, f"vel{i}@kiwion.dev", ref=code, ip=f"198.51.{i}.1")
    statuses = [referral_for(client, f"vel{i}@kiwion.dev").status for i in range(3)]
    assert statuses[:2] == ["confirmed", "confirmed"] and statuses[2] in ("review", "rejected")


def test_discount_is_capped(client):
    client.kiwion.store.update({"referral_discount_percent": 20, "referral_discount_cap": 30,
                                "referral_max_confirmed_per_day": 100})
    a = register(client, "cap@kiwion.dev")
    for i in range(3):
        register(client, f"cap{i}@kiwion.dev", ref=code_of(client, a), ip=f"192.0.{i}.7")
    assert client.get("/api/account/me", headers=a).json()["discount_percent"] == 30


def test_admin_can_approve_review(client):
    client.kiwion.store.update({"referral_review_threshold": 1, "referral_reject_threshold": 1000})
    admin = register(client, "admin@kiwion.dev")
    a = register(client, "rv@kiwion.dev", ip="10.0.0.1")
    register(client, "rv2@kiwion.dev", ref=code_of(client, a), ip="10.0.0.1")
    r = referral_for(client, "rv2@kiwion.dev")
    assert r.status == "review"
    res = client.post(f"/api/admin/referrals/{r.id}/decision", json={"approve": True}, headers=admin)
    assert res.json()["status"] == "confirmed"
    assert client.get("/api/account/me", headers=a).json()["bonus_tokens"] == 15000
