#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-$HOME/data}"
APP="${NRO_APP:-$HOME/nro-host4}"
GAME="${NRO_GAME:-$ROOT/a.jar}"
DATA="$ROOT/nro-data"
EMU_HOME="$DATA/microemu-home"
STATE="$EMU_HOME/.microemulator"
JAD="$EMU_HOME/game-manifest.jad"
MICROEMU="$APP/microemu"

[[ -s "$GAME" ]] || { echo "[game] missing $GAME" >&2; exit 1; }
mkdir -p "$STATE/suite-null"

for _ in {1..50}; do
  [[ -S /tmp/.X11-unix/X99 ]] && break
  sleep 0.1
done

unzip -p "$GAME" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r' >"$JAD"

MIDLET="$(
  awk '
    /^[ ]/ { sub(/^ /, ""); line=line $0; next }
    { if (line != "") print line; line=$0 }
    END { if (line != "") print line }
  ' "$JAD" |
  grep -m1 '^MIDlet-1[[:space:]]*:' |
  awk -F',' '{v=$NF; gsub(/^[ \t]+|[ \t]+$/, "", v); print v}'
)"

[[ -n "$MIDLET" ]] || { echo "[game] MIDlet-1 not found" >&2; exit 1; }

CP="$MICROEMU/microemulator.jar:$MICROEMU/lib/*:$MICROEMU/devices/*"
export DISPLAY=:99

echo "[game] MIDlet: $MIDLET"
echo "[game] heap: 16m -> ${JAVA_XMX:-160m}"
echo "[game] watchdog: OFF"

exec java   -Xms16m   -Xmx"${JAVA_XMX:-160m}"   -XX:+UseSerialGC   -Djava.awt.headless=false   -Duser.home="$EMU_HOME"   -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel   -cp "$CP"   org.microemu.app.Main   --rms file   --resizableDevice 320 240   --appclasspath "$GAME"   --propertiesjad "$JAD"   --quit   "$MIDLET"
