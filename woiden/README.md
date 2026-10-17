# Woiden Ninja School Online

Use `install.sh` on Ubuntu 22.04 x86_64, with working IPv6 DNS64/NAT64. The installer is designed for a single NSO Java ME client using MicroEmulator (Java 17), a loopback SOCKS5 NAT64 relay, and local-only VNC accessed via SSH forwarding.

Read `install.sh` before running. It installs OS packages as root and sets up optional systemd units. Do not expose port 1080 or VNC port 5901 publicly.

## Bare SSH console commands (Woiden only)

On an installed Woiden VPS, fetch `enable-console.sh` and `console-commands.sh` from GitHub and run `bash enable-console.sh`. The activation script seeds the existing GitHub root `game.jar` into `/opt/nso/game.jar` if no local game exists, creates a TigerVNC password on first use, and adds an interactive Bash sourcing hook to root's `~/.bashrc`.

In the existing SSH session, `source /opt/nso/console-commands.sh`. Future SSH logins load the commands automatically. Then type `list`, `status`, `restart stock game.jar`, `game-restart`, `stop`, `log`, `log-stop`, `game-errors`, `rms-mode`, `rms-reset`, `vnc`, or `help` directly, without `nsoctl`. No change is made to the Raven startup scripts or any other host.

The shell commands select local SOCKS5 NAT64 `127.0.0.1:1080` automatically when `start`, `restart`, or `game-restart` is invoked without an explicit proxy. Passing `direct` disables SOCKS5 per launch. The game only starts when the user issues a command; the installer does not enable the game service at boot. VNC listens on `127.0.0.1:5901` and requires an SSH tunnel from a client such as macOS.
