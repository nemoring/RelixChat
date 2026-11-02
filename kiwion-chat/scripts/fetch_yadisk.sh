#!/usr/bin/env bash
# Download a file (or a folder as zip) from a public Yandex Disk link:
#   scripts/fetch_yadisk.sh https://disk.yandex.ru/d/XXXX output-file
set -euo pipefail
LINK="${1:?public Yandex Disk link}"; OUT="${2:?output file}"
HREF="$(curl -fsSG https://cloud-api.yandex.net/v1/disk/public/resources/download --data-urlencode "public_key=$LINK" \
  | sed -n 's/.*"href":"\([^"]*\)".*/\1/p')"
[ -n "$HREF" ] || { echo "Yandex Disk did not return a download link (is the link public?)"; exit 1; }
curl -fL --retry 5 -o "$OUT" "$HREF"
echo "downloaded $(du -h "$OUT" | cut -f1) -> $OUT"
