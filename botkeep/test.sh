#!/usr/bin/env bash
set -euo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$dir/botkeep/start.sh" "$dir/botkeep/console.sh" "$dir/raven/bootstrap-runtime.sh"
bash "$dir/botkeep/console.sh" --check
for opt in 'HERO_XMX_MB=bad' 'HERO_XMS_MB=900' 'HERO_GEOMETRY=bad' 'HERO_VNC_PUBLIC=bad' 'HERO_VNC_PUBLIC=1'; do
  if env -u SERVER_PORT $opt bash "$dir/botkeep/start.sh" --check >/dev/null 2>&1; then
    echo "Invalid config passed: $opt" >&2; exit 1
  fi
done
bash "$dir/botkeep/start.sh" --check
echo 'Botkeep HERO smoke checks passed'
