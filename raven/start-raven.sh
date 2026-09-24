#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
DISABLED_MARKER="$DATA/stack.disabled"
export NRO_ROOT="$ROOT" NRO_DATA="$DATA"

mkdir -p "$ROOT/games" "$ROOT/emulators"
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
echo " Source       : $SCRIPT_DIR"
echo " Legacy game  : $ROOT/game.jar"
echo " Game uploads : $ROOT/games/"
echo " Emulators    : $ROOT/emulators/"
echo " Data/state   : $DATA"
echo " VNC address  : ${SERVER_IP:-tex.ravenhost.space}:$VNC_PORT"
echo " VNC password : $(cat "$PASS_TXT" 2>/dev/null || true)"
echo " Java         : $(java -version 2>&1 | head -n1)"
echo "============================================================"

shutdown() {
  echo "[raven] stopping NRO..."
  "$SCRIPT_DIR/nroctl.sh" stop >/dev/null 2>&1 || true
  exit 0
}
trap shutdown INT TERM

# A full Raven server restart always restores the selected runtime.
rm -f "$DISABLED_MARKER"
"$SCRIPT_DIR/nroctl.sh" start

watchdog_loop() {
  while true; do
    sleep 30

    # Console "stop" intentionally pauses automatic recovery until "start",
    # "restart", or a full Raven server restart.
    if [[ -e "$DISABLED_MARKER" ]]; then
      continue
    fi

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
LIVE_LOG_PID=""

stop_live_log() {
  if [[ -n "${LIVE_LOG_PID:-}" ]] && kill -0 "$LIVE_LOG_PID" 2>/dev/null; then
    kill "$LIVE_LOG_PID" 2>/dev/null || true
    wait "$LIVE_LOG_PID" 2>/dev/null || true
    echo "[LOG] live follow stopped"
  fi
  LIVE_LOG_PID=""
}

trap 'stop_live_log; kill "$WATCHDOG_PID" 2>/dev/null || true; shutdown' INT TERM

print_help() {
  echo "Commands:"
  echo "  list"
  echo "  start [<emulator> <game>]"
  echo "  stop"
  echo "  restart [<emulator> <game>]"
  echo "  status"
  echo "  log | log-stop"
  echo "  loop-check | game-restart"
  echo "  vnc | help"
  echo "Example: restart MICRO_NST AUTO50_X1"
}

echo "[raven] Console ready."
print_help

# Raven sends panel console input to stdin of the main process. This is not a shell.
while true; do
  if ! IFS= read -r cmd; then
    sleep 3600
    continue
  fi

  # Split into simple whitespace-separated args. Never eval panel input.
  read -r -a parts <<< "$cmd"
  action="${parts[0]:-}"
  args=("${parts[@]:1}")

  case "$action" in
    list)
      "$SCRIPT_DIR/nroctl.sh" list
      ;;
    start)
      rm -f "$DISABLED_MARKER"
      "$SCRIPT_DIR/nroctl.sh" start "${args[@]}"
      ;;
    stop)
      touch "$DISABLED_MARKER"
      stop_live_log
      "$SCRIPT_DIR/nroctl.sh" stop
      ;;
    status)
      "$SCRIPT_DIR/nroctl.sh" status
      ;;
    log|logs)
      if [[ -n "${LIVE_LOG_PID:-}" ]] && kill -0 "$LIVE_LOG_PID" 2>/dev/null; then
        echo "[LOG] live follow already running (pid $LIVE_LOG_PID)"
      else
        "$SCRIPT_DIR/nroctl.sh" log-follow &
        LIVE_LOG_PID=$!
        echo "[LOG] live follow ON (pid $LIVE_LOG_PID). Type: log-stop"
      fi
      ;;
    log-stop)
      stop_live_log
      ;;
    loop-check)
      "$SCRIPT_DIR/nroctl.sh" loop-check
      ;;
    game-restart)
      "$SCRIPT_DIR/nroctl.sh" game-restart
      ;;
    restart|use)
      rm -f "$DISABLED_MARKER"
      stop_live_log
      echo "[raven] restarting NRO stack..."
      "$SCRIPT_DIR/nroctl.sh" restart "${args[@]}"
      ;;
    vnc)
      echo "VNC address : ${SERVER_IP:-tex.ravenhost.space}:$VNC_PORT"
      echo "VNC password: $(cat "$PASS_TXT" 2>/dev/null || true)"
      ;;
    help|"")
      print_help
      ;;
    *)
      echo "[raven] unknown command: $cmd"
      print_help
      ;;
  esac
done
