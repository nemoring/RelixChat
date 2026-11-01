package dev.kiwifuzzy.kiwion;

import android.content.Context;
import android.content.SharedPreferences;

import java.security.SecureRandom;

/** Small wrapper around SharedPreferences (token, device id, server URL, theme, drafts). */
public final class Prefs {
    /** Only automated tests may point the app elsewhere; users cannot change the server. */
    static volatile String serverOverrideForTests;
    private final SharedPreferences p;
    private final String server;

    public Prefs(Context c) {
        p = c.getSharedPreferences("kiwion", Context.MODE_PRIVATE);
        // The official Kiwion server is fixed at build time (resource kiwion_server_url).
        server = c.getString(R.string.kiwion_server_url).replaceAll("/+$", "");
        if (p.contains("server")) p.edit().remove("server").apply();   // drop addresses saved by 1.0.0
    }

    public String token() { return p.getString("token", null); }
    public void token(String t) { p.edit().putString("token", t).apply(); }

    public String server() {
        String o = serverOverrideForTests;
        return o != null ? o : server;
    }

    /** "system" | "light" | "dark" */
    public String theme() { return p.getString("theme", "system"); }
    public void theme(String t) { p.edit().putString("theme", t).apply(); }

    public String draft(String chatId) { return p.getString("draft." + chatId, ""); }
    public void draft(String chatId, String text) {
        if (text == null || text.isEmpty()) p.edit().remove("draft." + chatId).apply();
        else p.edit().putString("draft." + chatId, text).apply();
    }

    public String lastChat() { return p.getString("lastChat", null); }
    public void lastChat(String id) { p.edit().putString("lastChat", id).apply(); }

    public String referral() { return p.getString("ref", null); }
    public void referral(String code) { p.edit().putString("ref", code).apply(); }

    public String deviceId() {
        String id = p.getString("device", null);
        if (id == null) {
            byte[] b = new byte[16];
            new SecureRandom().nextBytes(b);
            StringBuilder sb = new StringBuilder("android-");
            for (byte x : b) sb.append(String.format("%02x", x));
            id = sb.toString();
            p.edit().putString("device", id).apply();
        }
        return id;
    }
}
