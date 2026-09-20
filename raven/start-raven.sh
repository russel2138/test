#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
export NRO_ROOT="$ROOT" NRO_DATA="$DATA"

[[ -s "$ROOT/game.jar" ]] || {
  echo "[raven] ERROR: upload the NRO J2ME jar as $ROOT/game.jar" >&2
  exit 1
}

mkdir -p "$DATA" "$DATA/.vnc" "$DATA/microemu-home/.microemulator/suite-null"
chmod +x "$SCRIPT_DIR/bootstrap-runtime.sh" "$SCRIPT_DIR/nroctl.sh"
"$SCRIPT_DIR/bootstrap-runtime.sh"

VNC_LIB="$DATA/vnc/usr/lib/x86_64-linux-gnu:$DATA/vnc/lib/x86_64-linux-gnu:$DATA/vnc/usr/lib"
PASS_FILE="$DATA/.vnc/passwd"
PASS_TXT="$DATA/vnc-password.txt"
PASS_BIN="$DATA/vnc/usr/bin/tigervncpasswd"

if [[ ! -s "$PASS_FILE" ]]; then
  if [[ -s "$PASS_TXT" ]]; then
    VNC_PASSWORD="$(head -n1 "$PASS_TXT")"
  elif [[ -n "${VNC_PASSWORD:-}" ]]; then
    VNC_PASSWORD="${VNC_PASSWORD:0:8}"
    printf '%s\n' "$VNC_PASSWORD" > "$PASS_TXT"
  else
    VNC_PASSWORD="$(openssl rand -hex 4)"
    printf '%s\n' "$VNC_PASSWORD" > "$PASS_TXT"
  fi
  chmod 600 "$PASS_TXT"
  printf '%s\n' "$VNC_PASSWORD" | LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" "$PASS_BIN" -f > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
fi

VNC_PORT="${VNC_PORT:-${SERVER_PORT:-17149}}"
export VNC_PORT

echo "============================================================"
echo " NRO on Raven (GitHub managed runtime)"
echo " Source      : $SCRIPT_DIR"
echo " Game        : $ROOT/game.jar"
echo " State       : $DATA/microemu-home/.microemulator"
echo " VNC address : ${SERVER_IP:-tex.ravenhost.space}:$VNC_PORT"
echo " VNC password: $(cat "$PASS_TXT" 2>/dev/null || true)"
echo " Java        : $(java -version 2>&1 | head -n1)"
echo "============================================================"

shutdown() {
  echo "[raven] stopping NRO..."
  "$SCRIPT_DIR/nroctl.sh" stop >/dev/null 2>&1 || true
  exit 0
}
trap shutdown INT TERM

"$SCRIPT_DIR/nroctl.sh" start

watchdog_loop() {
  while true; do
    sleep 30

    bad=0
    if [[ ! -s "$DATA/vnc.pid" ]] || ! kill -0 "$(cat "$DATA/vnc.pid" 2>/dev/null)" 2>/dev/null; then
      echo "[raven] VNC process is down"
      bad=1
    fi
    if [[ ! -s "$DATA/game-supervisor.pid" ]] || ! kill -0 "$(cat "$DATA/game-supervisor.pid" 2>/dev/null)" 2>/dev/null; then
      echo "[raven] game supervisor is down"
      bad=1
    fi

    if [[ "$bad" -eq 1 ]]; then
      echo "[raven] restarting full NRO stack..."
      "$SCRIPT_DIR/nroctl.sh" restart || true
    fi
  done
}

watchdog_loop &
WATCHDOG_PID=$!
trap 'kill "$WATCHDOG_PID" 2>/dev/null || true; shutdown' INT TERM

echo "[raven] Console commands: status | log | game-restart | restart | vnc | help"

# Raven sends panel console input to stdin of the main process. Keep this
# script in the foreground so simple commands can be typed directly into
# the Raven console without SSH.
while true; do
  if ! IFS= read -r cmd; then
    sleep 3600
    continue
  fi

  case "$cmd" in
    status)
      "$SCRIPT_DIR/nroctl.sh" status
      ;;
    log|logs)
      "$SCRIPT_DIR/nroctl.sh" log
      ;;
    game-restart)
      "$SCRIPT_DIR/nroctl.sh" game-restart
      ;;
    restart)
      echo "[raven] restarting NRO stack..."
      "$SCRIPT_DIR/nroctl.sh" restart
      ;;
    vnc)
      echo "VNC address : ${SERVER_IP:-tex.ravenhost.space}:$VNC_PORT"
      echo "VNC password: $(cat "$PASS_TXT" 2>/dev/null || true)"
      ;;
    help|"")
      echo "Commands: status | log | game-restart | restart | vnc | help"
      ;;
    *)
      echo "[raven] unknown command: $cmd"
      echo "Commands: status | log | game-restart | restart | vnc | help"
      ;;
  esac
done
