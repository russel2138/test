#!/usr/bin/env bash
set -euo pipefail

WEB_PORT="${PORT:-${NOVNC_PORT:-8080}}"
VNC_PORT="${VNC_PORT:-5900}"

if [[ ! -s /data/game.jar ]]; then
  echo "[web] /data/game.jar missing; opening one-time upload page on port $WEB_PORT"
  python3 /app/upload.py
  echo "[web] game.jar uploaded; switching port $WEB_PORT to noVNC"
fi

echo "[web] noVNC listening on 0.0.0.0:$WEB_PORT"

while ! (echo >/dev/tcp/127.0.0.1/"$VNC_PORT") 2>/dev/null; do
  echo "[web] waiting for VNC on 127.0.0.1:$VNC_PORT"
  sleep 2
done

exec websockify \
  --web=/usr/share/novnc \
  "0.0.0.0:$WEB_PORT" \
  "127.0.0.1:$VNC_PORT"
