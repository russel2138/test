import java.io.BufferedReader;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

public final class SneakyHub {
    private static final String SCRIPT_URL =
        "https://raw.githubusercontent.com/russel2138/test/main/witchly/start.sh";

    private static final Path SCRIPT = Path.of("/tmp/witchly-start.sh");
    private static final Path ROOT = Path.of(
        System.getenv().getOrDefault("HOME", "/home/container")
    );
    private static final Path DATA = ROOT.resolve("nro-data");
    private static final Path VNC_PASS = DATA.resolve(".vnc/password.txt");
    private static final Path VNC_PORT = DATA.resolve("vnc-port.txt");
    private static final Path VNC_PID = DATA.resolve("vnc.pid");
    private static final Path GAME_PID = DATA.resolve("game.pid");

    private static final Object LOCK = new Object();
    private static volatile Process stack;

    public static void main(String[] args) throws Exception {
        System.out.println("[sneakyhub] Witchly launcher starting");
        System.out.println("[sneakyhub] Java: " + System.getProperty("java.version"));
        System.out.println("[sneakyhub] HOME: " + ROOT);

        download(SCRIPT_URL, SCRIPT);
        System.out.println("[sneakyhub] start.sh downloaded");

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            try {
                stopStack(false);
            } catch (Exception ignored) {
            }
        }, "witchly-shutdown"));

        startStack();
        printHelp();

        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                handle(line.trim());
            }
        }

        // Keep the panel process alive even if stdin gets detached.
        while (true) {
            Thread.sleep(Duration.ofHours(1).toMillis());
        }
    }

    private static void handle(String line) {
        if (line.isBlank()) return;

        String cmd = line.toLowerCase(Locale.ROOT);
        try {
            switch (cmd) {
                case "help", "?" -> printHelp();
                case "status" -> printStatus();
                case "vnc" -> printVnc();
                case "start" -> startStack();
                case "stop" -> stopStack(true);
                case "restart" -> {
                    stopStack(false);
                    startStack();
                }
                default -> {
                    System.out.println("[sneakyhub] unknown command: " + line);
                    printHelp();
                }
            }
        } catch (Exception e) {
            System.out.println("[sneakyhub] command failed: " + e.getMessage());
        }
    }

    private static void startStack() throws Exception {
        synchronized (LOCK) {
            if (stack != null && stack.isAlive()) {
                System.out.println("[sneakyhub] NRO is already running");
                return;
            }

            download(SCRIPT_URL, SCRIPT);

            ProcessBuilder pb = new ProcessBuilder("bash", SCRIPT.toString());
            pb.redirectInput(ProcessBuilder.Redirect.from(new File("/dev/null")));
            pb.redirectOutput(ProcessBuilder.Redirect.INHERIT);
            pb.redirectError(ProcessBuilder.Redirect.INHERIT);

            Process p = pb.start();
            stack = p;

            System.out.println("[sneakyhub] NRO stack started (supervisor pid " + p.pid() + ")");

            p.onExit().thenAccept(done -> {
                synchronized (LOCK) {
                    if (stack == done) stack = null;
                }
                System.out.println("[sneakyhub] NRO stack stopped, exit=" + done.exitValue());
                System.out.println("[sneakyhub] type 'start' to run it again");
            });
        }
    }

    private static void stopStack(boolean print) throws Exception {
        Process p;
        synchronized (LOCK) {
            p = stack;
        }

        if (p == null || !p.isAlive()) {
            if (print) System.out.println("[sneakyhub] NRO is already stopped");
            return;
        }

        if (print) System.out.println("[sneakyhub] stopping NRO stack...");
        p.destroy();

        if (!p.waitFor(8, TimeUnit.SECONDS)) {
            p.destroyForcibly();
            p.waitFor(3, TimeUnit.SECONDS);
        }

        if (print) System.out.println("[sneakyhub] NRO stack stopped");
    }

    private static void printStatus() {
        Process p = stack;
        boolean running = p != null && p.isAlive();

        System.out.println("================ WITCHLY STATUS ================");
        System.out.println("Stack:    " + (running ? "RUNNING" : "STOPPED"));
        System.out.println("Game PID: " + readText(GAME_PID, "-"));
        System.out.println("VNC PID:  " + readText(VNC_PID, "-"));
        System.out.println("VNC port: " + readText(VNC_PORT,
            System.getenv().getOrDefault("SERVER_PORT", "-")));
        System.out.println("Watchdog: OFF");
        System.out.println("=================================================");
    }

    private static void printVnc() {
        String host = System.getenv().getOrDefault(
            "SERVER_IP",
            System.getenv().getOrDefault("P_SERVER_IP", "<Witchly public IP/host>")
        );
        String port = readText(VNC_PORT,
            System.getenv().getOrDefault("SERVER_PORT", "-"));
        String pass = readText(VNC_PASS, "-");

        System.out.println("=================== VNC ========================");
        System.out.println("Address : " + host + ":" + port);
        System.out.println("Password: " + pass);
        System.out.println("TigerVNC: " + host + "::" + port);
        System.out.println("=================================================");
    }

    private static void printHelp() {
        System.out.println("Commands:");
        System.out.println("  status   - show NRO/VNC status");
        System.out.println("  vnc      - show VNC address/port/password");
        System.out.println("  stop     - stop NRO + VNC; Witchly stays online");
        System.out.println("  start    - start NRO + VNC");
        System.out.println("  restart  - restart NRO + VNC");
        System.out.println("  help     - show this help");
        System.out.println("Watchdog: OFF");
    }

    private static String readText(Path path, String fallback) {
        try {
            if (!Files.isRegularFile(path)) return fallback;
            String value = Files.readString(path, StandardCharsets.UTF_8).trim();
            return value.isEmpty() ? fallback : value;
        } catch (Exception e) {
            return fallback;
        }
    }

    private static void download(String url, Path target) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(20_000);
        conn.setReadTimeout(60_000);
        conn.setInstanceFollowRedirects(true);
        conn.setRequestProperty("User-Agent", "sneakyhub-witchly/2");

        int code = conn.getResponseCode();
        if (code < 200 || code >= 300) {
            throw new IllegalStateException("HTTP " + code + " downloading " + url);
        }

        try (InputStream in = conn.getInputStream()) {
            Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
        } finally {
            conn.disconnect();
        }
    }
}
