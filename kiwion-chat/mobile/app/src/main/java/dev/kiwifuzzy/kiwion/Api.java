package dev.kiwifuzzy.kiwion;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** Blocking HTTP client for the Kiwion backend. Call from background threads only. */
public final class Api {
    public static final String OVERLOADED =
            "Птичка киви немного устала 🥝. Сейчас слишком много запросов. Попробуйте отправить сообщение позже";

    public interface EventHandler {
        void onEvent(JSONObject event);
    }

    private final Prefs prefs;

    public Api(Prefs prefs) { this.prefs = prefs; }

    private HttpURLConnection open(String method, String path, int readTimeoutMs) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(prefs.server() + path).openConnection();
        if ("POST_PATCH".equals(method)) {
            c.setRequestMethod("POST");
            c.setRequestProperty("X-HTTP-Method-Override", "PATCH");
        } else {
            c.setRequestMethod(method);
        }
        c.setConnectTimeout(15000);
        c.setReadTimeout(readTimeoutMs);
        c.setRequestProperty("Accept", "application/json");
        c.setRequestProperty("User-Agent", "KiwionAndroid/" + BuildConfigKiwion.VERSION_NAME);
        String t = prefs.token();
        if (t != null) c.setRequestProperty("Authorization", "Bearer " + t);
        return c;
    }

    private static void writeBody(HttpURLConnection c, JSONObject body) throws IOException {
        if (body == null) return;
        byte[] data = body.toString().getBytes(StandardCharsets.UTF_8);
        c.setDoOutput(true);
        c.setRequestProperty("Content-Type", "application/json; charset=utf-8");
        c.setFixedLengthStreamingMode(data.length);
        OutputStream os = c.getOutputStream();
        os.write(data);
        os.close();
    }

    static String readAll(InputStream in) throws IOException {
        if (in == null) return "";
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        in.close();
        return new String(bo.toByteArray(), StandardCharsets.UTF_8);
    }

    static ApiException errorFrom(int status, String body) {
        String code = "error", msg = "Ошибка сервера (" + status + ")";
        try {
            JSONObject o = new JSONObject(body);
            Object d = o.opt("detail");
            if (d == null) d = o.opt("error");
            if (d instanceof JSONObject) {
                code = ((JSONObject) d).optString("code", code);
                msg = ((JSONObject) d).optString("message", msg);
            } else if (d instanceof String) {
                msg = (String) d;
            }
        } catch (JSONException ignored) { }
        if ("overloaded".equals(code)) msg = OVERLOADED;
        return new ApiException(status, code, msg);
    }

    private Object request(String method, String path, JSONObject body) throws ApiException {
        HttpURLConnection c = null;
        try {
            c = open(method, path, 30000);
            writeBody(c, body);
            int status = c.getResponseCode();
            String text = readAll(status >= 400 ? c.getErrorStream() : c.getInputStream());
            if (status == 401 && prefs.token() != null && !path.startsWith("/api/auth/login")) prefs.token(null);
            if (status >= 400) throw errorFrom(status, text);
            if (text.isEmpty()) return new JSONObject();
            text = text.trim();
            return text.startsWith("[") ? new JSONArray(text) : new JSONObject(text);
        } catch (SocketTimeoutException e) {
            throw new ApiException(0, "timeout", "Сервер долго не отвечает. Попробуйте ещё раз.");
        } catch (IOException e) {
            throw new ApiException(0, "network", "Нет соединения с сервером. Проверьте интернет.");
        } catch (JSONException e) {
            throw new ApiException(500, "bad_json", "Некорректный ответ сервера");
        } finally {
            if (c != null) c.disconnect();
        }
    }

    public JSONObject get(String path) throws ApiException { return (JSONObject) request("GET", path, null); }
    public JSONArray getArray(String path) throws ApiException { return (JSONArray) request("GET", path, null); }
    public JSONObject post(String path, JSONObject body) throws ApiException { return (JSONObject) request("POST", path, body == null ? new JSONObject() : body); }
    public JSONObject patch(String path, JSONObject body) throws ApiException {
        // HttpURLConnection does not support PATCH; the backend accepts the override header.
        return (JSONObject) request("POST_PATCH", path, body);
    }
    public JSONObject delete(String path) throws ApiException { return (JSONObject) request("DELETE", path, null); }

    /** A cancellable SSE stream (POST/PUT). */
    public static final class Stream {
        volatile HttpURLConnection conn;
        volatile boolean cancelled;

        public void cancel() {
            cancelled = true;
            HttpURLConnection c = conn;
            if (c != null) {
                try { c.disconnect(); } catch (Exception ignored) { }
            }
        }

        public boolean isCancelled() { return cancelled; }
    }

    /** Runs a streaming request, delivering every `data:` JSON event to the handler. */
    public void stream(String method, String path, JSONObject body, Stream handle, EventHandler handler) throws ApiException {
        HttpURLConnection c = null;
        try {
            c = open(method, path, 300000);  // slow hardware: allow long gaps between tokens
            c.setRequestProperty("Accept", "text/event-stream");
            handle.conn = c;
            writeBody(c, body == null ? new JSONObject() : body);
            int status = c.getResponseCode();
            if (status >= 400) throw errorFrom(status, readAll(c.getErrorStream()));
            BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8));
            String line;
            while (!handle.cancelled && (line = r.readLine()) != null) {
                if (!line.startsWith("data: ")) continue;
                String payload = line.substring(6);
                if ("[DONE]".equals(payload)) break;
                try {
                    handler.onEvent(new JSONObject(payload));
                } catch (JSONException ignored) { }
            }
            r.close();
        } catch (SocketTimeoutException e) {
            if (!handle.cancelled) throw new ApiException(0, "timeout", "Модель отвечает слишком долго. Попробуйте ещё раз.");
        } catch (IOException e) {
            if (!handle.cancelled) throw new ApiException(0, "network", "Соединение прервано. Проверьте интернет.");
        } finally {
            if (c != null) c.disconnect();
        }
    }
}
