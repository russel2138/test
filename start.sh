#!/usr/bin/env bash
set -uo pipefail

mkdir -p /data /run/nro /data/microemu-home/.microemulator

shutdown() {
  /app/nroctl stop all >/dev/null 2>&1 || true
  exit 0
}
trap shutdown INT TERM

WEB_PORT="${PORT:-${NOVNC_PORT:-8080}}"

echo "============================================================"
echo " NRO / Blitz lightweight"
echo " game      : /data/game.jar"
echo " state     : /data/microemu-home/.microemulator"
echo " web port  : $WEB_PORT"
echo " web       : https://nro.pyoska.blitz.cloud"
echo " watchdog  : OFF"
echo " autorestart: OFF"
echo " control   : /app/nroctl"
echo "============================================================"

# Independent processes, started once. If one dies it stays down until
# /app/nroctl start|restart <component> is run manually.
/app/nroctl start display
/app/nroctl start vnc
/app/nroctl start web

if [[ -s /data/game.jar ]]; then
  /app/nroctl start game
else
  echo "[game] /data/game.jar missing; uploader is available at the app URL"
fi

/app/nroctl status

# Keep only the Blitz main process alive. This loop does not inspect or
# restart any component.
while true; do
  sleep 3600 &
  wait $!
done
