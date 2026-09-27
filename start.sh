#!/usr/bin/env bash
set -uo pipefail

mkdir -p /data/microemu-home/.microemulator

PIDS=()

shutdown() {
  trap - INT TERM
  if (("${#PIDS[@]}" > 0)); then
    kill "${PIDS[@]}" 2>/dev/null || true
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
  exit 0
}
trap shutdown INT TERM

echo "============================================================"
echo " NRO / Blitz background + native VNC"
echo " game       : /app/game.jar"
echo " state      : /data/microemu-home/.microemulator"
echo " heap       : 8m -> ${JAVA_XMX:-128m}"
echo " display    : TigerVNC Xvnc 320x240x16"
echo " VNC        : 127.0.0.1:${VNC_PORT:-5900}"
echo " tunnel     : Cloudflare Named Tunnel (fixed hostname)"
echo " Blitz type : BACKGROUND"
echo " watchdog   : OFF"
echo " autorestart: OFF"
echo "============================================================"

/app/run-display.sh &
PIDS+=($!)

/app/run-game.sh &
PIDS+=($!)

/app/run-tunnel.sh &
PIDS+=($!)

sleep 1

echo "[status] display pid=${PIDS[0]}"
echo "[status] game    pid=${PIDS[1]}"
echo "[status] tunnel  pid=${PIDS[2]}"
if [[ -n "${TUNNEL_HOSTNAME:-}" ]]; then
  echo "[status] fixed VNC hostname: ${TUNNEL_HOSTNAME}"
fi

# No supervisor/watchdog/restart loop. Blitz remains a background worker.
wait
