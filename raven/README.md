# Raven Host runtime

Raven keeps its default Java startup command and launches `sneakyhub.jar` from `/home/container`.
The launcher clones/pulls this repository on every server start, then runs `raven/start-raven.sh`.

Only the game JAR is kept outside Git and must be uploaded manually:

```text
/home/container/game.jar
```

Persistent runtime/state is stored under:

```text
/home/container/nro-data/
```

So Git updates do not overwrite login/RMS state.

Expected Raven root:

```text
/home/container/
├── sneakyhub.jar
├── game.jar
├── .nro-raven-src/   # auto-cloned by launcher
└── nro-data/         # auto-created, persistent
```

The launcher repository is `russel2138/test`, branch `main`.
