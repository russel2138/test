# Woiden Ninja School Online

Use `install.sh` on Ubuntu 22.04 x86_64, with working IPv6 DNS64/NAT64. The installer is designed for a single NSO Java ME client using MicroEmulator (Java 17), a loopback SOCKS5 NAT64 relay, and local-only VNC accessed via SSH forwarding.

Read `install.sh` before running. It installs OS packages as root and sets up optional systemd units. Do not expose port 1080 or VNC port 5901 publicly.
