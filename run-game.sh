#!/usr/bin/env bash
set -uo pipefail

cd /data

JAVA_BIN="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}/bin/java"
MICROEMU_HOME=/app/microemu
MICROEMU_USER_HOME=/data/microemu-home
MICROEMU_STATE_ROOT="$MICROEMU_USER_HOME/.microemulator"
GAME_JAR=/data/game.jar
GAME_PROPERTIES="$MICROEMU_USER_HOME/game-manifest.jad"
CP="$MICROEMU_HOME/microemulator.jar:$MICROEMU_HOME/lib/*:$MICROEMU_HOME/devices/*"

if [[ ! -x "$JAVA_BIN" ]]; then
  echo "[nro] Java 17 runtime not found at $JAVA_BIN" >&2
  exit 1
fi

if [[ ! -s "$GAME_JAR" ]]; then
  echo "[nro] $GAME_JAR is missing" >&2
  exit 1
fi

if [[ ! -f "$MICROEMU_HOME/microemulator.jar" ]]; then
  echo "[nro] MicroEmulator JAR is missing" >&2
  exit 1
fi

# MicroEmulator stores config, RMS and its JSR-75 filesystem below
# ${user.home}/.microemulator. Keep that whole tree on Blitz's persistent
# /data volume so a container replacement does not reset the client.
mkdir -p "$MICROEMU_STATE_ROOT"

# Read the installed MIDlet metadata instead of hard-coding the entry class.
# The same manifest is also supplied as MIDlet properties when launching the
# class directly, so getAppProperty() keeps seeing the normal JAR metadata.
if ! MANIFEST_TEXT="$(unzip -p "$GAME_JAR" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r')"; then
  echo "[nro] unable to read META-INF/MANIFEST.MF from $GAME_JAR" >&2
  exit 1
fi

MIDLET_ENTRY="$(printf '%s\n' "$MANIFEST_TEXT" | sed -n 's/^MIDlet-1:[[:space:]]*//p' | head -n1)"
MIDLET_CLASS="${MIDLET_ENTRY##*,}"
MIDLET_CLASS="$(printf '%s' "$MIDLET_CLASS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
SUITE_NAME="$(printf '%s\n' "$MANIFEST_TEXT" | sed -n 's/^MIDlet-Name:[[:space:]]*//p' | head -n1)"
SUITE_NAME="$(printf '%s' "$SUITE_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [[ -z "$MIDLET_CLASS" ]]; then
  echo "[nro] MIDlet-1 entry class is missing from the game manifest" >&2
  exit 1
fi

MIDLET_CLASS_PATH="${MIDLET_CLASS//./\/}.class"
if ! unzip -p "$GAME_JAR" "$MIDLET_CLASS_PATH" >/dev/null 2>&1; then
  echo "[nro] MIDlet class $MIDLET_CLASS was not found in $GAME_JAR" >&2
  exit 1
fi

printf '%s\n' "$MANIFEST_TEXT" > "$GAME_PROPERTIES"

# Direct class launch leaves MicroEmulator's suite name unset, so its file RMS
# path becomes "suite-null". Point that path at the normal suite directory to
# preserve any state already created while the JAR was opened via the launcher.
if [[ -n "$SUITE_NAME" ]]; then
  NORMAL_SUITE_DIR="$MICROEMU_STATE_ROOT/suite-$SUITE_NAME"
  DIRECT_SUITE_DIR="$MICROEMU_STATE_ROOT/suite-null"
  mkdir -p "$NORMAL_SUITE_DIR"

  if [[ ! -e "$DIRECT_SUITE_DIR" && ! -L "$DIRECT_SUITE_DIR" ]]; then
    ln -s "suite-$SUITE_NAME" "$DIRECT_SUITE_DIR"
  elif [[ -L "$DIRECT_SUITE_DIR" ]]; then
    CURRENT_TARGET="$(readlink "$DIRECT_SUITE_DIR" || true)"
    if [[ "$CURRENT_TARGET" != "suite-$SUITE_NAME" ]]; then
      ln -sfn "suite-$SUITE_NAME" "$DIRECT_SUITE_DIR"
    fi
  else
    echo "[nro] existing $DIRECT_SUITE_DIR directory kept as-is"
  fi
fi

echo "[nro] emulator: MicroEmulator 2.0.4"
echo "[nro] persistent MicroEmulator home: $MICROEMU_USER_HOME"
echo "[nro] auto-launch MIDlet: $MIDLET_CLASS"
if [[ -n "$SUITE_NAME" ]]; then
  echo "[nro] MIDlet suite: $SUITE_NAME"
fi
echo "[nro] using Java: $JAVA_BIN"
"$JAVA_BIN" -version 2>&1 | sed 's/^/[java] /'

while true; do
  echo "[nro] starting Dragonboy directly (no launcher / Run click)..."
  "$JAVA_BIN" \
    -Xms16m \
    -Xmx"${JAVA_XMX:-160m}" \
    -XX:+UseSerialGC \
    -Djava.awt.headless=false \
    -Duser.home="$MICROEMU_USER_HOME" \
    -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel \
    -cp "$CP" \
    org.microemu.app.Main \
    --rms file \
    --resizableDevice 320 240 \
    --appclasspath "$GAME_JAR" \
    --propertiesjad "$GAME_PROPERTIES" \
    --quit \
    "$MIDLET_CLASS"

  rc=$?
  echo "[nro] game/emulator exited with code ${rc}; restarting in 5 seconds..."
  sleep 5
done
