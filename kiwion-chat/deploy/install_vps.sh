#!/usr/bin/env bash
# One-command installation of the Kiwion Chat server (backend + web + admin, HTTPS via Caddy) on a VPS.
# Run as root on a fresh Ubuntu/Debian VPS whose DNS A-record already points to it:
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<branch>/kiwion-chat/deploy/install_vps.sh -o install_vps.sh
#   sudo bash install_vps.sh chat.example.com admin@example.com <git-url> [branch]
#   sudo WITH_MODEL=1 bash install_vps.sh ...     # also run the model (OLMo 2 1B) on this VPS
#
# Without WITH_MODEL the inference node (home PC) is connected via WireGuard (see docs/DEPLOYMENT.md).
# With WITH_MODEL=1 you need >= 4 GB RAM and 2+ vCPU; llama.cpp is built and the original
# OLMo 2 weights are downloaded and converted to GGUF here (takes 15-40 minutes once).
#
# A single run installs everything. E-mail (SMTP) is configured afterwards in the admin panel
# (https://<domain>/admin/ → «Почта»); the admin account and its password are created by this script.
# Safe to re-run: it updates the code and restarts the services.
set -euo pipefail
DOMAIN="${1:?usage: install_vps.sh <domain> <admin-email> <git-url> [branch]}"
ADMIN="${2:?admin e-mail required}"
REPO="${3:?git url required}"
BRANCH="${4:-main}"
DIR=/opt/kiwion

# network to GitHub/Docker Hub can be flaky from some regions: retry instead of failing at once
retry() { local n=1; until "$@"; do [ $n -ge 6 ] && return 1; echo "retry $n/5: $*"; n=$((n+1)); sleep $((n*5)); done; }
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60
git() { command git -c http.version=HTTP/1.1 "$@"; }

apt-get update -q
apt-get install -y -q ca-certificates curl git openssl ufw
if ! command -v docker >/dev/null; then
  retry sh -c 'curl -fsSL https://get.docker.com | sh' || { apt-get install -y -q docker.io docker-compose-v2; }
fi
# Docker Hub is often unreachable from Russian data centres: fall back to Google's public mirror
if ! curl -s -m 15 -o /dev/null https://registry-1.docker.io/v2/; then
  echo "Docker Hub is not reachable — using the mirror.gcr.io registry mirror"
  mkdir -p /etc/docker
  [ -f /etc/docker/daemon.json ] || echo '{"registry-mirrors": ["https://mirror.gcr.io"]}' > /etc/docker/daemon.json
  systemctl restart docker
fi

if [ -d "$DIR/.git" ]; then
  retry git -C "$DIR" fetch -q origin "$BRANCH"
  git -C "$DIR" checkout -q -B "$BRANCH" "origin/$BRANCH"
elif [ -d "$DIR" ]; then            # e.g. weights were uploaded to $DIR/kiwion-chat/models before the first run
  git -C "$DIR" init -q && git -C "$DIR" remote add origin "$REPO" 2>/dev/null || true
  retry git -C "$DIR" fetch -q origin "$BRANCH"
  git -C "$DIR" checkout -q -f -B "$BRANCH" "origin/$BRANCH"
else
  retry git clone -q -b "$BRANCH" "$REPO" "$DIR"
fi
cd "$DIR/kiwion-chat"

if [ ! -f .env ]; then
  cp .env.example .env
  set_env() { sed -i "s#^$1=.*#$1=$2#" .env; }
  set_env KIWION_ENV production
  set_env KIWION_SECRET_KEY "$(openssl rand -hex 32)"
  set_env KIWION_INFERENCE_SECRET "$(openssl rand -hex 32)"
  set_env KIWION_PUBLIC_URL "https://$DOMAIN"
  set_env KIWION_DOMAIN "$DOMAIN"
  set_env KIWION_HTTPS 1
  if [ "${WITH_MODEL:-0}" = "1" ]; then
    set_env KIWION_INFERENCE_URL "http://inference:8090"
    set_env KIWION_THREADS "$(nproc)"
    set_env KIWION_INFERENCE_HOST 0.0.0.0
  else
    set_env KIWION_INFERENCE_URL "http://10.8.0.2:8090"
  fi
  set_env KIWION_ADMIN_EMAILS "$ADMIN"
  set_env KIWION_MAIL_MODE smtp      # SMTP server/password are set in the admin panel → «Почта»
  chmod 600 .env
  echo ">>> created $DIR/kiwion-chat/.env with random secrets"
fi
mkdir -p models/hf

ufw allow OpenSSH >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
[ "${WITH_MODEL:-0}" = "1" ] || ufw allow 51820/udp >/dev/null   # WireGuard to the home PC
ufw --force enable >/dev/null

PROFILE=()
if [ "${WITH_MODEL:-0}" = "1" ]; then
  PROFILE=(--profile model)
  MODEL_FILE="$(grep '^KIWION_MODEL_FILE=' .env | cut -d= -f2-)"
  MODEL_FILE="${MODEL_FILE:-olmo-2-1b-instruct-Q4_K_M.gguf}"
  if [ -f "models/$MODEL_FILE" ]; then
    echo "using existing model models/$MODEL_FILE"
  else
    apt-get install -y -q build-essential cmake python3-venv
    if ! swapon --show | grep -q .; then        # conversion is safer with some swap on 4 GB VPS
      fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
      grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    JOBS="$(nproc)" retry bash scripts/build_llamacpp.sh
    retry bash scripts/download_model.sh      # original OLMo 2 1B Instruct -> GGUF Q4_K_M
                                              # (reuses weights uploaded to models/hf/OLMo-2-0425-1B-Instruct)
  fi
fi

retry docker compose --env-file .env -f deploy/docker-compose.vps.yml "${PROFILE[@]}" up -d --build
for _ in $(seq 60); do
  curl -fsS "https://$DOMAIN/api/health" >/dev/null 2>&1 && break; sleep 3
done
curl -fsS "https://$DOMAIN/api/health" && echo || echo "!!! https://$DOMAIN does not answer yet — see: docker compose --env-file .env -f deploy/docker-compose.vps.yml logs --tail=50"

# administrator account (created once; the password is shown here and saved for root only)
CRED=/root/kiwion-admin.txt
if [ ! -f "$CRED" ]; then
  PASS="Kiwi7$(openssl rand -hex 6)"
  docker compose --env-file .env -f deploy/docker-compose.vps.yml exec -T backend \
    python -m kiwion_backend create-admin --email "$ADMIN" --password "$PASS" >/dev/null
  printf 'Kiwion admin\nurl: https://%s/admin/\nemail: %s\npassword: %s\n' "$DOMAIN" "$ADMIN" "$PASS" > "$CRED"
  chmod 600 "$CRED"
fi

echo
echo "================================================================"
echo " Kiwion Chat is up:  https://$DOMAIN"
echo " Admin panel:        https://$DOMAIN/admin/"
cat "$CRED" | sed -n '3,4p' | sed 's/^/ /'
echo " (saved in $CRED — change the password after the first login)"
echo " Next: admin panel → «Почта» → set up Gmail/Yandex so users receive their codes."
[ "${WITH_MODEL:-0}" = "1" ] || { echo " Home inference PC needs this secret:"; grep '^KIWION_INFERENCE_SECRET=' .env | sed 's/^/ /'; }
echo "================================================================"
