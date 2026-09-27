#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
RUNTIME="${WISPBYTE_RUNTIME:-$ROOT/nro-runtime}"
GAMES_DIR="$ROOT/games"
GAME="${NRO_GAME:-$GAMES_DIR/NRO_NEW.jar}"

RUNTIME_URL="${WISPBYTE_RUNTIME_URL:-https://github.com/russel2138/test/releases/download/wispbyte-runtime-v1/wispbyte-runtime-noble-amd64.tar}"
RUNTIME_SHA256="${WISPBYTE_RUNTIME_SHA256:-81c26b69aff84cb42aa8f6928172b0e41aab3105529ef1385dd94688a397c623}"

VNC_ORIG="$RUNTIME/usr/bin/Xtigervnc"
VNC_BIN="$RUNTIME/usr/bin/Xtigervnc-wispbyte"
XKBCOMP="$RUNTIME/usr/bin/xkbcomp"
XKBDIR="$RUNTIME/usr/share/X11/xkb"
VNC_LIB="$RUNTIME/usr/lib/x86_64-linux-gnu:$RUNTIME/lib/x86_64-linux-gnu:$RUNTIME/usr/lib"

DISPLAY_NUM="${DISPLAY_NUM:-:1}"
VNC_PORT="${VNC_PORT:-${SERVER_PORT:-}}"
VNC_GEOMETRY="${VNC_GEOMETRY:-640x480}"

JAVA_XMS="${JAVA_XMS:-16m}"
JAVA_XMX="${JAVA_XMX:-160m}"

# Intentionally disposable. Every server start begins with fresh RMS/settings.
SESSION="/tmp/nro-wispbyte"
EMU_HOME="$SESSION/home"
STATE="$EMU_HOME/.microemulator"
JAD="$EMU_HOME/game-manifest.jad"
VNC_PASS_FILE="$SESSION/vnc.passwd"
VNC_LOG="$SESSION/vnc.log"

fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 4 --retry-delay 2 --connect-timeout 20 "$url" -o "$out"
  else
    wget -O "$out" "$url"
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
    echo "[runtime] prebuilt runtime already present"
    return 0
  fi

  echo "[runtime] downloading prebuilt runtime; no apt/dpkg runs on Wispbyte"
  rm -rf "$RUNTIME" "$ROOT/.wispbyte-runtime.new"
  mkdir -p "$ROOT/.wispbyte-runtime.new"

  local archive="$ROOT/.wispbyte-runtime.tar"
  rm -f "$archive"
  fetch "$RUNTIME_URL" "$archive"

  echo "$RUNTIME_SHA256  $archive" | sha256sum -c -

  # Keep CPU bursts small because Wispbyte aggressively stops free servers.
  # This is only extraction of an already-built archive; no package resolver.
  nice -n 19 tar     --checkpoint=2048     --checkpoint-action=exec='sleep 0.05'     -xf "$archive"     -C "$ROOT/.wispbyte-runtime.new"

  rm -f "$archive"
  mv "$ROOT/.wispbyte-runtime.new" "$RUNTIME"

  runtime_ready || {
    echo "[ERROR] extracted runtime is incomplete" >&2
    exit 1
  }
  echo "[runtime] ready"
}

echo "[WISPBYTE] RAM limit: $(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unknown)"
echo "[WISPBYTE] CPU quota: $(cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo unknown)"
echo "[WISPBYTE] SERVER_PORT: ${SERVER_PORT:-unset}"

[[ -n "$VNC_PORT" ]] || {
  echo "[ERROR] SERVER_PORT/VNC_PORT is empty" >&2
  exit 1
}

ensure_runtime

[[ -s "$GAME" ]] || {
  echo "[ERROR] NRO game not found: $GAME" >&2
  echo "[ERROR] Upload it as: $GAMES_DIR/NRO_NEW.jar" >&2
  exit 1
}

# No persistent game state on this host.
rm -rf "$SESSION"
mkdir -p "$STATE/suite-null" /tmp/xxx

unzip -p "$GAME" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r' > "$JAD"
[[ -s "$JAD" ]] || {
  echo "[ERROR] META-INF/MANIFEST.MF missing from $GAME" >&2
  exit 1
}

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
  VNC_PASSWORD_ACTUAL="${VNC_PASSWORD:0:8}"
else
  VNC_PASSWORD_ACTUAL="$(printf '%s' "$(date +%s%N)-$RANDOM-$RANDOM" | sha256sum | cut -c1-8)"
fi

printf '%s\n' "$VNC_PASSWORD_ACTUAL" |
  "$RUNTIME/usr/bin/tigervncpasswd" -f > "$VNC_PASS_FILE"
chmod 600 "$VNC_PASS_FILE"

# Xtigervnc invokes /usr/bin/xkbcomp internally. Patch that fixed-length path
# to a private wrapper pointing at the bundled XKB tree.
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
  [[ -n "${VNC_PID:-}" ]] && kill "$VNC_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

: > "$VNC_LOG"
echo "[VNC] starting on port $VNC_PORT"

LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$VNC_BIN" "$DISPLAY_NUM"   -geometry "$VNC_GEOMETRY"   -depth 24   -rfbport "$VNC_PORT"   -localhost no   -SecurityTypes VncAuth   -rfbauth "$VNC_PASS_FILE"   -xkbdir "$XKBDIR"   >"$VNC_LOG" 2>&1 &
VNC_PID=$!

sleep 2
kill -0 "$VNC_PID" 2>/dev/null || {
  echo "[ERROR] TigerVNC failed to start" >&2
  tail -n 120 "$VNC_LOG" 2>/dev/null || true
  exit 1
}

export DISPLAY="$DISPLAY_NUM"
export LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}"

CP="$RUNTIME/microemu/microemulator.jar:$RUNTIME/microemu/lib/*:$RUNTIME/microemu/devices/*"

echo "================ NRO / WISPBYTE ================"
echo "Game:       $(basename "$GAME")"
echo "MIDlet:     $MIDLET"
echo "State:      $STATE (disposable)"
echo "VNC port:   $VNC_PORT"
echo "VNC pass:   $VNC_PASSWORD_ACTUAL"
echo "Heap:       $JAVA_XMS -> $JAVA_XMX"
echo "Watchdog:   OFF"
echo "================================================="
echo "[NRO] No apt/dpkg, no watchdog, no restart loop."

exec java   -Xms"$JAVA_XMS"   -Xmx"$JAVA_XMX"   -XX:+UseSerialGC   -Duser.home="$EMU_HOME"   -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel   -cp "$CP"   org.microemu.app.Main   --rms file   --resizableDevice 320 240   --appclasspath "$GAME"   --propertiesjad "$JAD"   --quit   "$MIDLET"
