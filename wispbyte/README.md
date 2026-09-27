# Wispbyte NRO target

Designed for the Wispbyte free Java server tested with:

- amd64 / x86_64
- Java 17
- cgroup RAM limit ~589 MiB
- CPU quota 35%
- one allocated TCP port via `SERVER_PORT`

This target intentionally has **no internal watchdogs and no restart loop**.

## Files

Upload the NRO client with Wispbyte File Manager:

```text
/home/container/games/NRO_NEW.jar
```

The repository ignores JAR files, so the game itself stays outside GitHub.

## Startup Command

Set Wispbyte Startup Command to:

```bash
bash -lc 'mkdir -p "$HOME/nro-data"; u="https://raw.githubusercontent.com/russel2138/test/main/wispbyte/start.sh"; t="$HOME/nro-data/wispbyte-start.sh.tmp"; if curl -fsSL "$u" -o "$t"; then mv "$t" "$HOME/nro-data/wispbyte-start.sh"; fi; exec bash "$HOME/nro-data/wispbyte-start.sh"'
```

The latest script is fetched from GitHub on every start. If the fetch fails, the cached script is used.

First boot downloads MicroEmulator and a portable TigerVNC runtime into:

```text
/home/container/nro-data/
```

## Connect

The script binds TigerVNC directly to Wispbyte's `SERVER_PORT`.

The Console prints:

```text
VNC port: ...
VNC pass: ...
Watchdog: OFF
```

Use the public allocation hostname/IP shown by Wispbyte plus that port in your VNC client.

You can set a fixed password with environment variable `VNC_PASSWORD`; VNC uses at most the first 8 characters.

## State

Per-game state:

```text
/home/container/nro-data/profiles/NRO_NEW/stock/.microemulator/
```

To wipe state, stop the NRO server, temporarily switch Startup Command to an interactive bash shell, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/russel2138/test/main/wispbyte/reset-state.sh | bash
```

Then restore the normal Startup Command and start the server.

## Resource defaults

```text
JAVA_XMS=16m
JAVA_XMX=160m
VNC_GEOMETRY=640x480
```

Override these through environment variables if needed.
