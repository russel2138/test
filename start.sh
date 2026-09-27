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
echo " NRO / Blitz browser"
echo " game       : /app/game.jar"
echo " state      : /data/microemu-home/.microemulator"
echo " heap       : 8m -> ${JAVA_XMX:-128m}"
echo " display    : TigerVNC Xvnc 320x240x16"
echo " browser    : noVNC -> ${PORT:-8080}"
echo " watchdog   : OFF"
echo " autorestart: OFF"
echo "============================================================"

/app/run-display.sh &
PIDS+=($!)

/app/run-game.sh &
PIDS+=($!)

/app/run-web.sh &
PIDS+=($!)

sleep 1

echo "[status] display pid=${PIDS[0]}"
echo "[status] game    pid=${PIDS[1]}"
echo "[status] web     pid=${PIDS[2]}"
echo "[status] open the Blitz public URL to control the game"

# No supervisor and no restart loop. If the game exits it stays down.
# PID 1 only remains alive to own the three child processes and handle SIGTERM.
wait
