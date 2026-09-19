#!/usr/bin/env bash
set -uo pipefail

PORT="${NOVNC_PORT:-8080}"
rm -f /data/tunnel-url.txt

echo "[tunnel] Cloudflare Quick Tunnel -> http://127.0.0.1:${PORT}"
echo "[tunnel] remote access is optional; game keeps running if this process dies"

cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${PORT}" 2>&1 |
while IFS= read -r line; do
  printf '[cloudflared] %s\n' "$line"
  if [[ "$line" =~ (https://[A-Za-z0-9-]+\.trycloudflare\.com) ]]; then
    url="${BASH_REMATCH[1]}"
    printf '%s\n' "$url" > /data/tunnel-url.txt
    printf '\nNRO_REMOTE_URL=%s\n\n' "$url"
  fi
done

exit "${PIPESTATUS[0]}"
