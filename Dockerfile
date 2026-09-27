FROM debian:bookworm-slim AS assets

ARG CLOUDFLARED_VERSION=2026.9.3
ARG TARGETARCH=amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget unzip \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/microemulator.zip \
      "https://sourceforge.net/projects/microemulator/files/microemulator/2.0.4/microemulator-2.0.4.zip/download" \
    && test "$(stat -c%s /tmp/microemulator.zip)" -gt 1500000 \
    && unzip -q /tmp/microemulator.zip -d /opt \
    && mv /opt/microemulator-2.0.4 /opt/microemu

# cloudflared is a single native binary. Named Tunnel keeps the hostname fixed.
RUN wget -q -O /opt/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${TARGETARCH}" \
    && chmod +x /opt/cloudflared

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    DISPLAY=:99 \
    VNC_PORT=5900 \
    JAVA_XMX=128m

# Minimal native-VNC runtime:
# Java + TigerVNC Xvnc + cloudflared. No Xvfb, x11vnc, websockify or noVNC.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      openjdk-17-jre \
      tigervnc-standalone-server \
      unzip \
      fonts-dejavu-core fontconfig \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    groupadd -g 1000 app; \
    useradd -m -u 1000 -g 1000 -s /bin/bash app; \
    mkdir -p /app /data /home/app /tmp/.X11-unix; \
    chmod 1777 /tmp/.X11-unix; \
    chown -R 1000:1000 /app /data /home/app

COPY --from=assets --chown=1000:1000 /opt/microemu /app/microemu
COPY --from=assets --chown=1000:1000 /opt/cloudflared /app/cloudflared
COPY --chown=1000:1000 game.jar /app/game.jar
COPY --chown=1000:1000 run-display.sh /app/run-display.sh
COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 run-tunnel.sh /app/run-tunnel.sh
COPY --chown=1000:1000 start.sh /app/start.sh

RUN chmod +x /app/*.sh /app/cloudflared \
    && test -s /app/game.jar \
    && unzip -p /app/game.jar META-INF/MANIFEST.MF | grep -q '^MIDlet-1:'

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]

CMD ["/app/start.sh"]
