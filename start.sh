#!/usr/bin/env bash
set -uo pipefail

if [[ "${RESET_STATE:-0}" == "1" ]]; then
  echo "[state] RESET_STATE=1 -> deleting /data/microemu-home"
  rm -rf /data/microemu-home
fi

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
echo " NRO / Blitz background + Quick Tunnel"
echo " game       : /app/game.jar"
echo " state      : /data/microemu-home/.microemulator"
echo " heap       : 8m -> ${JAVA_XMX:-128m}"
echo " display    : TigerVNC Xvnc 320x280x16"
echo " browser    : noVNC via random *.trycloudflare.com"
echo " game logs  : hidden from Blitz Logs"
echo " reset state: ${RESET_STATE:-0}"
echo " watchdog   : OFF"
echo " autorestart: OFF"
echo "============================================================"

/app/run-display.sh &
PIDS+=($!)

# Keep noisy game stdout/stderr out of Blitz Logs.
/app/run-game.sh >/tmp/nro-game.log 2>&1 &
PIDS+=($!)

/app/run-web.sh &
PIDS+=($!)

/app/run-tunnel.sh &
PIDS+=($!)

sleep 1

echo "[status] display pid=${PIDS[0]}"
echo "[status] game    pid=${PIDS[1]} (logs hidden)"
echo "[status] web     pid=${PIDS[2]}"
echo "[status] tunnel  pid=${PIDS[3]}"
echo "[status] open the https://*.trycloudflare.com URL printed by cloudflared"

# No supervisor/watchdog/restart loop.
wait
