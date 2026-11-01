#!/usr/bin/env bash
# Robolectric UI tests of the Android app. Starts a local backend + inference (mock engine) so the
# app's real networking code (registration with proof-of-work, e-mail code, SSE streaming, stop) is exercised.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
BPORT=18780; IPORT=18781
export KIWION_INFERENCE_SECRET="u$(printf 'i%.0s' {1..40})" KIWION_ENGINE=mock KIWION_MOCK_DELAY=0.06 \
  KIWION_INFERENCE_PORT=$IPORT KIWION_INFERENCE_URL=http://127.0.0.1:$IPORT KIWION_PORT=$BPORT \
  KIWION_PUBLIC_URL=http://127.0.0.1:$BPORT KIWION_DATABASE_URL="sqlite:///$TMP/db.sqlite" \
  KIWION_OUTBOX_DIR="$TMP/outbox" KIWION_POW_DIFFICULTY=8 KIWION_LOG_DIR="$TMP" KIWION_SECRET_KEY="$(printf 'q%.0s' {1..48})" \
  PYTHONPATH="$ROOT/shared:$ROOT/backend:$ROOT/inference:$ROOT/cli"
python3 -m kiwion_inference > "$TMP/inference.log" 2>&1 & IPID=$!
python3 -m kiwion_backend > "$TMP/backend.log" 2>&1 & BPID=$!
trap 'kill $IPID $BPID 2>/dev/null; [ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"; echo "tmp: $TMP"' EXIT
for _ in $(seq 60); do curl -sf "http://127.0.0.1:$BPORT/api/health" >/dev/null && break; sleep 0.3; done
KIWION_TEST_SERVER="http://127.0.0.1:$BPORT" KIWION_TEST_OUTBOX="$TMP/outbox" gradle --no-daemon -q testDebugUnitTest "$@"
