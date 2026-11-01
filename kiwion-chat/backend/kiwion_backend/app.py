"""Kiwion Backend application factory."""
from __future__ import annotations

import logging
import traceback
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from kiwion_shared.version import __version__

from .config import PROJECT_ROOT, Settings, get_settings
from .db import Database
from .deps import AppState, log_error
from .inference_client import InferenceClient
from .mailer import Mailer
from .routers import account, admin, auth, chats, keys, openai_api, public
from .security import ProofOfWork, RateLimiter
from .settings_store import SettingsStore

log = logging.getLogger("kiwion.backend")

CSP = ("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
       "media-src 'self' data: blob:; connect-src 'self'; font-src 'self' data:; object-src 'none'; "
       "base-uri 'self'; form-action 'self'; frame-ancestors 'none'")


def create_app(settings: Settings | None = None, inference: InferenceClient | None = None) -> FastAPI:
    settings = settings or get_settings()
    db = Database(settings.database_url)
    db.create_all()
    st = AppState(settings=settings, db=db, store=SettingsStore(db.SessionLocal), limiter=RateLimiter(),
                  pow=ProofOfWork(settings.secret_key, settings.pow_difficulty), mailer=Mailer(settings),
                  inference=inference or InferenceClient(settings))

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        await st.inference.aclose()

    app = FastAPI(title="Kiwion Chat API", version=__version__, lifespan=lifespan,
                  docs_url="/api/docs", redoc_url=None, openapi_url="/api/openapi.json",
                  description="Kiwion Chat by Kiwi_Fuzzy. Developer API is OpenAI-compatible: /v1/chat/completions")
    app.state.kiwion = st

    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_credentials=False,
                           allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
                           allow_headers=["Authorization", "Content-Type", "X-Api-Key"])

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        if request.url.path.startswith("/v1/") is False and request.url.path.startswith("/api/") \
                and request.headers.get("content-length", "0").isdigit() \
                and int(request.headers.get("content-length", "0")) > 1_000_000:
            return JSONResponse({"detail": {"code": "too_large", "message": "Запрос слишком большой"}}, status_code=413)
        response = await call_next(request)
        h = response.headers
        h.setdefault("X-Content-Type-Options", "nosniff")
        h.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        h.setdefault("X-Frame-Options", "DENY")
        h.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        if request.url.path.startswith("/api/docs"):
            pass  # swagger UI loads its assets from a CDN
        else:
            h.setdefault("Content-Security-Policy", CSP)
        if settings.https:
            h.setdefault("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
        if request.url.path.startswith(("/api/", "/v1/")):
            h.setdefault("Cache-Control", "no-store")
        return response

    @app.exception_handler(RequestValidationError)
    async def validation_handler(request: Request, exc: RequestValidationError):
        errs = [{"field": ".".join(str(x) for x in e.get("loc", [])[1:]), "message": e.get("msg", "")}
                for e in exc.errors()]
        if request.url.path.startswith("/v1/"):
            return JSONResponse(status_code=400, content={"error": {"message": "; ".join(
                f"{e['field']}: {e['message']}" for e in errs), "type": "invalid_request_error", "code": "invalid_request"}})
        return JSONResponse(status_code=422, content={"detail": {"code": "validation_error",
                                                                 "message": "Проверьте введённые данные", "errors": errs}})

    @app.exception_handler(HTTPException)
    async def http_handler(request: Request, exc: HTTPException):
        content = exc.detail if (isinstance(exc.detail, dict) and "error" in exc.detail) else {"detail": exc.detail}
        return JSONResponse(status_code=exc.status_code, content=content, headers=exc.headers)

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        log_error(st, f"{type(exc).__name__}: {exc}\n{traceback.format_exc(limit=8)}", path=request.url.path)
        return JSONResponse(status_code=500, content={"detail": {"code": "internal_error",
                                                                 "message": "Что-то пошло не так. Мы уже разбираемся."}})

    for r in (public.router, auth.router, account.router, chats.router, keys.router, openai_api.router, admin.router):
        app.include_router(r)

    if settings.serve_static:
        _mount_static(app)
    return app


def _mount_static(app: FastAPI) -> None:
    web = PROJECT_ROOT / "web"
    admin_dir = PROJECT_ROOT / "admin"
    assets = PROJECT_ROOT / "assets"
    if admin_dir.exists():
        app.mount("/admin", StaticFiles(directory=admin_dir, html=True), name="admin")
    if assets.exists():
        app.mount("/assets", StaticFiles(directory=assets), name="assets")
    if web.exists():
        @app.get("/launch", include_in_schema=False)
        def launch():
            return FileResponse(web / "launch.html")

        @app.get("/docs", include_in_schema=False)
        def docs():
            return FileResponse(web / "docs.html")

        @app.get("/admin", include_in_schema=False)
        def admin_redirect():
            return RedirectResponse("/admin/")

        app.mount("/", StaticFiles(directory=web, html=True), name="web")
