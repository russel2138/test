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

# Static noVNC files only. Lite UI autoconnects immediately.
RUN wget -q -O /tmp/novnc.tar.gz \
      "https://github.com/novnc/noVNC/archive/refs/tags/${NOVNC_VERSION}.tar.gz" \
    && mkdir -p /opt/novnc \
    && tar -xzf /tmp/novnc.tar.gz --strip-components=1 -C /opt/novnc \
    && cp /opt/novnc/vnc_lite.html /opt/novnc/index.html

RUN wget -q -O /opt/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${TARGETARCH}" \
    && chmod +x /opt/cloudflared

# Native Go websockify from noVNC's alternate implementations.
# Pinned commit keeps builds reproducible.
FROM debian:bookworm-slim AS wsproxy

ARG WEBSOCKIFY_GO_COMMIT=4bdeb8a624c62ec59804d11eef4e0019b6e7692f

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget golang-go \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN wget -q -O websockify.go \
      "https://raw.githubusercontent.com/novnc/websockify-other/${WEBSOCKIFY_GO_COMMIT}/golang/websockify.go" \
    && printf '%s\n' \
      'module websockify' \
      '' \
      'go 1.19' \
      '' \
      'require github.com/gorilla/websocket v1.4.2' > go.mod \
    && printf '%s\n' \
      'github.com/gorilla/websocket v1.4.2 h1:+/TMaTYc4QFitKJxsQ7Yye35DkWvkdLcvGKqM+x0Ufc=' \
      'github.com/gorilla/websocket v1.4.2/go.mod h1:YR8l580nyteQvAITg2hZ9XVh4b55+EU/adAjf1fMHhE=' > go.sum \
    && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /websockify-go websockify.go

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    DISPLAY=:99 \
    VNC_PORT=5900 \
    WEB_PORT=8080 \
    JAVA_XMX=192m

# Minimal runtime: Java + Xvnc. WebSocket/static proxy and cloudflared are native binaries.
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
COPY --from=assets --chown=1000:1000 /opt/novnc /app/novnc
COPY --from=assets --chown=1000:1000 /opt/cloudflared /app/cloudflared
COPY --from=wsproxy --chown=1000:1000 /websockify-go /app/websockify-go
COPY --chown=1000:1000 game.jar /app/game.jar
COPY --chown=1000:1000 run-display.sh /app/run-display.sh
COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 run-web.sh /app/run-web.sh
COPY --chown=1000:1000 run-tunnel.sh /app/run-tunnel.sh
COPY --chown=1000:1000 start.sh /app/start.sh

RUN chmod +x /app/*.sh /app/cloudflared /app/websockify-go \
    && test -s /app/game.jar \
    && unzip -p /app/game.jar META-INF/MANIFEST.MF | grep -q '^MIDlet-1:' \
    && test -s /app/novnc/index.html

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]

CMD ["/app/start.sh"]
