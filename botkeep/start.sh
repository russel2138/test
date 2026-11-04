#!/usr/bin/env bash
# Botkeep HERO: separate app and data, reuse Raven's rootless TigerVNC installer.
set -Eeuo pipefail
umask 077
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${BOTKEEP_ROOT:-${HOME:-$REPO}}"
[[ -d "$ROOT" && -w "$ROOT" ]] || ROOT="$REPO"
DATA="${HERO_DATA_DIR:-$ROOT/hero-data}"
RUNTIME="$DATA/runtime"
VNC_ROOT="$RUNTIME/vnc"
HOME_DIR="$DATA/home"
GAME_LOG="$DATA/hero.log"
VNC_LOG="$DATA/vnc.log"
GAME_PID=""
VNC_PID=""
log(){ printf '[hero] %s\n' "$*"; }
die(){ log "ERROR: $*" >&2; exit 1; }
cleanup(){
  trap - EXIT INT TERM
  for pid in "$GAME_PID" "$VNC_PID"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ "$(uname -m)" == x86_64 || "$(uname -m)" == amd64 ]] || die 'Portable VNC supports x86_64 only.'
XMS="${HERO_XMS_MB:-32}"
XMX="${HERO_XMX_MB:-160}"
for n in "$XMS" "$XMX"; do [[ "$n" =~ ^[0-9]{1,4}$ ]] || die 'Heap must be an integer (MB).'; done
(( XMS >= 16 && XMS <= XMX && XMX >= 64 && XMX <= 1024 )) || die 'Heap range: 16<=XMS<=XMX<=1024 MB.'
DISPLAY_NUM="${HERO_DISPLAY:-:92}"
GEOMETRY="${HERO_GEOMETRY:-800x600}"
[[ "$DISPLAY_NUM" =~ ^:[1-9][0-9]?$ ]] || die 'HERO_DISPLAY must be :1..:99.'
[[ "$GEOMETRY" =~ ^[0-9]{3,4}x[0-9]{3,4}$ ]] || die 'HERO_GEOMETRY must be WIDTHxHEIGHT.'
PUBLIC="${HERO_VNC_PUBLIC:-0}"
[[ "$PUBLIC" == 0 || "$PUBLIC" == 1 ]] || die 'HERO_VNC_PUBLIC must be 0 or 1.'
if [[ "$PUBLIC" == 1 ]]; then
  [[ -n "${SERVER_PORT:-}" ]] || die 'Raw TCP SERVER_PORT must be assigned by Botkeep before public VNC.'
  PORT="${HERO_VNC_PORT:-$SERVER_PORT}"
  [[ "$PORT" == "$SERVER_PORT" ]] || die 'Public VNC port must equal assigned SERVER_PORT.'
  LOCALHOST=no
else
  PORT="${HERO_VNC_PORT:-5901}"
  LOCALHOST=yes
fi
[[ "$PORT" =~ ^[0-9]{4,5}$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die 'Invalid VNC port.'
if [[ "${1:-}" == --check ]]; then
  log "CPU=$(uname -m), heap=${XMS}m..${XMX}m, display=$GEOMETRY, port=$PORT, public=$PUBLIC"
  log "java=$(command -v java || echo missing), apt-get=$(command -v apt-get || echo missing), dpkg-deb=$(command -v dpkg-deb || echo missing)"
  log "Upload HERO-Emulator-V2.jar into $ROOT; runtime data in $DATA"
  exit 0
fi
[[ "${1:-}" == '' ]] || die 'Usage: bash botkeep/start.sh [--check]'
mkdir -p "$DATA" "$HOME_DIR" "$DATA/cache" "$DATA/tmp" "$RUNTIME/.vnc"
JAR="${HERO_JAR:-$ROOT/HERO-Emulator-V2.jar}"
[[ "$JAR" == /* ]] || JAR="$ROOT/$JAR"
if [[ ! -s "$JAR" && -f "$ROOT/HERO-Emulator-V2.zip" ]]; then
  command -v unzip >/dev/null || die 'Extract ZIP locally and upload the JAR (unzip missing).'
  JAR="$DATA/HERO-Emulator-V2.jar"
  tmp="$(mktemp "$DATA/.jar.XXXXXXXX")"
  (ulimit -f 32768; unzip -p "$ROOT/HERO-Emulator-V2.zip" HERO-Emulator-V2.jar > "$tmp") || die 'ZIP does not contain HERO-Emulator-V2.jar.'
  mv "$tmp" "$JAR"
fi
[[ -s "$JAR" && ! -L "$JAR" ]] || die 'Upload HERO-Emulator-V2.jar (or original ZIP) to the server Files.'
(( $(wc -c < "$JAR") <= 33554432 )) || die 'JAR larger than 32 MiB.'
if command -v unzip >/dev/null; then
  unzip -p "$JAR" META-INF/MANIFEST.MF | tr -d '\r' | grep -q '^Main-Class: loader.Bootstrap$' || die 'Unexpected HERO JAR manifest.'
fi
[[ -f "$REPO/raven/bootstrap-runtime.sh" ]] || die 'Missing raven/bootstrap-runtime.sh.'
export NRO_ROOT="$ROOT" NRO_DATA="$RUNTIME" RAVEN_SKIP_MICROEMU=1
JAVA_BIN=""
if command -v java >/dev/null; then
  ver="$(java -version 2>&1 | head -n1 || true)"
  if [[ "$ver" =~ (openjdk|version)[[:space:]]*\"?([0-9]+) ]] && (( BASH_REMATCH[2] >= 17 )); then
    JAVA_BIN="$(command -v java)"
    export RAVEN_SKIP_JAVA=1
  fi
fi
log 'Installing/verifying rootless TigerVNC; no system package writes.'
bash "$REPO/raven/bootstrap-runtime.sh"
[[ -n "$JAVA_BIN" ]] || JAVA_BIN="$RUNTIME/java17/bin/java"
[[ -x "$JAVA_BIN" ]] || die 'Java 17+ not found.'
VNC_LIB="$VNC_ROOT/usr/lib/x86_64-linux-gnu:$VNC_ROOT/lib/x86_64-linux-gnu:$VNC_ROOT/usr/lib"
VNC_BIN="$VNC_ROOT/usr/bin/Xtigervnc-hero"
VNC_ORIG="$VNC_ROOT/usr/bin/Xtigervnc"
XKBCOMP="$VNC_ROOT/usr/bin/xkbcomp"
XKBDIR="$VNC_ROOT/usr/share/X11/xkb"
PASS="$RUNTIME/.vnc/passwd"
for p in "$VNC_ORIG" "$XKBCOMP" "$VNC_ROOT/usr/bin/tigervncpasswd" "$XKBDIR/rules/evdev"; do
  [[ -s "$p" ]] || die "Missing TigerVNC file: $p"
done
if [[ ! -s "$PASS" ]]; then
  pw="${VNC_PASSWORD:-}"
  if [[ -z "$pw" ]]; then
    pw="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
    printf '%s\n' "$pw" > "$DATA/vnc-password.txt"
    log "Random VNC password saved at $DATA/vnc-password.txt (not logged)."
  fi
  [[ "${#pw}" -ge 8 ]] || die 'VNC_PASSWORD must be at least 8 characters.'
  printf '%s\n' "$pw" | LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$VNC_ROOT/usr/bin/tigervncpasswd" -f > "$PASS"
  chmod 600 "$PASS"
fi
unset pw VNC_PASSWORD
mkdir -p /tmp/xxx
printf '#!/bin/sh\nexec "%s" -I"%s" "$@"\n' "$XKBCOMP" "$XKBDIR" > /tmp/xxx/xkbcomp
chmod 700 /tmp/xxx/xkbcomp
staged="$(mktemp "$VNC_ROOT/usr/bin/.hero-vnc.XXXXXXXX")"
cp "$VNC_ORIG" "$staged"
LC_ALL=C sed -i 's#/usr/bin#/tmp/xxx#g' "$staged"
chmod 700 "$staged"
mv -f "$staged" "$VNC_BIN"
n="${DISPLAY_NUM#:}"
[[ ! -e "/tmp/.X11-unix/X$n" && ! -e "/tmp/.X$n-lock" ]] || die 'X11 display already in use.'
LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$VNC_BIN" "$DISPLAY_NUM" \
  -geometry "$GEOMETRY" -depth 16 -rfbport "$PORT" \
  -SecurityTypes VncAuth -rfbauth "$PASS" -localhost "$LOCALHOST" \
  -xkbdir "$XKBDIR" -nolisten tcp > "$VNC_LOG" 2>&1 &
VNC_PID=$!
for _ in {1..30}; do
  kill -0 "$VNC_PID" 2>/dev/null || { tail -n 25 "$VNC_LOG" >&2; die 'TigerVNC exited'; }
  [[ -S "/tmp/.X11-unix/X$n" ]] && break
  sleep 0.2
done
[[ -S "/tmp/.X11-unix/X$n" ]] || die 'TigerVNC did not create its X11 socket.'
export DISPLAY="$DISPLAY_NUM" HOME="$HOME_DIR" XDG_CACHE_HOME="$DATA/cache" TMPDIR="$DATA/tmp"
log "Launching HERO -Xms${XMS}m -Xmx${XMX}m. VNC port=$PORT public=$PUBLIC"
# Open the game log synchronously before background Java starts.
: >> "$GAME_LOG" || die "Cannot create HERO game log: $GAME_LOG"
LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$JAVA_BIN" \
  -Xms"${XMS}m" -Xmx"${XMX}m" -XX:+UseSerialGC \
  -Djava.awt.headless=false -Dfile.encoding=UTF-8 \
  -Djava.io.tmpdir="$DATA/tmp" -Duser.home="$HOME_DIR" \
  -jar "$JAR" >> "$GAME_LOG" 2>&1 &
GAME_PID=$!
log "HERO pid=$GAME_PID, VNC pid=$VNC_PID. No watchdog or public tunnel."
log 'VNC access requires an approved raw TCP allocation; HTTP-only domains are not VNC.'
while kill -0 "$GAME_PID" 2>/dev/null; do
  if ! kill -0 "$VNC_PID" 2>/dev/null; then
    log 'Display exited; stopping game.'
    kill "$GAME_PID" 2>/dev/null || true
    break
  fi
  # Deleting a log should not crash the game supervisor.
  if [[ -f "$GAME_LOG" ]]; then
    log_size="$(wc -c < "$GAME_LOG" 2>/dev/null || printf '0')"
    if [[ "$log_size" =~ ^[0-9]+$ ]] && (( log_size > 8388608 )); then
      if tail -c 65536 "$GAME_LOG" > "$DATA/.hero-last"; then
        cat "$DATA/.hero-last" > "$GAME_LOG"
      fi
      rm -f "$DATA/.hero-last"
    fi
  fi
  sleep 15 & wait $! || true
done
set +e
wait "$GAME_PID"
rc=$?
set -e
log "HERO exited code $rc"
tail -n 25 "$GAME_LOG" 2>/dev/null || true
exit "$rc"
