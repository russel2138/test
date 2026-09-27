#!/usr/bin/env bash
set -euo pipefail

VNC_PORT="${VNC_PORT:-5900}"

if [[ -z "${TUNNEL_TOKEN:-}" ]]; then
  echo "[tunnel] TUNNEL_TOKEN is not set." >&2
  echo "[tunnel] Create a Cloudflare Named Tunnel, route its fixed hostname to tcp://127.0.0.1:${VNC_PORT}," >&2
  echo "[tunnel] then add the tunnel token to Blitz as TUNNEL_TOKEN." >&2
  exit 2
fi

echo "[tunnel] waiting for VNC on 127.0.0.1:${VNC_PORT}"
while ! (echo >/dev/tcp/127.0.0.1/"${VNC_PORT}") 2>/dev/null; do
  sleep 0.25
done

echo "[tunnel] starting Cloudflare Named Tunnel"
if [[ -n "${TUNNEL_HOSTNAME:-}" ]]; then
  echo "[tunnel] fixed hostname: ${TUNNEL_HOSTNAME}"
fi
echo "[tunnel] origin service must be configured as tcp://127.0.0.1:${VNC_PORT}"

exec /app/cloudflared tunnel \
  --no-autoupdate \
  run \
  --token "${TUNNEL_TOKEN}"
