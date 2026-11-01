package dev.kiwifuzzy.kiwion;

import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

/** Login, registration (with proof-of-work), password recovery and e-mail confirmation. */
public class AuthActivity extends BaseActivity {
    private LinearLayout form;
    private TextView error;
    private String mode;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        mode = getIntent().getStringExtra("mode");
        if (mode == null) mode = "login";
        Intent i = getIntent();
        if (i.getData() != null && i.getData().getQueryParameter("ref") != null) {
            app.prefs.referral(i.getData().getQueryParameter("ref"));
            mode = "register";
        }
        build();
    }

    private void build() {
        ScrollView sv = new ScrollView(this);
        sv.setFillViewport(true);
        LinearLayout outer = Ui.vbox(this);
        outer.setGravity(Gravity.CENTER_HORIZONTAL);
        int pad = Ui.dp(this, 22);
        outer.setPadding(pad, pad, pad, pad);
        KiwiView kiwi = new KiwiView(this);
        kiwi.setShadow(false);
        outer.addView(kiwi, new LinearLayout.LayoutParams(Ui.dp(this, 110), Ui.dp(this, 100)));
        TextView title = Ui.text(this, "Kiwion Chat", 28, pal.text, true);
        outer.addView(title);
        TextView sub = Ui.text(this, "ИИ-помощник от Kiwi_Fuzzy", 14, pal.muted, false);
        outer.addView(sub);
        form = Ui.card(this, pal);
        LinearLayout.LayoutParams flp = Ui.matchWrap(this, 18);
        outer.addView(form, flp);
        sv.addView(outer);
        setScreen(sv);
        render();
    }

    private void heading(String s) {
        form.addView(Ui.text(this, s, 21, pal.text, true));
    }

    private TextView link(String s, View.OnClickListener l) {
        TextView t = Ui.text(this, s, 15, pal.greenStrong, true);
        t.setPadding(0, Ui.dp(this, 12), 0, Ui.dp(this, 4));
        t.setOnClickListener(l);
        return t;
    }

    private void switchMode(String m) {
        mode = m;
        render();
    }

    private void render() {
        form.removeAllViews();
        error = Ui.text(this, "", 14, pal.danger, false);
        if ("register".equals(mode)) renderRegister();
        else if ("forgot".equals(mode)) renderForgot();
        else if ("verify".equals(mode)) renderVerify();
        else renderLogin();
    }

    private String deviceName() {
        return "Kiwion для Android · " + Build.MANUFACTURER + " " + Build.MODEL;
    }

    private void renderLogin() {
        heading("Вход");
        final EditText email = Ui.email(this, pal);
        final EditText pw = Ui.password(this, pal, "Пароль");
        Ui.add(form, email, 14);
        Ui.add(form, pw, 10);
        Ui.add(form, error, 8);
        final Button go = Ui.button(this, pal, "Войти", true);
        Ui.add(form, go, 6);
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                go.setEnabled(false);
                error.setText("");
                final JSONObject body = json("email", email.getText().toString().trim(), "password", pw.getText().toString(),
                        "device_id", app.prefs.deviceId(), "device_name", deviceName());
                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/auth/login", body); } },
                        new Done<JSONObject>() { public void done(JSONObject r) { go.setEnabled(true); loggedIn(r); } },
                        new Fail() { public void fail(ApiException e) { go.setEnabled(true); error.setText(e.getMessage()); } });
            }
        });
        form.addView(link("Создать аккаунт", new View.OnClickListener() { public void onClick(View v) { switchMode("register"); } }));
        form.addView(link("Забыли пароль?", new View.OnClickListener() { public void onClick(View v) { switchMode("forgot"); } }));
        form.addView(link("Адрес сервера", new View.OnClickListener() {
            public void onClick(View v) { SettingsActivity.editServer(AuthActivity.this, null); }
        }));
    }

    private void renderRegister() {
        heading("Регистрация");
        final EditText name = Ui.input(this, pal, "Как вас зовут", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        final EditText email = Ui.email(this, pal);
        final EditText pw = Ui.password(this, pal, "Пароль (8+ символов, буквы и цифры)");
        final EditText ref = Ui.input(this, pal, "Код приглашения (необязательно)", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        if (app.prefs.referral() != null) ref.setText(app.prefs.referral());
        final CheckBox terms = new CheckBox(this);
        terms.setText("Я принимаю условия использования");
        terms.setTextColor(pal.muted);
        terms.setChecked(true);
        Ui.add(form, name, 14);
        Ui.add(form, email, 10);
        Ui.add(form, pw, 10);
        Ui.add(form, ref, 10);
        Ui.add(form, terms, 8);
        Ui.add(form, error, 4);
        final Button go = Ui.button(this, pal, "Создать аккаунт", true);
        Ui.add(form, go, 6);
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                if (!terms.isChecked()) { error.setText("Необходимо принять условия использования"); return; }
                go.setEnabled(false);
                go.setText("Проверка защиты от ботов…");
                error.setText("");
                final String e = email.getText().toString().trim(), p = pw.getText().toString(),
                        n = name.getText().toString().trim(), code = ref.getText().toString().trim();
                bg(new Task<JSONObject>() {
                    public JSONObject run() throws ApiException {
                        JSONObject ch = app.api.get("/api/auth/challenge");
                        String nonce = Pow.solve(ch.optString("challenge"), ch.optInt("difficulty"));
                        JSONObject pow = json("challenge", ch.optString("challenge"), "nonce", nonce);
                        JSONObject body = json("email", e, "password", p, "display_name", n, "device_id", app.prefs.deviceId(),
                                "device_name", deviceName(), "accept_terms", true);
                        try {
                            body.put("pow", pow);
                            if (!code.isEmpty()) body.put("referral_code", code);
                        } catch (Exception ignored) { }
                        return app.api.post("/api/auth/register", body);
                    }
                }, new Done<JSONObject>() {
                    public void done(JSONObject r) {
                        app.prefs.referral(null);
                        app.prefs.token(r.optString("token"));
                        getIntent().putExtra("email", e);
                        switchMode("verify");
                    }
                }, new Fail() {
                    public void fail(ApiException ex) { go.setEnabled(true); go.setText("Создать аккаунт"); error.setText(ex.getMessage()); }
                });
            }
        });
        form.addView(link("Уже есть аккаунт? Войти", new View.OnClickListener() { public void onClick(View v) { switchMode("login"); } }));
    }

    private void renderForgot() {
        heading("Восстановление пароля");
        form.addView(Ui.text(this, "Пришлём письмо со ссылкой и кодом для смены пароля.", 14, pal.muted, false));
        final EditText email = Ui.email(this, pal);
        Ui.add(form, email, 12);
        final EditText code = Ui.input(this, pal, "Код из письма", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        final EditText pw = Ui.password(this, pal, "Новый пароль");
        code.setVisibility(View.GONE);
        pw.setVisibility(View.GONE);
        Ui.add(form, code, 10);
        Ui.add(form, pw, 10);
        Ui.add(form, error, 8);
        final Button go = Ui.button(this, pal, "Отправить письмо", true);
        Ui.add(form, go, 6);
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                error.setText("");
                if (code.getVisibility() == View.GONE) {
                    final JSONObject body = json("email", email.getText().toString().trim());
                    bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/auth/forgot", body); } },
                            new Done<JSONObject>() {
                                public void done(JSONObject r) {
                                    toast(r.optString("message"));
                                    code.setVisibility(View.VISIBLE);
                                    pw.setVisibility(View.VISIBLE);
                                    go.setText("Сменить пароль");
                                }
                            }, new Fail() { public void fail(ApiException e) { error.setText(e.getMessage()); } });
                } else {
                    final JSONObject body = json("token", code.getText().toString().trim(), "new_password", pw.getText().toString());
                    bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/auth/reset", body); } },
                            new Done<JSONObject>() { public void done(JSONObject r) { toast(r.optString("message")); switchMode("login"); } },
                            new Fail() { public void fail(ApiException e) { error.setText(e.getMessage()); } });
                }
            }
        });
        form.addView(link("Назад ко входу", new View.OnClickListener() { public void onClick(View v) { switchMode("login"); } }));
    }

    private void renderVerify() {
        heading("Подтвердите email");
        String email = getIntent().getStringExtra("email");
        form.addView(Ui.text(this, "Мы отправили письмо на " + (email == null ? "вашу почту" : email)
                + ". Откройте ссылку из письма или вставьте код подтверждения.", 15, pal.muted, false));
        final EditText code = Ui.input(this, pal, "Код подтверждения", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        Ui.add(form, code, 12);
        Ui.add(form, error, 8);
        final Button go = Ui.button(this, pal, "Подтвердить", true);
        Ui.add(form, go, 6);
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                final String c = code.getText().toString().trim();
                bg(new Task<JSONObject>() {
                    public JSONObject run() throws ApiException {
                        if (!c.isEmpty()) app.api.post("/api/auth/verify", json("token", c));
                        return app.api.get("/api/account/me");
                    }
                }, new Done<JSONObject>() {
                    public void done(JSONObject me) {
                        if (me.optBoolean("is_verified")) {
                            toast("Email подтверждён! Добро пожаловать 🥝");
                            openChats();
                        } else error.setText("Email ещё не подтверждён — проверьте почту и папку «Спам»");
                    }
                }, new Fail() { public void fail(ApiException e) { error.setText(e.getMessage()); } });
            }
        });
        form.addView(link("Отправить письмо ещё раз", new View.OnClickListener() {
            public void onClick(View v) {
                bg(new Task<JSONObject>() { public JSONObject run() throws ApiException { return app.api.post("/api/auth/resend-verification", null); } },
                        new Done<JSONObject>() { public void done(JSONObject r) { toast(r.optString("message")); } });
            }
        }));
        form.addView(link("Выйти", new View.OnClickListener() { public void onClick(View v) { app.prefs.token(null); switchMode("login"); } }));
    }

    private void loggedIn(JSONObject r) {
        app.prefs.token(r.optString("token"));
        JSONObject u = r.optJSONObject("user");
        if (u != null && !u.optBoolean("is_verified")) {
            getIntent().putExtra("email", u.optString("email"));
            switchMode("verify");
        } else openChats();
    }

    private void openChats() {
        Intent i = new Intent(this, ChatsActivity.class);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        startActivity(i);
        finish();
    }

    static JSONObject json(Object... kv) {
        JSONObject o = new JSONObject();
        try {
            for (int i = 0; i + 1 < kv.length; i += 2) o.put((String) kv[i], kv[i + 1]);
        } catch (Exception ignored) { }
        return o;
    }
}
