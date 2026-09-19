#!/usr/bin/env bash
set -uo pipefail

cd /data

JAVA_BIN="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}/bin/java"
MICROEMU_HOME=/app/microemu
CP="$MICROEMU_HOME/microemulator.jar:$MICROEMU_HOME/lib/*:$MICROEMU_HOME/devices/*"

if [[ ! -x "$JAVA_BIN" ]]; then
  echo "[nro] Java 17 runtime not found at $JAVA_BIN" >&2
  exit 1
fi

if [[ ! -s /data/game.jar ]]; then
  echo "[nro] /data/game.jar is missing" >&2
  exit 1
fi

if [[ ! -f "$MICROEMU_HOME/microemulator.jar" ]]; then
  echo "[nro] MicroEmulator JAR is missing" >&2
  exit 1
fi

echo "[nro] emulator: MicroEmulator 2.0.4"
echo "[nro] using Java: $JAVA_BIN"
"$JAVA_BIN" -version 2>&1 | sed 's/^/[java] /'

while true; do
  echo "[nro] starting Dragonboy via MicroEmulator..."
  "$JAVA_BIN" \
    -Xms16m \
    -Xmx"${JAVA_XMX:-160m}" \
    -XX:+UseSerialGC \
    -Djava.awt.headless=false \
    -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel \
    -cp "$CP" \
    org.microemu.app.Main \
    --resizableDevice 320 240 \
    /data/game.jar

  rc=$?
  echo "[nro] game exited with code ${rc}; restarting in 5 seconds..."
  sleep 5
done
