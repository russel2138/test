# NRO + MicroEmulator on Blitz

App URL:

```text
https://nro.pyoska.blitz.cloud
```

Startup command remains:

```text
/app/start.sh
```

## Lightweight runtime

The Blitz target now runs each component directly with no supervisor/watchdog loop:

```text
display  -> Xvfb 320x240x16
game     -> Java 17 + MicroEmulator 2.0.4
vnc      -> x11vnc
web      -> noVNC/websockify
```

Defaults:

```text
JAVA_XMS=8m
JAVA_XMX=128m
Watchdog=OFF
Automatic restart=OFF
```

If a component exits, it stays down until restarted manually.

## Persistent data

Game JAR:

```text
/data/game.jar
```

RMS/login state:

```text
/data/microemu-home/.microemulator
```

If `/data/game.jar` is missing, the app URL opens the upload page. After a valid J2ME JAR is uploaded, the game is started once and the web endpoint switches to noVNC.

## Controls

```bash
/app/nroctl status
/app/nroctl start all
/app/nroctl stop all
/app/nroctl restart all

/app/nroctl restart game
/app/nroctl restart remote

/app/nroctl log game
/app/nroctl log web
```

`remote` means `vnc + web`.

The VNC/upload password is persisted in:

```text
/data/vnc-password.txt
```
