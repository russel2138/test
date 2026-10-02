#!/usr/bin/env bash
set -euo pipefail

ROOT="${NRO_ROOT:-${HOME:-/home/container}}"
DATA="${NRO_DATA:-$ROOT/nro-data}"
MICROEMU="$DATA/microemu"
VNC="$DATA/vnc"
JAVA17="$DATA/java17"
JAVA17_URL="https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jre/hotspot/normal/eclipse"
APTROOT="$DATA/.raven-apt"
FOCAL_RUNTIME_URL="https://github.com/russel2138/test/releases/download/nro-runtime-v1/nro-runtime-focal-amd64.tar.gz"
FOCAL_RUNTIME_SHA256="54300034ec2de5a14647ac68bb1d141437f23c9c879bbb7e5f7ce391194fd69c"
mkdir -p "$DATA"

fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --connect-timeout 20 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=5 --timeout=20 -O "$out" "$url"
  else
    echo "[bootstrap] ERROR: curl/wget not found" >&2
    return 1
  fi
}

ensure_java17() {
  if [[ -x "$JAVA17/bin/java" ]]; then
    if "$JAVA17/bin/java" -version 2>&1 | head -n1 | grep -q '"17\.'; then
      echo "[bootstrap] Java 17 already present: $("$JAVA17/bin/java" -version 2>&1 | head -n1)"
      return 0
    fi
  fi

  echo "[bootstrap] downloading Eclipse Temurin JRE 17..."
  local tmp="$DATA/.temurin17.tar.gz"
  rm -f "$tmp"
  fetch "$JAVA17_URL" "$tmp"

  rm -rf "$JAVA17"
  mkdir -p "$JAVA17"
  tar -xzf "$tmp" -C "$JAVA17" --strip-components=1
  rm -f "$tmp"

  [[ -x "$JAVA17/bin/java" ]] || {
    echo "[bootstrap] ERROR: Java 17 binary missing after extraction" >&2
    return 1
  }

  if ! "$JAVA17/bin/java" -version 2>&1 | head -n1 | grep -q '"17\.'; then
    echo "[bootstrap] ERROR: downloaded runtime is not Java 17" >&2
    "$JAVA17/bin/java" -version 2>&1 | head -n3 >&2 || true
    return 1
  fi

  echo "[bootstrap] Java 17 ready: $("$JAVA17/bin/java" -version 2>&1 | head -n1)"
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

install_focal_runtime() {
  local tmp="$DATA/.nro-runtime-focal-amd64.tar.gz"

  echo "[bootstrap] downloading prebuilt Ubuntu focal TigerVNC runtime..."
  rm -f "$tmp"
  fetch "$FOCAL_RUNTIME_URL" "$tmp"

  if command -v sha256sum >/dev/null 2>&1; then
    local actual
    actual="$(sha256sum "$tmp" | awk '{print $1}')"
    if [[ "$actual" != "$FOCAL_RUNTIME_SHA256" ]]; then
      echo "[bootstrap] ERROR: runtime checksum mismatch" >&2
      echo "[bootstrap] expected: $FOCAL_RUNTIME_SHA256" >&2
      echo "[bootstrap] actual  : $actual" >&2
      rm -f "$tmp"
      return 1
    fi
  fi

  rm -rf "$VNC"
  mkdir -p "$VNC"

  # The release bundle contains usr/, lib/ and other runtime directories plus
  # microemu/. Keep VNC native files under nro-data/vnc; MicroEmulator remains
  # at nro-data/microemu for backward compatibility.
  tar -xzf "$tmp" -C "$VNC" --exclude='./microemu' --exclude='microemu'
  if [[ ! -s "$MICROEMU/microemulator.jar" ]]; then
    tar -xzf "$tmp" -C "$DATA" ./microemu 2>/dev/null ||       tar -xzf "$tmp" -C "$DATA" microemu
  fi
  rm -f "$tmp"

  # Ubuntu 20.04 provides this binary from tigervnc-common. Keep the newer
  # runtime name expected by start-raven.sh as an alias when needed.
  if [[ ! -x "$VNC/usr/bin/tigervncpasswd" && -x "$VNC/usr/bin/vncpasswd" ]]; then
    ln -s vncpasswd "$VNC/usr/bin/tigervncpasswd"
  fi
}

ensure_vnc() {
  if [[ -x "$VNC/usr/bin/Xtigervnc" && -x "$VNC/usr/bin/xkbcomp" && -x "$VNC/usr/bin/tigervncpasswd" && -s "$VNC/usr/share/X11/xkb/keycodes/evdev" && -s "$VNC/usr/share/X11/xkb/rules/evdev" ]]; then
    echo "[bootstrap] TigerVNC runtime + XKB data already present"
    return 0
  fi

  local arch codename user
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  [[ "$arch" == "amd64" || "$arch" == "x86_64" ]] || {
    echo "[bootstrap] ERROR: only amd64 is supported (got $arch)" >&2
    return 1
  }

  . /etc/os-release
  codename="${VERSION_CODENAME:-}"

  # Zampto java_8 is Ubuntu 20.04/focal. Use our prebuilt bundle so startup
  # does not depend on apt repository availability or root permissions.
  if [[ "$codename" == "focal" ]]; then
    install_focal_runtime
  else
    if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
      echo "[bootstrap] ERROR: apt-get/dpkg-deb missing in host image" >&2
      return 1
    fi

    case "$codename" in
      jammy|noble) ;;
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
      -o "Acquire::Retries=5"
    )

    apt-get "${APT_OPTS[@]}" update
    apt-get "${APT_OPTS[@]}" -y --download-only --no-install-recommends install       tigervnc-standalone-server tigervnc-tools x11-xkb-utils xkb-data xfonts-base       fonts-dejavu-core libx11-6 libxext6 libxi6 libxrender1 libxtst6       libxrandr2 libxfixes3 libxinerama1 libxcb1 libxau6 libxdmcp6

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
  fi

  [[ -x "$VNC/usr/bin/Xtigervnc" ]] || { echo "[bootstrap] ERROR: Xtigervnc missing" >&2; return 1; }
  [[ -x "$VNC/usr/bin/xkbcomp" ]] || { echo "[bootstrap] ERROR: xkbcomp missing" >&2; return 1; }
  [[ -x "$VNC/usr/bin/tigervncpasswd" ]] || { echo "[bootstrap] ERROR: tigervncpasswd missing" >&2; return 1; }
  [[ -s "$VNC/usr/share/X11/xkb/keycodes/evdev" ]] || { echo "[bootstrap] ERROR: XKB keycodes/evdev missing" >&2; return 1; }
  [[ -s "$VNC/usr/share/X11/xkb/rules/evdev" ]] || { echo "[bootstrap] ERROR: XKB rules/evdev missing" >&2; return 1; }

  echo "[bootstrap] TigerVNC runtime + XKB data ready"
}

ensure_java17
ensure_microemu
ensure_vnc
