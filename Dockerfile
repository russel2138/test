FROM maven:3.9-eclipse-temurin-17 AS microemu-build

ARG MICROEMU_COMMIT=31efc58943c355d30b5d89574b9cc1adb76ae747
RUN git clone https://github.com/lolo-san/microemu-minimal.git /src/microemu \
    && cd /src/microemu \
    && git checkout "$MICROEMU_COMMIT" \
    && mvn clean install -Dmaven.test.skip=true \
    && test -f /src/microemu/microemulator/target/microemulator-3.0.0-SNAPSHOT-jar-with-dependencies.jar

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    PORT=8080 \
    JAVA_XMX=160m \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Runtime: Java desktop/AWT + X11 libs required by MicroEmulator Swing UI.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget openssl python3 \
      openjdk-17-jre xvfb xauth \
      fonts-dejavu-core fontconfig \
      libxext6 libxrender1 libxtst6 libxi6 libxrandr2 libfreetype6 libgtk-3-0 \
    && test -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java \
    && /usr/lib/jvm/java-17-openjdk-amd64/bin/java -version \
    && rm -rf /var/lib/apt/lists/*

# Xpra + browser client.
RUN wget -qO /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
    && wget -qO /etc/apt/sources.list.d/xpra.sources \
       https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/noble/xpra.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends xpra xpra-x11 xpra-html5 \
    && test -d /usr/share/xpra/www \
    && rm -rf /var/lib/apt/lists/*

# Cloudflare Quick Tunnel for Blitz background-worker mode.
RUN wget -qO /usr/local/bin/cloudflared \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    && chmod 0755 /usr/local/bin/cloudflared \
    && /usr/local/bin/cloudflared --version

COPY --from=microemu-build \
  /src/microemu/microemulator/target/microemulator-3.0.0-SNAPSHOT-jar-with-dependencies.jar \
  /app/microemulator.jar

# Ubuntu 24.04 may already have uid/gid 1000. Reuse them when present.
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
