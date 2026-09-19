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
GAME_JAR=/data/game.jar
GAME_PROPERTIES="$MICROEMU_USER_HOME/game-manifest.jad"
CP="$MICROEMU_HOME/microemulator.jar:$MICROEMU_HOME/lib/*:$MICROEMU_HOME/devices/*"

if [[ -z "$JAVA_BIN" || ! -x "$JAVA_BIN" ]]; then
  echo "[game] Java runtime not found" >&2
  exit 1
fi

if [[ ! -s "$GAME_JAR" ]]; then
  echo "[game] /data/game.jar missing; upload/copy it into persistent storage" >&2
  sleep 10
  exit 2
fi

mkdir -p "$MICROEMU_STATE_ROOT"

# The game needs an X server, but it does not own or supervise the display.
# If Xvfb is temporarily down, only this component waits/restarts.
while [[ ! -S /tmp/.X11-unix/X99 ]]; do
  echo "[game] waiting for display ${DISPLAY:-:99}"
  sleep 2
done

MANIFEST_TEXT="$(unzip -p "$GAME_JAR" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r')"
MIDLET_ENTRY="$(printf '%s\n' "$MANIFEST_TEXT" | sed -n 's/^MIDlet-1:[[:space:]]*//p' | head -n1)"
MIDLET_CLASS="${MIDLET_ENTRY##*,}"
MIDLET_CLASS="$(printf '%s' "$MIDLET_CLASS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
SUITE_NAME="$(printf '%s\n' "$MANIFEST_TEXT" | sed -n 's/^MIDlet-Name:[[:space:]]*//p' | head -n1)"
SUITE_NAME="$(printf '%s' "$SUITE_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [[ -z "$MIDLET_CLASS" ]]; then
  echo "[game] MIDlet-1 entry class missing" >&2
  exit 3
fi

MIDLET_CLASS_PATH="${MIDLET_CLASS//./\/}.class"
if ! unzip -p "$GAME_JAR" "$MIDLET_CLASS_PATH" >/dev/null 2>&1; then
  echo "[game] MIDlet class $MIDLET_CLASS not found in game.jar" >&2
  exit 4
fi

mkdir -p "$MICROEMU_USER_HOME"
printf '%s\n' "$MANIFEST_TEXT" > "$GAME_PROPERTIES"

if [[ -n "$SUITE_NAME" ]]; then
  NORMAL_SUITE_DIR="$MICROEMU_STATE_ROOT/suite-$SUITE_NAME"
  DIRECT_SUITE_DIR="$MICROEMU_STATE_ROOT/suite-null"
  mkdir -p "$NORMAL_SUITE_DIR"

  if [[ ! -e "$DIRECT_SUITE_DIR" && ! -L "$DIRECT_SUITE_DIR" ]]; then
    ln -s "suite-$SUITE_NAME" "$DIRECT_SUITE_DIR"
  elif [[ -L "$DIRECT_SUITE_DIR" ]]; then
    ln -sfn "suite-$SUITE_NAME" "$DIRECT_SUITE_DIR"
  fi
fi

echo "[game] MicroEmulator 2.0.4"
echo "[game] state: $MICROEMU_STATE_ROOT"
echo "[game] MIDlet: $MIDLET_CLASS"
echo "[game] heap: ${JAVA_XMX:-160m}"

exec "$JAVA_BIN"   -Xms16m   -Xmx"${JAVA_XMX:-160m}"   -XX:+UseSerialGC   -Djava.awt.headless=false   -Duser.home="$MICROEMU_USER_HOME"   -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel   -cp "$CP"   org.microemu.app.Main   --rms file   --resizableDevice 320 240   --appclasspath "$GAME_JAR"   --propertiesjad "$GAME_PROPERTIES"   --quit   "$MIDLET_CLASS"
