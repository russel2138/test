#!/usr/bin/env bash
set -euo pipefail

rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
exec Xvfb "${DISPLAY:-:99}" -screen 0 360x640x16 -nolisten tcp -noreset
