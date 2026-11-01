package dev.kiwifuzzy.kiwion;

import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Test helper: reads verification codes from the backend's dev outbox (KIWION_TEST_OUTBOX). */
final class TestMail {
    private TestMail() {}

    static String verifyCode(String server, String email) throws Exception {
        Path dir = Paths.get(System.getenv("KIWION_TEST_OUTBOX"));
        for (int i = 0; i < 100; i++) {
            try (DirectoryStream<Path> ds = Files.newDirectoryStream(dir, "*_" + email + ".eml")) {
                for (Path p : ds) {
                    String raw = new String(Files.readAllBytes(p), StandardCharsets.UTF_8);
                    String text = decode(raw);
                    Matcher m = Pattern.compile("token=([A-Za-z0-9_\\-]+)").matcher(text);
                    if (m.find()) return m.group(1);
                }
            } catch (java.nio.file.NoSuchFileException ignored) { }
            Thread.sleep(100);
        }
        throw new AssertionError("no verification mail for " + email);
    }

    /** The plain-text part is base64 (utf-8) in Python's EmailMessage. */
    static String decode(String raw) {
        StringBuilder out = new StringBuilder(raw);
        Matcher m = Pattern.compile("Content-Transfer-Encoding: base64\\s*\\n([A-Za-z0-9+/=\\n]+)").matcher(raw.replace("\r", ""));
        while (m.find()) out.append(new String(java.util.Base64.getMimeDecoder().decode(m.group(1)), StandardCharsets.UTF_8));
        return out.toString();
    }

    static String registerVerified(String server, String email) throws Exception {
        JSONObject ch = new JSONObject(get(server + "/api/auth/challenge"));
        String nonce = Pow.solve(ch.getString("challenge"), ch.getInt("difficulty"));
        JSONObject body = new JSONObject().put("email", email).put("password", "kiwi12345")
                .put("pow", new JSONObject().put("challenge", ch.getString("challenge")).put("nonce", nonce));
        String token = new JSONObject(post(server + "/api/auth/register", body)).getString("token");
        post(server + "/api/auth/verify", new JSONObject().put("token", verifyCode(server, email)));
        return token;
    }

    static String get(String url) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try (InputStream in = c.getInputStream()) { return new String(readAll(in), StandardCharsets.UTF_8); }
    }

    static String post(String url, JSONObject body) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setRequestMethod("POST");
        c.setDoOutput(true);
        c.setRequestProperty("Content-Type", "application/json");
        c.getOutputStream().write(body.toString().getBytes(StandardCharsets.UTF_8));
        try (InputStream in = c.getInputStream()) { return new String(readAll(in), StandardCharsets.UTF_8); }
    }

    static byte[] readAll(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        byte[] b = new byte[8192];
        int n;
        while ((n = in.read(b)) > 0) bo.write(b, 0, n);
        return bo.toByteArray();
    }
}
