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
printf ' NRO background service starting\n'
printf ' Local UI port: %s\n' "${PORT:-8080}"
printf ' Xpra / first-upload password: %s\n' "$XPRA_PASSWORD"
printf ' Watch Logs for: NRO_REMOTE_URL=https://...trycloudflare.com\n'
printf '============================================================\n\n'

# Start an outbound Cloudflare Quick Tunnel first. It points at localhost:8080.
# Initially that port is the one-time uploader; after the JAR is uploaded the
# uploader exits and Xpra takes over the same port, so the same tunnel keeps
# working without needing a Blitz public address.
 /app/run-tunnel.sh &
TUNNEL_SUPERVISOR_PID=$!

cleanup() {
  kill "$TUNNEL_SUPERVISOR_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# The game binary is deliberately NOT stored in the public GitHub repository.
# On first deploy, expose a tiny password-protected upload form through the
# trycloudflare URL. The uploaded JAR is persisted at /data/game.jar.
if [[ ! -s /data/game.jar ]]; then
  echo "[nro] /data/game.jar not found."
  echo "[nro] Wait for NRO_REMOTE_URL in Logs, open it, then upload the JAR."
  export UPLOAD_PASSWORD="$XPRA_PASSWORD"
  python3 /app/upload.py
fi

if [[ ! -s /data/game.jar ]]; then
  echo "[nro] upload server exited but /data/game.jar is missing" >&2
  exit 1
fi

echo "[nro] game JAR present; starting Xpra HTML5 on localhost:${PORT:-8080}"

# Bind only to loopback. The public path is cloudflared -> localhost -> Xpra.
xpra start :100 \
  --bind-tcp="127.0.0.1:${PORT:-8080},auth=env" \
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
