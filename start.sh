#!/usr/bin/env bash
set -euo pipefail

mkdir -p /data "$HOME/.xpra"

# Use an explicit password if supplied by the host. Otherwise generate one once
# and persist it in /data so it survives container restarts.
if [[ -n "${XPRA_PASSWORD:-}" ]]; then
  printf '%s' "$XPRA_PASSWORD" > /data/xpra-password
  chmod 600 /data/xpra-password
else
  if [[ ! -s /data/xpra-password ]]; then
    umask 077
    openssl rand -hex 12 > /data/xpra-password
  fi
  XPRA_PASSWORD="$(cat /data/xpra-password)"
  export XPRA_PASSWORD
fi

printf '\n============================================================\n'
printf ' NRO service starting on port %s\n' "${PORT:-8080}"
printf ' Xpra / first-upload password: %s\n' "$XPRA_PASSWORD"
printf ' Password is also stored in /data/xpra-password\n'
printf '============================================================\n\n'

# The game binary is deliberately NOT stored in the public GitHub repository.
# On first deploy, expose a tiny password-protected upload form. The uploaded
# JAR is persisted at /data/game.jar, then this process hands the same port to Xpra.
if [[ ! -s /data/game.jar ]]; then
  echo "[nro] /data/game.jar not found; starting one-time browser uploader..."
  export UPLOAD_PASSWORD="$XPRA_PASSWORD"
  python3 /app/upload.py
fi

if [[ ! -s /data/game.jar ]]; then
  echo "[nro] upload server exited but /data/game.jar is missing" >&2
  exit 1
fi

exec xpra start :100 \
  --bind-tcp="0.0.0.0:${PORT:-8080},auth=env" \
  --html=on \
  --daemon=no \
  --dbus=no \
  --mdns=no \
  --pulseaudio=no \
  --notifications=no \
  --printing=no \
  --webcam=no \
  --file-transfer=no \
  --clipboard=no \
  --exit-with-children=no \
  --session-name=NRO \
  --start-child=/app/run-game.sh
