FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    DISPLAY=:99 \
    NOVNC_PORT=8080 \
    VNC_PORT=5900 \
    JAVA_XMX=160m

# Keep the runtime deliberately small:
# - Xvfb: virtual X display required by MicroEmulator/AWT
# - x11vnc: lightweight VNC bridge
# - novnc + websockify: browser access without a desktop environment
# - Java 17: MicroEmulator runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget unzip \
      openjdk-17-jre \
      xvfb x11vnc python3-minimal \
      fonts-dejavu-core fontconfig \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O /tmp/microemulator.zip \
      "https://sourceforge.net/projects/microemulator/files/microemulator/2.0.4/microemulator-2.0.4.zip/download" \
    && test "$(stat -c%s /tmp/microemulator.zip)" -gt 1500000 \
    && unzip -q /tmp/microemulator.zip -d /opt \
    && mkdir -p /app \
    && mv /opt/microemulator-2.0.4 /app/microemu \
    && rm -f /tmp/microemulator.zip

# noVNC is static HTML/JS. Install the upstream release directly instead of
# Debian's novnc package, which pulls Node.js/NumPy that are unnecessary here.
RUN wget -qO /tmp/novnc.tar.gz \
      https://github.com/novnc/noVNC/archive/refs/tags/v1.7.0.tar.gz \
    && tar -xzf /tmp/novnc.tar.gz -C /opt \
    && mv /opt/noVNC-1.7.0 /usr/share/novnc \
    && rm -rf /usr/share/novnc/docs /usr/share/novnc/tests /usr/share/novnc/.github \
    && rm -f /tmp/novnc.tar.gz

# Basic websockify only needs Python's standard library. Run upstream source
# directly so the image does not pull NumPy/JWT/Redis dependencies.
RUN wget -qO /tmp/websockify.tar.gz \
      https://github.com/novnc/websockify/archive/refs/tags/v0.13.0.tar.gz \
    && tar -xzf /tmp/websockify.tar.gz -C /opt \
    && mv /opt/websockify-0.13.0 /opt/websockify \
    && rm -rf /opt/websockify/tests /opt/websockify/.github \
    && rm -f /tmp/websockify.tar.gz

# Optional remote access for background-only hosts such as Blitz.
RUN wget -qO /usr/local/bin/cloudflared \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod 0755 /usr/local/bin/cloudflared

RUN set -eux; \
    groupadd -g 1000 app; \
    useradd -m -u 1000 -g 1000 -s /bin/bash app; \
    mkdir -p /app /data /run/nro /home/app; \
    chown -R 1000:1000 /app /data /run/nro /home/app

COPY --chown=1000:1000 supervise.sh /app/supervise.sh
COPY --chown=1000:1000 run-display.sh /app/run-display.sh
COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 run-vnc.sh /app/run-vnc.sh
COPY --chown=1000:1000 run-web.sh /app/run-web.sh
COPY --chown=1000:1000 run-tunnel.sh /app/run-tunnel.sh
COPY --chown=1000:1000 nroctl /app/nroctl
COPY --chown=1000:1000 start.sh /app/start.sh
RUN chmod +x /app/*.sh /app/nroctl

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]
EXPOSE 8080

CMD ["/app/start.sh"]
