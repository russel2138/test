FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    PORT=8080 \
    GAME_WIDTH=320 \
    GAME_HEIGHT=240 \
    GAME_SCALE=2 \
    JAVA_XMX=128m \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Base tools + a full Java 17 desktop runtime. FreeJ2ME uses AWT/X11, so we
# intentionally install the non-headless JDK plus the common X11 runtime libs.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget git ant openssl python3 \
      openjdk-17-jdk xvfb xauth \
      fonts-dejavu-core fontconfig \
      libxext6 libxrender1 libxtst6 libxi6 libxrandr2 libfreetype6 libgtk-3-0 \
    && test -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java \
    && /usr/lib/jvm/java-17-openjdk-amd64/bin/java -version \
    && rm -rf /var/lib/apt/lists/*

# Xpra packages for Ubuntu 24.04.
# xpra-x11 is required for seamless X11 mode and xpra-html5 provides the
# built-in browser client under /usr/share/xpra/www.
RUN wget -qO /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
    && wget -qO /etc/apt/sources.list.d/xpra.sources \
       https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/noble/xpra.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends xpra xpra-x11 xpra-html5 \
    && test -d /usr/share/xpra/www \
    && rm -rf /var/lib/apt/lists/*

# cloudflared provides an outbound Quick Tunnel so the app can run in Blitz
# background-worker mode (never sleeps) while Xpra remains reachable in a browser.
RUN wget -qO /usr/local/bin/cloudflared \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod 0755 /usr/local/bin/cloudflared \
    && /usr/local/bin/cloudflared --version

# Pin FreeJ2ME to a known commit and build the standalone AWT JAR.
ARG FREEJ2ME_COMMIT=fae9304b85ac1c61d0117f6c8efe528612388278
RUN git clone https://github.com/hex007/freej2me.git /tmp/freej2me \
    && cd /tmp/freej2me \
    && git checkout "$FREEJ2ME_COMMIT" \
    && ant \
    && mkdir -p /app \
    && cp build/freej2me.jar /app/freej2me.jar \
    && rm -rf /tmp/freej2me

# Ubuntu 24.04 may already have uid/gid 1000 (usually the ubuntu account).
# Reuse that numeric uid/gid when present instead of failing on groupadd/useradd.
RUN set -eux; \
    if ! getent group 1000 >/dev/null; then groupadd -g 1000 app; fi; \
    if ! getent passwd 1000 >/dev/null; then useradd -m -u 1000 -g 1000 -s /bin/bash app; fi; \
    mkdir -p /app /data /home/app/.xpra; \
    chown -R 1000:1000 /app /data /home/app

COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 run-tunnel.sh /app/run-tunnel.sh
COPY --chown=1000:1000 start.sh /app/start.sh
COPY --chown=1000:1000 upload.py /app/upload.py
RUN chmod +x /app/run-game.sh /app/run-tunnel.sh /app/start.sh /app/upload.py

USER 1000:1000
WORKDIR /data

VOLUME ["/data"]

EXPOSE 8080

CMD ["/app/start.sh"]
