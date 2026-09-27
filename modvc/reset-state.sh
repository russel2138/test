#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-$(pwd)}"
DATA="${NRO_DATA:-$ROOT/.nro-data}"
STATE="$DATA/home/.microemulator"

case "$STATE" in
  "$ROOT"/.nro-data/home/.microemulator|"$DATA"/home/.microemulator)
    ;;
  *)
    echo "[ERROR] refusing unexpected state path: $STATE" >&2
    exit 1
    ;;
esac

echo "[STATE] deleting: $STATE"
rm -rf -- "$STATE"
mkdir -p "$STATE/suite-null"
rm -f -- "$DATA/game-manifest.jad"
echo "[STATE] reset complete"
