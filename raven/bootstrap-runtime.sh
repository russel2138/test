#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
MICROEMU="$DATA/microemu"
VNC="$DATA/vnc"
APTROOT="$DATA/.raven-apt"
mkdir -p "$DATA"

fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 4 --retry-delay 2 --connect-timeout 20 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    echo "[bootstrap] ERROR: curl/wget not found" >&2
    return 1
  fi
}

ensure_microemu() {
  if [[ -s "$MICROEMU/microemulator.jar" ]]; then
    echo "[bootstrap] MicroEmulator already present"
    return 0
  fi

  echo "[bootstrap] downloading MicroEmulator 2.0.4..."
  local tmp="$DATA/.microemulator-2.0.4.zip"
  rm -f "$tmp"
  fetch "https://downloads.sourceforge.net/project/microemulator/microemulator/2.0.4/microemulator-2.0.4.zip" "$tmp"

  local size
  size="$(wc -c < "$tmp" | tr -d ' ')"
  if [[ "$size" -lt 1500000 ]]; then
    echo "[bootstrap] ERROR: invalid MicroEmulator download ($size bytes)" >&2
    rm -f "$tmp"
    return 1
  fi

  rm -rf "$DATA/.microemu-extract" "$MICROEMU"
  mkdir -p "$DATA/.microemu-extract"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$tmp" -d "$DATA/.microemu-extract"
  else
    (cd "$DATA/.microemu-extract" && jar xf "$tmp")
  fi

  local src
  src="$(find "$DATA/.microemu-extract" -maxdepth 2 -type f -name microemulator.jar -printf '%h\n' 2>/dev/null | head -n1 || true)"
  if [[ -z "$src" ]]; then
    echo "[bootstrap] ERROR: microemulator.jar not found after extraction" >&2
    return 1
  fi
  mv "$src" "$MICROEMU"
  rm -rf "$DATA/.microemu-extract" "$tmp"
  echo "[bootstrap] MicroEmulator ready"
}

ensure_vnc() {
  if [[ -x "$VNC/usr/bin/Xtigervnc" && -x "$VNC/usr/bin/xkbcomp" && -x "$VNC/usr/bin/tigervncpasswd" && -s "$VNC/usr/share/X11/xkb/keycodes/evdev" && -s "$VNC/usr/share/X11/xkb/rules/evdev" ]]; then
    echo "[bootstrap] TigerVNC runtime + XKB data already present"
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "[bootstrap] ERROR: apt-get/dpkg-deb missing in Raven image" >&2
    return 1
  fi

  local arch codename user
  arch="$(dpkg --print-architecture 2>/dev/null || true)"
  [[ "$arch" == "amd64" ]] || {
    echo "[bootstrap] ERROR: only amd64 is supported (got $arch)" >&2
    return 1
  }

  . /etc/os-release
  codename="${VERSION_CODENAME:-}"
  case "$codename" in
    focal|jammy|noble) ;;
    *)
      echo "[bootstrap] ERROR: unsupported Ubuntu base: ${PRETTY_NAME:-unknown} ($codename)" >&2
      return 1
      ;;
  esac
  user="$(id -un)"

  echo "[bootstrap] preparing portable TigerVNC for Ubuntu $codename..."
  rm -rf "$APTROOT" "$VNC"
  mkdir -p "$APTROOT/state/lists/partial" "$APTROOT/cache/archives/partial" "$APTROOT/log" "$VNC"

  cat > "$APTROOT/sources.list" <<SRC
# Unprivileged package download only; nothing is installed system-wide.
deb [arch=amd64] http://archive.ubuntu.com/ubuntu $codename main universe
deb [arch=amd64] http://archive.ubuntu.com/ubuntu ${codename}-updates main universe
deb [arch=amd64] http://security.ubuntu.com/ubuntu ${codename}-security main universe
SRC

  APT_OPTS=(
    -o "Dir::Etc::sourcelist=$APTROOT/sources.list"
    -o "Dir::Etc::sourceparts=-"
    -o "Dir::State=$APTROOT/state"
    -o "Dir::State::status=/var/lib/dpkg/status"
    -o "Dir::Cache=$APTROOT/cache"
    -o "Dir::Log=$APTROOT/log"
    -o "Debug::NoLocking=1"
    -o "APT::Sandbox::User=$user"
    -o "Acquire::Check-Valid-Until=false"
  )

  apt-get "${APT_OPTS[@]}" update
  apt-get "${APT_OPTS[@]}" -y --download-only --no-install-recommends install     tigervnc-standalone-server tigervnc-tools x11-xkb-utils xkb-data xfonts-base     fonts-dejavu-core libx11-6 libxext6 libxi6 libxrender1 libxtst6     libxrandr2 libxfixes3 libxinerama1 libxcb1 libxau6 libxdmcp6

  (cd "$APTROOT/cache/archives" && apt-get "${APT_OPTS[@]}" download xkb-data x11-xkb-utils)

  shopt -s nullglob
  local debs=("$APTROOT/cache/archives/"*.deb)
  if (( ${#debs[@]} == 0 )); then
    echo "[bootstrap] ERROR: apt downloaded no packages" >&2
    return 1
  fi
  local deb
  for deb in "${debs[@]}"; do
    dpkg-deb -x "$deb" "$VNC"
  done
  shopt -u nullglob

  [[ -x "$VNC/usr/bin/Xtigervnc" ]] || { echo "[bootstrap] ERROR: Xtigervnc missing" >&2; return 1; }
  [[ -x "$VNC/usr/bin/xkbcomp" ]] || { echo "[bootstrap] ERROR: xkbcomp missing" >&2; return 1; }
  [[ -x "$VNC/usr/bin/tigervncpasswd" ]] || { echo "[bootstrap] ERROR: tigervncpasswd missing" >&2; return 1; }
  [[ -s "$VNC/usr/share/X11/xkb/keycodes/evdev" ]] || { echo "[bootstrap] ERROR: XKB keycodes/evdev missing" >&2; return 1; }
  [[ -s "$VNC/usr/share/X11/xkb/rules/evdev" ]] || { echo "[bootstrap] ERROR: XKB rules/evdev missing" >&2; return 1; }

  echo "[bootstrap] TigerVNC runtime + XKB data ready"
}

ensure_microemu
ensure_vnc
