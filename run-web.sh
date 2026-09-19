#!/usr/bin/env bash
set -euo pipefail

PORT="${NOVNC_PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"

if [[ ! -s /data/game.jar ]]; then
  echo "[web] game.jar missing; starting one-time upload page"
  python3 /app/upload.py
  echo "[web] upload completed; starting noVNC"
fi

while ! (echo >/dev/tcp/127.0.0.1/"$VNC_PORT") 2>/dev/null; do
  echo "[web] waiting for VNC on 127.0.0.1:$VNC_PORT"
  sleep 2
done

exec websockify   --web=/usr/share/novnc   "0.0.0.0:$PORT"   "127.0.0.1:$VNC_PORT"
