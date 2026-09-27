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
