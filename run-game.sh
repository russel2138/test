#!/usr/bin/env bash
set -uo pipefail

cd /data

JAVA_BIN="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}/bin/java"

if [[ ! -x "$JAVA_BIN" ]]; then
  echo "[nro] Java 17 runtime not found at $JAVA_BIN" >&2
  exit 1
fi

echo "[nro] using Java: $JAVA_BIN"
"$JAVA_BIN" -version 2>&1 | sed 's/^/[java] /'

while true; do
  echo "[nro] starting Dragonboy via FreeJ2ME..."
  "$JAVA_BIN" \
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
