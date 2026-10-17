#!/usr/bin/env bash
# Source into an interactive Bash session on the Woiden VPS.
# Adds bare commands without modifying the existing Raven runtime.
[[ $- == *i* ]] || return 0

_nso_root=/opt/nso
_nso_data=/opt/nso/nro-data
_nso_proxy=127.0.0.1:1080

_nso_run() {
  NRO_ROOT="$_nso_root" NRO_DATA="$_nso_data" VNC_PORT=5901 \
    JAVA_XMS=16m JAVA_XMX=160m \
    /bin/bash "$_nso_root/source/raven/nroctl.sh" "$@"
}

_nso_start_restart() {
  local action="$1"
  shift
  # No explicit proxy means the host-local NAT64 SOCKS5 bridge.
  # 'direct' or an explicit proxy overrides this default.
  if (( $# == 0 )); then
    _nso_run "$action" "$_nso_proxy"
  elif (( $# == 2 )); then
    _nso_run "$action" "$1" "$2" "$_nso_proxy"
  else
    _nso_run "$action" "$@"
  fi
}

list() { _nso_run list; }
status() { _nso_run status; }
start() { _nso_start_restart start "$@"; }
restart() { _nso_start_restart restart "$@"; }
stop() { log-stop; _nso_run stop; }
game-restart() {
  if (( $# == 0 )); then
    _nso_run game-restart "$_nso_proxy"
  else
    _nso_run game-restart "$@"
  fi
}
rms-mode() { _nso_run rms-mode "$@"; }
rms-reset() { _nso_run rms-reset "$@"; }
game-errors() { _nso_run game-errors "$@"; }
vnc() {
  echo 'VNC: 127.0.0.1::5901 (SSH tunnel required)'
  if [[ -s "$_nso_data/vnc-password.txt" ]]; then
    echo "Password: $(cat "$_nso_data/vnc-password.txt")"
  else
    echo 'VNC password has not been created.'
  fi
}

_NSO_CONSOLE_LOG_PID=""
log() {
  if [[ -n "$_NSO_CONSOLE_LOG_PID" ]] &&
     kill -0 "$_NSO_CONSOLE_LOG_PID" 2>/dev/null; then
    echo "[LOG] already following (pid $_NSO_CONSOLE_LOG_PID)"
    return 0
  fi
  tail -n 40 -F "$_nso_data/game.log" "$_nso_data/vnc.log" &
  _NSO_CONSOLE_LOG_PID=$!
  echo "[LOG] live log ON (pid $_NSO_CONSOLE_LOG_PID). Run log-stop to stop."
}
log-stop() {
  if [[ -n "$_NSO_CONSOLE_LOG_PID" ]] &&
     kill -0 "$_NSO_CONSOLE_LOG_PID" 2>/dev/null; then
    kill "$_NSO_CONSOLE_LOG_PID" 2>/dev/null || true
    wait "$_NSO_CONSOLE_LOG_PID" 2>/dev/null || true
    echo '[LOG] live log OFF'
  fi
  _NSO_CONSOLE_LOG_PID=""
}

nso-help() {
  cat <<'HELP'
Ninja School console commands (SSH shell):
  list
  status
  start [emulator game] [ip:port[:user:password]|direct]
  restart [emulator game] [ip:port[:user:password]|direct]
  game-restart [ip:port[:user:password]|direct]
  stop
  log | log-stop
  game-errors
  rms-mode [file|memory] | rms-reset
  vnc
  help
With no proxy argument, start/restart/game-restart use local NAT64 SOCKS5.
Examples:
  restart stock game.jar
  game-restart
  restart stock game.jar direct
Your usual shell commands (ls, cd, bash, git) still work.
HELP
}
help() { nso-help; }
