package dev.kiwifuzzy.kiwion;

import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

/** Settings and all account pages. The "about" page hides the Fluffy Kiwi easter egg. */
public class SettingsActivity extends BaseActivity {
    private LinearLayout body;
    private String page;
    private KiwiEasterEgg egg;
    private final TapCounter taps = new TapCounter(5, 1500, new TapCounter.Clock() {
        public long now() { return SystemClock.uptimeMillis(); }
    });

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        page = getIntent().getStringExtra("page");
        if (page == null) page = "main";
        String title = "main".equals(page) ? "Настройки" : titleOf(page);
        LinearLayout root = Ui.vbox(this);
        root.addView(topBar(title, true));
        ScrollView sv = new ScrollView(this);
        body = Ui.vbox(this);
        int p = Ui.dp(this, 14);
        body.setPadding(p, 0, p, Ui.dp(this, 30));
        sv.addView(body);
        root.addView(sv, new LinearLayout.LayoutParams(-1, 0, 1));
        setScreen(root);
        render();
    }

    @Override
    public void onBackPressed() {
        if (egg != null && egg.isOpen()) { egg.close(); return; }
        super.onBackPressed();
    }

    private static String titleOf(String p) {
        switch (p) {
            case "profile": return "Профиль";
            case "theme": return "Оформление";
            case "security": return "Безопасность и устройства";
            case "keys": return "API-ключи";
            case "referrals": return "Рефералы";
            case "about": return "О приложении";
            default: return "Настройки";
        }
    }

    private void render() {
        body.removeAllViews();
        switch (page) {
            case "profile": profile(); break;
            case "theme": theme(); break;
            case "security": security(); break;
            case "keys": keys(); break;
            case "referrals": referrals(); break;
            case "about": about(); break;
            default: main();
        }
    }

    private TextView row(LinearLayout card, String title, String sub, View.OnClickListener l) {
        LinearLayout r = Ui.vbox(this);
        r.setPadding(0, Ui.dp(this, 12), 0, Ui.dp(this, 12));
        TextView t = Ui.text(this, title, 16, pal.text, false);
        r.addView(t);
        TextView s = null;
        if (sub != null) { s = Ui.text(this, sub, 13, pal.muted, false); r.addView(s); }
        if (l != null) r.setOnClickListener(l);
        card.addView(r);
        return s != null ? s : t;
    }

    private View.OnClickListener go(final String p) {
        return new View.OnClickListener() {
            public void onClick(View v) { startActivity(new Intent(SettingsActivity.this, SettingsActivity.class).putExtra("page", p)); }
        };
    }

    private void main() {
        LinearLayout card = Ui.card(this, pal);
        row(card, "Профиль", "Имя, лимиты и бонусы", go("profile"));
        row(card, "Оформление", "Светлая и тёмная тема", go("theme"));
        row(card, "Безопасность и устройства", "Пароль, сессии, удаление аккаунта", go("security"));
        row(card, "API-ключи", "Developer API в формате OpenAI", go("keys"));
        row(card, "Рефералы", "Пригласите друзей и получите бонусы", go("referrals"));
        row(card, "О приложении", "Версия, модель, лицензии", go("about"));
        Ui.add(body, card, 6);
        LinearLayout card2 = Ui.card(this, pal);
        row(card2, "Выйти", null, new View.OnClickListener() {
            public void onClick(View v) {
                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/auth/logout", null); } },
                        new Done<JSONObject>() { public void done(JSONObject r) { toLogin(); } },
                        new Fail() { public void fail(ApiException e) { toLogin(); } });
            }
        });
        Ui.add(body, card2, 12);
    }

    private void profile() {
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.get("/api/account/me"); } },
                new Done<JSONObject>() {
                    public void done(JSONObject me) {
                        LinearLayout card = Ui.card(SettingsActivity.this, pal);
                        final EditText name = Ui.input(SettingsActivity.this, pal, "Имя", InputType.TYPE_CLASS_TEXT);
                        name.setText(me.optString("display_name"));
                        card.addView(Ui.text(SettingsActivity.this, me.optString("email"), 14, pal.muted, false));
                        Ui.add(card, name, 10);
                        Button save = Ui.button(SettingsActivity.this, pal, "Сохранить", true);
                        save.setOnClickListener(new View.OnClickListener() {
                            public void onClick(View v) {
                                final JSONObject body = AuthActivity.json("display_name", name.getText().toString().trim());
                                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.patch("/api/account/me", body); } },
                                        new Done<JSONObject>() { public void done(JSONObject r) { toast("Сохранено"); } });
                            }
                        });
                        Ui.add(card, save, 10);
                        Ui.add(body, card, 6);
                        JSONObject q = me.optJSONObject("quota");
                        LinearLayout c2 = Ui.card(SettingsActivity.this, pal);
                        c2.addView(Ui.text(SettingsActivity.this, "Лимиты", 17, pal.text, true));
                        if (q != null) {
                            row(c2, "Использовано сегодня", q.optInt("used_today") + " токенов", null);
                            row(c2, "Дневной лимит", q.optInt("daily_limit") + " токенов", null);
                        }
                        row(c2, "Бонусные токены", String.valueOf(me.optInt("bonus_tokens")), null);
                        row(c2, "Накопленная скидка", me.optInt("discount_percent") + "%", null);
                        Ui.add(body, c2, 12);
                    }
                });
    }

    private void theme() {
        LinearLayout card = Ui.card(this, pal);
        String[][] opts = {{"system", "Как в системе"}, {"light", "Светлая"}, {"dark", "Тёмная"}};
        for (final String[] o : opts) {
            Button b = Ui.button(this, pal, (o[0].equals(app.prefs.theme()) ? "✓ " : "") + o[1], o[0].equals(app.prefs.theme()));
            b.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) {
                    app.prefs.theme(o[0]);
                    final JSONObject body = AuthActivity.json("theme", o[0]);
                    bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.patch("/api/account/me", body); } }, null,
                            new Fail() { public void fail(ApiException e) { } });
                    Intent i = new Intent(SettingsActivity.this, ChatsActivity.class);
                    i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
                    startActivity(i);   // recreate the stack with the new theme
                }
            });
            Ui.add(card, b, 8);
        }
        Ui.add(body, card, 6);
    }

    private void security() {
        LinearLayout card = Ui.card(this, pal);
        card.addView(Ui.text(this, "Смена пароля", 17, pal.text, true));
        final EditText old = Ui.password(this, pal, "Текущий пароль");
        final EditText nw = Ui.password(this, pal, "Новый пароль");
        Ui.add(card, old, 10);
        Ui.add(card, nw, 8);
        Button ch = Ui.button(this, pal, "Изменить пароль", true);
        ch.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                final JSONObject b = AuthActivity.json("old_password", old.getText().toString(), "new_password", nw.getText().toString());
                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/account/password", b); } },
                        new Done<JSONObject>() { public void done(JSONObject r) { toast(r.optString("message")); render(); } });
            }
        });
        Ui.add(card, ch, 10);
        Ui.add(body, card, 6);

        final LinearLayout sessions = Ui.card(this, pal);
        sessions.addView(Ui.text(this, "Устройства и сессии", 17, pal.text, true));
        Ui.add(body, sessions, 12);
        bg(new Task<JSONArray>() { public JSONArray run() throws ApiException { return app.api.getArray("/api/account/sessions"); } },
                new Done<JSONArray>() {
                    public void done(JSONArray a) {
                        for (int i = 0; i < a.length(); i++) {
                            final JSONObject s = a.optJSONObject(i);
                            String sub = s.optString("ip") + " · " + s.optString("last_seen_at").replace("T", " ").substring(0, 16);
                            row(sessions, s.optString("device_name") + (s.optBoolean("current") ? "  (это устройство)" : ""), sub,
                                    s.optBoolean("current") ? null : new View.OnClickListener() {
                                        public void onClick(View v) {
                                            bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.delete("/api/account/sessions/" + s.optString("id")); } },
                                                    new Done<JSONObject>() { public void done(JSONObject r) { toast("Сессия завершена"); render(); } });
                                        }
                                    });
                        }
                        sessions.addView(Ui.text(SettingsActivity.this, "Нажмите на устройство, чтобы завершить его сессию", 12, pal.muted, false));
                    }
                });

        LinearLayout danger = Ui.card(this, pal);
        danger.addView(Ui.text(this, "Удаление аккаунта", 17, pal.danger, true));
        danger.addView(Ui.text(this, "Аккаунт, диалоги и API-ключи будут удалены безвозвратно.", 14, pal.muted, false));
        Button del = Ui.danger(this, pal, "Удалить аккаунт");
        del.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                final EditText pw = Ui.password(SettingsActivity.this, pal, "Пароль");
                LinearLayout f = Ui.vbox(SettingsActivity.this);
                f.setPadding(Ui.dp(SettingsActivity.this, 20), 0, Ui.dp(SettingsActivity.this, 20), 0);
                f.addView(pw);
                new AlertDialog.Builder(SettingsActivity.this).setTitle("Удалить аккаунт навсегда?").setView(f)
                        .setPositiveButton("Удалить", new DialogInterface.OnClickListener() {
                            public void onClick(DialogInterface d, int w) {
                                final JSONObject b = AuthActivity.json("password", pw.getText().toString(), "confirm", "DELETE");
                                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/account/delete", b); } },
                                        new Done<JSONObject>() { public void done(JSONObject r) { toast(r.optString("message")); toLogin(); } });
                            }
                        }).setNegativeButton("Отмена", null).show();
            }
        });
        Ui.add(danger, del, 10);
        Ui.add(body, danger, 12);
    }

    private void keys() {
        LinearLayout card = Ui.card(this, pal);
        card.addView(Ui.text(this, "Ключи для OpenAI-совместимого API: " + app.prefs.server() + "/v1/chat/completions. "
                + "Полный ключ показывается только один раз.", 14, pal.muted, false));
        final EditText name = Ui.input(this, pal, "Название ключа", InputType.TYPE_CLASS_TEXT);
        Ui.add(card, name, 10);
        Button create = Ui.button(this, pal, "Создать ключ", true);
        create.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                String n = name.getText().toString().trim();
                final JSONObject b = AuthActivity.json("name", n.isEmpty() ? "Android" : n);
                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/keys", b); } },
                        new Done<JSONObject>() {
                            public void done(final JSONObject k) {
                                TextView key = Ui.text(SettingsActivity.this, k.optString("key"), 14, pal.text, false);
                                key.setTextIsSelectable(true);
                                key.setTypeface(android.graphics.Typeface.MONOSPACE);
                                LinearLayout f = Ui.vbox(SettingsActivity.this);
                                f.setPadding(Ui.dp(SettingsActivity.this, 20), Ui.dp(SettingsActivity.this, 8), Ui.dp(SettingsActivity.this, 20), 0);
                                f.addView(Ui.text(SettingsActivity.this, k.optString("warning"), 13, pal.muted, false));
                                Ui.add(f, key, 8);
                                new AlertDialog.Builder(SettingsActivity.this).setTitle("Новый API-ключ").setView(f)
                                        .setPositiveButton("Копировать", new DialogInterface.OnClickListener() {
                                            public void onClick(DialogInterface d, int w) { copy(k.optString("key")); render(); }
                                        }).setNegativeButton("Закрыть", new DialogInterface.OnClickListener() {
                                            public void onClick(DialogInterface d, int w) { render(); }
                                        }).setCancelable(false).show();
                            }
                        });
            }
        });
        Ui.add(card, create, 8);
        Ui.add(body, card, 6);
        final LinearLayout listCard = Ui.card(this, pal);
        listCard.addView(Ui.text(this, "Ваши ключи", 17, pal.text, true));
        Ui.add(body, listCard, 12);
        bg(new Task<JSONArray>() { public JSONArray run() throws ApiException { return app.api.getArray("/api/keys"); } },
                new Done<JSONArray>() {
                    public void done(JSONArray a) {
                        if (a.length() == 0) listCard.addView(Ui.text(SettingsActivity.this, "Ключей пока нет", 14, pal.muted, false));
                        for (int i = 0; i < a.length(); i++) {
                            final JSONObject k = a.optJSONObject(i);
                            String sub = k.optString("prefix") + "… · " + (k.optBoolean("revoked") ? "отозван" : "активен")
                                    + " · " + k.optInt("rpm_limit") + " запр/мин · сегодня " + k.optInt("tokens_today") + " ток.";
                            row(listCard, k.optString("name"), sub, new View.OnClickListener() {
                                public void onClick(View v) { keyMenu(k); }
                            });
                        }
                    }
                });
        final LinearLayout stats = Ui.card(this, pal);
        Ui.add(body, stats, 12);
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.get("/api/keys/usage"); } },
                new Done<JSONObject>() {
                    public void done(JSONObject u) {
                        JSONObject t = u.optJSONObject("totals");
                        stats.addView(Ui.text(SettingsActivity.this, "Статистика за 14 дней", 17, pal.text, true));
                        row(stats, "Запросов", String.valueOf(t.optInt("requests")), null);
                        row(stats, "Токенов (запрос / ответ)", t.optInt("prompt_tokens") + " / " + t.optInt("completion_tokens"), null);
                        row(stats, "Ошибок", String.valueOf(t.optInt("errors")), null);
                    }
                });
    }

    private void keyMenu(final JSONObject k) {
        String[] items = k.optBoolean("revoked") ? new String[]{"Удалить"} : new String[]{"Отозвать", "Удалить"};
        new AlertDialog.Builder(this).setTitle(k.optString("name")).setItems(items, new DialogInterface.OnClickListener() {
            public void onClick(DialogInterface d, int w) {
                final boolean revoke = !k.optBoolean("revoked") && w == 0;
                bg(new Task<JSONObject>() {
                    public JSONObject run() throws ApiException {
                        return revoke ? app.api.post("/api/keys/" + k.optString("id") + "/revoke", null)
                                : app.api.delete("/api/keys/" + k.optString("id"));
                    }
                }, new Done<JSONObject>() { public void done(JSONObject r) { render(); } });
            }
        }).show();
    }

    private void referrals() {
        bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.get("/api/account/referrals"); } },
                new Done<JSONObject>() {
                    public void done(final JSONObject r) {
                        JSONObject rc = r.optJSONObject("rewards_config");
                        LinearLayout card = Ui.card(SettingsActivity.this, pal);
                        card.addView(Ui.text(SettingsActivity.this, "Пригласите друзей 🥝", 18, pal.text, true));
                        Ui.add(card, Ui.text(SettingsActivity.this, "За каждого друга, подтвердившего email: вам +" + rc.optInt("referrer_bonus_tokens")
                                + " токенов и скидка " + rc.optInt("discount_percent") + "% (до " + rc.optInt("discount_cap") + "%), другу +"
                                + rc.optInt("invitee_bonus_tokens") + " токенов.", 14, pal.muted, false), 6);
                        TextView link = Ui.text(SettingsActivity.this, r.optString("link"), 14, pal.text, false);
                        link.setTextIsSelectable(true);
                        link.setBackground(Ui.round(pal.surface2, Ui.dp(SettingsActivity.this, 10)));
                        link.setPadding(Ui.dp(SettingsActivity.this, 10), Ui.dp(SettingsActivity.this, 10), Ui.dp(SettingsActivity.this, 10), Ui.dp(SettingsActivity.this, 10));
                        Ui.add(card, link, 10);
                        LinearLayout btns = Ui.hbox(SettingsActivity.this);
                        Button cp = Ui.button(SettingsActivity.this, pal, "Копировать", true);
                        cp.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { copy(r.optString("link")); } });
                        Button share = Ui.button(SettingsActivity.this, pal, "Поделиться", false);
                        share.setOnClickListener(new View.OnClickListener() {
                            public void onClick(View v) {
                                Intent s = new Intent(Intent.ACTION_SEND).setType("text/plain")
                                        .putExtra(Intent.EXTRA_TEXT, "Попробуй Kiwion Chat 🥝 " + r.optString("link"));
                                startActivity(Intent.createChooser(s, "Поделиться"));
                            }
                        });
                        btns.addView(cp);
                        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
                        lp.leftMargin = Ui.dp(SettingsActivity.this, 8);
                        btns.addView(share, lp);
                        Ui.add(card, btns, 10);
                        card.addView(Ui.text(SettingsActivity.this, "Код: " + r.optString("code"), 13, pal.muted, false));
                        Ui.add(body, card, 6);

                        JSONObject st = r.optJSONObject("stats");
                        LinearLayout c2 = Ui.card(SettingsActivity.this, pal);
                        row(c2, "Приглашено / подтверждено", st.optInt("total") + " / " + st.optInt("confirmed"), null);
                        row(c2, "Бонусные токены", String.valueOf(r.optInt("bonus_tokens")), null);
                        row(c2, "Скидка", r.optInt("discount_percent") + "%", null);
                        JSONArray inv = r.optJSONArray("invites");
                        for (int i = 0; inv != null && i < inv.length(); i++) {
                            JSONObject x = inv.optJSONObject(i);
                            row(c2, x.optString("invitee"), statusRu(x.optString("status")), null);
                        }
                        Ui.add(body, c2, 12);
                        LinearLayout c3 = Ui.card(SettingsActivity.this, pal);
                        c3.addView(Ui.text(SettingsActivity.this, "История начислений", 17, pal.text, true));
                        JSONArray rw = r.optJSONArray("rewards");
                        if (rw == null || rw.length() == 0) c3.addView(Ui.text(SettingsActivity.this, "Начислений пока нет", 14, pal.muted, false));
                        for (int i = 0; rw != null && i < rw.length(); i++) {
                            JSONObject w = rw.optJSONObject(i);
                            row(c3, w.optString("note"), ("discount".equals(w.optString("kind")) ? "+" + w.optInt("amount") + "%" : "+" + w.optInt("amount") + " токенов"), null);
                        }
                        Ui.add(body, c3, 12);
                    }
                });
    }

    private static String statusRu(String s) {
        switch (s) {
            case "confirmed": return "подтверждено";
            case "pending": return "ждёт подтверждения email";
            case "review": return "на проверке";
            case "rejected": return "отклонено";
            default: return s;
        }
    }

    private void about() {
        LinearLayout head = Ui.vbox(this);
        head.setGravity(Gravity.CENTER_HORIZONTAL);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.logo);
        logo.setClipToOutline(true);
        logo.setBackground(Ui.round(pal.surface, Ui.dp(this, 28)));
        head.addView(logo, new LinearLayout.LayoutParams(Ui.dp(this, 120), Ui.dp(this, 120)));
        head.addView(Ui.text(this, "Kiwion Chat", 24, pal.text, true));
        head.addView(Ui.text(this, "Разработчик: Kiwi_Fuzzy", 14, pal.muted, false));
        Ui.add(body, head, 10);
        LinearLayout card = Ui.card(this, pal);
        // Settings → О приложении → Версия приложения: 5 quick taps start the secret animation.
        TextView version = row(card, "Версия приложения", BuildConfigKiwion.VERSION_NAME + " (" + BuildConfigKiwion.VERSION_CODE + ")", null);
        View versionRow = (View) version.getParent();
        versionRow.setContentDescription("Версия приложения " + BuildConfigKiwion.VERSION_NAME);
        versionRow.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                if (taps.tap()) {
                    if (egg == null) egg = new KiwiEasterEgg(SettingsActivity.this, pal);
                    egg.open();
                }
            }
        });
        row(card, "Модель", "OLMo 2 1B Instruct (Ai2, Apache 2.0)", null);
        row(card, "Инференс", "llama.cpp на собственном сервере Kiwion", null);
        row(card, "Сервер", app.prefs.server(), null);
        row(card, "Документация API", app.prefs.server() + "/docs", null);
        Ui.add(body, card, 12);
        TextView foot = Ui.text(this, "Сделано с любовью к пушистым птичкам 🥝", 13, pal.muted, false);
        foot.setGravity(Gravity.CENTER);
        Ui.add(body, foot, 16);
    }

    private void copy(String s) {
        ((ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Kiwion", s));
        toast("Скопировано");
    }
}
