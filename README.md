# NRO Dragonboy + FreeJ2ME + Xpra HTML5

Run one NRO J2ME account in a long-running Linux container while keeping a browser UI available for occasional control.

## Why `game.jar` is not in this public repository

Blitz currently builds public GitHub repositories. To avoid publishing the game JAR in GitHub, the container provides a small password-protected upload page on the **first** start. Upload your local `Dragonboy250 v4.0.jar` there. It is saved as `/data/game.jar`, and `/data` is declared as a persistent volume.

After the upload completes, the same HTTPS URL switches to Xpra HTML5 and shows the FreeJ2ME game window. Closing the browser does **not** stop the container or game.

## Deploy on blitz.cloud

1. In blitz.cloud choose **Host something new** -> **My own code**.
2. Paste this public GitHub repository URL.
3. Deploy it. The Dockerfile exposes port `8080` and runs as uid/gid `1000`.
4. Ensure `/data` is listed as a kept/persistent folder (the Dockerfile declares `VOLUME ["/data"]`, so Blitz should detect it).
5. Recommended: add an encrypted environment variable `XPRA_PASSWORD` with a strong password. If omitted, the container generates one and prints it in the app logs.
6. Open the app HTTPS URL. On the first run you will see **NRO first setup** instead of Xpra.
7. Enter the Xpra password and upload your local game `.jar`.
8. Wait 10-20 seconds and refresh the URL. Xpra HTML5 should appear. Enter the same password and connect.
9. Configure/login the game. You can close the browser afterwards; the container keeps running.

## Useful environment variables

- `XPRA_PASSWORD`: browser UI and first-upload password. Recommended.
- `GAME_WIDTH`: default `320`.
- `GAME_HEIGHT`: default `240`.
- `GAME_SCALE`: default `2`.
- `JAVA_XMX`: default `128m`, kept conservative for a 512 MB ceiling.
- `PORT`: default `8080`.

## Persistence

Everything stateful is placed under `/data`:

- `/data/game.jar`
- `/data/xpra-password`
- FreeJ2ME save/config files created from `/data` as the working directory

Blitz persistent folders survive app restarts, but are not backups. Deleting the app deletes its kept files.

## Local test

```bash
docker build --platform linux/amd64 -t nro-freej2me .
docker run --rm --platform linux/amd64 --user 1000:1000 --cap-drop ALL \
  --security-opt no-new-privileges \
  -p 8080:8080 \
  -e XPRA_PASSWORD='replace-this' \
  -v nro-data:/data \
  nro-freej2me
```

Open `http://localhost:8080`, upload the JAR once, wait, then refresh for Xpra.

## Notes

- FreeJ2ME is built from pinned commit `fae9304b85ac1c61d0117f6c8efe528612388278`.
- The container uses Xpra HTML5 directly; no VNC/noVNC stack.
- Xpra authentication uses the `env` module and `XPRA_PASSWORD`.
- If memory is tight, lower `JAVA_XMX` to `96m` or set `GAME_SCALE=1`.
