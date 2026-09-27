#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
RUNTIME="${NRO_RUNTIME:-$ROOT/nro-runtime}"
GAME="${NRO_GAME:-$ROOT/a.jar}"

RUNTIME_URL="${NRO_RUNTIME_URL:-https://github.com/russel2138/test/releases/download/nro-runtime-v1/nro-runtime-focal-amd64.tar.gz}"

DISPLAY_NUM="${DISPLAY_NUM:-:1}"
VNC_PORT="${VNC_PORT:-${SERVER_PORT:-${PORT:-}}}"
VNC_GEOMETRY="${VNC_GEOMETRY:-640x480}"
VNC_DEPTH="${VNC_DEPTH:-24}"

JAVA_XMS="${JAVA_XMS:-16m}"
JAVA_XMX="${JAVA_XMX:-160m}"

DATA="${NRO_DATA:-$ROOT/nro-data}"
GAME_NAME="$(basename "$GAME")"
GAME_KEY="$(printf '%s' "${GAME_NAME%.jar}" | sed 's/[^A-Za-z0-9._-]/_/g')"
EMU_HOME="$DATA/profiles/$GAME_KEY/stock"
STATE="$EMU_HOME/.microemulator"
JAD="$EMU_HOME/game-manifest.jad"

VNC_ORIG="$RUNTIME/usr/bin/Xtigervnc"
VNC_BIN="$RUNTIME/usr/bin/Xtigervnc-witchly"
XKBCOMP="$RUNTIME/usr/bin/xkbcomp"
XKBDIR="$RUNTIME/usr/share/X11/xkb"
VNC_LIB="$RUNTIME/usr/lib/x86_64-linux-gnu:$RUNTIME/lib/x86_64-linux-gnu:$RUNTIME/usr/lib"

VNC_DIR="$DATA/.vnc"
VNC_PASS_FILE="$VNC_DIR/passwd"
VNC_PASSWORD_FILE="$VNC_DIR/password.txt"
VNC_LOG="$DATA/vnc.log"
VNC_PID_FILE="$DATA/vnc.pid"
GAME_PID_FILE="$DATA/game.pid"
VNC_PORT_FILE="$DATA/vnc-port.txt"

fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 4 --retry-delay 2 --connect-timeout 20 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    echo "[ERROR] curl/wget not found" >&2
    return 1
  fi
}

runtime_ready() {
  [[ -x "$VNC_ORIG" &&
     -x "$XKBCOMP" &&
     -x "$RUNTIME/usr/bin/tigervncpasswd" &&
     -s "$XKBDIR/keycodes/evdev" &&
     -s "$RUNTIME/microemu/microemulator.jar" ]]
}

ensure_runtime() {
  if runtime_ready; then
    echo "[runtime] portable runtime already present"
    return 0
  fi

  [[ "$(uname -m)" == "x86_64" ]] || {
    echo "[ERROR] runtime currently supports x86_64 only; got $(uname -m)" >&2
    exit 1
  }

  echo "[runtime] downloading prebuilt MicroEmulator + TigerVNC runtime..."
  local archive="$ROOT/.nro-runtime.tar.gz"
  local tmp="$ROOT/.nro-runtime.new"

  rm -rf "$tmp" "$archive"
  mkdir -p "$tmp"

  fetch "$RUNTIME_URL" "$archive"
  tar -xzf "$archive" -C "$tmp"
  rm -f "$archive"

  rm -rf "$RUNTIME"
  mv "$tmp" "$RUNTIME"

  runtime_ready || {
    echo "[ERROR] extracted runtime is incomplete" >&2
    exit 1
  }
  echo "[runtime] ready"
}

echo "[WITCHLY] Java:"
java -version 2>&1 | head -n 3 || true
echo "[WITCHLY] RAM limit: $(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unknown)"
echo "[WITCHLY] CPU quota: $(cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo unknown)"
echo "[WITCHLY] SERVER_PORT: ${SERVER_PORT:-unset}"
echo "[WITCHLY] PORT: ${PORT:-unset}"

[[ -n "$VNC_PORT" ]] || {
  echo "[ERROR] no port env found. Set VNC_PORT to the port shown in Witchly Network/Overview." >&2
  exit 1
}

[[ -s "$GAME" ]] || {
  echo "[ERROR] NRO game not found: $GAME" >&2
  echo "[ERROR] Upload/rename the game as: $ROOT/a.jar" >&2
  exit 1
}

ensure_runtime

mkdir -p "$STATE/suite-null" "$VNC_DIR" /tmp/xxx
printf '%s\n' "$VNC_PORT" > "$VNC_PORT_FILE"

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
  printf '%s\n' "${VNC_PASSWORD:0:8}" > "$VNC_PASSWORD_FILE"
elif [[ ! -s "$VNC_PASSWORD_FILE" ]]; then
  random="$(printf '%s' "$(date +%s%N)-$RANDOM-$RANDOM" | sha256sum | cut -c1-8)"
  printf '%s\n' "$random" > "$VNC_PASSWORD_FILE"
fi
VNC_PASSWORD_ACTUAL="$(head -c 8 "$VNC_PASSWORD_FILE")"

printf '%s\n' "$VNC_PASSWORD_ACTUAL" |
  "$RUNTIME/usr/bin/tigervncpasswd" -f > "$VNC_PASS_FILE"
chmod 600 "$VNC_PASS_FILE"

cat > /tmp/xxx/xkbcomp <<EOF
#!/bin/sh
exec "$XKBCOMP" -I"$XKBDIR" "\$@"
EOF
chmod +x /tmp/xxx/xkbcomp

cp "$VNC_ORIG" "$VNC_BIN"
sed -i 's#/usr/bin#/tmp/xxx#g' "$VNC_BIN"
chmod +x "$VNC_BIN"

cleanup() {
  set +e
  if [[ -n "${GAME_PID:-}" ]]; then
    kill "$GAME_PID" 2>/dev/null || true
    wait "$GAME_PID" 2>/dev/null || true
  fi
  if [[ -n "${VNC_PID:-}" ]]; then
    kill "$VNC_PID" 2>/dev/null || true
    wait "$VNC_PID" 2>/dev/null || true
  fi
  rm -f "$GAME_PID_FILE" "$VNC_PID_FILE"
}
trap cleanup EXIT INT TERM

: > "$VNC_LOG"

echo "[VNC] starting on port $VNC_PORT"
LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$VNC_BIN" "$DISPLAY_NUM"   -geometry "$VNC_GEOMETRY"   -depth "$VNC_DEPTH"   -rfbport "$VNC_PORT"   -SecurityTypes VncAuth   -rfbauth "$VNC_PASS_FILE"   -xkbdir "$XKBDIR"   >"$VNC_LOG" 2>&1 &
VNC_PID=$!
printf '%s\n' "$VNC_PID" > "$VNC_PID_FILE"

sleep 2
kill -0 "$VNC_PID" 2>/dev/null || {
  echo "[ERROR] TigerVNC failed to start" >&2
  tail -n 120 "$VNC_LOG" 2>/dev/null || true
  exit 1
}

export DISPLAY="$DISPLAY_NUM"
export LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}"

CP="$RUNTIME/microemu/microemulator.jar:$RUNTIME/microemu/lib/*:$RUNTIME/microemu/devices/*"

echo "================ NRO / WITCHLY ================="
echo "Game:       $GAME_NAME"
echo "MIDlet:     $MIDLET"
echo "State:      $STATE"
echo "VNC port:   $VNC_PORT"
echo "VNC pass:   $VNC_PASSWORD_ACTUAL"
echo "Heap:       $JAVA_XMS -> $JAVA_XMX"
echo "Watchdog:   OFF"
echo "================================================="
echo "[NRO] No watchdog / no restart loop."

java   -Xms"$JAVA_XMS"   -Xmx"$JAVA_XMX"   -XX:+UseSerialGC   -Duser.home="$EMU_HOME"   -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel   -cp "$CP"   org.microemu.app.Main   --rms file   --resizableDevice 320 240   --appclasspath "$GAME"   --propertiesjad "$JAD"   --quit   "$MIDLET"   </dev/null &
GAME_PID=$!
printf '%s\n' "$GAME_PID" > "$GAME_PID_FILE"

set +e
wait "$GAME_PID"
GAME_RC=$?
set -e

echo "[NRO] game exited with code $GAME_RC"
exit "$GAME_RC"
