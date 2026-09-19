# NRO Dragonboy + MicroEmulator + Xpra + Cloudflare Quick Tunnel

This repo runs the uploaded J2ME NRO JAR with **MicroEmulator** instead of FreeJ2ME.

Architecture:

```
Blitz background worker
  -> MicroEmulator + Dragonboy JAR
  -> Xpra HTML5 on 127.0.0.1:8080
  -> cloudflared Quick Tunnel
  -> https://random.trycloudflare.com
  -> browser
```

## Emulator

The image builds the modernized `lolo-san/microemu-minimal` fork at pinned commit:

```
31efc58943c355d30b5d89574b9cc1adb76ae747
```

Its README supports launching a MIDlet with:

```
java -jar microemulator-3.0.0-SNAPSHOT-jar-with-dependencies.jar <midlet.jar>
```

The runtime here uses Java 17 with desktop/AWT/X11 libraries and launches `/data/game.jar`.

## Blitz flow

1. Keep `XPRA_PASSWORD` in Environment.
2. Keep `/data` persistent.
3. Switch the app to **Run it in the background**.
4. Open Logs and find:

   ```
   NRO_REMOTE_URL=https://....trycloudflare.com
   ```

5. First run only: open the URL, upload your local NRO `.jar` with `XPRA_PASSWORD`.
6. Refresh the same URL after upload.
7. Xpra HTML5 should show the MicroEmulator window.
8. Closing the browser does not stop the background worker.

## Persistent data

Stored under `/data`:

- `game.jar`
- Xpra password
- latest tunnel URL
- any emulator/game data written to the working directory

## Notes

- Quick Tunnel URL can change after restart.
- Xpra binds only to localhost.
- No VNC/noVNC stack is used.
