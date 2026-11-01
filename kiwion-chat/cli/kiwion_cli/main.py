"""kiwion — terminal client for Kiwion Chat.

    kiwion chat                 interactive chat (local inference node or Developer API)
    kiwion status               backend / inference / model status
    kiwion models               available models (local GGUF files and served model)
    kiwion server start|stop|restart|logs   manage the local inference service (and backend)
    kiwion benchmark            measure time-to-first-token and tokens/second
    kiwion secret               generate a random shared secret

Connection is configured with environment variables (or a .env file):
    KIWION_INFERENCE_URL + KIWION_INFERENCE_SECRET  -> talk to the inference node directly
    KIWION_API_URL + KIWION_API_KEY                 -> talk to the public Developer API
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path

import httpx

from kiwion_shared.messages import OVERLOADED_RU
from kiwion_shared.signing import sign_request
from kiwion_shared.version import MODEL_DISPLAY_NAME, __version__

PROJECT_ROOT = Path(__file__).resolve().parents[2]
HOME = Path(os.getenv("KIWION_HOME", Path.home() / ".kiwion"))
GREEN, DIM, BOLD, RED, YELLOW, RESET = "\033[32m", "\033[2m", "\033[1m", "\033[31m", "\033[33m", "\033[0m"
if not sys.stdout.isatty() or os.getenv("NO_COLOR"):
    GREEN = DIM = BOLD = RED = YELLOW = RESET = ""

KIWI = rf"""{GREEN}
     ,~~.
    (  6 )-_,     {BOLD}Kiwion Chat{RESET}{GREEN}  v{__version__}
 (\___ )=='-'     {RESET}{DIM}by Kiwi_Fuzzy · {MODEL_DISPLAY_NAME}{RESET}{GREEN}
  \ .   ) )
   \ `-' /
    `~j-'
      "=:        {RESET}"""


def load_dotenv() -> None:
    for p in (Path.cwd() / ".env", PROJECT_ROOT / ".env"):
        if p.exists():
            for line in p.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
            break


# ------------------------------------------------------------------ transports
class InferenceTarget:
    """Direct, signed connection to Kiwion Inference."""
    def __init__(self, url: str, secret: str):
        self.url, self.secret = url.rstrip("/"), secret
        verify: bool | str = os.getenv("KIWION_INFERENCE_CA_CERT") or True
        self.http = httpx.Client(base_url=self.url, timeout=httpx.Timeout(10, read=600), verify=verify)

    def _h(self, method, path, body=b""):
        h = {"Content-Type": "application/json"}
        if self.secret:
            h.update(sign_request(self.secret, method, path, body))
        return h

    def status(self) -> dict:
        r = self.http.get("/v1/status", headers=self._h("GET", "/v1/status"))
        r.raise_for_status()
        return r.json()

    def models(self) -> list[dict]:
        r = self.http.get("/v1/models", headers=self._h("GET", "/v1/models"))
        r.raise_for_status()
        return r.json()["data"]

    def stream(self, messages, max_tokens=512, temperature=0.7):
        body = json.dumps({"messages": messages, "max_tokens": max_tokens, "temperature": temperature}).encode()
        with self.http.stream("POST", "/v1/generate", content=body, headers=self._h("POST", "/v1/generate", body)) as r:
            if r.status_code == 503:
                data = json.loads(r.read() or b"{}")
                yield {"type": "error", "code": data.get("error", "unavailable"), "message": data.get("message", "")}
                return
            if r.status_code == 401:
                yield {"type": "error", "code": "unauthorized", "message": "wrong KIWION_INFERENCE_SECRET"}
                return
            r.raise_for_status()
            for line in r.iter_lines():
                if line.strip():
                    yield json.loads(line)


class ApiTarget:
    """OpenAI-compatible Developer API with an API key."""
    def __init__(self, url: str, key: str):
        self.http = httpx.Client(base_url=url.rstrip("/"), timeout=httpx.Timeout(10, read=600),
                                 headers={"Authorization": f"Bearer {key}", "User-Agent": f"kiwion-cli/{__version__}"})

    def status(self) -> dict:
        r = self.http.get("/api/model/status")
        r.raise_for_status()
        return r.json()

    def models(self) -> list[dict]:
        r = self.http.get("/v1/models")
        r.raise_for_status()
        return r.json()["data"]

    def stream(self, messages, max_tokens=512, temperature=0.7):
        body = {"model": "olmo-2-1b-instruct", "messages": messages, "max_tokens": max_tokens,
                "temperature": temperature, "stream": True, "stream_options": {"include_usage": True}}
        t0 = time.monotonic()
        with self.http.stream("POST", "/v1/chat/completions", json=body) as r:
            if r.status_code != 200:
                data = json.loads(r.read() or b"{}").get("error", {})
                yield {"type": "error", "code": data.get("code", str(r.status_code)), "message": data.get("message", "")}
                return
            yield {"type": "start"}
            usage = {}
            for line in r.iter_lines():
                if not line.startswith("data: "):
                    continue
                payload = line[6:]
                if payload == "[DONE]":
                    break
                obj = json.loads(payload)
                if obj.get("usage"):
                    usage = obj["usage"]
                for ch in obj.get("choices", []):
                    if ch.get("delta", {}).get("content"):
                        yield {"type": "token", "text": ch["delta"]["content"]}
            secs = time.monotonic() - t0
            ct = usage.get("completion_tokens", 0)
            yield {"type": "done", "prompt_tokens": usage.get("prompt_tokens", 0), "completion_tokens": ct,
                   "tokens_per_second": round(ct / secs, 2) if secs and ct else None}


def make_target(args):
    api_key = getattr(args, "api_key", None) or os.getenv("KIWION_API_KEY")
    if api_key:
        return ApiTarget(getattr(args, "api_url", None) or os.getenv("KIWION_API_URL", "http://127.0.0.1:8080"), api_key)
    url = getattr(args, "url", None) or os.getenv("KIWION_INFERENCE_URL", "http://127.0.0.1:8090")
    return InferenceTarget(url, os.getenv("KIWION_INFERENCE_SECRET", ""))


# ------------------------------------------------------------------ commands
def cmd_chat(args) -> int:
    target = make_target(args)
    print(KIWI)
    print(f"{DIM}Команды: /new — новый диалог, /exit — выход, /system <текст> — системный промпт. "
          f"Ctrl+C останавливает генерацию.{RESET}\n")
    history: list[dict] = []
    if args.system:
        history.append({"role": "system", "content": args.system})
    while True:
        try:
            text = input(f"{BOLD}{GREEN}вы ›{RESET} ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if not text:
            continue
        if text in ("/exit", "/quit", "exit"):
            return 0
        if text == "/new":
            history = [m for m in history if m["role"] == "system"]
            print(f"{DIM}— новый диалог —{RESET}")
            continue
        if text.startswith("/system "):
            history = [m for m in history if m["role"] != "system"]
            history.insert(0, {"role": "system", "content": text[8:]})
            continue
        history.append({"role": "user", "content": text})
        reply = []
        print(f"{BOLD}{GREEN}киви ›{RESET} ", end="", flush=True)
        try:
            for ev in target.stream(history, args.max_tokens, args.temperature):
                t = ev.get("type")
                if t == "queued":
                    print(f"\r{DIM}в очереди: {ev['position']}…{RESET}", end="", flush=True)
                elif t == "start":
                    print(f"\r{BOLD}{GREEN}киви ›{RESET} ", end="", flush=True)
                elif t == "token":
                    reply.append(ev["text"])
                    print(ev["text"], end="", flush=True)
                elif t == "done":
                    tps = ev.get("tokens_per_second")
                    print(f"\n{DIM}[{ev.get('completion_tokens', 0)} ток."
                          f"{f', {tps} ток/с' if tps else ''}]{RESET}\n")
                elif t == "error":
                    msg = OVERLOADED_RU if ev.get("code") == "overloaded" else f"ошибка: {ev.get('code')} {ev.get('message', '')}"
                    print(f"\n{YELLOW}{msg}{RESET}\n")
                    history.pop()
                    break
        except KeyboardInterrupt:
            print(f"\n{DIM}[генерация остановлена]{RESET}\n")
        except httpx.HTTPError as e:
            print(f"\n{RED}Нет соединения с сервером: {e}{RESET}\n")
            history.pop()
            continue
        if reply:
            history.append({"role": "assistant", "content": "".join(reply)})
    return 0


def cmd_status(args) -> int:
    ok = True
    backend = os.getenv("KIWION_API_URL", "http://127.0.0.1:8080")
    print(f"{BOLD}Kiwion Chat {__version__}{RESET}")
    try:
        r = httpx.get(backend + "/api/health", timeout=3)
        print(f"  backend    {GREEN}online{RESET}  {backend}" if r.status_code == 200 else f"  backend    {RED}HTTP {r.status_code}{RESET}")
    except httpx.HTTPError:
        print(f"  backend    {DIM}offline{RESET} {backend}")
    pid = _read_pid("inference")
    print(f"  service    {'pid ' + str(pid) if pid else DIM + 'not started by kiwion server' + RESET}")
    url = os.getenv("KIWION_INFERENCE_URL", "http://127.0.0.1:8090")
    try:
        s = InferenceTarget(url, os.getenv("KIWION_INFERENCE_SECRET", "")).status()
        color = GREEN if s["state"] == "ready" else YELLOW
        q = s["queue"]
        print(f"  inference  {color}{s['state']}{RESET}  {url}  engine={s['engine']}")
        print(f"  model      {s['model_name']} ({s.get('model_file') or '-'}) ctx={s['ctx_size']} threads={s['threads']}")
        print(f"  queue      active {q['active']}/{q['parallel']}, waiting {q['waiting']}/{q['max_queue']}, "
              f"served {q['total_served']}, rejected {q['total_rejected']}")
        print(f"  tokens     prompt {s['total_prompt_tokens']}, completion {s['total_completion_tokens']}, "
              f"last speed {s.get('last_tokens_per_second') or '-'} tok/s")
        if s.get("error"):
            print(f"  {RED}error: {s['error']}{RESET}")
            ok = False
    except httpx.HTTPStatusError as e:
        print(f"  inference  {RED}HTTP {e.response.status_code}{RESET} (check KIWION_INFERENCE_SECRET)")
        ok = False
    except httpx.HTTPError:
        print(f"  inference  {RED}offline{RESET} {url}  (start it with `kiwion server start`)")
        ok = False
    return 0 if ok else 1


def cmd_models(args) -> int:
    print(f"{BOLD}Local GGUF files{RESET} ({PROJECT_ROOT / 'models'}):")
    files = sorted((PROJECT_ROOT / "models").glob("*.gguf")) if (PROJECT_ROOT / "models").exists() else []
    active = os.path.basename(os.getenv("KIWION_MODEL_PATH", ""))
    for f in files:
        mark = f" {GREEN}← KIWION_MODEL_PATH{RESET}" if f.name == active else ""
        print(f"  {f.name:48s} {f.stat().st_size / 1e6:9.1f} MB{mark}")
    if not files:
        print(f"  {DIM}none — run scripts/download_model.sh{RESET}")
    try:
        served = make_target(args).models()
        print(f"\n{BOLD}Served model{RESET}:")
        for m in served:
            print(f"  {m['id']}  {m.get('name', '')}  {m.get('state', '')}")
    except httpx.HTTPError:
        print(f"\n{DIM}inference service is not reachable{RESET}")
    return 0


def _pidfile(name: str) -> Path:
    return HOME / f"{name}.pid"


def _read_pid(name: str) -> int | None:
    p = _pidfile(name)
    if not p.exists():
        return None
    try:
        pid = int(p.read_text().strip())
        os.kill(pid, 0)
        return pid
    except (ValueError, ProcessLookupError, PermissionError):
        p.unlink(missing_ok=True)
        return None


def _start(name: str, module: str, env_extra: dict | None = None) -> int:
    if pid := _read_pid(name):
        print(f"{name} already running (pid {pid})")
        return pid
    (HOME / "logs").mkdir(parents=True, exist_ok=True)
    log = open(HOME / "logs" / f"{name}.log", "ab")
    env = {**os.environ, **(env_extra or {})}
    env["PYTHONPATH"] = os.pathsep.join([str(PROJECT_ROOT / d) for d in ("shared", "backend", "inference", "cli")]
                                        + [env.get("PYTHONPATH", "")])
    proc = subprocess.Popen([sys.executable, "-m", module], stdout=log, stderr=subprocess.STDOUT,
                            stdin=subprocess.DEVNULL, start_new_session=True, env=env, cwd=str(PROJECT_ROOT))
    _pidfile(name).write_text(str(proc.pid))
    return proc.pid


def _stop(name: str) -> bool:
    pid = _read_pid(name)
    if not pid:
        return False
    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    for _ in range(100):
        try:
            os.kill(pid, 0)
            time.sleep(0.2)
        except ProcessLookupError:
            break
    else:
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    _pidfile(name).unlink(missing_ok=True)
    return True


def cmd_server(args) -> int:
    if args.action in ("stop", "restart"):
        stopped = [n for n in ("backend", "inference") if _stop(n)]
        print("stopped: " + (", ".join(stopped) if stopped else "nothing was running"))
        if args.action == "stop":
            return 0
    if args.action == "logs":
        p = HOME / "logs" / f"{args.component}.log"
        print(p.read_text(errors="replace")[-8000:] if p.exists() else f"no log at {p}")
        return 0
    if not os.getenv("KIWION_INFERENCE_SECRET") and not os.getenv("KIWION_INFERENCE_INSECURE_DEV"):
        print(f"{RED}KIWION_INFERENCE_SECRET is not set.{RESET} Put it into .env (generate: kiwion secret).")
        return 1
    extra = {}
    if args.engine:
        extra["KIWION_ENGINE"] = args.engine
    if args.model:
        extra["KIWION_MODEL_PATH"] = str(Path(args.model).resolve())
    pid = _start("inference", "kiwion_inference", extra)
    print(f"inference starting (pid {pid}), log: {HOME / 'logs/inference.log'}")
    if args.with_backend:
        bpid = _start("backend", "kiwion_backend")
        print(f"backend starting (pid {bpid}), log: {HOME / 'logs/backend.log'}")
    if args.wait:
        url = os.getenv("KIWION_INFERENCE_URL", "http://127.0.0.1:8090")
        deadline = time.monotonic() + args.wait
        while time.monotonic() < deadline:
            try:
                r = httpx.get(url + "/health", timeout=2)
                if r.status_code == 200:
                    print(f"{GREEN}inference is ready{RESET}")
                    return 0
                if r.json().get("status") == "error":
                    print(f"{RED}model failed to load — see `kiwion server logs`{RESET}")
                    return 1
            except httpx.HTTPError:
                pass
            if not _read_pid("inference"):
                print(f"{RED}inference process exited — see `kiwion server logs`{RESET}")
                return 1
            time.sleep(0.5)
        print(f"{YELLOW}still loading after {args.wait}s{RESET}")
        return 1
    return 0


BENCH_PROMPTS = [
    "Explain in three sentences why the kiwi bird cannot fly.",
    "Напиши функцию на Python, которая проверяет, является ли строка палиндромом.",
    "List five tips for saving memory when running a language model on an old laptop.",
]


def cmd_benchmark(args) -> int:
    if args.llama_bench:
        binary = PROJECT_ROOT / "third_party/llama.cpp/build/bin/llama-bench"
        model = os.getenv("KIWION_MODEL_PATH", str(PROJECT_ROOT / "models/olmo-2-1b-instruct-Q4_K_M.gguf"))
        threads = os.getenv("KIWION_THREADS", "")
        cmd = [str(binary), "-m", model, "-p", "128", "-n", "64", "-r", "2"] + (["-t", threads] if threads else [])
        print("running:", " ".join(cmd))
        return subprocess.call(cmd)
    target = make_target(args)
    ttfts, speeds, totals = [], [], []
    print(f"{BOLD}Kiwion benchmark{RESET}: {args.runs} runs, max_tokens={args.max_tokens}\n")
    for i in range(args.runs):
        prompt = BENCH_PROMPTS[i % len(BENCH_PROMPTS)]
        t0 = time.monotonic()
        first = None
        n = 0
        done = {}
        for ev in target.stream([{"role": "user", "content": prompt}], args.max_tokens, 0.2):
            if ev["type"] == "token":
                n += 1
                if first is None:
                    first = time.monotonic() - t0
            elif ev["type"] == "done":
                done = ev
            elif ev["type"] == "error":
                print(f"{RED}run {i + 1}: {ev.get('code')} {ev.get('message', '')}{RESET}")
                return 1
        total = time.monotonic() - t0
        ct = done.get("completion_tokens") or n
        gen_time = total - (first or 0)
        tps = done.get("tokens_per_second") or (ct / gen_time if gen_time > 0 else 0)
        ttfts.append(first or total)
        speeds.append(tps)
        totals.append(total)
        print(f"  run {i + 1}: ttft {ttfts[-1]:.2f}s  {ct} tokens in {total:.2f}s  → {tps:.2f} tok/s")
    print(f"\n  median TTFT  {statistics.median(ttfts):.2f}s")
    print(f"  median speed {statistics.median(speeds):.2f} tok/s")
    print(f"  median total {statistics.median(totals):.2f}s")
    return 0


def cmd_secret(args) -> int:
    print(secrets.token_hex(32))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="kiwion", description="Kiwion Chat terminal client")
    p.add_argument("--version", action="version", version=f"kiwion {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    def conn(sp):
        sp.add_argument("--url", help="inference URL (default $KIWION_INFERENCE_URL)")
        sp.add_argument("--api-url", help="backend URL for Developer API mode")
        sp.add_argument("--api-key", help="use the Developer API with this key")

    c = sub.add_parser("chat", help="interactive terminal chat")
    conn(c)
    c.add_argument("--max-tokens", type=int, default=512)
    c.add_argument("--temperature", type=float, default=0.7)
    c.add_argument("--system", help="system prompt")
    c.set_defaults(func=cmd_chat)

    s = sub.add_parser("status", help="show service status")
    s.set_defaults(func=cmd_status)

    m = sub.add_parser("models", help="list models")
    conn(m)
    m.set_defaults(func=cmd_models)

    sv = sub.add_parser("server", help="manage local services")
    sv.add_argument("action", choices=["start", "stop", "restart", "logs"])
    sv.add_argument("component", nargs="?", default="inference", choices=["inference", "backend"])
    sv.add_argument("--with-backend", action="store_true", help="also start the backend API")
    sv.add_argument("--engine", choices=["llamacpp", "mock"], help="override KIWION_ENGINE (mock = tests only)")
    sv.add_argument("--model", help="path to a GGUF file")
    sv.add_argument("--wait", type=float, default=0, help="wait up to N seconds for the model to load")
    sv.set_defaults(func=cmd_server)

    b = sub.add_parser("benchmark", help="measure generation speed")
    conn(b)
    b.add_argument("--runs", type=int, default=3)
    b.add_argument("--max-tokens", type=int, default=128)
    b.add_argument("--llama-bench", action="store_true", help="run llama.cpp's llama-bench on the GGUF file")
    b.set_defaults(func=cmd_benchmark)

    sec = sub.add_parser("secret", help="generate a random secret")
    sec.set_defaults(func=cmd_secret)
    return p


def main(argv: list[str] | None = None) -> None:
    load_dotenv()
    args = build_parser().parse_args(argv)
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
