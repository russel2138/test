#!/usr/bin/env bash
set -euo pipefail

WEB_PORT="${WEB_PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"

echo "[web] waiting for VNC on 127.0.0.1:${VNC_PORT}"
while ! (echo >/dev/tcp/127.0.0.1/"${VNC_PORT}") 2>/dev/null; do
  sleep 0.25
done

echo "[web] noVNC internal: http://127.0.0.1:${WEB_PORT}"

exec /usr/bin/websockify \
  --web=/app/novnc \
  "127.0.0.1:${WEB_PORT}" \
  "127.0.0.1:${VNC_PORT}"
