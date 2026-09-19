FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/app \
    PORT=8080 \
    GAME_WIDTH=320 \
    GAME_HEIGHT=240 \
    GAME_SCALE=2 \
    JAVA_XMX=128m

# Base tools + Java + X11 dependencies. Python is used only for the one-time
# browser upload page on the first deploy.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates wget git ant openssl python3 \
      openjdk-17-jdk xvfb xauth \
      fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Current Xpra packages for Ubuntu 24.04, including the HTML5 client.
RUN wget -qO /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
    && wget -qO /etc/apt/sources.list.d/xpra.sources \
       https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/noble/xpra.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends xpra \
    && rm -rf /var/lib/apt/lists/*

# Pin FreeJ2ME to a known commit and build the standalone AWT JAR.
ARG FREEJ2ME_COMMIT=fae9304b85ac1c61d0117f6c8efe528612388278
RUN git clone https://github.com/hex007/freej2me.git /tmp/freej2me \
    && cd /tmp/freej2me \
    && git checkout "$FREEJ2ME_COMMIT" \
    && ant \
    && mkdir -p /app \
    && cp build/freej2me.jar /app/freej2me.jar \
    && rm -rf /tmp/freej2me

RUN groupadd -g 1000 app \
    && useradd -m -u 1000 -g 1000 -s /bin/bash app \
    && mkdir -p /app /data /home/app/.xpra \
    && chown -R 1000:1000 /app /data /home/app

COPY --chown=1000:1000 run-game.sh /app/run-game.sh
COPY --chown=1000:1000 start.sh /app/start.sh
COPY --chown=1000:1000 upload.py /app/upload.py
RUN chmod +x /app/run-game.sh /app/start.sh /app/upload.py

USER 1000:1000
WORKDIR /data

# FreeJ2ME save/config, the uploaded game JAR and Xpra password live here.
VOLUME ["/data"]

# Blitz detects this HTTP port and puts HTTPS in front of it.
EXPOSE 8080

CMD ["/app/start.sh"]
