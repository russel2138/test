#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
CACHE="${NRO_GITHUB_CACHE:-$ROOT/.nro-elysian-src}"
BRANCH="${NRO_GITHUB_BRANCH:-main}"
REMOTE="https://raw.githubusercontent.com/russel2138/test/$BRANCH/elysian/nroctl.sh"
TARGET="$CACHE/nroctl.sh"
TMP="$CACHE/.nroctl.sh.tmp.$$"

mkdir -p "$CACHE"

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --max-time 45 "$REMOTE" -o "$TMP"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 45 -O "$TMP" "$REMOTE"
  else
    echo "[github] ERROR: curl/wget not found" >&2
    return 1
  fi
}

if fetch && [[ -s "$TMP" ]] && head -n1 "$TMP" | grep -q '^#!/usr/bin/env bash'; then
  chmod +x "$TMP"
  mv -f "$TMP" "$TARGET"
else
  rm -f "$TMP"
  if [[ ! -s "$TARGET" ]]; then
    echo "[github] ERROR: could not download controller and no cached copy exists" >&2
    exit 1
  fi
  echo "[github] update failed; using cached controller" >&2
fi

exec bash "$TARGET" "$@"
