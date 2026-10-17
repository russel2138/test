#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo 'Run as root on the Woiden VPS.' >&2
  exit 1
fi
ROOT=/opt/nso
DATA="$ROOT/nro-data"
HERE="$(cd "$(dirname "$0")" && pwd)"
[[ -s "$HERE/console-commands.sh" ]] || {
  echo 'Place console-commands.sh beside enable-console.sh.' >&2
  exit 1
}
[[ -s "$ROOT/source/raven/nroctl.sh" ]] || {
  echo 'The Woiden Raven runtime has not been installed yet.' >&2
  exit 1
}
[[ -s "$DATA/microemu/microemulator.jar" ]] || {
  echo 'Stock MicroEmulator is missing.' >&2
  exit 1
}

install -m 0644 "$HERE/console-commands.sh" "$ROOT/console-commands.sh"
mkdir -p "$ROOT/games" "$ROOT/emulators" "$DATA/.vnc"

# Use the same default game.jar bundled in the existing GitHub repository.
# Never overwrite a game already placed on the VPS.
if [[ ! -e "$ROOT/game.jar" && -s "$ROOT/source/game.jar" ]]; then
  cp "$ROOT/source/game.jar" "$ROOT/game.jar"
  echo "[GAME] Seeded $ROOT/game.jar from GitHub"
fi

PASS_BIN="$DATA/vnc/usr/bin/tigervncpasswd"
PASS_FILE="$DATA/.vnc/passwd"
PASS_TXT="$DATA/vnc-password.txt"
VNC_LIB="$DATA/vnc/usr/lib/x86_64-linux-gnu:$DATA/vnc/lib/x86_64-linux-gnu:$DATA/vnc/usr/lib"

if [[ ! -s "$PASS_FILE" ]]; then
  [[ -x "$PASS_BIN" ]] || { echo 'TigerVNC password tool missing.' >&2; exit 1; }
  if [[ -s "$PASS_TXT" ]]; then
    password="$(head -n1 "$PASS_TXT")"
  else
    password="$(openssl rand -hex 4)"
    printf '%s\n' "$password" > "$PASS_TXT"
    chmod 600 "$PASS_TXT"
  fi
  printf '%s\n' "$password" | LD_LIBRARY_PATH="$VNC_LIB" "$PASS_BIN" -f > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
  echo '[VNC] Password generated/loaded; port 5901 remains localhost-only.'
fi

BASHRC=/root/.bashrc
touch "$BASHRC"
if ! grep -Fq '# Woiden NSO console commands' "$BASHRC"; then
  cat >> "$BASHRC" <<'EOF'

# Woiden NSO console commands (interactive SSH only).
if [[ $- == *i* && -f /opt/nso/console-commands.sh ]]; then
  source /opt/nso/console-commands.sh
fi
EOF
fi

echo '[CONSOLE] Ready. Run the following in your CURRENT SSH window:'
echo '  source /opt/nso/console-commands.sh'
echo '  list'
echo '  status'
echo '  restart stock game.jar'
echo 'Your next interactive SSH login will load these commands automatically.'
