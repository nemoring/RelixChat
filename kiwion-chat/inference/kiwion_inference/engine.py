"""Inference engines.

* LlamaCppEngine — production engine. Runs llama.cpp's `llama-server` as a child
  process bound to 127.0.0.1 and talks to its native /completion endpoint. The
  OLMo 2 chat template is applied by Kiwion itself (kiwion_shared.prompt), so the
  prompt format does not depend on the GGUF metadata.
* MockEngine — deterministic engine for automated tests and UI development only.
  It never runs unless KIWION_ENGINE=mock is set explicitly, and the status
  endpoint reports engine="mock" so clients can show that it is not the model.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import shlex
import signal
import subprocess
import time
from pathlib import Path
from typing import AsyncIterator

import httpx

from kiwion_shared.prompt import BOS, STOP_SEQUENCES, render_olmo2

from .config import InferenceConfig

log = logging.getLogger("kiwion.inference.engine")


class EngineUnavailable(Exception):
    pass


class BaseEngine:
    name = "base"

    def __init__(self, cfg: InferenceConfig):
        self.cfg = cfg
        self.state = "stopped"          # stopped | loading | ready | error
        self.error: str | None = None
        self.started_at = time.time()
        self.total_prompt_tokens = 0
        self.total_completion_tokens = 0
        self.total_requests = 0
        self.last_tokens_per_second: float | None = None

    async def start(self) -> None: ...
    async def stop(self) -> None: ...

    def info(self) -> dict:
        ident = self.cfg.identity()
        return {
            "engine": self.name,
            "state": self.state,
            "error": self.error,
            "model": ident["id"],
            "model_name": ident["name"],
            "model_license": ident["license"],
            "prompt_format": self.prompt_mode(),
            "model_file": Path(self.cfg.model_path).name if self.name != "mock" else None,
            "ctx_size": self.cfg.ctx_size,
            "threads": self.cfg.threads,
            "uptime_seconds": int(time.time() - self.started_at),
            "total_requests": self.total_requests,
            "total_prompt_tokens": self.total_prompt_tokens,
            "total_completion_tokens": self.total_completion_tokens,
            "last_tokens_per_second": self.last_tokens_per_second,
        }

    def prompt_mode(self) -> str:
        return "olmo2" if self.cfg.uses_olmo_template() else "model"

    async def render(self, messages: list[dict]) -> str:
        """Turn chat messages into the prompt string for /completion."""
        return render_olmo2(messages)

    def generate(self, prompt: str, max_tokens: int, temperature: float, top_p: float,
                 stop: list[str], seed: int | None = None) -> AsyncIterator[dict]:
        raise NotImplementedError


class LlamaCppEngine(BaseEngine):
    name = "llamacpp"

    def __init__(self, cfg: InferenceConfig):
        super().__init__(cfg)
        self.proc: subprocess.Popen | None = None
        self.base_url = f"http://127.0.0.1:{cfg.llama_port}"
        self.client = httpx.AsyncClient(timeout=httpx.Timeout(connect=5, read=600, write=30, pool=30))
        self.adds_bos = False
        self.bos_token = BOS
        self.has_template = False
        self._log_file = None
        self._watch_task: asyncio.Task | None = None

    def command(self) -> list[str]:
        c = self.cfg
        cmd = [
            c.llama_server_bin,
            "-m", c.model_path,
            "--host", "127.0.0.1",
            "--port", str(c.llama_port),
            "-c", str(c.ctx_size * c.parallel),
            "-np", str(c.parallel),
            "-t", str(c.threads),
            "-tb", str(c.threads),
            "-b", str(c.batch_size),
            "-ub", str(min(c.batch_size, 256)),
            "-ngl", str(c.gpu_layers),
            "--no-webui",
            "--metrics",
        ]
        if c.kv_cache_type and c.kv_cache_type != "f16":
            cmd += ["-ctk", c.kv_cache_type, "-ctv", c.kv_cache_type, "-fa", "on"]
        if c.mlock:
            cmd.append("--mlock")
        if c.extra_args:
            cmd += shlex.split(c.extra_args)
        return cmd

    async def start(self) -> None:
        if not Path(self.cfg.model_path).exists():
            self.state = "error"
            self.error = (f"model file not found: {self.cfg.model_path}. "
                          "Run scripts/download_model.sh to fetch and convert OLMo 2 1B Instruct.")
            log.error(self.error)
            return
        self.state = "loading"
        cmd = self.command()
        log.info("starting llama-server: %s", " ".join(shlex.quote(x) for x in cmd))
        log_dir = Path(os.getenv("KIWION_LOG_DIR", Path.home() / ".kiwion/logs"))
        log_dir.mkdir(parents=True, exist_ok=True)
        self._log_file = open(log_dir / "llama-server.log", "ab")
        try:
            self.proc = subprocess.Popen(cmd, stdout=self._log_file, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL, start_new_session=True)
        except FileNotFoundError:
            self.state = "error"
            self.error = (f"llama-server binary not found ({self.cfg.llama_server_bin}). "
                          "Run scripts/build_llamacpp.sh or set KIWION_LLAMA_SERVER_BIN.")
            log.error(self.error)
            return
        self._watch_task = asyncio.create_task(self._wait_ready())

    async def _wait_ready(self) -> None:
        deadline = time.monotonic() + self.cfg.startup_timeout
        while time.monotonic() < deadline:
            if self.proc and self.proc.poll() is not None:
                self.state = "error"
                self.error = f"llama-server exited with code {self.proc.returncode} (see ~/.kiwion/logs/llama-server.log)"
                log.error(self.error)
                return
            try:
                r = await self.client.get(self.base_url + "/health", timeout=2)
                if r.status_code == 200:
                    await self._detect_bos()
                    self.state = "ready"
                    self.error = None
                    log.info("llama-server ready: %s, prompt=%s, adds_bos=%s",
                             self.cfg.identity()["name"], self.prompt_mode(), self.adds_bos)
                    asyncio.create_task(self._supervise())
                    return
            except httpx.HTTPError:
                pass
            await asyncio.sleep(0.5)
        self.state = "error"
        self.error = "llama-server did not become ready in time"

    async def _supervise(self) -> None:
        """Restart llama-server if it crashes (e.g. OOM on a small machine)."""
        while self.proc is not None:
            await asyncio.sleep(2)
            if self.proc is None:
                return
            if self.proc.poll() is not None and self.state != "stopped":
                log.error("llama-server died with code %s, restarting", self.proc.returncode)
                self.state = "loading"
                await asyncio.sleep(1)
                await self.start()
                return

    async def _detect_bos(self) -> None:
        try:
            r = await self.client.post(self.base_url + "/tokenize",
                                       json={"content": "", "add_special": True}, timeout=10)
            self.adds_bos = bool(r.json().get("tokens"))
        except Exception:  # pragma: no cover - defensive
            self.adds_bos = False
        try:
            props = (await self.client.get(self.base_url + "/props", timeout=10)).json()
            self.bos_token = props.get("bos_token") or BOS
            self.has_template = bool(props.get("chat_template"))
        except Exception:  # pragma: no cover - defensive
            pass

    async def render(self, messages: list[dict]) -> str:
        if self.prompt_mode() == "olmo2":
            return render_olmo2(messages)
        # the chat template stored in the GGUF (Gemma, Qwen, Llama, ...), applied by llama.cpp
        try:
            r = await self.client.post(self.base_url + "/apply-template", json={"messages": messages}, timeout=30)
            r.raise_for_status()
            return r.json()["prompt"]
        except (httpx.HTTPError, KeyError, ValueError) as e:
            raise EngineUnavailable(f"chat template failed: {e}") from e

    async def stop(self) -> None:
        self.state = "stopped"
        proc, self.proc = self.proc, None
        if proc and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                await asyncio.to_thread(proc.wait, 15)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
        if self._log_file:
            self._log_file.close()
        await self.client.aclose()

    async def generate(self, prompt: str, max_tokens: int, temperature: float, top_p: float,
                       stop: list[str], seed: int | None = None) -> AsyncIterator[dict]:
        if self.state != "ready":
            raise EngineUnavailable(self.error or f"engine is {self.state}")
        bos = self.bos_token or BOS
        if self.adds_bos and bos and prompt.startswith(bos):
            prompt = prompt[len(bos):]   # llama.cpp adds BOS itself; avoid a double BOS
        payload = {
            "prompt": prompt,
            "n_predict": max_tokens,
            "temperature": temperature,
            "top_p": top_p,
            "stop": list(dict.fromkeys((STOP_SEQUENCES if self.prompt_mode() == "olmo2" else []) + (stop or []))),
            "stream": True,
            "cache_prompt": True,
            "repeat_penalty": 1.1,
        }
        if seed is not None:
            payload["seed"] = seed
        self.total_requests += 1
        started = time.monotonic()
        final: dict = {}
        try:
            async with self.client.stream("POST", self.base_url + "/completion", json=payload) as r:
                if r.status_code != 200:
                    body = (await r.aread()).decode(errors="replace")[:500]
                    raise EngineUnavailable(f"llama-server error {r.status_code}: {body}")
                async for line in r.aiter_lines():
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if not data or data == "[DONE]":
                        continue
                    chunk = json.loads(data)
                    text = chunk.get("content", "")
                    if text:
                        yield {"type": "token", "text": text}
                    if chunk.get("stop"):
                        final = chunk
                        break
        except httpx.HTTPError as e:
            raise EngineUnavailable(f"llama-server connection error: {e}") from e
        prompt_tokens = int(final.get("tokens_evaluated") or 0)
        completion_tokens = int(final.get("tokens_predicted") or 0)
        self.total_prompt_tokens += prompt_tokens
        self.total_completion_tokens += completion_tokens
        timings = final.get("timings") or {}
        tps = timings.get("predicted_per_second")
        if tps:
            self.last_tokens_per_second = round(float(tps), 2)
        stop_type = final.get("stop_type", "")
        finish = "length" if stop_type == "limit" or final.get("truncated") else "stop"
        yield {
            "type": "done",
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "finish_reason": finish,
            "seconds": round(time.monotonic() - started, 3),
            "tokens_per_second": self.last_tokens_per_second,
        }


class MockEngine(BaseEngine):
    """Test-only engine: streams a deterministic reply that echoes the last user turn."""
    name = "mock"

    async def start(self) -> None:
        self.state = "ready"

    async def generate(self, prompt: str, max_tokens: int, temperature: float, top_p: float,
                       stop: list[str], seed: int | None = None) -> AsyncIterator[dict]:
        self.total_requests += 1
        last_user = prompt.rsplit("<|user|>\n", 1)[-1].split("\n<|assistant|>")[0].strip()
        if "__error__" in last_user:
            raise EngineUnavailable("mock failure requested")
        reply = f"🥝 Kiwion (mock) получил: **{last_user[:200]}**\n\n```python\nprint('kiwi')\n```"
        words = reply.split(" ")
        n = 0
        for i, w in enumerate(words):
            if n >= max_tokens:
                break
            await asyncio.sleep(self.cfg.mock_delay)
            n += 1
            yield {"type": "token", "text": w + ("" if i == len(words) - 1 else " ")}
        p = max(1, len(prompt) // 4)
        self.total_prompt_tokens += p
        self.total_completion_tokens += n
        yield {"type": "done", "prompt_tokens": p, "completion_tokens": n,
               "finish_reason": "length" if n >= max_tokens else "stop",
               "seconds": 0.0, "tokens_per_second": None}


def make_engine(cfg: InferenceConfig) -> BaseEngine:
    if cfg.engine == "mock":
        return MockEngine(cfg)
    if cfg.engine == "llamacpp":
        return LlamaCppEngine(cfg)
    raise SystemExit(f"unknown KIWION_ENGINE={cfg.engine!r} (expected llamacpp)")
