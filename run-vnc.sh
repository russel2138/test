#!/usr/bin/env bash
set -euo pipefail

mkdir -p /data
PASSFILE=/data/vnc.pass
PLAINTEXT=/data/vnc-password.txt

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  printf '%s\n' "$VNC_PASSWORD" > "$PLAINTEXT"
fi

if [[ ! -s "$PLAINTEXT" ]]; then
  generated="$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-12)"
  printf '%s\n' "$generated" > "$PLAINTEXT"
fi

if [[ ! -s "$PASSFILE" || "${VNC_PASSWORD:-}" != "" ]]; then
  x11vnc -storepasswd "$(head -n1 "$PLAINTEXT")" "$PASSFILE" >/dev/null
  chmod 600 "$PASSFILE" "$PLAINTEXT"
fi

echo "[vnc] password: $(head -n1 "$PLAINTEXT")"

while [[ ! -S /tmp/.X11-unix/X99 ]]; do
  echo "[vnc] waiting for display ${DISPLAY:-:99}"
  sleep 2
done

exec x11vnc -display "${DISPLAY:-:99}" -rfbport "${VNC_PORT:-5900}" -rfbauth "$PASSFILE" -forever -shared -noxdamage -repeat -quiet
