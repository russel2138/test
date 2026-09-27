#!/usr/bin/env bash
set -euo pipefail

WEB_PORT="${PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"

echo "[web] waiting for VNC on 127.0.0.1:${VNC_PORT}"
while ! (echo >/dev/tcp/127.0.0.1/"${VNC_PORT}") 2>/dev/null; do
  sleep 0.25
done

echo "[web] noVNC ready on 0.0.0.0:${WEB_PORT}"
echo "[web] open the Blitz public URL in a browser"

exec /usr/bin/websockify \
  --web=/app/novnc \
  "0.0.0.0:${WEB_PORT}" \
  "127.0.0.1:${VNC_PORT}"
