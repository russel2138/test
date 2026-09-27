import java.io.File;
import java.util.ArrayList;
import java.util.List;

public final class Launcher {
    private static int run(List<String> command, File dir) throws Exception {
        ProcessBuilder pb = new ProcessBuilder(command);
        if (dir != null) pb.directory(dir);
        pb.inheritIO();
        return pb.start().waitFor();
    }

    private static void check(int code, String step) {
        if (code != 0) {
            System.err.println("[launcher] " + step + " failed with exit code " + code);
            System.exit(code);
        }
    }

    public static void main(String[] args) throws Exception {
        String home = System.getenv("HOME");
        if (home == null || home.trim().isEmpty()) home = "/home/container";

        File root = new File(home);
        File src = new File(root, ".nro-raven-src");
        File gitDir = new File(src, ".git");

        System.out.println("[launcher] NRO Pterodactyl launcher (Java 8+)");
        System.out.println("[launcher] root: " + root.getAbsolutePath());

        if (gitDir.isDirectory()) {
            check(run(cmd("git", "fetch", "--depth=1", "origin", "main"), src), "git fetch");
            check(run(cmd("git", "reset", "--hard", "origin/main"), src), "git reset");
        } else {
            if (src.exists()) {
                check(run(cmd("rm", "-rf", src.getAbsolutePath()), root), "cleanup old source");
            }
            check(run(cmd("git", "clone", "--depth=1", "--branch", "main",
                    "https://github.com/russel2138/test.git", src.getAbsolutePath()), root), "git clone");
        }

        File start = new File(src, "raven/start-raven.sh");
        if (!start.isFile()) {
            System.err.println("[launcher] missing: " + start.getAbsolutePath());
            System.exit(2);
        }

        System.out.println("[launcher] starting Raven-compatible runtime...");
        int code = run(cmd("bash", start.getAbsolutePath()), root);
        System.exit(code);
    }

    private static List<String> cmd(String... values) {
        List<String> out = new ArrayList<String>();
        for (String value : values) out.add(value);
        return out;
    }
}
