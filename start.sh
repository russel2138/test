#!/usr/bin/env bash
set -euo pipefail

mkdir -p /data "$HOME/.xpra" /data/microemu-home/.microemulator

# Xpra warns/fails in some container environments when XDG_RUNTIME_DIR is
# missing. Use a private writable runtime directory for uid 1000.
export XDG_RUNTIME_DIR=/tmp/xdg-runtime-1000
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

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
printf ' Persistent game state: /data/microemu-home/.microemulator\n'
printf ' Watch Logs for: NRO_REMOTE_URL=https://...trycloudflare.com\n'
printf '============================================================\n\n'

# Runtime diagnostics so Blitz logs show exactly what Xpra packages are present.
echo "[diag] XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "[diag] xpra binary: $(command -v xpra || true)"
xpra --version 2>&1 | sed 's/^/[diag] /' || true
dpkg-query -W -f='[diag] ${Package} ${Version}\n' xpra xpra-x11 xpra-html5 2>&1 || true
echo "[diag] Xvfb binary: $(command -v Xvfb || true)"

/app/run-tunnel.sh &
TUNNEL_SUPERVISOR_PID=$!

cleanup() {
  xpra stop :100 >/dev/null 2>&1 || true
  kill "$TUNNEL_SUPERVISOR_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' INT TERM

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

# Keep the container alive even if Xpra itself fails. This prevents Blitz from
# immediately rolling back the whole background worker and also leaves the
# Cloudflare tunnel supervisor running while we capture the real Xpra error.
while true; do
  if xpra start :100 \
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
    --start=/app/run-game.sh
  then
    rc=0
  else
    rc=$?
  fi

  echo "[xpra] exited with code $rc; retrying in 5 seconds..."
  sleep 5
done
