#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
TARGET="$ROOT/nroctl.sh"
REMOTE="https://raw.githubusercontent.com/russel2138/test/main/elysian/launcher.sh"
TMP="$ROOT/.nroctl-launcher.tmp.$$"

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --max-time 45 "$REMOTE" -o "$TMP"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 45 -O "$TMP" "$REMOTE"
  else
    echo "[install] ERROR: curl/wget not found" >&2
    return 1
  fi
}

fetch
[[ -s "$TMP" ]] || { echo "[install] ERROR: launcher download is empty" >&2; exit 1; }

if [[ -f "$TARGET" ]]; then
  backup="$ROOT/nroctl.sh.pre-github.$(date +%Y%m%d-%H%M%S)"
  cp -p "$TARGET" "$backup"
  echo "[install] old controller backed up: $backup"
fi

chmod +x "$TMP"
mv -f "$TMP" "$TARGET"

mkdir -p "$ROOT/games" "$ROOT/emulators" "$ROOT/nro-data"

echo "[install] GitHub-managed launcher installed: $TARGET"
echo "[install] next:"
echo "  $TARGET list"
echo "  $TARGET status"
