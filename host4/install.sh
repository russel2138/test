#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-$HOME/data}"
APP="${NRO_APP:-$HOME/nro-host4}"
GAME="${NRO_GAME:-$ROOT/a.jar}"
MICROEMU="$APP/microemu"

mkdir -p "$APP" "$ROOT/nro-data" "$ROOT/logs" "$ROOT/run"

echo "[host4] installing Java + Xvfb + x11vnc..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends   openjdk-17-jre xvfb x11vnc unzip ca-certificates curl

echo "[host4] installing MicroEmulator 2.0.4..."
if [[ ! -s "$MICROEMU/microemulator.jar" ]]; then
  tmp="$(mktemp -d)"
  curl -fL --retry 4     https://downloads.sourceforge.net/project/microemulator/microemulator/2.0.4/microemulator-2.0.4.zip     -o "$tmp/microemu.zip"
  unzip -q "$tmp/microemu.zip" -d "$tmp/out"
  src="$(find "$tmp/out" -maxdepth 3 -type f -name microemulator.jar -printf '%h\n' | head -n1)"
  [[ -n "$src" ]]
  rm -rf "$MICROEMU"
  mkdir -p "$MICROEMU"
  cp -a "$src"/. "$MICROEMU"/
  rm -rf "$tmp"
fi

echo "[host4] fetching runtime scripts..."
base="https://raw.githubusercontent.com/russel2138/test/main/host4"
for file in nroctl run-display.sh run-vnc.sh run-game.sh; do
  curl -fsSL "$base/$file" -o "$APP/$file"
  chmod +x "$APP/$file"
done

if [[ ! -s "$GAME" ]]; then
  echo "[host4] game missing: $GAME"
  echo "Upload a.jar to $ROOT/a.jar, then run: $APP/nroctl start"
  exit 0
fi

"$APP/nroctl" start
"$APP/nroctl" status
