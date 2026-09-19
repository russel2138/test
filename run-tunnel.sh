#!/usr/bin/env bash
set -uo pipefail

PORT="${PORT:-8080}"

while true; do
  rm -f /data/tunnel-url.txt
  echo "[tunnel] starting Cloudflare Quick Tunnel -> http://127.0.0.1:${PORT}"
  echo "[tunnel] the URL changes whenever cloudflared/container restarts"

  last_url=""
  cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${PORT}" 2>&1 |
  while IFS= read -r line; do
    printf '[cloudflared] %s\n' "$line"
    if [[ "$line" =~ (https://[A-Za-z0-9-]+\.trycloudflare\.com) ]]; then
      url="${BASH_REMATCH[1]}"
      if [[ "$url" != "$last_url" ]]; then
        last_url="$url"
        printf '%s\n' "$url" > /data/tunnel-url.txt
        printf '\n============================================================\n'
        printf ' NRO_REMOTE_URL=%s\n' "$url"
        printf ' Open that URL in your browser.\n'
        printf ' Password: XPRA_PASSWORD (same password for first upload).\n'
        printf '============================================================\n\n'
      fi
    fi
  done

  rc=${PIPESTATUS[0]}
  echo "[tunnel] cloudflared exited with code ${rc}; retrying in 5 seconds..."
  sleep 5
done
