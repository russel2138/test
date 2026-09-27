#!/usr/bin/env bash
set -euo pipefail

cd /data

JAVA_BIN="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}/bin/java"
if [[ ! -x "$JAVA_BIN" ]]; then
  JAVA_BIN="$(command -v java || true)"
fi

MICROEMU_HOME=/app/microemu
MICROEMU_USER_HOME=/data/microemu-home
MICROEMU_STATE_ROOT="$MICROEMU_USER_HOME/.microemulator"
GAME_JAR="${GAME_JAR:-/app/game.jar}"
GAME_PROPERTIES="$MICROEMU_USER_HOME/game-manifest.jad"
CP="$MICROEMU_HOME/microemulator.jar:$MICROEMU_HOME/lib/*:$MICROEMU_HOME/devices/*"

[[ -n "$JAVA_BIN" && -x "$JAVA_BIN" ]] || {
  echo "[game] Java runtime not found" >&2
  exit 1
}
[[ -s "$GAME_JAR" ]] || {
  echo "[game] bundled game missing: $GAME_JAR" >&2
  exit 2
}

mkdir -p "$MICROEMU_STATE_ROOT/suite-null"

while [[ ! -S /tmp/.X11-unix/X99 ]]; do
  echo "[game] waiting for display ${DISPLAY:-:99}"
  sleep 1
done

MANIFEST_TEXT="$(unzip -p "$GAME_JAR" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r')"
MIDLET_ENTRY="$(printf '%s\n' "$MANIFEST_TEXT" | sed -n 's/^MIDlet-1:[[:space:]]*//p' | head -n1)"
MIDLET_CLASS="${MIDLET_ENTRY##*,}"
MIDLET_CLASS="$(printf '%s' "$MIDLET_CLASS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

[[ -n "$MIDLET_CLASS" ]] || {
  echo "[game] MIDlet-1 entry class missing" >&2
  exit 3
}

mkdir -p "$MICROEMU_USER_HOME"
printf '%s\n' "$MANIFEST_TEXT" >"$GAME_PROPERTIES"

echo "[game] MicroEmulator 2.0.4"
echo "[game] jar: $GAME_JAR"
echo "[game] state: $MICROEMU_STATE_ROOT"
echo "[game] MIDlet: $MIDLET_CLASS"
echo "[game] heap: 8m -> ${JAVA_XMX:-192m}"
echo "[game] watchdog: OFF"

exec "$JAVA_BIN" \
  -Xms8m \
  -Xmx"${JAVA_XMX:-192m}" \
  -XX:+UseSerialGC \
  -Djava.awt.headless=false \
  -Duser.home="$MICROEMU_USER_HOME" \
  -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel \
  -cp "$CP" \
  org.microemu.app.Main \
  --rms file \
  --resizableDevice 400 300 \
  --appclasspath "$GAME_JAR" \
  --propertiesjad "$GAME_PROPERTIES" \
  --quit \
  "$MIDLET_CLASS"
