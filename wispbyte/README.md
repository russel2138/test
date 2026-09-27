# Wispbyte NRO target

Designed for the Wispbyte free Java server tested with:

- amd64 / x86_64
- Java 17
- cgroup RAM limit ~589 MiB
- CPU quota 35%
- one allocated TCP port via `SERVER_PORT`

This target intentionally has **no internal watchdogs and no restart loop**.

## Why the runtime is prebuilt

Wispbyte stopped the free server while `apt/dpkg` was preparing TigerVNC, even though the reported average CPU was only about 18%.

To avoid that startup spike, GitHub Actions builds the Ubuntu 24.04 amd64 runtime and publishes it at:

```text
https://github.com/russel2138/test/releases/tag/wispbyte-runtime-v1
```

Wispbyte only downloads and extracts the finished runtime. It does not run `apt` or `dpkg`.

## Game file

Upload the NRO client as:

```text
/home/container/games/NRO_NEW.jar
```

JAR files remain outside GitHub.

## Run from an interactive Bash console

```bash
curl -fsSL https://raw.githubusercontent.com/russel2138/test/main/wispbyte/start.sh -o /tmp/wispbyte-start.sh && bash /tmp/wispbyte-start.sh
```

On first run the script downloads the prebuilt runtime into:

```text
/home/container/nro-runtime
```

Later runs reuse it.

## VNC

TigerVNC binds directly to Wispbyte's `SERVER_PORT`. The Console prints:

```text
VNC port: ...
VNC pass: ...
Watchdog: OFF
```

Connect with a VNC client using the public Wispbyte allocation plus that port.

## State

Game RMS/settings are intentionally disposable:

```text
/tmp/nro-wispbyte/home/.microemulator
```

Every start removes and recreates this session directory.

## Resource defaults

```text
JAVA_XMS=16m
JAVA_XMX=160m
VNC_GEOMETRY=640x480
```

Override them with environment variables if needed.
