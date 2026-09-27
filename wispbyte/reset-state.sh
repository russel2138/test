#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
GAME_NAME="${1:-NRO_NEW.jar}"
GAME_KEY="$(printf '%s' "${GAME_NAME%.jar}" | sed 's/[^A-Za-z0-9._-]/_/g')"
STATE="$DATA/profiles/$GAME_KEY/stock/.microemulator"
JAD="$DATA/profiles/$GAME_KEY/stock/game-manifest.jad"

case "$STATE" in
  "$DATA"/profiles/*/stock/.microemulator) ;;
  *)
    echo "[ERROR] refusing unexpected state path: $STATE" >&2
    exit 1
    ;;
esac

echo "[STATE] deleting: $STATE"
rm -rf -- "$STATE"
mkdir -p "$STATE/suite-null"
rm -f -- "$JAD"
echo "[STATE] reset complete for $GAME_NAME"
