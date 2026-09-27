#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-$HOME/data}"
DATA="$ROOT/nro-data"
PASS_TXT="$DATA/vnc-password.txt"
PASS_FILE="$DATA/vnc.pass"
mkdir -p "$DATA"

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  printf '%s\n' "${VNC_PASSWORD:0:8}" >"$PASS_TXT"
elif [[ ! -s "$PASS_TXT" ]]; then
  printf '%s\n' "$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-8)" >"$PASS_TXT"
fi

x11vnc -storepasswd "$(head -n1 "$PASS_TXT")" "$PASS_FILE" >/dev/null
chmod 600 "$PASS_FILE" "$PASS_TXT"

for _ in {1..50}; do
  [[ -S /tmp/.X11-unix/X99 ]] && break
  sleep 0.1
done

echo "[vnc] password: $(head -n1 "$PASS_TXT")"
exec x11vnc -display :99 -rfbport 5900 -rfbauth "$PASS_FILE" -forever -shared -localhost -noxdamage -repeat -quiet
