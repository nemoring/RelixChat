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
set -euo pipefail
DOMAIN="${1:?usage: install_vps.sh <domain> <admin-email> <git-url> [branch]}"
ADMIN="${2:?admin e-mail required}"
REPO="${3:?git url required}"
BRANCH="${4:-main}"
DIR=/opt/kiwion

apt-get update -q
apt-get install -y -q ca-certificates curl git openssl ufw
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi

if [ ! -d "$DIR/.git" ]; then git clone -b "$BRANCH" "$REPO" "$DIR"; else git -C "$DIR" pull --ff-only; fi
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
  set_env KIWION_MAIL_MODE smtp
  chmod 600 .env
  echo ">>> .env created. Fill in KIWION_SMTP_* (mail) in $DIR/kiwion-chat/.env, then re-run this script."
  if [ "${WITH_MODEL:-0}" != "1" ]; then
    echo ">>> Copy KIWION_INFERENCE_SECRET to the home inference PC's .env:"
    grep '^KIWION_INFERENCE_SECRET=' .env
  fi
  exit 0
fi

ufw allow OpenSSH >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
[ "${WITH_MODEL:-0}" = "1" ] || ufw allow 51820/udp >/dev/null   # WireGuard to the home PC
ufw --force enable >/dev/null

PROFILE=()
if [ "${WITH_MODEL:-0}" = "1" ]; then
  PROFILE=(--profile model)
  if [ ! -f models/olmo-2-1b-instruct-Q4_K_M.gguf ]; then
    apt-get install -y -q build-essential cmake python3-venv
    if ! swapon --show | grep -q .; then        # conversion is safer with some swap on 4 GB VPS
      fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
      grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    JOBS="$(nproc)" bash scripts/build_llamacpp.sh
    bash scripts/download_model.sh            # original OLMo 2 1B Instruct -> GGUF Q4_K_M
  fi
fi

docker compose -f deploy/docker-compose.vps.yml "${PROFILE[@]}" up -d --build
for _ in $(seq 60); do
  curl -fsS "https://$DOMAIN/api/health" >/dev/null 2>&1 && break; sleep 3
done
curl -fsS "https://$DOMAIN/api/health" && echo
echo "Kiwion Chat is up: https://$DOMAIN  (admin panel: https://$DOMAIN/admin/)"
echo "Register $ADMIN on the site — it becomes an administrator after e-mail confirmation."
echo "Android build for this server:  KIWION_SERVER_URL=https://$DOMAIN mobile/build_apk.sh"
