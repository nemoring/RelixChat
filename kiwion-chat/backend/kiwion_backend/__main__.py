"""Run: python -m kiwion_backend [serve|create-admin|init-db]"""
from __future__ import annotations

import argparse
import getpass
import logging
import sys

from kiwion_shared.redact import install_redaction


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="kiwion-backend")
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("serve", help="run the API server (default)")
    sub.add_parser("init-db", help="create database tables")
    ca = sub.add_parser("create-admin", help="create or promote an admin account")
    ca.add_argument("--email", required=True)
    ca.add_argument("--password", help="omit to be prompted (recommended)")
    args = p.parse_args(argv)

    from .config import get_settings
    s = get_settings()
    logging.basicConfig(level=s.log_level, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    install_redaction()

    if args.cmd == "init-db":
        from .db import Database
        Database(s.database_url).create_all()
        print("database ready")
        return
    if args.cmd == "create-admin":
        _create_admin(s, args.email, args.password)
        return
    import uvicorn
    from .app import create_app
    uvicorn.run(create_app(s), host=s.host, port=s.port, proxy_headers=bool(s.trusted_proxies),
                forwarded_allow_ips=",".join(s.trusted_proxies) or None, access_log=False)


def _create_admin(s, email: str, password: str | None) -> None:
    from sqlalchemy import select
    from .db import Database, User, utcnow
    from .routers.auth import _referral_code
    from .security import hash_password, normalize_email, validate_password_strength
    db = Database(s.database_url)
    db.create_all()
    email = email.strip().lower()
    with db.SessionLocal() as session:
        user = session.scalar(select(User).where(User.email == email))
        if user:
            user.role = "admin"
            if password:
                user.password_hash = hash_password(password)
            session.commit()
            print(f"user {email} is now admin")
            return
        password = password or getpass.getpass("Admin password: ")
        if err := validate_password_strength(password):
            sys.exit(err)
        session.add(User(email=email, email_normalized=normalize_email(email), password_hash=hash_password(password),
                         display_name="Admin", role="admin", is_verified=True, verified_at=utcnow(),
                         referral_code=_referral_code(session)))
        session.commit()
        print(f"admin {email} created")


if __name__ == "__main__":
    main()
