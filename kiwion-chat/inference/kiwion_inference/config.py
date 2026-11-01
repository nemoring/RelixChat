from __future__ import annotations

import os
import shutil
from dataclasses import dataclass, field
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _physical_cores() -> int:
    """Physical cores are the sweet spot for llama.cpp; hyper-threads mostly add contention."""
    try:
        cores = set()
        with open("/proc/cpuinfo") as f:
            phys = core = None
            for line in f:
                if line.startswith("physical id"):
                    phys = line.split(":")[1].strip()
                elif line.startswith("core id"):
                    core = line.split(":")[1].strip()
                    cores.add((phys, core))
        if cores:
            return max(1, len(cores))
    except OSError:
        pass
    return max(1, (os.cpu_count() or 2) // 2)


def _find_llama_server() -> str:
    env = os.getenv("KIWION_LLAMA_SERVER_BIN")
    if env:
        return env
    for cand in (PROJECT_ROOT / "third_party/llama.cpp/build/bin/llama-server",
                 Path.home() / ".kiwion/llama.cpp/build/bin/llama-server"):
        if cand.exists():
            return str(cand)
    return shutil.which("llama-server") or "llama-server"


def _bool(name: str, default: bool = False) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


@dataclass
class InferenceConfig:
    host: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: int(os.getenv("KIWION_INFERENCE_PORT", "8090")))
    secret: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_SECRET", ""))
    insecure_dev: bool = field(default_factory=lambda: _bool("KIWION_INFERENCE_INSECURE_DEV"))
    engine: str = field(default_factory=lambda: os.getenv("KIWION_ENGINE", "llamacpp"))
    llama_server_bin: str = field(default_factory=_find_llama_server)
    model_path: str = field(default_factory=lambda: os.getenv(
        "KIWION_MODEL_PATH", str(PROJECT_ROOT / "models/olmo-2-1b-instruct-Q4_K_M.gguf")))
    model_id: str = field(default_factory=lambda: os.getenv("KIWION_MODEL_ID", "olmo-2-1b-instruct"))
    llama_port: int = field(default_factory=lambda: int(os.getenv("KIWION_LLAMA_PORT", "8091")))
    threads: int = field(default_factory=lambda: int(os.getenv("KIWION_THREADS", "0")) or _physical_cores())
    ctx_size: int = field(default_factory=lambda: int(os.getenv("KIWION_CTX", "2048")))
    parallel: int = field(default_factory=lambda: int(os.getenv("KIWION_PARALLEL", "1")))
    max_queue: int = field(default_factory=lambda: int(os.getenv("KIWION_MAX_QUEUE", "8")))
    queue_timeout: float = field(default_factory=lambda: float(os.getenv("KIWION_QUEUE_TIMEOUT", "180")))
    max_tokens_cap: int = field(default_factory=lambda: int(os.getenv("KIWION_MAX_TOKENS_CAP", "1024")))
    batch_size: int = field(default_factory=lambda: int(os.getenv("KIWION_BATCH", "256")))
    kv_cache_type: str = field(default_factory=lambda: os.getenv("KIWION_KV_CACHE_TYPE", "f16"))
    mlock: bool = field(default_factory=lambda: _bool("KIWION_MLOCK"))
    gpu_layers: int = field(default_factory=lambda: int(os.getenv("KIWION_GPU_LAYERS", "0")))
    extra_args: str = field(default_factory=lambda: os.getenv("KIWION_LLAMA_EXTRA_ARGS", ""))
    startup_timeout: float = field(default_factory=lambda: float(os.getenv("KIWION_STARTUP_TIMEOUT", "300")))
    ssl_certfile: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_SSL_CERT", ""))
    ssl_keyfile: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_SSL_KEY", ""))
    ssl_client_ca: str = field(default_factory=lambda: os.getenv("KIWION_INFERENCE_SSL_CLIENT_CA", ""))
    mock_delay: float = field(default_factory=lambda: float(os.getenv("KIWION_MOCK_DELAY", "0.02")))

    def validate(self) -> None:
        if not self.secret and not self.insecure_dev:
            raise SystemExit(
                "KIWION_INFERENCE_SECRET is not set. Generate one with `python -m kiwion_cli secret` "
                "or set KIWION_INFERENCE_INSECURE_DEV=1 for local development only.")
        if self.secret and len(self.secret) < 32:
            raise SystemExit("KIWION_INFERENCE_SECRET must be at least 32 characters long")
        if self.parallel < 1 or self.max_queue < 0:
            raise SystemExit("KIWION_PARALLEL must be >= 1 and KIWION_MAX_QUEUE >= 0")
