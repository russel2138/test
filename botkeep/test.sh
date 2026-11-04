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
output="$(bash "$dir/botkeep/start.sh" --check)"
[[ "$output" == *"heap=32m..160m"* ]] || { echo "Unexpected Free plan heap default" >&2; exit 1; }
grep -Fq 'if [[ -f "$GAME_LOG" ]]; then' "$dir/botkeep/start.sh"
# Botkeep allocation must automatically select the allocated TCP port.
public_output="$(env -u HERO_VNC_PUBLIC SERVER_PORT=53360 bash "$dir/botkeep/start.sh" --check)"
[[ "$public_output" == *"port=53360, public=1"* ]] || {
  echo 'Botkeep assigned-port detection failed' >&2; exit 1;
}
private_output="$(env SERVER_PORT=53360 HERO_VNC_PUBLIC=0 bash "$dir/botkeep/start.sh" --check)"
[[ "$private_output" == *"port=5901, public=0"* ]] || {
  echo 'Botkeep private-VNC override failed' >&2; exit 1;
}
# No secrets are output at boot; password is displayed only on explicit 'vnc'.
grep -Fq '      vnc)' "$dir/botkeep/console.sh"
grep -Fq 'VNC password:' "$dir/botkeep/console.sh"
echo 'Botkeep HERO smoke checks passed'
