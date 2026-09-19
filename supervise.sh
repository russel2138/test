#!/usr/bin/env bash
set -uo pipefail

name="${1:?component name required}"
shift
mkdir -p /run/nro

echo "$$" > "/run/nro/${name}.supervisor.pid"

cleanup() {
  if [[ -s "/run/nro/${name}.pid" ]]; then
    pid="$(cat "/run/nro/${name}.pid" 2>/dev/null || true)"
    [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
  fi
  rm -f "/run/nro/${name}.pid" "/run/nro/${name}.supervisor.pid"
}

shutdown() {
  cleanup
  exit 0
}

trap cleanup EXIT
trap shutdown INT TERM

while true; do
  "$@" &
  child=$!
  echo "$child" > "/run/nro/${name}.pid"
  wait "$child"
  rc=$?
  rm -f "/run/nro/${name}.pid"
  echo "[${name}] exited with code ${rc}; restarting in 3s"
  sleep 3
done
