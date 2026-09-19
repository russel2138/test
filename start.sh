#!/usr/bin/env bash
set -uo pipefail

mkdir -p /data /run/nro /data/microemu-home/.microemulator

cleanup() {
  /app/nroctl stop all >/dev/null 2>&1 || true
}

shutdown() {
  cleanup
  exit 0
}

trap cleanup EXIT
trap shutdown INT TERM

WEB_PORT="${PORT:-${NOVNC_PORT:-8080}}"

echo "============================================================"
echo " NRO lightweight runtime"
echo " game state : /data/microemu-home/.microemulator"
if [[ -s /data/game.jar ]]; then
  echo " game jar   : /data/game.jar (persistent, present)"
else
  echo " game jar   : MISSING - upload at app URL"
fi
echo " web port   : $WEB_PORT"
echo " web url    : https://nro.pyoska.blitz.cloud"
echo " control    : /app/nroctl"
echo "============================================================"

/app/nroctl start display
/app/nroctl start game
/app/nroctl start vnc
/app/nroctl start web

/app/nroctl status

while true; do
  sleep 3600 &
  wait $!
done
