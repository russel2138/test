#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-$(pwd)}"
DATA="${NRO_DATA:-$ROOT/.nro-data}"
GAMES_DIR="${NRO_GAMES_DIR:-$ROOT/games}"
GAME="${NRO_GAME:-$GAMES_DIR/NRO_NEW.jar}"

EMU_DIR="$DATA/microemu"
EMU_ZIP="$DATA/microemulator-2.0.4.zip"
EMU_URL="${MICROEMU_URL:-https://downloads.sourceforge.net/project/microemulator/microemulator/2.0.4/microemulator-2.0.4.zip}"

EMU_HOME="$DATA/home"
STATE="$EMU_HOME/.microemulator"
JAD="$DATA/game-manifest.jad"

DISPLAY_NUM="${DISPLAY_NUM:-:99}"
VNC_PORT="${VNC_PORT:-5900}"
HTTP_PORT="${PORT:-3000}"
JAVA_XMS="${JAVA_XMS:-16m}"
JAVA_XMX="${JAVA_XMX:-128m}"

NOVNC_SYSTEM="/usr/share/novnc"
NOVNC_WEB="$DATA/novnc-web"
VNC_PASS_FILE="$DATA/vnc.pass"

mkdir -p "$DATA" "$GAMES_DIR" "$EMU_HOME" "$STATE/suite-null"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] missing command: $1" >&2
    exit 1
  }
}

for cmd in java curl unzip Xvfb x11vnc websockify; do
  need "$cmd"
done

if [[ ! -s "$GAME" ]]; then
  echo "[ERROR] NRO game not found: $GAME"
  echo "[ERROR] Upload your game JAR to: $GAMES_DIR/NRO_NEW.jar"
  exit 1
fi

if [[ ! -s "$EMU_DIR/microemulator.jar" ]]; then
  echo "[SETUP] downloading MicroEmulator 2.0.4..."
  rm -rf "$DATA/microemu.unpack" "$EMU_ZIP"
  curl -fL --connect-timeout 15 --max-time 120 "$EMU_URL" -o "$EMU_ZIP"
  unzip -tqq "$EMU_ZIP"
  mkdir -p "$DATA/microemu.unpack"
  unzip -q "$EMU_ZIP" -d "$DATA/microemu.unpack"

  found="$(find "$DATA/microemu.unpack" -type f -name microemulator.jar -print -quit)"
  [[ -n "$found" ]] || {
    echo "[ERROR] microemulator.jar was not found after extraction" >&2
    exit 1
  }

  rm -rf "$EMU_DIR"
  mkdir -p "$EMU_DIR"
  cp -a "$(dirname "$found")/." "$EMU_DIR/"
  rm -rf "$DATA/microemu.unpack"
fi

CP="$EMU_DIR/microemulator.jar:$EMU_DIR/lib/*:$EMU_DIR/devices/*"

unzip -p "$GAME" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r' > "$JAD.tmp" || true
[[ -s "$JAD.tmp" ]] || {
  rm -f "$JAD.tmp"
  echo "[ERROR] META-INF/MANIFEST.MF missing from $GAME" >&2
  exit 1
}
mv -f "$JAD.tmp" "$JAD"

MIDLET="$(
  awk '
    /^[ ]/ {
      sub(/^ /, "")
      line = line $0
      next
    }
    {
      if (line != "") print line
      line = $0
    }
    END {
      if (line != "") print line
    }
  ' "$JAD" |
  grep -m1 '^MIDlet-1[[:space:]]*:' |
  awk -F',' '{v=$NF; gsub(/^[ \t]+|[ \t]+$/, "", v); print v}'
)"

[[ -n "$MIDLET" ]] || {
  echo "[ERROR] MIDlet-1 not found in $GAME" >&2
  exit 1
}

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  printf '%s\n' "$VNC_PASSWORD" > "$VNC_PASS_FILE.plain"
else
  if [[ ! -s "$VNC_PASS_FILE.plain" ]]; then
    pass="$(printf '%s' "$(date +%s%N)-$RANDOM-$RANDOM" | sha256sum | cut -c1-8)"
    printf '%s\n' "$pass" > "$VNC_PASS_FILE.plain"
  fi
fi
VNC_PASSWORD_ACTUAL="$(cat "$VNC_PASS_FILE.plain")"
x11vnc -storepasswd "$VNC_PASSWORD_ACTUAL" "$VNC_PASS_FILE" >/dev/null

[[ -d "$NOVNC_SYSTEM" ]] || {
  echo "[ERROR] noVNC web files not found at $NOVNC_SYSTEM" >&2
  exit 1
}
rm -rf "$NOVNC_WEB"
mkdir -p "$NOVNC_WEB"
cp -a "$NOVNC_SYSTEM/." "$NOVNC_WEB/"
if [[ ! -e "$NOVNC_WEB/index.html" && -e "$NOVNC_WEB/vnc.html" ]]; then
  ln -s vnc.html "$NOVNC_WEB/index.html"
fi

cleanup() {
  set +e
  [[ -n "${JAVA_PID:-}" ]] && kill "$JAVA_PID" 2>/dev/null
  [[ -n "${WS_PID:-}" ]] && kill "$WS_PID" 2>/dev/null
  [[ -n "${VNC_PID_ACTUAL:-}" ]] && kill "$VNC_PID_ACTUAL" 2>/dev/null
  [[ -n "${XVFB_PID:-}" ]] && kill "$XVFB_PID" 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "[NRO] starting Xvfb on $DISPLAY_NUM"
Xvfb "$DISPLAY_NUM" -screen 0 640x480x24 -nolisten tcp >"$DATA/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 1
kill -0 "$XVFB_PID" 2>/dev/null || {
  echo "[ERROR] Xvfb failed"
  cat "$DATA/xvfb.log" 2>/dev/null || true
  exit 1
}

export DISPLAY="$DISPLAY_NUM"

echo "[NRO] starting x11vnc on localhost:$VNC_PORT"
x11vnc   -display "$DISPLAY_NUM"   -rfbport "$VNC_PORT"   -localhost   -forever   -shared   -rfbauth "$VNC_PASS_FILE"   -noxdamage   >"$DATA/x11vnc.log" 2>&1 &
VNC_PID_ACTUAL=$!
sleep 1
kill -0 "$VNC_PID_ACTUAL" 2>/dev/null || {
  echo "[ERROR] x11vnc failed"
  cat "$DATA/x11vnc.log" 2>/dev/null || true
  exit 1
}

echo "[NRO] starting noVNC/websockify on 0.0.0.0:$HTTP_PORT"
websockify   --web="$NOVNC_WEB"   "0.0.0.0:$HTTP_PORT"   "127.0.0.1:$VNC_PORT"   >"$DATA/websockify.log" 2>&1 &
WS_PID=$!
sleep 1
kill -0 "$WS_PID" 2>/dev/null || {
  echo "[ERROR] websockify failed"
  cat "$DATA/websockify.log" 2>/dev/null || true
  exit 1
}

echo "============================================"
echo "[NRO] game:      $GAME"
echo "[NRO] MIDlet:    $MIDLET"
echo "[NRO] state:     $STATE"
echo "[NRO] web port:  $HTTP_PORT"
echo "[NRO] VNC pass:  $VNC_PASSWORD_ACTUAL"
echo "[NRO] watchdog:  OFF"
echo "============================================"

echo "[NRO] starting game (no internal watchdog / no restart loop)"
java   -Xms"$JAVA_XMS"   -Xmx"$JAVA_XMX"   -XX:+UseSerialGC   -Duser.home="$EMU_HOME"   -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel   -cp "$CP"   org.microemu.app.Main   --rms file   --resizableDevice 320 240   --appclasspath "$GAME"   --propertiesjad "$JAD"   --quit   "$MIDLET"   >"$DATA/game.log" 2>&1 &
JAVA_PID=$!

wait "$JAVA_PID"
rc=$?
echo "[NRO] Java exited with code $rc"
exit "$rc"
