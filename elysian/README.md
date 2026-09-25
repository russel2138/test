# ElysianNodes NRO runtime

Elysian keeps the heavy runtime files on the server and manages only the controller from GitHub.

## Server layout

```text
~/
├── nroctl.sh              # tiny GitHub launcher
├── game.jar               # legacy game, optional
├── games/                 # new game JARs
├── microemu/              # legacy/stock MicroEmulator runtime
├── emulators/             # custom MicroEmulator-compatible JARs
├── vnc/                   # existing portable TigerVNC runtime
├── .vnc/passwd
├── microemu-home/         # legacy stock + game.jar RMS/state
├── nro-data/
│   ├── current-selection.env
│   ├── logs/
│   └── profiles/
└── .nro-elysian-src/      # cached controller downloaded from GitHub
```

The launcher downloads the latest `main/elysian/nroctl.sh` on every command. If GitHub is temporarily unreachable, it falls back to the last cached controller.

## One-time migration

Stop the existing stack first, then install the launcher:

```bash
./nroctl.sh stop
curl -fsSL https://raw.githubusercontent.com/russel2138/test/main/elysian/install.sh | bash
```

The installer backs up the old `~/nroctl.sh` before replacing it.

## Normal commands

```bash
~/nroctl.sh list
~/nroctl.sh start
~/nroctl.sh start MICRO_NST AUTO50_X1
~/nroctl.sh restart MICRO_NST AUTO50_X1
~/nroctl.sh stop
~/nroctl.sh status
~/nroctl.sh log
```

The selected emulator/game pair is remembered in `~/nro-data/current-selection.env`.

## State reset

Reset only the currently selected pair:

```bash
~/nroctl.sh reset-state
```

Or reset a specific pair:

```bash
~/nroctl.sh reset-state MICRO_NST AUTO50_X1
```

`reset-state` stops the stack first and deletes only the selected pair's `.microemulator` state. It refuses paths outside the known legacy/profile locations. It does not delete game JARs, emulator JARs, VNC files, logs, or other profiles.

After reset:

```bash
~/nroctl.sh start
```

For the old `stock + game.jar` pair, state remains at `~/microemu-home/.microemulator` for backward compatibility until explicitly reset.
