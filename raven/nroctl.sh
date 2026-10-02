#!/usr/bin/env bash
set -u

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"

GAMES_DIR="$ROOT/games"
EMULATORS_DIR="$ROOT/emulators"
PROFILES_DIR="$DATA/profiles"
SELECTION_FILE="$DATA/current-selection.env"

EMU_SELECTOR=""
GAME_SELECTOR=""
EMU_NAME=""
GAME_NAME=""
EMU_JAR=""
GAME=""
EMU_HOME=""
STATE=""
JAD=""
CP=""
MIDLET_CLASS=""

VNC_ROOT="$DATA/vnc"
VNC_ORIG="$VNC_ROOT/usr/bin/Xtigervnc"
VNC_BIN="$VNC_ROOT/usr/bin/Xtigervnc-raven"
XKBCOMP="$VNC_ROOT/usr/bin/xkbcomp"
XKBDIR="$VNC_ROOT/usr/share/X11/xkb"
VNC_PASS="$DATA/.vnc/passwd"
VNC_LIB="$VNC_ROOT/usr/lib/x86_64-linux-gnu:$VNC_ROOT/lib/x86_64-linux-gnu:$VNC_ROOT/usr/lib"

DISPLAY_NUM=":1"
VNC_PORT="${VNC_PORT:-${SERVER_PORT:-17149}}"
VNC_GEOMETRY="${VNC_GEOMETRY:-640x480}"

JAVA_BIN="${JAVA_BIN:-$DATA/java17/bin/java}"
JAVA_XMS="${JAVA_XMS:-16m}"
JAVA_XMX="${JAVA_XMX:-160m}"

VNC_PID="$DATA/vnc.pid"
GAME_PID="$DATA/game.pid"
VNC_LOG="$DATA/vnc.log"
GAME_LOG="$DATA/game.log"

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
  cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
  [[ "$cmd" == *"Xtigervnc"* ]] || return 1
  printf '%s\n' "$p"
}

find_game_pid() {
  local p cmd
  [[ -s "$GAME_PID" ]] || return 1
  p="$(cat "$GAME_PID" 2>/dev/null || true)"
  [[ -n "$p" ]] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
  [[ "$cmd" == *"org.microemu.app.Main"* ]] || return 1
  printf '%s\n' "$p"
}

port_listening() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$VNC_PORT$"
}

safe_key() {
  printf '%s' "$1" | sed 's/\.jar$//I; s/[^A-Za-z0-9._-]/_/g'
}

load_selection() {
  EMU_SELECTOR=""
  GAME_SELECTOR=""
  if [[ -s "$SELECTION_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SELECTION_FILE"
  fi
  [[ -n "$EMU_SELECTOR" && -n "$GAME_SELECTOR" ]]
}

save_selection() {
  mkdir -p "$DATA"
  {
    printf 'EMU_SELECTOR=%q\n' "$EMU_SELECTOR"
    printf 'GAME_SELECTOR=%q\n' "$GAME_SELECTOR"
  } > "$SELECTION_FILE"
}

resolve_emulator() {
  local sel="$1" candidate="" dir=""
  EMU_SELECTOR="$sel"

  if [[ "$sel" == "stock" ]]; then
    [[ -s "$DATA/microemu/microemulator.jar" ]] || return 1
    EMU_NAME="stock"
    EMU_JAR="$DATA/microemu/microemulator.jar"
    CP="$DATA/microemu/microemulator.jar:$DATA/microemu/lib/*:$DATA/microemu/devices/*"
    return 0
  fi

  if [[ -s "$EMULATORS_DIR/$sel" ]]; then
    candidate="$EMULATORS_DIR/$sel"
  elif [[ -s "$EMULATORS_DIR/$sel.jar" ]]; then
    candidate="$EMULATORS_DIR/$sel.jar"
  else
    return 1
  fi

  if command -v unzip >/dev/null 2>&1; then
    unzip -l "$candidate" org/microemu/app/Main.class 2>/dev/null |
      grep -q 'org/microemu/app/Main.class' || {
        echo "[ERROR] Emulator is not MicroEmulator-compatible: $candidate" >&2
        return 1
      }
  elif command -v jar >/dev/null 2>&1; then
    jar tf "$candidate" 2>/dev/null |
      grep -qx 'org/microemu/app/Main.class' || {
        echo "[ERROR] Emulator is not MicroEmulator-compatible: $candidate" >&2
        return 1
      }
  fi

  EMU_JAR="$candidate"
  EMU_NAME="$(basename "$candidate")"
  EMU_NAME="${EMU_NAME%.jar}"
  dir="$(dirname "$candidate")"
  CP="$candidate:$dir/lib/*:$dir/devices/*"
}

resolve_game() {
  local sel="$1"
  GAME_SELECTOR="$sel"

  if [[ "$sel" == "game" || "$sel" == "game.jar" ]]; then
    [[ -s "$ROOT/game.jar" ]] || return 1
    GAME="$ROOT/game.jar"
  elif [[ -s "$GAMES_DIR/$sel" ]]; then
    GAME="$GAMES_DIR/$sel"
  elif [[ -s "$GAMES_DIR/$sel.jar" ]]; then
    GAME="$GAMES_DIR/$sel.jar"
  else
    return 1
  fi

  GAME_NAME="$(basename "$GAME")"
}

read_game_manifest() {
  if command -v unzip >/dev/null 2>&1; then
    unzip -p "$GAME" META-INF/MANIFEST.MF 2>/dev/null
    return $?
  fi

  if command -v jar >/dev/null 2>&1; then
    local tmp rc
    tmp="$(mktemp -d "$DATA/.manifest.XXXXXX")" || return 1
    (
      cd "$tmp"
      jar xf "$GAME" META-INF/MANIFEST.MF >/dev/null 2>&1
      cat META-INF/MANIFEST.MF
    )
    rc=$?
    rm -rf "$tmp"
    return $rc
  fi

  echo "[ERROR] Neither unzip nor jar is available to inspect the game JAR" >&2
  return 1
}

detect_midlet() {
  local unfolded line cls

  unfolded="$(
    read_game_manifest |
      tr -d '\r' |
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
      '
  )"

  line="$(printf '%s\n' "$unfolded" | grep -m1 '^MIDlet-1[[:space:]]*:')"
  [[ -n "$line" ]] || {
    echo "[ERROR] MIDlet-1 not found in $GAME" >&2
    return 1
  }

  cls="$(printf '%s\n' "$line" | awk -F',' '{v=$NF; gsub(/^[ \t]+|[ \t]+$/, "", v); print v}')"
  [[ -n "$cls" ]] || return 1
  MIDLET_CLASS="$cls"
}

select_runtime() {
  local emu_sel="$1" game_sel="$2" game_key emu_key

  resolve_emulator "$emu_sel" || {
    echo "[ERROR] Emulator not found: $emu_sel" >&2
    return 1
  }

  resolve_game "$game_sel" || {
    echo "[ERROR] Game not found: $game_sel" >&2
    return 1
  }

  detect_midlet || return 1

  if [[ "$EMU_NAME" == "stock" && "$GAME" == "$ROOT/game.jar" ]]; then
    EMU_HOME="$DATA/microemu-home"
  else
    game_key="$(safe_key "$GAME_NAME")"
    emu_key="$(safe_key "$EMU_NAME")"
    EMU_HOME="$PROFILES_DIR/$game_key/$emu_key"
  fi

  STATE="$EMU_HOME/.microemulator"
  JAD="$EMU_HOME/game-manifest.jad"
}

choose_runtime() {
  local emu_arg="${1:-}" game_arg="${2:-}"

  if [[ -n "$emu_arg" || -n "$game_arg" ]]; then
    if [[ -z "$emu_arg" || -z "$game_arg" ]]; then
      echo "[ERROR] Give both emulator and game" >&2
      return 1
    fi
    select_runtime "$emu_arg" "$game_arg" || return 1
    save_selection
    return 0
  fi

  if load_selection; then
    select_runtime "$EMU_SELECTOR" "$GAME_SELECTOR"
    return $?
  fi

  if [[ -s "$DATA/microemu/microemulator.jar" && -s "$ROOT/game.jar" ]]; then
    select_runtime "stock" "game.jar" || return 1
    save_selection
    return 0
  fi

  echo "[ERROR] No runtime selected" >&2
  echo "        Run 'list', then 'restart <emulator> <game>'" >&2
  return 1
}

list_runtime() {
  local f name found=0

  mkdir -p "$GAMES_DIR" "$EMULATORS_DIR" "$PROFILES_DIR"

  echo "================ AVAILABLE ================="
  echo "Emulators:"
  if [[ -s "$DATA/microemu/microemulator.jar" ]]; then
    printf '  %-22s %s\n' "stock" "$DATA/microemu/microemulator.jar"
    found=1
  fi
  for f in "$EMULATORS_DIR"/*.jar; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    printf '  %-22s %s\n' "${name%.jar}" "$f"
    found=1
  done
  [[ "$found" -eq 1 ]] || echo "  (none)"

  echo
  echo "Games:"
  found=0
  if [[ -s "$ROOT/game.jar" ]]; then
    printf '  %-26s %s (legacy)\n' "game.jar" "$ROOT/game.jar"
    found=1
  fi
  for f in "$GAMES_DIR"/*.jar; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    printf '  %-26s %s\n' "$name" "$f"
    found=1
  done
  [[ "$found" -eq 1 ]] || echo "  (none)"

  echo
  if load_selection; then
    echo "Current selection:"
    echo "  emulator: $EMU_SELECTOR"
    echo "  game:     $GAME_SELECTOR"
  else
    echo "Current selection: legacy default (stock + game.jar)"
  fi
  echo "============================================"
}

prepare() {
  mkdir -p "$DATA" "$EMU_HOME" "$STATE" "$DATA/.vnc" /tmp/xxx

  [[ -s "$GAME" ]] || { echo "[ERROR] Missing game: $GAME"; return 1; }
  [[ -s "$EMU_JAR" ]] || { echo "[ERROR] Missing emulator: $EMU_JAR"; return 1; }
  [[ -s "$VNC_PASS" ]] || { echo "[ERROR] Missing VNC password file: $VNC_PASS"; return 1; }

  read_game_manifest 2>/dev/null | tr -d '\r' > "$JAD.tmp" || true
  if [[ -s "$JAD.tmp" ]]; then
    mv -f "$JAD.tmp" "$JAD"
  else
    rm -f "$JAD.tmp"
  fi

  mkdir -p "$STATE/suite-null"

  rm -f /tmp/xxx/xkbcomp
  cat > /tmp/xxx/xkbcomp <<EOF
#!/bin/sh
exec "$XKBCOMP" -I"$XKBDIR" "\$@"
EOF
  chmod +x /tmp/xxx/xkbcomp

  cp "$VNC_ORIG" "$VNC_BIN"
  sed -i 's#/usr/bin#/tmp/xxx#g' "$VNC_BIN"
  chmod +x "$VNC_BIN"
}

start_vnc() {
  local p i

  p="$(find_vnc_pid || true)"
  if [[ -n "$p" ]] && port_listening; then
    echo "[VNC] already ON (pid $p, port $VNC_PORT)"
    return 0
  fi

  rm -f "$VNC_PID"
  : > "$VNC_LOG"

  echo "[VNC] starting"
  LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}"   nohup "$VNC_BIN" "$DISPLAY_NUM"     -geometry "$VNC_GEOMETRY"     -depth 24     -rfbport "$VNC_PORT"     -SecurityTypes VncAuth     -rfbauth "$VNC_PASS"     -xkbdir "$XKBDIR"     >"$VNC_LOG" 2>&1 </dev/null &

  echo $! > "$VNC_PID"

  for i in 1 2 3 4 5 6; do
    sleep 0.5
    if find_vnc_pid >/dev/null 2>&1 && port_listening; then
      echo "[VNC] ON (pid $(cat "$VNC_PID"), port $VNC_PORT)"
      return 0
    fi
  done

  echo "[VNC] failed to start"
  tail -n 100 "$VNC_LOG" 2>/dev/null || true
  rm -f "$VNC_PID"
  return 1
}

start_game() {
  local p

  p="$(find_game_pid || true)"
  if [[ -n "$p" ]]; then
    echo "[GAME] already ON (pid $p)"
    return 0
  fi

  rm -f "$GAME_PID"
  : > "$GAME_LOG"

  echo "[GAME] starting directly (manual restart only)"
  [[ -x "$JAVA_BIN" ]] || { echo "[ERROR] Java 17 runtime missing: $JAVA_BIN"; return 1; }

  DISPLAY="$DISPLAY_NUM"   LD_LIBRARY_PATH="$VNC_LIB:${LD_LIBRARY_PATH:-}"   nohup "$JAVA_BIN"     -Xms"$JAVA_XMS"     -Xmx"$JAVA_XMX"     -XX:+UseSerialGC     -Duser.home="$EMU_HOME"     -Dswing.defaultlaf=javax.swing.plaf.nimbus.NimbusLookAndFeel     -cp "$CP"     org.microemu.app.Main     --rms file     --resizableDevice 320 240     --appclasspath "$GAME"     --propertiesjad "$JAD"     --quit     "$MIDLET_CLASS"     >"$GAME_LOG" 2>&1 </dev/null &

  echo $! > "$GAME_PID"
  sleep 1

  p="$(find_game_pid || true)"
  if [[ -n "$p" ]]; then
    echo "[GAME] ON (pid $p)"
    return 0
  fi

  echo "[GAME] failed to start"
  tail -n 100 "$GAME_LOG" 2>/dev/null || true
  rm -f "$GAME_PID"
  return 1
}

stop_pidfile() {
  local f="$1" p i cmd

  [[ -s "$f" ]] || return 0
  p="$(cat "$f" 2>/dev/null || true)"
  [[ -n "$p" ]] || { rm -f "$f"; return 0; }

  if ! kill -0 "$p" 2>/dev/null; then
    rm -f "$f"
    return 0
  fi

  cmd="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
  case "$f" in
    "$VNC_PID")
      [[ "$cmd" == *"Xtigervnc"* ]] || { rm -f "$f"; return 0; }
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
  rm -f "$f"
}

stop_game() {
  stop_pidfile "$GAME_PID"
  echo "[GAME] OFF"
}

stop_all() {
  echo "[NRO] stopping..."
  stop_pidfile "$GAME_PID"
  stop_pidfile "$VNC_PID"
  echo "[NRO] stopped"
}

restart_game() {
  choose_runtime || return 1
  prepare || return 1
  stop_game
  start_game
}

status() {
  local vpid="" gpid=""
  vpid="$(find_vnc_pid || true)"
  gpid="$(find_game_pid || true)"

  echo "================ NRO STATUS ================"
  [[ -n "$EMU_NAME" ]] && echo "Emulator:            $EMU_NAME" || echo "Emulator:            (not resolved)"
  [[ -n "$GAME_NAME" ]] && echo "Game:                $GAME_NAME" || echo "Game:                (not resolved)"
  [[ -n "$MIDLET_CLASS" ]] && echo "MIDlet:              $MIDLET_CLASS"
  [[ -n "$vpid" ]] && echo "[ON]  VNC process      pid=$vpid" || echo "[OFF] VNC process"
  port_listening && echo "[ON]  VNC port         :$VNC_PORT LISTEN" || echo "[OFF] VNC port         :$VNC_PORT"
  [[ -n "$gpid" ]] && echo "[ON]  Game Java        pid=$gpid" || echo "[OFF] Game Java"
  [[ -s "$GAME" ]] && echo "[ON]  game.jar         $GAME" || echo "[OFF] game.jar"
  if [[ -x "$JAVA_BIN" ]]; then
    echo "Java game:           $("$JAVA_BIN" -version 2>&1 | head -n1)"
    echo "Java path:           $JAVA_BIN"
  else
    echo "Java game:           MISSING ($JAVA_BIN)"
  fi
  echo "Autorestart:         OFF"
  echo "State:               $STATE"
  echo "============================================"
}

show_log() {
  echo "=== GAME ==="
  tail -n 120 "$GAME_LOG" 2>/dev/null || true
  echo
  echo "=== VNC ==="
  tail -n 120 "$VNC_LOG" 2>/dev/null || true
}

follow_log() {
  echo "[LOG] live follow started (GAME + VNC)"
  tail -n 40 -F "$GAME_LOG" "$VNC_LOG" 2>/dev/null
}

case "${1:-}" in
  list)
    list_runtime
    ;;
  start)
    choose_runtime "${2:-}" "${3:-}" || exit 1
    prepare || exit 1
    start_vnc || exit 1
    start_game || exit 1
    sleep 1
    status
    ;;
  stop)
    stop_all
    ;;
  restart)
    choose_runtime "${2:-}" "${3:-}" || exit 1
    stop_all
    sleep 1
    prepare || exit 1
    start_vnc || exit 1
    start_game || exit 1
    sleep 1
    status
    ;;
  status)
    choose_runtime >/dev/null 2>&1 || true
    status
    ;;
  log)
    show_log
    ;;
  log-follow)
    follow_log
    ;;
  game-restart)
    restart_game
    ;;
  *)
    echo "Usage: $0 {list|start [emulator game]|stop|restart [emulator game]|status|log|log-follow|game-restart}"
    exit 1
    ;;
esac
