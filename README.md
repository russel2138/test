# NRO Dragonboy + FreeJ2ME + Xpra + Cloudflare Quick Tunnel

This repository is designed for **Blitz background-worker mode**:

```
Blitz background worker (never sleeps)
  -> FreeJ2ME / Dragonboy
  -> Xpra HTML5 on 127.0.0.1:8080
  -> cloudflared outbound Quick Tunnel
  -> https://random.trycloudflare.com
  -> browser
```

Blitz background workers have no Blitz address/port and do not sleep. The container therefore uses an outbound Cloudflare Quick Tunnel to make Xpra reachable in a browser.

## Deploy on Blitz

1. Deploy this repo normally and keep `XPRA_PASSWORD` set in Environment.
2. After a successful build, go to **Settings -> Run it in the background -> Switch**.
3. Open the Blitz **Logs** tab.
4. Wait for a line like:

   ```
   NRO_REMOTE_URL=https://random-words.trycloudflare.com
   ```

5. Open that URL.
6. First run only: the URL shows **NRO first setup**. Enter the same `XPRA_PASSWORD`, select your local `Dragonboy250 v4.0.jar`, and upload it.
7. Wait about 10-20 seconds and refresh the **same trycloudflare URL**. Xpra HTML5 should appear.
8. Enter `XPRA_PASSWORD` again, open the FreeJ2ME window, login/configure NRO, then close the browser whenever you want. The background worker keeps running.

## Important behavior

- The Blitz app itself should be switched to **background mode**. That UI setting cannot be encoded in the Dockerfile.
- `cloudflared` is started automatically by `start.sh`.
- The Quick Tunnel URL is printed in Logs as `NRO_REMOTE_URL=...`.
- The latest URL is also written to `/data/tunnel-url.txt`.
- A Quick Tunnel gets a **new random URL after a container/cloudflared restart**. Check Logs again after a restart.
- Quick Tunnels are a Cloudflare development/testing feature, not an SLA-backed production endpoint.
- Xpra is password-protected with `XPRA_PASSWORD`.
- Xpra binds only to `127.0.0.1`; cloudflared is the only public path.

## Persistence

State is under `/data`:

- `/data/game.jar`
- `/data/xpra-password`
- `/data/tunnel-url.txt`
- FreeJ2ME save/config files

The Dockerfile declares `VOLUME ["/data"]`. Make sure Blitz keeps this folder if its UI exposes the kept-folder setting.

## Environment variables

- `XPRA_PASSWORD`: recommended; used for both initial JAR upload and Xpra login.
- `GAME_WIDTH`: default `320`.
- `GAME_HEIGHT`: default `240`.
- `GAME_SCALE`: default `2`.
- `JAVA_XMX`: default `128m`.
- `PORT`: default `8080`.

## Local test

```bash
docker build --platform linux/amd64 -t nro-freej2me .
docker run --rm --platform linux/amd64 \
  -e XPRA_PASSWORD='replace-this' \
  -v nro-data:/data \
  nro-freej2me
```

The container will print a `trycloudflare.com` URL. Use that URL instead of exposing a local Docker port.

## Notes

- FreeJ2ME is pinned to commit `fae9304b85ac1c61d0117f6c8efe528612388278`.
- No VNC/noVNC stack is used.
- Closing the browser does not stop FreeJ2ME or the game.
