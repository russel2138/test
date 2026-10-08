# RavenHost / Pterodactyl Java runtime

Thư mục này là runtime cho RavenHost và các host Pterodactyl Java tương thích.

## Launcher

File dùng chung:

```text
ptero-launcher.jar
```

Launcher tương thích Java 8+, tự clone/pull:

```text
https://github.com/russel2138/test.git
```

vào:

```text
/home/container/.nro-raven-src
```

rồi chạy:

```text
raven/start-raven.sh
```

Tên JAR trên từng host có thể khác nhau:

```text
RavenHost:  sneakyhub.jar   (nếu egg đang cố định tên này)
Zampto:     server.jar      (Minecraft Java Generic)
```

Chỉ cần đổi tên cùng một `ptero-launcher.jar`; không cần fork runtime riêng cho từng host.

## Persistent files

Game mặc định:

```text
/home/container/game.jar
```

Game bổ sung:

```text
/home/container/games/*.jar
```

Emulator bổ sung:

```text
/home/container/emulators/*.jar
```

State:

```text
/home/container/nro-data/
```

Không xóa `nro-data/` khi update launcher hoặc scripts.

## Runtime selection

Uploaded emulator JAR phải tương thích MicroEmulator (`org.microemu.app.Main`). MIDlet class được đọc tự động từ `META-INF/MANIFEST.MF`.

Mỗi cặp game/emulator riêng có state riêng:

```text
/home/container/nro-data/profiles/<game>/<emulator>/.microemulator/
```

Selection hiện tại:

```text
/home/container/nro-data/current-selection.env
```

## Panel console commands

Panel console là stdin của runtime, **không phải shell**.

```text
list
status
restart MICRO_NST AUTO50_X1
restart
start
stop
game-restart
loop-check
log
log-stop
vnc
help
```

`restart <emulator> <game>` đổi runtime và ghi nhớ selection.

`stop` tạm dừng stack cho tới `start`, `restart`, hoặc full server restart.


## Java 17 game runtime

RavenHost có thể vẫn dùng image Java 8 để khởi động `ptero-launcher.jar`. Runtime tự tải Eclipse Temurin JRE 17 portable vào:

```text
/home/container/nro-data/java17/
```

MicroEmulator/game luôn được chạy bằng:

```text
/home/container/nro-data/java17/bin/java
```

Không cần panel hỗ trợ đổi Docker image sang Java 17.

## Optional SOCKS5 proxy (game JVM only)

The proxy is selected per command. Omitting the proxy always starts the game with a **direct connection**; the proxy is **not** written to the saved emulator/game selection.

```text
restart                                    # direct, reuse chosen emulator/game
restart MICRO_NST V9_X1.jar                 # direct, choose emulator/game
restart 1.2.3.4:1080                       # SOCKS5 without authentication
restart 1.2.3.4:1080:user:password         # SOCKS5 with authentication
restart MICRO_NST V9_X1.jar 1.2.3.4:1080
restart MICRO_NST V9_X1.jar 1.2.3.4:1080:user:password
game-restart 1.2.3.4:1080:user:password     # restart just the game
```

`start` accepts the same optional arguments, but if a game is already running, use `restart` or `game-restart` to apply changes. Format is `ip:port` or `ip:port:user:password`; domain names are accepted as hostnames. IPv6 addresses, colons within credentials, and spaces in credentials are not supported by this command parser.

A SOCKS5 endpoint without credentials sets only JVM SOCKS settings. A SOCKS5 endpoint with credentials additionally starts the `Socks5AuthAgent`, which registers a JVM `Authenticator`. The agent source is `Socks5AuthAgent.java` and the Java 8-compatible agent payload is `socks5-auth-agent.jar.b64`. The script decodes and SHA-256 verifies it into `/home/container/nro-data/socks5-auth-agent.jar` on first authenticated use; no JDK is needed on the host.

Credentials are passed to the **game JVM** through environment variables rather than JVM `-D` arguments, but the proxy value still appears in the Pterodactyl console input/history, and users who can inspect process environments may read credentials. Do not commit real passwords into the repository.

Only Java sockets respecting JVM SOCKS proxy settings are redirected. This is not a container-wide proxy and does not affect the launcher or VNC. Verify real game connections before relying on the proxy.
