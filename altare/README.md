# Altare Java ME runtime (canonical setup source)

This directory owns the **Java ME / JAR setup implementation** for the Altare Python Hosting launcher.

- Source: `altare/jar_setup.py` in `russel2138/test`
- Compatibility entrypoint: `altare/jar_setup.py` in `russel2138/tgll` fetches this installer when `setup jar` is run
- Run inside the existing Altare Python launcher, with `native_setup.py`, `jar_tigervnc.py`, the existing game files and the existing `.tgll-runtime` directory in place
- Use the console commands `stop`, `update`, `setup jar`, `logs 80`, `start`
- The source move **does not reinstall or delete game files, RMS, VNC credentials/port, TGLL or Wine**
- Java ME game runtime remains **TigerVNC-only**; do not add an x11vnc fallback to `jar_run.py`

This installer is not a standalone VPS bootstrap script. It depends on the Altare launcher environment. The `setup jar` compatibility entrypoint resolves an immutable commit from this repository where possible and downloads the installer on demand.
