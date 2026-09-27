#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
MICROEMU="$DATA/microemu"
VNC="$DATA/vnc"
APTROOT="$DATA/.wispbyte-apt"

mkdir -p "$DATA"

fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 180 "$url" -o "$out"
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
  unzip -q "$tmp" -d "$DATA/.microemu-extract"

  local src
  src="$(find "$DATA/.microemu-extract" -maxdepth 3 -type f -name microemulator.jar -printf '%h\n' 2>/dev/null | head -n1 || true)"
  [[ -n "$src" ]] || {
    echo "[bootstrap] ERROR: microemulator.jar not found after extraction" >&2
    return 1
  }

  mv "$src" "$MICROEMU"
  rm -rf "$DATA/.microemu-extract" "$tmp"
  echo "[bootstrap] MicroEmulator ready"
}

write_sources() {
  local id codename version
  . /etc/os-release
  id="${ID:-}"
  codename="${VERSION_CODENAME:-}"
  version="${VERSION_ID:-}"

  case "$id:$codename" in
    ubuntu:focal|ubuntu:jammy|ubuntu:noble)
      cat > "$APTROOT/sources.list" <<SRC
deb [arch=amd64] http://archive.ubuntu.com/ubuntu $codename main universe
deb [arch=amd64] http://archive.ubuntu.com/ubuntu ${codename}-updates main universe
deb [arch=amd64] http://security.ubuntu.com/ubuntu ${codename}-security main universe
SRC
      ;;
    debian:bookworm|debian:trixie)
      cat > "$APTROOT/sources.list" <<SRC
deb [arch=amd64] http://deb.debian.org/debian $codename main
deb [arch=amd64] http://deb.debian.org/debian ${codename}-updates main
deb [arch=amd64] http://security.debian.org/debian-security ${codename}-security main
SRC
      ;;
    *)
      echo "[bootstrap] ERROR: unsupported apt base: id=$id codename=$codename version=$version" >&2
      echo "[bootstrap] Send: cat /etc/os-release" >&2
      return 1
      ;;
  esac
}

ensure_vnc() {
  if [[ -x "$VNC/usr/bin/Xtigervnc" &&
        -x "$VNC/usr/bin/xkbcomp" &&
        -x "$VNC/usr/bin/tigervncpasswd" &&
        -s "$VNC/usr/share/X11/xkb/keycodes/evdev" &&
        -s "$VNC/usr/share/X11/xkb/rules/evdev" ]]; then
    echo "[bootstrap] TigerVNC runtime + XKB data already present"
    return 0
  fi

  command -v apt-get >/dev/null 2>&1 || {
    echo "[bootstrap] ERROR: apt-get missing" >&2
    return 1
  }
  command -v dpkg-deb >/dev/null 2>&1 || {
    echo "[bootstrap] ERROR: dpkg-deb missing" >&2
    return 1
  }

  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || true)"
  [[ "$arch" == "amd64" ]] || {
    echo "[bootstrap] ERROR: only amd64 is supported (got $arch)" >&2
    return 1
  }

  echo "[bootstrap] preparing portable TigerVNC..."
  rm -rf "$APTROOT" "$VNC"
  mkdir -p     "$APTROOT/state/lists/partial"     "$APTROOT/cache/archives/partial"     "$APTROOT/log"     "$VNC"

  write_sources

  local -a APT_OPTS
  APT_OPTS=(
    -o "Dir::Etc::sourcelist=$APTROOT/sources.list"
    -o "Dir::Etc::sourceparts=-"
    -o "Dir::State=$APTROOT/state"
    -o "Dir::State::status=/var/lib/dpkg/status"
    -o "Dir::Cache=$APTROOT/cache"
    -o "Dir::Log=$APTROOT/log"
    -o "Debug::NoLocking=1"
    -o "Acquire::Check-Valid-Until=false"
  )

  apt-get "${APT_OPTS[@]}" update
  apt-get "${APT_OPTS[@]}" -y --download-only --no-install-recommends install     tigervnc-standalone-server tigervnc-tools x11-xkb-utils xkb-data xfonts-base     fonts-dejavu-core libx11-6 libxext6 libxi6 libxrender1 libxtst6     libxrandr2 libxfixes3 libxinerama1 libxcb1 libxau6 libxdmcp6

  # Some apt versions leave data-only packages out of the install download
  # because the base image already has them. Force local copies for portability.
  (cd "$APTROOT/cache/archives" && apt-get "${APT_OPTS[@]}" download xkb-data x11-xkb-utils >/dev/null 2>&1 || true)

  shopt -s nullglob
  local debs=("$APTROOT/cache/archives/"*.deb)
  (( ${#debs[@]} > 0 )) || {
    echo "[bootstrap] ERROR: apt downloaded no packages" >&2
    return 1
  }

  local deb
  for deb in "${debs[@]}"; do
    dpkg-deb -x "$deb" "$VNC"
  done
  shopt -u nullglob

  [[ -x "$VNC/usr/bin/Xtigervnc" ]] || { echo "[bootstrap] ERROR: Xtigervnc missing"; return 1; }
  [[ -x "$VNC/usr/bin/xkbcomp" ]] || { echo "[bootstrap] ERROR: xkbcomp missing"; return 1; }
  [[ -x "$VNC/usr/bin/tigervncpasswd" ]] || { echo "[bootstrap] ERROR: tigervncpasswd missing"; return 1; }
  [[ -s "$VNC/usr/share/X11/xkb/keycodes/evdev" ]] || { echo "[bootstrap] ERROR: XKB data missing"; return 1; }

  echo "[bootstrap] TigerVNC runtime + XKB data ready"
}

ensure_microemu
ensure_vnc
