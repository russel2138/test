#!/usr/bin/env bash
set -uo pipefail

cd /data

while true; do
  echo "[nro] starting Dragonboy via FreeJ2ME..."
  java \
    -Xms16m \
    -Xmx"${JAVA_XMX:-128m}" \
    -XX:+UseSerialGC \
    -Djava.awt.headless=false \
    -jar /app/freej2me.jar \
    file:///data/game.jar \
    "${GAME_WIDTH:-320}" \
    "${GAME_HEIGHT:-240}" \
    "${GAME_SCALE:-2}"

  rc=$?
  echo "[nro] game exited with code ${rc}; restarting in 5 seconds..."
  sleep 5
done
