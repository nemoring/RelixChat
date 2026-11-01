#!/usr/bin/env bash
# One-command local development: backend + inference on this machine.
#   scripts/dev.sh            # real model (needs models/*.gguf and llama.cpp)
#   scripts/dev.sh mock       # mock engine — UI development without model weights
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f .env ] || { cp .env.example .env; sed -i "s/^KIWION_INFERENCE_SECRET=.*/KIWION_INFERENCE_SECRET=$(python3 -c 'import secrets;print(secrets.token_hex(32))')/" .env; echo "created .env"; }
ENGINE_ARGS=()
[ "${1:-}" = "mock" ] && ENGINE_ARGS=(--engine mock)
python3 -m kiwion_cli server start --with-backend --wait 300 "${ENGINE_ARGS[@]}"
echo "open http://127.0.0.1:${KIWION_PORT:-8080}  (stop: python3 -m kiwion_cli server stop)"
