#!/usr/bin/env bash
# Botkeep process supervisor. Keeps console commands available after HERO crashes.
set -Eeuo pipefail
umask 077

REPO="${HERO_REPO_ROOT:-$PWD}"
if [[ ! -f "$REPO/raven/bootstrap-runtime.sh" && -f "${HOME:-/home/container}/raven/bootstrap-runtime.sh" ]]; then
  REPO="$HOME"
fi
BASE_URL="https://raw.githubusercontent.com/russel2138/test/botkeep/hero-v2"
FILES=(
  botkeep/console.sh
  botkeep/start.sh
  botkeep/test.sh
  botkeep/README.md
  raven/bootstrap-runtime.sh
)
APP_PID=""
log() { printf '[hero-console] %s\n' "$*"; }

fetch_file() {
  local url="$1" output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 12 --max-time 90 "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=45 -O "$output" "$url"
  else
    log 'ERROR: curl or wget is required to update from GitHub.'
    return 1
  fi
}

update_files() {
  local stage rel target temp
  mkdir -p "$REPO/botkeep" "$REPO/raven" || return 1
  stage="$(mktemp -d "$REPO/.hero-update.XXXXXXXX")" || return 1

  for rel in "${FILES[@]}"; do
    mkdir -p "$stage/$(dirname "$rel")"
    if ! fetch_file "$BASE_URL/$rel" "$stage/$rel"; then
      log "Download failed: $rel. Existing files were not changed."
      rm -rf "$stage"
      return 1
    fi
    if [[ ! -s "$stage/$rel" ]] || (( $(wc -c < "$stage/$rel") > 262144 )); then
      log "Invalid or oversized update file: $rel"
      rm -rf "$stage"
      return 1
    fi
  done

  if ! bash -n "$stage/botkeep/console.sh" "$stage/botkeep/start.sh" \
      "$stage/botkeep/test.sh" "$stage/raven/bootstrap-runtime.sh"; then
    log 'Downloaded code failed bash -n; existing files are intact.'
    rm -rf "$stage"
    return 1
  fi
  if ! bash "$stage/botkeep/test.sh"; then
    log 'Downloaded code failed smoke checks; existing files are intact.'
    rm -rf "$stage"
    return 1
  fi

  for rel in "${FILES[@]}"; do
    target="$REPO/$rel"
    temp="$(mktemp "$(dirname "$target")/.hero-new.XXXXXXXX")" || {
      rm -rf "$stage"; return 1;
    }
    if ! cp "$stage/$rel" "$temp"; then
      rm -f "$temp"; rm -rf "$stage"; return 1
    fi
    if [[ "$rel" == *.sh ]]; then chmod 700 "$temp"; else chmod 600 "$temp"; fi
    if ! mv -f "$temp" "$target"; then
      rm -f "$temp"; rm -rf "$stage"; return 1
    fi
  done
  rm -rf "$stage"
  log "Updated ${FILES[*]} from GitHub branch botkeep/hero-v2."
  return 0
}

start_app() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    log "HERO already running (runner PID $APP_PID)."
    return
  fi
  if [[ ! -f "$REPO/botkeep/start.sh" ]]; then
    log 'HERO runner missing. Type update to download it.'
    return
  fi
  bash "$REPO/botkeep/start.sh" </dev/null &
  APP_PID=$!
  log "Started runner PID $APP_PID."
}

stop_app() {
  if [[ -n "$APP_PID" ]]; then
    if kill -0 "$APP_PID" 2>/dev/null; then
      kill -TERM "$APP_PID" 2>/dev/null || true
    fi
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
}

reap_app() {
  if [[ -n "$APP_PID" ]] && ! kill -0 "$APP_PID" 2>/dev/null; then
    local result=0
    wait "$APP_PID" 2>/dev/null || result=$?
    log "HERO exited (status $result). Console stays online: update / restart / logs."
    APP_PID=""
  fi
}

shutdown() {
  trap - EXIT INT TERM
  stop_app
}
trap shutdown EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${1:-}" == --check ]]; then
  log "Console script syntax OK. Repository root: $REPO"
  exit 0
fi
[[ "${1:-}" == "" || "${1:-}" == --no-fetch ]] || {
  log 'Usage: bash botkeep/console.sh [--check|--no-fetch]'
  exit 2
}

if [[ "${1:-}" != --no-fetch ]]; then
  log 'Checking GitHub for latest HERO runtime...'
  if ! update_files; then
    log 'Could not refresh code. Existing local files will be used.'
  fi
fi
start_app
log 'Console commands: update | restart | stop | status | logs | help'
while :; do
  reap_app
  if IFS= read -r -t 2 command_line; then
    # Pterodactyl console input is a line, not a shell command.
    case "$command_line" in
      update)
        log 'Fetching new Botkeep runtime (not GitHub Import/Sync)...'
        if update_files; then
          log 'Update validated. Restarting HERO with the latest code.'
          stop_app
          exec bash "$REPO/botkeep/console.sh" --no-fetch
        fi
        log 'Update failed; running process and saves were preserved.'
        ;;
      restart)
        stop_app
        start_app
        ;;
      stop)
        stop_app
        log 'HERO stopped. Console remains active; type restart.'
        ;;
      status)
        if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
          log "Runner active: PID $APP_PID"
        else
          log 'HERO is stopped (or startup failed).'
        fi
        ;;
      logs)
        if [[ -f "$REPO/hero-data/hero.log" ]]; then
          tail -n 45 "$REPO/hero-data/hero.log"
        else
          log 'Game log missing; check previous console output.'
        fi
        ;;
      help)
        log 'update: fetch tested code from GitHub and restart game'
        log 'restart: restart game without fetching'
        log 'stop: stop game but keep console alive'
        log 'status: print process state'
        log 'logs: last 45 game log lines'
        ;;
      "") ;;
      *) log "Unknown command: $command_line (help for supported commands)" ;;
    esac
  else
    # Avoid busy-looping if the panel disconnects stdin.
    sleep 1
  fi
done
