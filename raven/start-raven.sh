#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
export NRO_ROOT="$ROOT" NRO_DATA="$DATA"

mkdir -p "$ROOT/games" "$ROOT/emulators"
mkdir -p "$DATA" "$DATA/.vnc" "$DATA/microemu-home/.microemulator/suite-null"
chmod +x "$SCRIPT_DIR/bootstrap-runtime.sh" "$SCRIPT_DIR/nroctl.sh"
"$SCRIPT_DIR/bootstrap-runtime.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_GAME="$REPO_ROOT/game.jar"
echo "[raven] repo game   : $REPO_GAME"
echo "[raven] host game   : $ROOT/game.jar"
if [[ ! -s "$ROOT/game.jar" ]]; then
  if [[ -s "$REPO_GAME" ]]; then
    echo "[raven] seeding default game.jar from repository ($(wc -c < "$REPO_GAME") bytes)"
    cp -f "$REPO_GAME" "$ROOT/game.jar"
    sync "$ROOT/game.jar" 2>/dev/null || true
    [[ -s "$ROOT/game.jar" ]] || {
      echo "[raven] ERROR: host game.jar is still missing after copy" >&2
      exit 1
    }
    echo "[raven] host game ready ($(wc -c < "$ROOT/game.jar") bytes)"
  else
    echo "[raven] ERROR: repository game.jar missing at $REPO_GAME" >&2
  fi
else
  echo "[raven] keeping existing host game.jar ($(wc -c < "$ROOT/game.jar") bytes)"
fi

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
echo " NRO on Raven / Pterodactyl"
echo " Source       : $SCRIPT_DIR"
echo " Legacy game  : $ROOT/game.jar"
echo " Game uploads : $ROOT/games/"
echo " Emulators    : $ROOT/emulators/"
echo " Data/state   : $DATA"
echo " VNC address  : ${SERVER_IP:-0.0.0.0}:$VNC_PORT"
echo " VNC password : $(cat "$PASS_TXT" 2>/dev/null || true)"
echo " Java         : $(java -version 2>&1 | head -n1)"
echo " Autorestart  : OFF"
echo "============================================================"

LIVE_LOG_PID=""

stop_live_log() {
  if [[ -n "${LIVE_LOG_PID:-}" ]] && kill -0 "$LIVE_LOG_PID" 2>/dev/null; then
    kill "$LIVE_LOG_PID" 2>/dev/null || true
    wait "$LIVE_LOG_PID" 2>/dev/null || true
    echo "[LOG] live follow stopped"
  fi
  LIVE_LOG_PID=""
}

shutdown() {
  trap - INT TERM
  stop_live_log
  echo "[raven] stopping NRO..."
  "$SCRIPT_DIR/nroctl.sh" stop >/dev/null 2>&1 || true
  exit 0
}
trap shutdown INT TERM

if ! "$SCRIPT_DIR/nroctl.sh" start; then
  echo "[raven] NRO stack did not start; console stays available."
  echo "[raven] Run 'list', then 'restart <emulator> <game>' after fixing files."
fi

print_help() {
  echo "Commands:"
  echo "  list"
  echo "  start [<emulator> <game>]"
  echo "  stop"
  echo "  restart [<emulator> <game>]"
  echo "  game-restart"
  echo "  status"
  echo "  log | log-stop"
  echo "  vnc | help"
  echo "  update              # pull latest GitHub runtime and reload"
  echo "  exit | shutdown     # stop everything and exit main server process"
  echo "Example: restart stock game.jar"
}

echo "[raven] Console ready."
print_help

while true; do
  if ! IFS= read -r cmd; then
    sleep 3600
    continue
  fi

  read -r -a parts <<< "$cmd"
  action="${parts[0]:-}"
  args=("${parts[@]:1}")

  case "$action" in
    list)
      "$SCRIPT_DIR/nroctl.sh" list
      ;;
    start)
      "$SCRIPT_DIR/nroctl.sh" start "${args[@]}"
      ;;
    stop)
      stop_live_log
      "$SCRIPT_DIR/nroctl.sh" stop
      ;;
    restart|use)
      stop_live_log
      "$SCRIPT_DIR/nroctl.sh" restart "${args[@]}"
      ;;
    game-restart)
      "$SCRIPT_DIR/nroctl.sh" game-restart
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
    vnc)
      echo "VNC address : ${SERVER_IP:-0.0.0.0}:$VNC_PORT"
      echo "VNC password: $(cat "$PASS_TXT" 2>/dev/null || true)"
      ;;
    update)
      echo "[raven] updating runtime from GitHub..."
      stop_live_log
      "$SCRIPT_DIR/nroctl.sh" stop >/dev/null 2>&1 || true
      if git -C "$REPO_ROOT" fetch --depth=1 origin main && git -C "$REPO_ROOT" reset --hard origin/main; then
        echo "[raven] update complete; reloading runtime..."
        exec bash "$REPO_ROOT/raven/start-raven.sh"
      else
        echo "[raven] update failed; runtime remains stopped" >&2
      fi
      ;;
    exit|shutdown)
      echo "[raven] shutting down main server process..."
      shutdown
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
