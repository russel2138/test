#!/usr/bin/env bash
set -euo pipefail

exec websockify   --web=/usr/share/novnc   "0.0.0.0:${NOVNC_PORT:-8080}"   "127.0.0.1:${VNC_PORT:-5900}"
