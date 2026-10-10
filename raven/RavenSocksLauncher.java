import java.lang.reflect.InvocationTargetException;
import java.net.Authenticator;
import java.net.PasswordAuthentication;

/** Installs SOCKS5 credentials without a Java premain agent, then runs MicroEmulator. */
public final class RavenSocksLauncher {
    private RavenSocksLauncher() {}

    public static void main(String[] args) throws Exception {
        final String username = System.getenv("NRO_SOCKS5_USER");
        final String password = System.getenv("NRO_SOCKS5_PASS");
        if (username != null && !username.isEmpty()) {
            if (password == null || password.isEmpty()) {
                throw new IllegalArgumentException("SOCKS5 password missing");
            }
            Authenticator.setDefault(new Authenticator() {
                @Override
                protected PasswordAuthentication getPasswordAuthentication() {
                    if ("SOCKS5".equalsIgnoreCase(getRequestingProtocol())) {
                        return new PasswordAuthentication(username, password.toCharArray());
                    }
                    return null;
                }
            });
        }
        try {
            Class.forName("org.microemu.app.Main")
                    .getMethod("main", String[].class)
                    .invoke(null, (Object) args);
        } catch (InvocationTargetException error) {
            Throwable cause = error.getCause();
            if (cause instanceof Exception) throw (Exception) cause;
            if (cause instanceof Error) throw (Error) cause;
            throw error;
        }
    }
}
