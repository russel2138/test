#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/opt/nso
SRC=$ROOT/source
REPO=https://github.com/russel2138/test.git
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if (( EUID != 0 )); then
  echo 'Run as root: sudo bash install.sh' >&2
  exit 1
fi
if [[ "$(uname -m)" != x86_64 ]]; then
  echo 'Expected Linux x86_64' >&2
  exit 1
fi
. /etc/os-release
if [[ "${ID:-}:${VERSION_CODENAME:-}" != ubuntu:jammy ]]; then
  echo "Expected Ubuntu 22.04 jammy; detected ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi
if [[ ! -f "$SCRIPT_DIR/nat64_socks5.py" || ! -f "$SCRIPT_DIR/test_proxy.py" ]]; then
  echo 'Download the complete woiden/ directory, not install.sh alone.' >&2
  exit 1
fi

echo '[1/6] Installing dependencies via IPv6/DNS64...'
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::ForceIPv6=true update
apt-get -o Acquire::ForceIPv6=true install -y --no-install-recommends \
  git curl wget ca-certificates bash python3 unzip tar openssl \
  iproute2 procps xz-utils

echo '[2/6] Preparing directories and source...'
mkdir -p "$ROOT/games" "$ROOT/emulators" "$ROOT/nro-data"
if [[ -d "$SRC/.git" ]]; then
  echo "Keeping existing checkout: $SRC"
elif [[ -e "$SRC" ]]; then
  echo "Not a Git checkout: $SRC (refusing to overwrite)" >&2
  exit 1
else
  git clone --depth 1 "$REPO" "$SRC"
fi
install -m 0644 "$SCRIPT_DIR/nat64_socks5.py" "$ROOT/nat64_socks5.py"
install -m 0644 "$SCRIPT_DIR/test_proxy.py" "$ROOT/test_proxy.py"

echo '[3/6] Patching local checkout for NSO and loopback-only VNC...'
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
ctl = src / 'raven/nroctl.sh'
s = ctl.read_text()
old = '-rfbport "$VNC_PORT"'
new = '-rfbport "$VNC_PORT" -localhost'
if new not in s:
    if s.count(old) != 1:
        raise SystemExit('Unexpected VNC command in nroctl.sh')
    ctl.write_text(s.replace(old, new, 1))

start = src / 'raven/start-raven.sh'
s = start.read_text()
old = 'if ! "$SCRIPT_DIR/nroctl.sh" start; then'
new = 'if ! "$SCRIPT_DIR/nroctl.sh" start stock NSO.jar 127.0.0.1:1080; then'
if new not in s:
    if s.count(old) != 1:
        raise SystemExit('Unexpected default launch command in start-raven.sh')
    start.write_text(s.replace(old, new, 1))
print('Only local checkout patched; GitHub Raven runtime unchanged.')
PY

echo '[4/6] Bootstrapping Java 17, MicroEmulator, TigerVNC...'
NRO_ROOT="$ROOT" NRO_DATA="$ROOT/nro-data" bash "$SRC/raven/bootstrap-runtime.sh"
"$ROOT/nro-data/java17/bin/java" -version 2>&1 | head -n 2

echo '[5/6] Writing system services and command wrapper...'
cat > /etc/systemd/system/nat64-socks5.service <<'EOF'
[Unit]
Description=Loopback SOCKS5 NAT64 bridge for NSO
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/bin/python3 -u /opt/nso/nat64_socks5.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/nso-game.service <<'EOF'
[Unit]
Description=Ninja School Online Java 17 + MicroEmulator + VNC
After=network-online.target nat64-socks5.service
Wants=network-online.target
Requires=nat64-socks5.service

[Service]
Type=simple
WorkingDirectory=/opt/nso
Environment=NRO_ROOT=/opt/nso
Environment=NRO_DATA=/opt/nso/nro-data
Environment=VNC_PORT=5901
Environment=JAVA_XMS=16m
Environment=JAVA_XMX=160m
ExecStart=/bin/bash /opt/nso/source/raven/start-raven.sh
ExecStop=/usr/local/bin/nsoctl stop
Restart=on-failure
RestartSec=8
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/nsoctl <<'EOF'
#!/usr/bin/env bash
export NRO_ROOT=/opt/nso NRO_DATA=/opt/nso/nro-data VNC_PORT=5901 JAVA_XMS=16m JAVA_XMX=160m
exec /bin/bash /opt/nso/source/raven/nroctl.sh "$@"
EOF
chmod 0755 /usr/local/bin/nsoctl

echo '[6/6] Starting SOCKS5, leaving game stopped until NSO.jar is supplied...'
if [[ "$(ps -p 1 -o comm= | tr -d ' ')" == systemd ]]; then
  systemctl daemon-reload
  systemctl enable --now nat64-socks5.service
  systemctl disable nso-game.service 2>/dev/null || true
  echo 'After placing NSO.jar in /opt/nso/games/: systemctl enable --now nso-game'
else
  echo 'PID 1 is not systemd; start the proxy manually with:'
  echo 'nohup python3 -u /opt/nso/nat64_socks5.py > /opt/nso/nat64.log 2>&1 < /dev/null &'
  echo 'After uploading NSO.jar, start the game with:'
  echo 'NRO_ROOT=/opt/nso NRO_DATA=/opt/nso/nro-data VNC_PORT=5901 nohup bash /opt/nso/source/raven/start-raven.sh > /opt/nso/game-run.log 2>&1 < /dev/null &'
fi

echo '=== SETUP COMPLETE ==='
echo 'Test SOCKS5: python3 /opt/nso/test_proxy.py'
echo 'Java 17: /opt/nso/nro-data/java17/bin/java -version'
echo 'Game JAR destination: /opt/nso/games/NSO.jar'
echo 'VNC: localhost-only TCP 5901 (access via SSH tunnel)'
echo 'RMS remains file-backed. No TUN, FUSE or route changes.'
