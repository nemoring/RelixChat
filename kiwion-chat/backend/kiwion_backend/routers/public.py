from __future__ import annotations

from fastapi import APIRouter, Request

from kiwion_shared.version import DEVELOPER, MODEL_DISPLAY_NAME, PRODUCT_NAME, __version__

from ..deps import state

router = APIRouter(prefix="/api", tags=["public"])


@router.get("/config/public")
async def public_config(request: Request):
    st = state(request)
    cfg = st.store.all()
    model = await st.inference.model_identity()
    return {"product": PRODUCT_NAME, "developer": DEVELOPER, "version": __version__,
            "model": model["name"], "model_id": model["id"], "model_license": model["license"],
            "launch_at": st.settings.launch_at,
            "registration_open": cfg["registration_open"] and not cfg["maintenance_mode"],
            "maintenance": cfg["maintenance_mode"], "maintenance_message": cfg["maintenance_message"],
            "referral_enabled": cfg["referral_enabled"], "pow_difficulty": st.pow.difficulty,
            "max_message_chars": cfg["max_message_chars"]}


@router.get("/model/status")
async def model_status(request: Request):
    st = state(request)
    s = await st.inference.status()
    q = s.get("queue") or {}
    state_ = s.get("state", "offline")
    return {"state": {"ready": "online"}.get(state_, state_), "engine": s.get("engine"),
            "model": s.get("model_name", MODEL_DISPLAY_NAME), "queue_active": q.get("active", 0),
            "queue_waiting": q.get("waiting", 0), "queue_capacity": q.get("max_queue", 0),
            "busy": bool(q) and q.get("waiting", 0) >= max(1, q.get("max_queue", 1)),
            "tokens_per_second": s.get("last_tokens_per_second")}


@router.get("/health")
def health():
    return {"status": "ok", "version": __version__}
