import java.lang.instrument.Instrumentation;
import java.net.Authenticator;
import java.net.PasswordAuthentication;

/** Authenticates JVM SOCKS5 sockets using credentials from the game process environment. */
public final class Socks5AuthAgent {
    private Socks5AuthAgent() { }

    public static void premain(String args, Instrumentation instrumentation) {
        final String username = System.getenv("NRO_SOCKS5_USER");
        final String password = System.getenv("NRO_SOCKS5_PASS");
        if (username == null || password == null) return;
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
}
