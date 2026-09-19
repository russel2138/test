# NRO + MicroEmulator on Blitz

App URL:

```
https://nro.pyoska.blitz.cloud
```

No Cloudflare tunnel is used.

## Persistent game and login state

The game JAR is **not stored in Git**.

Runtime JAR:

```
/data/game.jar
```

RMS/login state:

```
/data/microemu-home/.microemulator
```

If `/data/game.jar` already exists, it is used as-is and is never overwritten by deploys.

If it is missing, the app URL temporarily shows a password-protected upload page. Upload a valid J2ME JAR there; it is saved atomically as `/data/game.jar`. The game supervisor then starts it automatically and the same URL switches back to noVNC.

## Runtime

```
Blitz address
  -> noVNC/websockify
  -> x11vnc
  -> Xvfb
  -> MicroEmulator + /data/game.jar
```

Components are independent:

```
display  -> Xvfb
game     -> Java + MicroEmulator
vnc      -> x11vnc
web      -> uploader when JAR is missing, otherwise noVNC/websockify
```

Useful commands:

```bash
/app/nroctl status
/app/nroctl log game
/app/nroctl log web
/app/nroctl restart game
```

VNC/upload password is persisted in `/data/vnc-password.txt`, or can be supplied with `VNC_PASSWORD`.
