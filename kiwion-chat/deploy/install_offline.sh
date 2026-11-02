#!/usr/bin/env bash
# Kiwion Chat installation WITHOUT GitHub, Docker Hub or PyPI.
# Everything comes from the offline bundle (code, llama.cpp sources, Python wheels) plus the
# Ubuntu package mirror (python3, build tools, Caddy for HTTPS). For Ubuntu 24.04 (Python 3.12).
#
#   tar xzf kiwion-offline.tar.gz && cd kiwion-offline
#   sudo bash install.sh kiwion.duckdns.org admin@mail.ru            # model on a home PC
#   sudo WITH_MODEL=1 bash install.sh kiwion.duckdns.org admin@mail.ru  # model on this VPS
#
# Model weights (WITH_MODEL=1), any of:
#   * models/*.gguf next to install.sh (or KIWION_WEIGHTS_URL = Yandex Disk public link to a .gguf)
#   * the original Hugging Face folder in models/hf/OLMo-2-0425-1B-Instruct (or a zip of it via
#     KIWION_WEIGHTS_URL) + kiwion-convert-tools.tar.gz next to this script (PyTorch etc. for conversion)
# Safe to re-run (updates code, keeps data and secrets).
set -euo pipefail
DOMAIN="${1:?usage: install.sh <domain> <admin-email>}"
ADMIN="${2:?admin e-mail required}"
SRC="$(cd "$(dirname "$0")" && pwd)"
APP=/opt/kiwion-app
WITH_MODEL="${WITH_MODEL:-0}"
say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

say "packages from the Ubuntu mirror"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q python3 python3-venv python3-dev build-essential cmake caddy ufw openssl curl unzip rsync

say "copying Kiwion to $APP"
id kiwion >/dev/null 2>&1 || useradd -r -m -d /var/lib/kiwion -s /usr/sbin/nologin kiwion
mkdir -p "$APP"
rsync -a --delete --exclude .env --exclude data --exclude models --exclude .venv --exclude third_party/llama.cpp/build \
  "$SRC/kiwion-chat/" "$APP/"
mkdir -p "$APP/data" "$APP/models/hf" "$APP/third_party"
rsync -a --exclude build "$SRC/llama.cpp/" "$APP/third_party/llama.cpp/"

say "Python environment (offline wheels)"
[ -x "$APP/.venv/bin/python" ] || python3 -m venv "$APP/.venv"
"$APP/.venv/bin/pip" install -q --no-index --find-links "$SRC/wheels/runtime" \
  fastapi "uvicorn[standard]" sqlalchemy argon2-cffi cryptography pydantic email-validator httpx

ENV="$APP/.env"
if [ ! -f "$ENV" ]; then
  say "creating $ENV with random secrets"
  cp "$APP/.env.example" "$ENV"
  set_env() { sed -i "s#^$1=.*#$1=$2#" "$ENV"; }
  set_env KIWION_ENV production
  set_env KIWION_SECRET_KEY "$(openssl rand -hex 32)"
  set_env KIWION_INFERENCE_SECRET "$(openssl rand -hex 32)"
  set_env KIWION_PUBLIC_URL "https://$DOMAIN"
  set_env KIWION_DOMAIN "$DOMAIN"
  set_env KIWION_HTTPS 1
  set_env KIWION_TRUSTED_PROXIES 127.0.0.1
  set_env KIWION_ADMIN_EMAILS "$ADMIN"
  set_env KIWION_MAIL_MODE smtp
  set_env KIWION_DATABASE_URL "sqlite:///$APP/data/kiwion.db"
  if [ "$WITH_MODEL" = "1" ]; then
    set_env KIWION_INFERENCE_URL http://127.0.0.1:8090
    set_env KIWION_INFERENCE_HOST 127.0.0.1
    set_env KIWION_THREADS "$(nproc)"
  else
    set_env KIWION_INFERENCE_URL http://10.8.0.2:8090
  fi
fi
grep -q '^KIWION_LOG_DIR=' "$ENV" || echo "KIWION_LOG_DIR=$APP/data/logs" >> "$ENV"

if [ "$WITH_MODEL" = "1" ]; then
  say "building llama.cpp for this CPU (5-20 min)"
  if [ ! -x "$APP/third_party/llama.cpp/build/bin/llama-server" ]; then
    if ! swapon --show | grep -q .; then
      fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
      grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    (cd "$APP/third_party/llama.cpp" && cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DLLAMA_CURL=OFF \
       -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON -DLLAMA_USE_PREBUILT_UI=OFF >/dev/null \
     && cmake --build build -j "$(nproc)" --target llama-server llama-quantize llama-bench)
  fi

  say "model weights"
  cp -n "$SRC"/models/*.gguf "$APP/models/" 2>/dev/null || true
  [ -d "$SRC/models/hf" ] && rsync -a "$SRC/models/hf/" "$APP/models/hf/"
  if [ -n "${KIWION_WEIGHTS_URL:-}" ] && ! ls "$APP"/models/*.gguf >/dev/null 2>&1; then
    bash "$APP/scripts/fetch_yadisk.sh" "$KIWION_WEIGHTS_URL" "$APP/models/download.bin"
    if unzip -tq "$APP/models/download.bin" >/dev/null 2>&1; then
      unzip -oq "$APP/models/download.bin" -d "$APP/models/unpacked" && rm "$APP/models/download.bin"
      find "$APP/models/unpacked" -name '*.gguf' -exec mv {} "$APP/models/" \;
      CFG="$(find "$APP/models/unpacked" -name config.json | head -1)"
      [ -n "$CFG" ] && rsync -a "$(dirname "$CFG")/" "$APP/models/hf/OLMo-2-0425-1B-Instruct/"
      rm -rf "$APP/models/unpacked"
    else
      mv "$APP/models/download.bin" "$APP/models/olmo-2-1b-instruct-Q4_K_M.gguf"
    fi
  fi
  GGUF="$(ls -S "$APP"/models/*.gguf 2>/dev/null | grep -v tiny | head -1 || true)"
  if [ -z "$GGUF" ]; then
    HF="$APP/models/hf/OLMo-2-0425-1B-Instruct"
    [ -f "$HF/config.json" ] || HF="$(dirname "$(find "$APP/models/hf" -name config.json | head -1)" 2>/dev/null || true)"
    if [ -z "$HF" ] || [ ! -f "$HF/config.json" ]; then
      echo "!!! no model weights found. Put a .gguf into $SRC/models/ or the Hugging Face folder into"
      echo "    $SRC/models/hf/OLMo-2-0425-1B-Instruct/ (or set KIWION_WEIGHTS_URL) and run this script again."
      exit 1
    fi
    TOOLS="$(ls "$SRC"/kiwion-convert-tools*.tar.gz "$SRC"/../kiwion-convert-tools*.tar.gz 2>/dev/null | head -1 || true)"
    [ -n "$TOOLS" ] || { echo "!!! converting HF weights needs kiwion-convert-tools.tar.gz next to install.sh"; exit 1; }
    say "converting the original OLMo 2 weights to GGUF (Q4_K_M)"
    TMPW="$(mktemp -d)"; tar xzf "$TOOLS" -C "$TMPW"
    python3 -m venv "$TMPW/venv"
    "$TMPW/venv/bin/pip" install -q --no-index --find-links "$TMPW/wheels" torch numpy sentencepiece transformers protobuf
    "$TMPW/venv/bin/python" "$APP/third_party/llama.cpp/convert_hf_to_gguf.py" "$HF" --outtype f16 --outfile "$APP/models/olmo-2-1b-instruct-F16.gguf"
    "$APP/third_party/llama.cpp/build/bin/llama-quantize" "$APP/models/olmo-2-1b-instruct-F16.gguf" "$APP/models/olmo-2-1b-instruct-Q4_K_M.gguf" Q4_K_M
    rm -rf "$TMPW" "$APP/models/olmo-2-1b-instruct-F16.gguf"
    GGUF="$APP/models/olmo-2-1b-instruct-Q4_K_M.gguf"
  fi
  sed -i "s#^KIWION_MODEL_PATH=.*#KIWION_MODEL_PATH=$GGUF#" "$ENV"
  echo "model: $GGUF"
fi
chown -R kiwion:kiwion "$APP"
chmod 600 "$ENV"

say "systemd services"
PYPATH="$APP/shared:$APP/backend:$APP/inference:$APP/cli"
cat > /etc/systemd/system/kiwion-backend.service <<UNIT
[Unit]
Description=Kiwion Backend API
After=network-online.target
[Service]
User=kiwion
WorkingDirectory=$APP
EnvironmentFile=$ENV
Environment=PYTHONPATH=$PYPATH
ExecStart=$APP/.venv/bin/python -m kiwion_backend
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$APP/data
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
if [ "$WITH_MODEL" = "1" ]; then
cat > /etc/systemd/system/kiwion-inference.service <<UNIT
[Unit]
Description=Kiwion Inference (OLMo 2 1B via llama.cpp)
After=network-online.target
[Service]
User=kiwion
WorkingDirectory=$APP
EnvironmentFile=$ENV
Environment=PYTHONPATH=$PYPATH
ExecStart=$APP/.venv/bin/python -m kiwion_inference
Restart=always
RestartSec=5
Nice=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$APP/data
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
fi
systemctl daemon-reload
systemctl enable -q kiwion-backend && systemctl restart kiwion-backend
if [ "$WITH_MODEL" = "1" ]; then systemctl enable -q kiwion-inference && systemctl restart kiwion-inference; fi

say "HTTPS (Caddy + Let's Encrypt) for $DOMAIN"
cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8080 {
		flush_interval -1
	}
	header Strict-Transport-Security "max-age=63072000; includeSubDomains"
	request_body {
		max_size 2MB
	}
}
CADDY
systemctl enable -q caddy && systemctl restart caddy

say "firewall"
ufw allow OpenSSH >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
[ "$WITH_MODEL" = "1" ] || ufw allow 51820/udp >/dev/null
ufw --force enable >/dev/null

say "waiting for the backend"
for _ in $(seq 60); do curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:8080/api/health >/dev/null || { journalctl -u kiwion-backend -n 30 --no-pager; exit 1; }

CRED=/root/kiwion-admin.txt
if [ ! -f "$CRED" ]; then
  PASS="Kiwi7$(openssl rand -hex 6)"
  sudo -u kiwion bash -c 'set -a; . "$1"; set +a; export PYTHONPATH="$2"; exec "$3" -m kiwion_backend create-admin --email "$4" --password "$5"' \
    _ "$ENV" "$PYPATH" "$APP/.venv/bin/python" "$ADMIN" "$PASS" >/dev/null
  printf 'Kiwion admin\nurl: https://%s/admin/\nemail: %s\npassword: %s\n' "$DOMAIN" "$ADMIN" "$PASS" > "$CRED"
  chmod 600 "$CRED"
fi

echo
echo "================================================================"
echo " Kiwion Chat:   https://$DOMAIN   (HTTPS certificate may take ~1 min)"
echo " Admin panel:   https://$DOMAIN/admin/"
sed -n '3,4p' "$CRED" | sed 's/^/ /'
echo " (saved in $CRED)"
echo " Next: admin panel → «Почта» → set up Gmail/Yandex for verification codes."
[ "$WITH_MODEL" = "1" ] && echo " Model status:  journalctl -u kiwion-inference -f"
echo " Logs:          journalctl -u kiwion-backend -f"
echo "================================================================"
