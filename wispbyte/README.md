# Wispbyte Free — chạy NRO Java ME bằng Java Generic

> Trạng thái: cấu hình triển khai để thử trên Wispbyte, **chưa có kết quả chạy thực tế**. Wispbyte Free không phải VPS và có thể không cho phép game client hoặc các binary bổ sung theo fair-use policy. Xác nhận với host trước khi dùng.

## 1. Upload launcher

Dùng file **[main.jar](main.jar)** trong thư mục này. Đây là bản sao chính xác của `../raven/ptero-launcher.jar` (Java 8+), **không phải** JAR game NRO. Không cần tải source của repo vào Files nếu launcher tự clone được GitHub.

1. Tạo server với runtime **Java** trên Wispbyte.
2. Trong **Files**, upload file `wispbyte/main.jar` vào thư mục làm việc của panel, thường là `/home/container/main.jar`.
3. Ở **Startup**, nhập:

   ```bash
   java -Dterminal.jline=false -Dterminal.ansi=true -jar main.jar
   ```

4. Start và xem console. Hai cờ `-Dterminal.*` chỉ ảnh hưởng việc xử lý terminal; không chạy Java ME trực tiếp.

Wispbyte có thể cung cấp biến JAR filename riêng. Nếu panel dùng biến này, đặt nó thành `main.jar`; kiểm tra lệnh thực tế được in trong Console. Không đặt `game.jar` làm `main.jar`: launcher và game là hai file khác nhau.

## 2. Launcher làm gì?

`main.jar` sử dụng `HOME` (mặc định `/home/container`), gọi `git` để clone/pull `https://github.com/russel2138/test.git` (branch `main`) vào `$HOME/.nro-raven-src`, rồi chạy `raven/start-raven.sh`. Tên log vẫn dùng tiền tố `[raven]` vì cùng runtime, không phải lỗi.

Script sẽ bootstrap Java 17, MicroEmulator 2.0.4, TigerVNC, sau đó khởi động NRO; console hỗ trợ `list`, `status`, `start`, `restart`, `stop`, `game-restart`, `log`, `log-stop`, `vnc`, `help`.

Các file lưu trên host:

| Đường dẫn | Mục đích |
|---|---|
| `$HOME/main.jar` | Launcher Wispbyte do bạn upload |
| `$HOME/game.jar` | Game mặc định; nếu trống thì runtime seed từ `game.jar` của repo |
| `$HOME/games/*.jar` | Game bổ sung upload thủ công |
| `$HOME/emulators/*.jar` | Emulator MicroEmulator-compatible bổ sung |
| `$HOME/nro-data/` | Java portable, VNC, RMS, profile, logs và state; **không xóa** khi cập nhật |

Game Java ME không thể chạy trực tiếp bằng `java -jar game.jar`; nó cần MicroEmulator và màn hình X11/VNC. Port VNC lấy từ `SERVER_PORT` (hoặc `VNC_PORT` nếu tự cấu hình); phải được host cấp TCP/UDP phù hợp mới truy cập từ xa được. Lưu ý VNC Authentication mặc định của runtime không mã hóa đường truyền.

## 3. Điều kiện tương thích cần kiểm tra

Runtime Raven hiện tại **chưa được port sang mọi distro**. Bootstrap yêu cầu:

- Linux `x86_64/amd64`, không phải ARM64.
- Có `git`, `bash`, `tar`, `curl` hoặc `wget`, `unzip` hoặc `jar` cùng một số tiện ích shell.
- TigerVNC portable: Ubuntu `focal` tải bundle release; `jammy`/`noble` yêu cầu `apt-get`, `dpkg-deb`, internet và quyền ghi ở `$HOME`. Debian/Alpine hiện **không được hỗ trợ**.
- Có đủ ổ đĩa 1 GB và RAM 512 MB cho Java 17, MicroEmulator, TigerVNC, file game và state. Java game hiện giới hạn heap mặc định 160 MB nhưng tổng RSS có thể cao hơn.
- Host cho phép tải và chạy binary Linux, mở port, Java Swing/X11 và game client. CPU 35% vCore free có thể bị giới hạn/dừng khi duy trì tải cao.

Nếu server báo lỗi `git not found`, `unsupported Ubuntu base`, `apt-get/dpkg-deb missing`, `CPU limit` hoặc `OOM`: đó là giới hạn môi trường, không được giải quyết chỉ bằng thay cờ Java. Đừng xóa `nro-data` hoặc thay đổi launcher để né quy định host.

## 4. Debug nhanh

- `Unable to access jarfile main.jar`: sai tên hoặc vị trí file upload.
- `no main manifest attribute`: đã upload nhầm game JAR hoặc file launcher hỏng.
- `Cannot run program "git"`: Docker image Java thiếu `git`; cần image khác / tính năng GitHub deploy được host hỗ trợ.
- `only amd64 is supported` hoặc `unsupported Ubuntu base`: runtime native VNC chưa tương thích.
- `[GAME] failed to start`: đọc `game-errors` hoặc `log` từ panel để xem lỗi MicroEmulator/display.
- Nếu chỉ có Java không có desktop/X11, phải dùng TigerVNC runtime; `-Djava.awt.headless=true` không thay thế được.

Không có watchdog hay vòng autorestart. Vui lòng xem [tài liệu Startup Wispbyte](https://wispbyte.com/kb/startup-settings) và [Fair Use](https://wispbyte.com/kb/getting-started) trước khi triển khai.
