package dev.kiwifuzzy.kiwion;

import android.animation.ObjectAnimator;
import android.animation.PropertyValuesHolder;
import android.animation.ValueAnimator;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/** Launch screen: hopping kiwi + "Kiwion Chat", then routes to auth or chats. Also the error screen. */
public class SplashActivity extends BaseActivity {
    private LinearLayout box;
    private KiwiView kiwi;
    private TextView status;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        box = Ui.vbox(this);
        box.setGravity(Gravity.CENTER);
        kiwi = new KiwiView(this);
        box.addView(kiwi, new LinearLayout.LayoutParams(Ui.dp(this, 170), Ui.dp(this, 155)));
        TextView title = Ui.text(this, "Kiwion Chat", 32, pal.text, true);
        title.setGravity(Gravity.CENTER);
        box.addView(title);
        TextView sub = Ui.text(this, "by Kiwi_Fuzzy", 14, pal.muted, false);
        sub.setGravity(Gravity.CENTER);
        box.addView(sub);
        status = Ui.text(this, "Загружаем птичку киви…", 14, pal.muted, false);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, Ui.dp(this, 18), 0, 0);
        box.addView(status);
        setScreen(box);
        if (!KiwiEasterEgg.animationsReduced(this)) {
            ObjectAnimator hop = ObjectAnimator.ofPropertyValuesHolder(kiwi,
                    PropertyValuesHolder.ofFloat(View.TRANSLATION_Y, 0f, -Ui.dp(this, 16), 0f),
                    PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 1.03f, 1f));
            hop.setDuration(900);
            hop.setRepeatCount(ValueAnimator.INFINITE);
            hop.start();
        }
        start();
    }

    private void start() {
        status.setText("Загружаем птичку киви…");
        final long t0 = System.currentTimeMillis();
        bg(new Task<JSONObject>() {
            public JSONObject run() throws ApiException {
                JSONObject cfg = app.api.get("/api/config/public");
                JSONObject me = null;
                if (app.prefs.token() != null) {
                    try { me = app.api.get("/api/account/me"); } catch (ApiException e) { if (e.status != 401) throw e; }
                }
                JSONObject out = new JSONObject();
                try { out.put("cfg", cfg); out.put("me", me == null ? JSONObject.NULL : me); } catch (Exception ignored) { }
                return out;
            }
        }, new Done<JSONObject>() {
            public void done(final JSONObject r) {
                long wait = Math.max(0, 700 - (System.currentTimeMillis() - t0));
                app.main.postDelayed(new Runnable() { public void run() { route(r); } }, wait);
            }
        }, new Fail() {
            public void fail(ApiException e) { showError(e); }
        });
    }

    private void route(JSONObject r) {
        if (destroyed) return;
        JSONObject me = r.optJSONObject("me");
        Intent i;
        if (me == null) {
            i = new Intent(this, AuthActivity.class);
        } else if (!me.optBoolean("is_verified")) {
            i = new Intent(this, AuthActivity.class).putExtra("mode", "verify").putExtra("email", me.optString("email"));
        } else {
            i = new Intent(this, ChatsActivity.class);
        }
        startActivity(i);
        overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out);
        finish();
    }

    private void showError(ApiException e) {
        status.setText((e.isNetwork() ? "Сервер недоступен. " : "") + e.getMessage());
        status.setTextColor(pal.danger);
        if (box.findViewWithTag("retry") != null) return;
        LinearLayout row = Ui.hbox(this);
        row.setGravity(Gravity.CENTER);
        row.setTag("retry");
        Button retry = Ui.button(this, pal, "Повторить", true);
        retry.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { status.setTextColor(pal.muted); start(); } });
        row.addView(retry);
        Ui.add(box, row, 16);
    }

    @Override
    protected void onBackOnline() { start(); }
}
