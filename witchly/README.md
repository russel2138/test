# Witchly NRO target

Witchly free tier currently provides enough headroom for the existing NRO stack (2 GB RAM / 100% CPU according to Witchly's free-tier docs).

This target keeps the same lightweight setup:

- Java 17
- MicroEmulator 2.0.4
- TigerVNC
- `JAVA_XMS=16m`
- `JAVA_XMX=160m`
- no watchdog
- no internal restart loop
- persistent RMS/state under `~/nro-data`

## Game file

Upload:

```text
/home/container/games/NRO_NEW.jar
```

## Startup / Console command

```bash
curl -fsSL https://raw.githubusercontent.com/russel2138/test/main/witchly/start.sh -o /tmp/witchly-start.sh && bash /tmp/witchly-start.sh
```

The first run downloads a prebuilt Ubuntu 20.04 amd64-compatible MicroEmulator + TigerVNC bundle from GitHub Releases. Later starts reuse `/home/container/nro-runtime`.

## Port

The script tries, in order:

1. `VNC_PORT`
2. `SERVER_PORT`
3. `PORT`

If Witchly exposes none of these environment variables, set `VNC_PORT` to the port shown on the server Overview/Network page.

## VNC

The Console prints:

```text
VNC port: ...
VNC pass: ...
Watchdog: OFF
```

Connect your VNC viewer to the Witchly public IP/hostname and that port.

## Persistent state

```text
/home/container/nro-data/profiles/NRO_NEW/stock/.microemulator
```

The state is not deleted on restart.
