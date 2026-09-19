#!/usr/bin/env bash
set -uo pipefail

mkdir -p /data /run/nro /data/microemu-home/.microemulator

cleanup() {
  /app/nroctl stop all >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "============================================================"
echo " NRO lightweight runtime"
echo " game state : /data/microemu-home/.microemulator"
echo " game jar   : /data/game.jar"
echo " control    : /app/nroctl"
echo "============================================================"

/app/nroctl start display
/app/nroctl start game

if [[ "${REMOTE_ENABLED:-1}" == "1" ]]; then
  /app/nroctl start vnc
  /app/nroctl start web
  if [[ "${TUNNEL_ENABLED:-1}" == "1" ]]; then
    /app/nroctl start tunnel
  fi
else
  echo "[remote] disabled; set REMOTE_ENABLED=1 or run: /app/nroctl start remote"
fi

/app/nroctl status

# PID 1 only keeps the container alive. It does not own component lifecycles.
while true; do
  sleep 3600 &
  wait $!
done
