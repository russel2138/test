# NRO hosting

Repo này giữ các target đang dùng:

- **Blitz**: runtime Docker ở thư mục root.
- **RavenHost / Pterodactyl Java**: runtime ở `raven/`.
- **Wispbyte (Java Generic)**: launcher sẵn dùng tại `wispbyte/main.jar`, hướng dẫn ở [wispbyte/README.md](wispbyte/README.md). Dùng chung runtime `raven/`, không fork game/emulator.

Zampto không có runtime riêng. Nếu cần test Zampto, dùng lại runtime `raven/` qua `raven/ptero-launcher.jar` và đặt tên file thành `server.jar`.

## Blitz

Blitz build trực tiếp từ root repo:

```text
Dockerfile
start.sh
run-display.sh
run-game.sh
run-web.sh
run-tunnel.sh
game.jar
```

Startup command:

```text
/app/start.sh
```

Runtime hiện tại:

```text
TigerVNC Xvnc : 400x340x16
MicroEmulator : resizable device 400x300
Java heap     : Xms 8m, Xmx 192m mặc định
watchdog      : OFF
autorestart   : OFF
state         : /data/microemu-home/.microemulator
```

## RavenHost / Pterodactyl Java

Xem [raven/README.md](raven/README.md).

Launcher dùng chung:

```text
raven/ptero-launcher.jar
```

Launcher tự clone/pull branch `main` mỗi lần server start, sau đó chạy:

```text
raven/start-raven.sh
```

Game JAR và state không nằm trong Git; giữ ở `/home/container` và `/home/container/nro-data` trên host.

## Wispbyte / Java Generic

File upload lên Wispbyte (giữ đúng tên `main.jar`):

```text
wispbyte/main.jar
```

Startup command trong panel:

```bash
java -Dterminal.jline=false -Dterminal.ansi=true -jar main.jar
```

`wispbyte/main.jar` là bản sao byte-for-byte của launcher `raven/ptero-launcher.jar`, **không phải game JAR**. Nó vẫn clone/pull `main` và gọi `raven/start-raven.sh`. Không đổi gameplay, RMS, logic proxy hoặc cơ chế restart.

Wispbyte Free là container Java chứ không phải VPS/root. Runtime hiện tại yêu cầu Linux x86_64, Bash/Git, khả năng tải dependency và các công cụ Ubuntu phù hợp để bootstrap TigerVNC. Chưa kiểm chứng tương thích hoàn toàn với image Wispbyte, tài nguyên free hoặc chính sách host game client; xem hướng dẫn và checklist ở [wispbyte/README.md](wispbyte/README.md).
