# ModVC NRO (no internal watchdog)

This target runs NRO in MicroEmulator behind Xvfb + x11vnc + noVNC.

There is **no game watchdog, render-loop watchdog, stall watchdog, or restart loop** in this target. If Java exits, `start.sh` exits as well. Any restart performed by ModVC itself is outside this script.

## ModVC setup

1. Connect the GitHub repository `russel2138/test`.
2. Select the Java runtime.
3. Turn **AI Auto-Detect OFF**.
4. Set **Start Command** to:

```bash
bash modvc/start.sh
```

5. Upload the NRO game JAR with ModVC File Manager to:

```text
games/NRO_NEW.jar
```

6. Start the instance.
7. In Console, look for:

```text
[NRO] VNC pass: ...
[NRO] watchdog:  OFF
```

8. Open the ModVC public app URL. The root page is noVNC. Use the password printed in Console.

You can set a stable VNC password with the ModVC environment variable `VNC_PASSWORD`.

## State

MicroEmulator state is stored at:

```text
.nro-data/home/.microemulator/
```

To wipe the NRO login/settings/state, stop the instance first and then run:

```bash
bash modvc/reset-state.sh
```

Then start the instance again.

## Optional environment variables

```text
NRO_GAME=/app/games/NRO_NEW.jar
JAVA_XMS=16m
JAVA_XMX=160m
VNC_PASSWORD=your-password
PORT=<provided by ModVC>
```

The default game is `games/NRO_NEW.jar`.
