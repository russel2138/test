FROM debian:bookworm-slim AS microemu

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget unzip \
    && wget -O /tmp/microemulator.zip \
      "https://sourceforge.net/projects/microemulator/files/microemulator/2.0.4/microemulator-2.0.4.zip/download" \
    && test "$(stat -c%s /tmp/microemulator.zip)" -gt 1500000 \
    && unzip -q /tmp/microemulator.zip -d /opt \
    && mv /opt/microemulator-2.0.4 /opt/microemu

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    DISPLAY=:99 \
    JAVA_XMX=128m

# Background-only Blitz runtime:
# Java + Xvfb + MicroEmulator. No VNC, no noVNC, no web server,
# no supervisor/watchdog and no automatic restart loop.
RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jre \
      xvfb \
      unzip \
      fonts-dejavu-core fontconfig \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    groupadd -g 1000 app; \
    useradd -m -u 1000 -g 1000 -s /bin/bash app; \
    mkdir -p /app /data /run/nro /home/app; \
    chown -R 1000:1000 /app /data /run/nro /home/app

COPY --from=microemu --chown=1000:1000 /opt/microemu /app/microemu
COPY --chown=1000:1000 game.jar /app/game.jar
COPY --chown=1000:1000 run-display.sh /app/run-display.sh
COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 nroctl /app/nroctl
COPY --chown=1000:1000 start.sh /app/start.sh

RUN chmod +x /app/*.sh /app/nroctl \
    && test -s /app/game.jar \
    && unzip -p /app/game.jar META-INF/MANIFEST.MF | grep -q '^MIDlet-1:'

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]

CMD ["/app/start.sh"]
