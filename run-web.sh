#!/usr/bin/env bash
set -euo pipefail

export PYTHONPATH=/opt/websockify
exec python3 -m websockify.websocketproxy \
  --web=/usr/share/novnc \
  "0.0.0.0:${NOVNC_PORT:-8080}" \
  "127.0.0.1:${VNC_PORT:-5900}"
