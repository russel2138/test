#!/usr/bin/env bash
set -euo pipefail

WEB_PORT="${WEB_PORT:-8080}"

echo "[tunnel] waiting for noVNC on 127.0.0.1:${WEB_PORT}"
while ! (echo >/dev/tcp/127.0.0.1/"${WEB_PORT}") 2>/dev/null; do
  sleep 0.25
done

echo "============================================================"
echo " Cloudflare Quick Tunnel"
echo " Open the https://*.trycloudflare.com URL printed below"
echo " URL changes whenever this tunnel process restarts"
echo "============================================================"

exec /app/cloudflared tunnel \
  --no-autoupdate \
  --url "http://127.0.0.1:${WEB_PORT}"
