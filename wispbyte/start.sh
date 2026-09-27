#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
GAMES_DIR="$ROOT/games"
GAME="${NRO_GAME:-$GAMES_DIR/NRO_NEW.jar}"

VNC_ROOT="$DATA/vnc"
VNC_ORIG="$VNC_ROOT/usr/bin/Xtigervnc"
VNC_BIN="$VNC_ROOT/usr/bin/Xtigervnc-wispbyte"
XKBCOMP="$VNC_ROOT/usr/bin/xkbcomp"
XKBDIR="$VNC_ROOT/usr/share/X11/xkb"
VNC_LIB="$VNC_ROOT/usr/lib/x86_64-linux-gnu:$VNC_ROOT/lib/x86_64-linux-gnu:$VNC_ROOT/usr/lib"

DISPLAY_NUM="${DISPLAY_NUM:-:1}"
VNC_PORT="${VNC_PORT:-${SERVER_PORT:-}}"
VNC_GEOMETRY="${VNC_GEOMETRY:-640x480}"

JAVA_XMS="${JAVA_XMS:-16m}"
JAVA_XMX="${JAVA_XMX:-160m}"

BOOTSTRAP="$DATA/wispbyte-bootstrap-runtime.sh"
BOOTSTRAP_URL="${WISPBYTE_BOOTSTRAP_URL:-https://raw.githubusercontent.com/russel2138/test/main/wispbyte/bootstrap-runtime.sh}"

mkdir -p "$DATA" "$GAMES_DIR" "$DATA/.vnc" /tmp/xxx

fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 "$url" -o "$out"
  else
    wget -O "$out" "$url"
  fi
}

echo "[WISPBYTE] RAM limit: $(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unknown)"
echo "[WISPBYTE] CPU quota: $(cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo unknown)"
echo "[WISPBYTE] SERVER_PORT: ${SERVER_PORT:-unset}"

[[ -n "$VNC_PORT" ]] || {
  echo "[ERROR] SERVER_PORT/VNC_PORT is empty" >&2
  exit 1
}

# Refresh bootstrap from GitHub, but keep the last working copy if GitHub
# is temporarily unavailable.
tmp="$BOOTSTRAP.tmp.$$"
if fetch "$BOOTSTRAP_URL" "$tmp" && [[ -s "$tmp" ]]; then
  chmod +x "$tmp"
  mv -f "$tmp" "$BOOTSTRAP"
else
  rm -f "$tmp"
  [[ -s "$BOOTSTRAP" ]] || {
    echo "[ERROR] could not download bootstrap and no cached copy exists" >&2
    exit 1
  }
  echo "[WISPBYTE] GitHub unavailable; using cached bootstrap"
fi

bash "$BOOTSTRAP"

[[ -s "$GAME" ]] || {
  echo "[ERROR] NRO game not found: $GAME" >&2
  echo "[ERROR] Upload your game as: $GAMES_DIR/NRO_NEW.jar" >&2
  exit 1
}

GAME_NAME="$(basename "$GAME")"
GAME_KEY="$(printf '%s' "${GAME_NAME%.jar}" | sed 's/[^A-Za-z0-9._-]/_/g')"
EMU_HOME="$DATA/profiles/$GAME_KEY/stock"
STATE="$EMU_HOME/.microemulator"
JAD="$EMU_HOME/game-manifest.jad"

mkdir -p "$EMU_HOME" "$STATE/suite-null"

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

VNC_PASSWORD_FILE="$DATA/vnc-password.txt"
if [[ -n "${VNC_PASSWORD:-}" ]]; then
  printf '%s\n' "${VNC_PASSWORD:0:8}" > "$VNC_PASSWORD_FILE"
elif [[ ! -s "$VNC_PASSWORD_FILE" ]]; then
  random="$(printf '%s' "$(date +%s%N)-$RANDOM-$RANDOM" | sha256sum | cut -c1-8)"
  printf '%s\n' "$random" > "$VNC_PASSWORD_FILE"
fi
VNC_PASSWORD_ACTUAL="$(head -c 8 "$VNC_PASSWORD_FILE")"

printf '%s\n' "$VNC_PASSWORD_ACTUAL" |
  "$VNC_ROOT/usr/bin/tigervncpasswd" -f > "$DATA/.vnc/passwd"
chmod 600 "$DATA/.vnc/passwd"

# TigerVNC calls /usr/bin/xkbcomp internally. We do not have root on Wispbyte,
# so patch that same-length path to /tmp/xxx and provide a wrapper using the
# portable XKB tree.
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
  if [[ -n "${VNC_PID:-}" ]]; then
    kill "$VNC_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

VNC_LOG="$DATA/vnc.log"
: > "$VNC_LOG"

echo "[VNC] starting on :$VNC_PORT"
LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$VNC_BIN" "$DISPLAY_NUM"   -geometry "$VNC_GEOMETRY"   -depth 24   -rfbport "$VNC_PORT"   -localhost no   -SecurityTypes VncAuth   -rfbauth "$DATA/.vnc/passwd"   -xkbdir "$XKBDIR"   >"$VNC_LOG" 2>&1 &
VNC_PID=$!

sleep 2
kill -0 "$VNC_PID" 2>/dev/null || {
  echo "[ERROR] TigerVNC failed to start" >&2
  tail -n 120 "$VNC_LOG" 2>/dev/null || true
  exit 1
}

export DISPLAY="$DISPLAY_NUM"
export LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}"

CP="$DATA/microemu/microemulator.jar:$DATA/microemu/lib/*:$DATA/microemu/devices/*"

echo "================ NRO / WISPBYTE ================"
echo "Game:       $GAME_NAME"
echo "MIDlet:     $MIDLET"
echo "State:      $STATE"
echo "VNC port:   $VNC_PORT"
echo "VNC pass:   $VNC_PASSWORD_ACTUAL"
echo "Heap:       $JAVA_XMS -> $JAVA_XMX"
echo "Watchdog:   OFF"
echo "================================================="
echo "[NRO] Java runs in foreground. If Java exits, this script exits."
echo "[NRO] No restart loop / network watchdog / loop watchdog / stall watchdog."

java   -Xms"$JAVA_XMS"   -Xmx"$JAVA_XMX"   -XX:+UseSerialGC   -Duser.home="$EMU_HOME"   -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel   -cp "$CP"   org.microemu.app.Main   --rms file   --resizableDevice 320 240   --appclasspath "$GAME"   --propertiesjad "$JAD"   --quit   "$MIDLET"
