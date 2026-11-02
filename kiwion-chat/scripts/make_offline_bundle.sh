#!/usr/bin/env bash
# Build the offline installation bundle (for servers that cannot reach GitHub / Docker Hub / PyPI):
#   kiwion-offline.tar.gz        code + llama.cpp sources + Python wheels for Ubuntu 24.04 (cp312, x86_64)
#   kiwion-convert-tools.tar.gz  PyTorch (CPU) etc., only needed to convert original HF weights to GGUF
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
LLAMA="$ROOT/third_party/llama.cpp"
[ -d "$LLAMA" ] || { echo "run scripts/build_llamacpp.sh first (needs the llama.cpp sources)"; exit 1; }
WORK="$(mktemp -d)"; B="$WORK/kiwion-offline"
mkdir -p "$B/kiwion-chat" "$B/wheels/runtime" "$B/models" "$OUT"
(cd "$ROOT" && git ls-files -z | grep -zv '^mobile/' | xargs -0 -I{} cp --parents {} "$B/kiwion-chat/")
rsync -a --exclude .git --exclude build --exclude 'models/*.gguf' "$LLAMA/" "$B/llama.cpp/"
cp "$ROOT/deploy/install_offline.sh" "$B/install.sh"
PLAT=(--only-binary=:all: --platform manylinux_2_28_x86_64 --platform manylinux2014_x86_64 --platform manylinux_2_17_x86_64 --python-version 3.12 --implementation cp)
pip download -q -d "$B/wheels/runtime" "${PLAT[@]}" fastapi "uvicorn[standard]" sqlalchemy argon2-cffi cryptography pydantic email-validator httpx
tar czf "$OUT/kiwion-offline.tar.gz" -C "$WORK" kiwion-offline
T="$WORK/convert"; mkdir -p "$T/wheels"
pip download -q -d "$T/wheels" "${PLAT[@]}" --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple \
  "torch==2.11.0" "numpy~=2.2.6" "sentencepiece>=0.1.98,<0.3.0" "transformers==4.57.6" "protobuf>=4.21.0,<5.0.0"
tar czf "$OUT/kiwion-convert-tools.tar.gz" -C "$T" wheels
rm -rf "$WORK"
ls -la "$OUT"
