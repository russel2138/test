# NRO hosting

Repo này chỉ giữ các target đang dùng:

- **Blitz**: runtime Docker ở thư mục root.
- **RavenHost / Pterodactyl Java**: runtime ở `raven/`.

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

Xem `raven/README.md`.

Launcher dùng chung:

```text
raven/ptero-launcher.jar
```

Launcher tự clone/pull branch `main` mỗi lần server start, sau đó chạy:

```text
raven/start-raven.sh
```

Game JAR và state không nằm trong Git; giữ ở `/home/container` và `/home/container/nro-data` trên host.
