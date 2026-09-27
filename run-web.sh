#!/usr/bin/env bash
set -euo pipefail

WEB_PORT="${WEB_PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"

echo "[web] waiting for VNC on 127.0.0.1:${VNC_PORT}"
while ! (echo >/dev/tcp/127.0.0.1/"${VNC_PORT}") 2>/dev/null; do
  sleep 0.25
done

echo "[web] native websockify + noVNC: http://127.0.0.1:${WEB_PORT}"

exec /app/websockify-go \
  -l "127.0.0.1:${WEB_PORT}" \
  -t "127.0.0.1:${VNC_PORT}" \
  -web /app/novnc
