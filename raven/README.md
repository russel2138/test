# Raven Host runtime

Raven keeps its default Java startup command and launches `sneakyhub.jar` from `/home/container`.
The launcher clones/pulls this repository on every server start, then runs `raven/start-raven.sh`.

The runtime stays backward-compatible with the original setup:

```text
/home/container/game.jar
```

with the stock MicroEmulator and the existing RMS/login state under:

```text
/home/container/nro-data/microemu-home/
```

## Multiple emulator/game JARs

Upload your own JARs outside Git:

```text
/home/container/
|-- sneakyhub.jar
|-- game.jar                  # optional legacy/default game
|-- games/
|   |-- AUTO50_X1.jar
|   `-- another-game.jar
|-- emulators/
|   |-- MICRO_NST.jar
|   `-- another-emulator.jar
|-- .nro-raven-src/          # auto-cloned by launcher
`-- nro-data/                # persistent runtime/state
```

Uploaded emulator JARs must be MicroEmulator-compatible (`org.microemu.app.Main`).
The game MIDlet class is detected automatically from `META-INF/MANIFEST.MF`.

Each non-legacy emulator/game pair gets its own persistent state:

```text
/home/container/nro-data/profiles/<game>/<emulator>/.microemulator/
```

The selected pair is remembered in:

```text
/home/container/nro-data/current-selection.env
```

## Raven console

The Raven panel console is stdin for `start-raven.sh`; it is not a shell.

Commands:

```text
list
status
restart MICRO_NST AUTO50_X1
restart
start
stop
game-restart
loop-check
log
log-stop
vnc
help
```

`restart <emulator> <game>` switches to that pair and remembers it.
`restart` without arguments restarts the current pair.

`stop` intentionally pauses the stack watchdog until `start`, `restart`, or a full Raven server restart.

The launcher repository is `russel2138/test`, branch `main`.
