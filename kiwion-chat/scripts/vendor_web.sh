#!/usr/bin/env bash
# Re-download the small browser libraries used by Kiwion Web into web/vendor.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
cd "$TMP"
npm init -y >/dev/null
npm i --silent marked@12.0.2 dompurify@3.1.6 @highlightjs/cdn-assets@11.10.0
N="$TMP/node_modules"
cp "$N/marked/marked.min.js" "$N/dompurify/dist/purify.min.js" "$N/@highlightjs/cdn-assets/highlight.min.js" "$ROOT/web/vendor/"
cp "$N/@highlightjs/cdn-assets/styles/github.min.css" "$ROOT/web/vendor/hljs-light.css"
cp "$N/@highlightjs/cdn-assets/styles/github-dark.min.css" "$ROOT/web/vendor/hljs-dark.css"
rm -rf "$TMP"
echo "vendored libraries updated"
