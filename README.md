# NRO + MicroEmulator lightweight runtime

This image is optimized for tiny always-on container hosts such as Blitz Cloud.

## Runtime

The stack intentionally avoids a desktop environment and Xpra:

- **Xvfb**: virtual X display required by MicroEmulator/AWT.
- **MicroEmulator 2.0.4 + Java 17**: runs `/data/game.jar`.
- **x11vnc**: optional VNC access.
- **noVNC/websockify**: optional browser bridge.
- **cloudflared Quick Tunnel**: optional public URL for background-worker hosts.

The game only needs **Xvfb**. VNC, browser access and the tunnel can all stop without stopping the game.

## Independent components

Every component has its own supervisor and PID files:

```
display  -> Xvfb
game     -> Java + MicroEmulator
vnc      -> x11vnc
web      -> websockify + noVNC
tunnel   -> cloudflared
```

Use:

```bash
/app/nroctl status
/app/nroctl start game
/app/nroctl stop game
/app/nroctl restart game
/app/nroctl log game

/app/nroctl stop remote
/app/nroctl start remote
```

`remote` means only `vnc + web + tunnel`. Stopping it does **not** stop the game.

## Persistent files

Keep `/data` persistent.

Required:

```
/data/game.jar
```

Game/RMS state stays in:

```
/data/microemu-home/.microemulator
```

Remote-access files, when enabled:

```
/data/vnc-password.txt
/data/vnc.pass
/data/tunnel-url.txt
```

If `/data/game.jar` is missing, the web component temporarily serves a one-time upload page on the same remote URL. After a valid J2ME JAR is uploaded, it is saved as `/data/game.jar`; the uploader exits and the same port switches to noVNC.

## Defaults

```
DISPLAY=:99
JAVA_XMX=160m
NOVNC_PORT=8080
VNC_PORT=5900
REMOTE_ENABLED=1
TUNNEL_ENABLED=1
```

For the lightest steady-state after the account is already logged in:

```bash
/app/nroctl stop remote
```

or deploy with:

```
REMOTE_ENABLED=0
```

The Java game and its persistent RMS state keep running.

## Blitz Cloud

For background-worker mode, leave `REMOTE_ENABLED=1` and `TUNNEL_ENABLED=1` when you need browser access.

Check logs or:

```bash
/app/nroctl status
```

for:

```
remote   : https://....trycloudflare.com
vnc pass : ...
```

Open the URL and use the VNC password shown by `nroctl status`.

After finishing interaction, `/app/nroctl stop remote` removes the unnecessary remote-access processes while leaving the game online.
