FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    DISPLAY=:99 \
    NOVNC_PORT=8080 \
    VNC_PORT=5900 \
    JAVA_XMX=160m

# Lightweight runtime:
# - Xvfb: virtual X display required by MicroEmulator/AWT
# - x11vnc: VNC server
# - noVNC + websockify: browser access through Blitz's own app address
# - Java 17: MicroEmulator runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget unzip \
      openjdk-17-jre \
      xvfb x11vnc websockify \
      fonts-dejavu-core fontconfig \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O /tmp/microemulator.zip \
      "https://sourceforge.net/projects/microemulator/files/microemulator/2.0.4/microemulator-2.0.4.zip/download" \
    && test "$(stat -c%s /tmp/microemulator.zip)" -gt 1500000 \
    && unzip -q /tmp/microemulator.zip -d /opt \
    && mkdir -p /app \
    && mv /opt/microemulator-2.0.4 /app/microemu \
    && rm -f /tmp/microemulator.zip

# noVNC is static HTML/JS.
RUN wget -qO /tmp/novnc.tar.gz \
      https://github.com/novnc/noVNC/archive/refs/tags/v1.7.0.tar.gz \
    && tar -xzf /tmp/novnc.tar.gz -C /opt \
    && mv /opt/noVNC-1.7.0 /usr/share/novnc \
    && rm -rf /usr/share/novnc/docs /usr/share/novnc/tests /usr/share/novnc/.github \
    && rm -f /usr/share/novnc/index.html \
    && rm -f /tmp/novnc.tar.gz

COPY novnc-index.html /usr/share/novnc/index.html

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
COPY --chown=1000:1000 upload.py /app/upload.py
COPY --chown=1000:1000 nroctl /app/nroctl
COPY --chown=1000:1000 start.sh /app/start.sh
RUN chmod +x /app/*.sh /app/nroctl /app/upload.py

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]
EXPOSE 8080

CMD ["/app/start.sh"]
