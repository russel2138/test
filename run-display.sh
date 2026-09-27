#!/usr/bin/env bash
set -euo pipefail

DISPLAY_NUM="${DISPLAY:-:99}"
VNC_PORT="${VNC_PORT:-5900}"

rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true

echo "[display] TigerVNC Xvnc ${DISPLAY_NUM} 240x180x16, VNC localhost:${VNC_PORT}"

exec /usr/bin/Xtigervnc "${DISPLAY_NUM}" \
  -geometry 240x180 \
  -depth 16 \
  -rfbport "${VNC_PORT}" \
  -localhost \
  -SecurityTypes None \
  -AlwaysShared \
  -DisconnectClients=0 \
  -desktop NRO \
  -nolisten tcp \
  -noreset
