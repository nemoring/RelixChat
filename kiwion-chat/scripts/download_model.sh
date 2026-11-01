#!/usr/bin/env bash
# Download the ORIGINAL OLMo 2 1B Instruct weights from Hugging Face (allenai/OLMo-2-0425-1B-Instruct),
# convert them to GGUF with llama.cpp's converter and quantize for weak hardware.
#
#   scripts/download_model.sh                 # -> models/olmo-2-1b-instruct-Q4_K_M.gguf (~0.9 GB RAM)
#   QUANT=Q8_0 scripts/download_model.sh      # better quality, ~1.6 GB
#   QUANT=F16  scripts/download_model.sh      # no quantization, ~3 GB
#
# Requirements: python3, ~7 GB free disk during conversion, scripts/build_llamacpp.sh already run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${OLMO_REPO:-allenai/OLMo-2-0425-1B-Instruct}"
QUANT="${QUANT:-Q4_K_M}"
LLAMA="$ROOT/third_party/llama.cpp"
HF_DIR="$ROOT/models/hf/OLMo-2-0425-1B-Instruct"
F16="$ROOT/models/olmo-2-1b-instruct-F16.gguf"
OUT="$ROOT/models/olmo-2-1b-instruct-$QUANT.gguf"

[ -x "$LLAMA/build/bin/llama-quantize" ] || { echo "run scripts/build_llamacpp.sh first"; exit 1; }
mkdir -p "$ROOT/models"
VENV="$ROOT/models/.venv-convert"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -r "$LLAMA/requirements/requirements-convert_hf_to_gguf.txt" "huggingface_hub>=0.23"
fi

echo "[1/3] downloading original weights: $REPO"
"$VENV/bin/python" - "$REPO" "$HF_DIR" <<'PY'
import sys
from huggingface_hub import snapshot_download
snapshot_download(repo_id=sys.argv[1], local_dir=sys.argv[2],
                  allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model", "tokenizer*"])
print("downloaded to", sys.argv[2])
PY

echo "[2/3] converting to GGUF (F16)"
"$VENV/bin/python" "$LLAMA/convert_hf_to_gguf.py" "$HF_DIR" --outtype f16 --outfile "$F16"

if [ "$QUANT" = "F16" ]; then
  OUT="$F16"
else
  echo "[3/3] quantizing to $QUANT"
  "$LLAMA/build/bin/llama-quantize" "$F16" "$OUT" "$QUANT"
  [ "${KEEP_F16:-0}" = "1" ] || rm -f "$F16"
fi
sha256sum "$OUT" | tee "$OUT.sha256"
echo
echo "done: $OUT"
echo "set KIWION_MODEL_PATH=$OUT in .env (it is the default for Q4_K_M)"
