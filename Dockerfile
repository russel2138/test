FROM debian:bookworm-slim AS assets

ARG NOVNC_VERSION=v1.7.0
ARG CLOUDFLARED_VERSION=2026.9.3
ARG TARGETARCH=amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget unzip tar gzip \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/microemulator.zip \
      "https://sourceforge.net/projects/microemulator/files/microemulator/2.0.4/microemulator-2.0.4.zip/download" \
    && test "$(stat -c%s /tmp/microemulator.zip)" -gt 1500000 \
    && unzip -q /tmp/microemulator.zip -d /opt \
    && mv /opt/microemulator-2.0.4 /opt/microemu

RUN wget -q -O /tmp/novnc.tar.gz \
      "https://github.com/novnc/noVNC/archive/refs/tags/${NOVNC_VERSION}.tar.gz" \
    && mkdir -p /opt/novnc \
    && tar -xzf /tmp/novnc.tar.gz --strip-components=1 -C /opt/novnc \
    && cp /opt/novnc/vnc_lite.html /opt/novnc/index.html \
    && sed -i "s/readQueryVariable('scale', false)/readQueryVariable('scale', true)/" /opt/novnc/index.html

# Single static Go binary used only for the outbound Quick Tunnel.
RUN wget -q -O /opt/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${TARGETARCH}" \
    && chmod +x /opt/cloudflared

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    DISPLAY=:99 \
    VNC_PORT=5900 \
    WEB_PORT=8080 \
    JAVA_XMX=128m

# Background-worker runtime:
# Java + TigerVNC Xvnc + websockify. noVNC is static; cloudflared is one binary.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      openjdk-17-jre \
      tigervnc-standalone-server \
      websockify \
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
COPY --from=assets --chown=1000:1000 /opt/novnc /app/novnc
COPY --from=assets --chown=1000:1000 /opt/cloudflared /app/cloudflared
COPY --chown=1000:1000 game.jar /app/game.jar
COPY --chown=1000:1000 run-display.sh /app/run-display.sh
COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 run-web.sh /app/run-web.sh
COPY --chown=1000:1000 run-tunnel.sh /app/run-tunnel.sh
COPY --chown=1000:1000 start.sh /app/start.sh

RUN chmod +x /app/*.sh /app/cloudflared \
    && test -s /app/game.jar \
    && unzip -p /app/game.jar META-INF/MANIFEST.MF | grep -q '^MIDlet-1:' \
    && test -s /app/novnc/index.html

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]

CMD ["/app/start.sh"]
