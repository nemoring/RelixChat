#!/usr/bin/env bash
# Create a private CA plus server/client certificates for mutual TLS between
# Kiwion Backend (VPS) and Kiwion Inference (home computer).
#
#   scripts/gen_certs.sh inference.example.org 10.8.0.2
# Output in deploy/certs/: ca.crt, inference.crt/.key (server), backend.crt/.key (client)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${KIWION_CERTS_DIR:-$ROOT/deploy/certs}"
HOST="${1:-kiwion-inference}"
IP="${2:-127.0.0.1}"
mkdir -p "$OUT"; cd "$OUT"
umask 077
[ -f ca.key ] || openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj "/CN=Kiwion Private CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -keyout ca.key -out ca.crt
cat > san.ext <<EXT
subjectAltName=DNS:${HOST},DNS:localhost,IP:${IP},IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=critical,digitalSignature,keyEncipherment
basicConstraints=critical,CA:FALSE
authorityKeyIdentifier=keyid
EXT
openssl req -newkey rsa:2048 -nodes -subj "/CN=${HOST}" -keyout inference.key -out inference.csr
openssl x509 -req -in inference.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 825 -extfile san.ext -out inference.crt
printf 'extendedKeyUsage=clientAuth\nkeyUsage=critical,digitalSignature,keyEncipherment\nbasicConstraints=critical,CA:FALSE\nauthorityKeyIdentifier=keyid\n' > client.ext
openssl req -newkey rsa:2048 -nodes -subj "/CN=kiwion-backend" -keyout backend.key -out backend.csr
openssl x509 -req -in backend.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 825 -extfile client.ext -out backend.crt
rm -f *.csr *.ext
echo "certificates in $OUT"
echo "inference node: KIWION_INFERENCE_SSL_CERT=inference.crt KIWION_INFERENCE_SSL_KEY=inference.key KIWION_INFERENCE_SSL_CLIENT_CA=ca.crt"
echo "backend (VPS):  KIWION_INFERENCE_URL=https://${HOST}:8090 KIWION_INFERENCE_CA_CERT=ca.crt KIWION_INFERENCE_CLIENT_CERT=backend.crt KIWION_INFERENCE_CLIENT_KEY=backend.key"
