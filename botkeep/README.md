# HERO Emulator V2 on Botkeep (experimental)

Separate runtime for the user-supplied HERO-Emulator-V2.jar (Main-Class: loader.Bootstrap). This is NOT the repo's original NRO game or the Altare nroemu profile. Reuses raven/bootstrap-runtime.sh for rootless TigerVNC; skips downloading MicroEmulator. Existing Raven/Blitz/Wispbyte behavior is unchanged.

**Not yet live-tested on Botkeep.** Botkeep supports Java applications but does not promise raw inbound TCP, OS packages, X11, compatible distro, or unlimited resources. The current Free v2 resource pool is 512 MiB RAM / 0.5 vCore / 1 GiB storage. Verify host policy and game rules; do not bypass resource or network restrictions.

## GitHub deployment

- Import repository russel2138/test, branch botkeep/hero-v2, root directory, Java runtime.
- Upload HERO-Emulator-V2.jar from your original HERO-Emulator-V2.zip to Botkeep Files in your HOME directory; alternatively upload the ZIP if unzip is installed. The binary is deliberately **not** committed to public GitHub.
- Set startup command to: **bash botkeep/start.sh**. One-off preflight: **bash botkeep/start.sh --check**.
- Set Environment secret VNC_PASSWORD (at least 8 characters; classic VNC only uses the first 8) if you want a consistent password. Otherwise one is generated and kept in hero-data/vnc-password.txt, mode 0600.
- Default VNC is **localhost-only on 5901**, no public tunnel. Only if Botkeep allocates a **raw TCP** port for this app, set HERO_VNC_PUBLIC=1 and use Botkeep's SERVER_PORT. HTTP/HTTPS Domains do not by themselves expose raw VNC. VNC password auth does not encrypt traffic.
- Logs in hero-data/hero.log and hero-data/vnc.log; persistent state in hero-data/home. Back this directory up before reinstall/redeploy.

Default Java heap is -Xms32m -Xmx192m (adjust with HERO_XMS_MB and HERO_XMX_MB); display is 800x600 at :92 (HERO_GEOMETRY, HERO_DISPLAY). The Windows BAT is unused. Do not assume the 512 MiB plan can sustain Java GUI + TigerVNC; inspect cgroup memory and logs for OOM.

Requirements: Linux x86_64, Bash, Java 17+ or network access to portable JRE, and Raven's rootless TigerVNC prerequisites (Debian bookworm/trixie or Ubuntu focal/jammy/noble with apt-get/dpkg-deb; no sudo). If the Botkeep image lacks these, this target may fail and you need a supported image. It does not auto-restart, install Wine, run a tunnel, change game saves, or bypass restrictions.

The source JAR contains an encrypted payload. Static manifest checks alone cannot verify its game UI, actual farming behavior, or compatibility; test in the real Botkeep console/VNC.

See Botkeep documentation: https://botkeep.cloud/docs/hosting
