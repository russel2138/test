#!/usr/bin/env bash
set -uo pipefail

mkdir -p /data /run/nro /data/microemu-home/.microemulator

shutdown() {
  /app/nroctl stop all >/dev/null 2>&1 || true
  exit 0
}
trap shutdown INT TERM

echo "============================================================"
echo " NRO / Blitz background"
echo " game       : /app/game.jar (bundled from GitHub)"
echo " state      : /data/microemu-home/.microemulator"
echo " heap       : 8m -> ${JAVA_XMX:-128m}"
echo " display    : Xvfb 320x240x16"
echo " watchdog   : OFF"
echo " autorestart: OFF"
echo " control    : /app/nroctl"
echo "============================================================"

/app/nroctl start display
/app/nroctl start game
/app/nroctl status

# Blitz has no interactive terminal. Stream the game log to the platform
# runtime log so startup/runtime errors are visible from the dashboard.
touch /tmp/nro-game.log
tail -n 0 -F /tmp/nro-game.log &
LOG_TAIL_PID=$!

# Keep the Blitz worker process alive only. This never checks or restarts
# the game/display. If either dies, it stays down until manually restarted.
while true; do
  sleep 3600 &
  wait $!
done
