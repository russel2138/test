#!/usr/bin/env bash
set -u

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
GAME="$ROOT/game.jar"

EMU="$DATA/microemu"
EMU_HOME="$DATA/microemu-home"
STATE="$EMU_HOME/.microemulator"
JAD="$EMU_HOME/game-manifest.jad"

VNC_ROOT="$DATA/vnc"
VNC_ORIG="$VNC_ROOT/usr/bin/Xtigervnc"
VNC_BIN="$VNC_ROOT/usr/bin/Xtigervnc-raven"
XKBCOMP="$VNC_ROOT/usr/bin/xkbcomp"
XKBDIR="$VNC_ROOT/usr/share/X11/xkb"
VNC_PASS="$DATA/.vnc/passwd"
VNC_LIB="$VNC_ROOT/usr/lib/x86_64-linux-gnu:$VNC_ROOT/lib/x86_64-linux-gnu:$VNC_ROOT/usr/lib"

DISPLAY_NUM=":1"
VNC_PORT="${VNC_PORT:-${SERVER_PORT:-17149}}"
VNC_GEOMETRY="640x480"

NRO_SERVER_PORT="${NRO_SERVER_PORT:-14445}"
HEALTH_GRACE="${HEALTH_GRACE:-120}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-30}"
HEALTH_FAILS="${HEALTH_FAILS:-4}"

CP="$EMU/microemulator.jar:$EMU/lib/*:$EMU/devices/*"

VNC_PID="$DATA/vnc.pid"
SUP_PID="$DATA/game-supervisor.pid"
GAME_PID="$DATA/game.pid"
VNC_LOG="$DATA/vnc.log"
GAME_LOG="$DATA/game.log"
SUP_LOG="$DATA/supervisor.log"

SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

pid_alive() {
  local f="$1" p
  [[ -s "$f" ]] || return 1
  p="$(cat "$f" 2>/dev/null || true)"
  [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null
}

find_vnc_pid() {
  local p cmd
  [[ -s "$VNC_PID" ]] || return 1
  p="$(cat "$VNC_PID" 2>/dev/null || true)"
  [[ -n "$p" ]] || return 1
  kill -0 "$p" 2>/dev/null || return 1

  # Avoid treating a reused/stale PID as our VNC process.
  cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
  [[ "$cmd" == *"Xtigervnc"* ]] || return 1

  printf '%s\n' "$p"
}

find_game_pid() {
  if pid_alive "$GAME_PID"; then cat "$GAME_PID"; return 0; fi
  return 1
}

port_listening() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$VNC_PORT$"
}

game_connected() {
  ss -Htn state established 2>/dev/null | awk -v p=":$NRO_SERVER_PORT" '$5 ~ (p "$") {ok=1} END {exit !ok}'
}

trim_log() {
  local f="$1" tmp="${1}.tmp.$$"
  [[ -f "$f" ]] || return 0
  tail -n 160 "$f" > "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$f" 2>/dev/null || true
}

prepare() {
  mkdir -p "$DATA" "$EMU_HOME" "$STATE" "$DATA/.vnc" /tmp/xxx

  [[ -s "$GAME" ]] || { echo "[ERROR] Missing $GAME"; return 1; }
  [[ -s "$EMU/microemulator.jar" ]] || { echo "[ERROR] Missing $EMU/microemulator.jar"; return 1; }
  [[ -s "$VNC_PASS" ]] || { echo "[ERROR] Missing VNC password file: $VNC_PASS"; return 1; }

  if command -v unzip >/dev/null 2>&1; then
    unzip -p "$GAME" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r' > "$JAD.tmp" || true
    if [[ -s "$JAD.tmp" ]]; then mv -f "$JAD.tmp" "$JAD"; else rm -f "$JAD.tmp"; fi
  fi

  if [[ ! -e "$STATE/suite-null" && ! -L "$STATE/suite-null" ]]; then
    mkdir -p "$STATE/suite-null"
  fi

  # Xtigervnc was built to execute /usr/bin/xkbcomp. We cannot install
  # packages system-wide on Raven, so patch that fixed-length path to /tmp/xxx
  # and place a wrapper there. The wrapper injects the portable XKB include
  # root, which fixes "Can't find file evdev for keycodes include".
  rm -f /tmp/xxx/xkbcomp
  cat > /tmp/xxx/xkbcomp <<EOF
#!/bin/sh
exec "$XKBCOMP" -I"$XKBDIR" "\$@"
EOF
  chmod +x /tmp/xxx/xkbcomp

  # Rebuild the patched binary on every start so a script update is never
  # masked by a stale cached Xtigervnc-raven binary.
  cp "$VNC_ORIG" "$VNC_BIN"
  sed -i 's#/usr/bin#/tmp/xxx#g' "$VNC_BIN"
  chmod +x "$VNC_BIN"
}

start_vnc() {
  local p
  p="$(find_vnc_pid || true)"
  if [[ -n "$p" ]] && port_listening; then
    echo "[VNC] already ON (pid $p, port $VNC_PORT)"
    return 0
  fi

  # Stale PID file or half-dead X server: do not skip startup.
  if [[ -s "$VNC_PID" ]]; then
    echo "[VNC] stale/dead pidfile detected; starting a fresh X/VNC server"
    rm -f "$VNC_PID"
  fi

  : > "$VNC_LOG"
  echo "[VNC] starting with portable XKB root: $XKBDIR"
  LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}" \
  nohup "$VNC_BIN" "$DISPLAY_NUM" \
    -geometry "$VNC_GEOMETRY" \
    -depth 24 \
    -rfbport "$VNC_PORT" \
    -localhost no \
    -SecurityTypes VncAuth \
    -rfbauth "$VNC_PASS" \
    -xkbdir "$XKBDIR" \
    >"$VNC_LOG" 2>&1 &

  echo $! > "$VNC_PID"
  local i
  for i in 1 2 3 4 5 6; do
    sleep 0.5
    if pid_alive "$VNC_PID" && port_listening; then break; fi
  done

  if pid_alive "$VNC_PID" && port_listening; then
    echo "[VNC] ON (pid $(cat "$VNC_PID"), port $VNC_PORT)"
  else
    echo "[VNC] failed to start"
    tail -n 100 "$VNC_LOG" 2>/dev/null || true
    return 1
  fi
}

game_loop() {
  trap 'if [[ -s "'"$GAME_PID"'" ]]; then p="$(cat "'"$GAME_PID"'" 2>/dev/null)"; [[ -n "$p" ]] && kill "$p" 2>/dev/null || true; fi; rm -f "'"$GAME_PID"'"; exit 0' TERM INT

  export DISPLAY="$DISPLAY_NUM"
  export LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}"

  while true; do
    : > "$GAME_LOG"
    java       -Xms16m       -Xmx160m       -XX:+UseSerialGC       -Duser.home="$EMU_HOME"       -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel       -cp "$CP"       org.microemu.app.Main       --rms file       --resizableDevice 320 240       --appclasspath "$GAME"       --propertiesjad "$JAD"       --quit       nro.GameMidlet       >>"$GAME_LOG" 2>&1 &

    local child=$!
    echo "$child" > "$GAME_PID"
    printf '[%s] watchdog started game pid=%s\n' "$(date '+%F %T')" "$child" >> "$SUP_LOG"

    local started failures elapsed
    started="$(date +%s)"
    failures=0
    while kill -0 "$child" 2>/dev/null; do
      sleep "$HEALTH_INTERVAL"
      kill -0 "$child" 2>/dev/null || break
      elapsed=$(( $(date +%s) - started ))
      [[ "$elapsed" -lt "$HEALTH_GRACE" ]] && continue

      if game_connected; then
        failures=0
      else
        failures=$((failures + 1))
        printf '[%s] watchdog: NRO TCP :%s missing (%s/%s), pid=%s\n'           "$(date '+%F %T')" "$NRO_SERVER_PORT" "$failures" "$HEALTH_FAILS" "$child" >> "$SUP_LOG"
        trim_log "$SUP_LOG"
        if [[ "$failures" -ge "$HEALTH_FAILS" ]]; then
          echo "[$(date '+%F %T')] watchdog: restarting game" >> "$SUP_LOG"
          kill "$child" 2>/dev/null || true
          sleep 3
          kill -9 "$child" 2>/dev/null || true
          break
        fi
      fi
    done

    wait "$child" 2>/dev/null || true
    rm -f "$GAME_PID"
    echo "[$(date '+%F %T')] game ended; restart in 2s" >> "$SUP_LOG"
    trim_log "$SUP_LOG"
    sleep 2
  done
}

start_game() {
  if pid_alive "$SUP_PID"; then
    echo "[GAME] supervisor already ON (pid $(cat "$SUP_PID"))"
    return 0
  fi

  : > "$SUP_LOG"
  nohup "$SELF" _game_loop >>"$SUP_LOG" 2>&1 &
  echo $! > "$SUP_PID"
  sleep 1
  if pid_alive "$SUP_PID"; then
    echo "[GAME] supervisor ON (pid $(cat "$SUP_PID"))"
  else
    echo "[GAME] supervisor failed"
    tail -n 80 "$SUP_LOG" 2>/dev/null || true
    return 1
  fi
}

stop_pidfile() {
  local f="$1" p i cmd=""
  if pid_alive "$f"; then
    p="$(cat "$f")"

    # A stale pidfile can point at an unrelated process after a container
    # restart. Only signal known NRO-owned processes.
    cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
    case "$f" in
      "$VNC_PID")
        [[ "$cmd" == *"Xtigervnc"* ]] || { rm -f "$f"; return 0; }
        ;;
      "$SUP_PID")
        [[ "$cmd" == *"nroctl.sh"*"_game_loop"* || "$cmd" == *"/raven/nroctl.sh"*"_game_loop"* ]] || { rm -f "$f"; return 0; }
        ;;
      "$GAME_PID")
        [[ "$cmd" == *"org.microemu.app.Main"* ]] || { rm -f "$f"; return 0; }
        ;;
    esac

    kill "$p" 2>/dev/null || true
    for i in 1 2 3 4 5; do
      kill -0 "$p" 2>/dev/null || break
      sleep 0.4
    done
    kill -9 "$p" 2>/dev/null || true
  fi
  rm -f "$f"
}

stop_all() {
  echo "[NRO] stopping..."
  stop_pidfile "$SUP_PID"
  stop_pidfile "$GAME_PID"
  stop_pidfile "$VNC_PID"
  echo "[NRO] stopped"
}

status() {
  local vpid="" gpid="" spid=""
  vpid="$(find_vnc_pid || true)"
  gpid="$(find_game_pid || true)"
  if pid_alive "$SUP_PID"; then spid="$(cat "$SUP_PID")"; fi

  echo "================ NRO STATUS ================"
  [[ -n "$vpid" ]] && echo "[ON]  VNC process      pid=$vpid" || echo "[OFF] VNC process"
  port_listening && echo "[ON]  VNC port         :$VNC_PORT LISTEN" || echo "[OFF] VNC port         :$VNC_PORT"
  [[ -n "$spid" ]] && echo "[ON]  Game supervisor  pid=$spid" || echo "[OFF] Game supervisor"
  [[ -n "$gpid" ]] && echo "[ON]  Game Java        pid=$gpid" || echo "[OFF] Game Java"
  game_connected && echo "[ON]  Game network     TCP :$NRO_SERVER_PORT ESTABLISHED" || echo "[OFF] Game network"
  [[ -s "$GAME" ]] && echo "[ON]  game.jar         $GAME" || echo "[OFF] game.jar"
  echo "State: $STATE"
  echo "============================================"
}

show_log() {
  echo "=== GAME ==="; tail -n 100 "$GAME_LOG" 2>/dev/null || true
  echo; echo "=== SUPERVISOR ==="; tail -n 100 "$SUP_LOG" 2>/dev/null || true
  echo; echo "=== VNC ==="; tail -n 100 "$VNC_LOG" 2>/dev/null || true
}

case "${1:-}" in
  start) prepare || exit 1; start_vnc || exit 1; start_game || exit 1; sleep 1; status ;;
  stop) stop_all ;;
  restart) stop_all; sleep 1; prepare || exit 1; start_vnc || exit 1; start_game || exit 1; sleep 1; status ;;
  status) status ;;
  log) show_log ;;
  _game_loop) game_loop ;;
  *) echo "Usage: $0 {start|stop|restart|status|log}"; exit 1 ;;
esac
