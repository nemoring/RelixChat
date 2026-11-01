package dev.kiwifuzzy.kiwion;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkInfo;
import android.net.NetworkRequest;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/** Common activity: theme colors, offline banner, background tasks and messages. */
public abstract class BaseActivity extends Activity {
    protected KiwionApp app;
    protected Palette pal;
    private TextView offlineBanner;
    private ConnectivityManager.NetworkCallback netCallback;
    protected boolean destroyed;

    public interface Task<T> { T run() throws ApiException; }
    public interface Done<T> { void done(T result); }
    public interface Fail { void fail(ApiException e); }

    @Override
    protected void onCreate(Bundle b) {
        app = KiwionApp.get();
        pal = Palette.of(this);
        setTheme(pal.dark ? android.R.style.Theme_Material_NoActionBar : android.R.style.Theme_Material_Light_NoActionBar);
        super.onCreate(b);
        Window w = getWindow();
        w.setStatusBarColor(pal.bg);
        w.setNavigationBarColor(pal.bg);
        if (!pal.dark) w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        w.getDecorView().setBackgroundColor(pal.bg);
    }

    /** Wraps content with an offline banner on top. */
    protected void setScreen(View content) {
        LinearLayout root = Ui.vbox(this);
        root.setBackgroundColor(pal.bg);
        offlineBanner = Ui.text(this, "Нет подключения к интернету — ждём сеть…", 13, Color.WHITE, false);
        offlineBanner.setGravity(Gravity.CENTER);
        offlineBanner.setBackgroundColor(pal.warn);
        offlineBanner.setPadding(0, Ui.dp(this, 6), 0, Ui.dp(this, 6));
        offlineBanner.setVisibility(isOnline() ? View.GONE : View.VISIBLE);
        root.addView(offlineBanner, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(content, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        root.setFitsSystemWindows(true);
        setContentView(root);
    }

    @Override
    protected void onStart() {
        super.onStart();
        ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        netCallback = new ConnectivityManager.NetworkCallback() {
            @Override public void onAvailable(Network n) { app.main.post(new Runnable() { public void run() { updateOffline(); } }); }
            @Override public void onLost(Network n) { app.main.postDelayed(new Runnable() { public void run() { updateOffline(); } }, 300); }
        };
        try {
            cm.registerNetworkCallback(new NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), netCallback);
        } catch (RuntimeException ignored) { netCallback = null; }
        updateOffline();
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (netCallback != null) {
            try {
                ((ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE)).unregisterNetworkCallback(netCallback);
            } catch (RuntimeException ignored) { }
            netCallback = null;
        }
    }

    @Override
    protected void onDestroy() {
        destroyed = true;
        super.onDestroy();
    }

    private void updateOffline() {
        if (offlineBanner == null) return;
        boolean online = isOnline();
        boolean wasOffline = offlineBanner.getVisibility() == View.VISIBLE;
        offlineBanner.setVisibility(online ? View.GONE : View.VISIBLE);
        if (online && wasOffline) onBackOnline();
    }

    protected void onBackOnline() { }

    @SuppressWarnings("deprecation")
    public boolean isOnline() {
        ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo ni = cm.getActiveNetworkInfo();
        return ni != null && ni.isConnected();
    }

    /** Run a network task off the main thread, deliver the result on the main thread. */
    protected <T> void bg(final Task<T> task, final Done<T> done, final Fail fail) {
        app.io.execute(new Runnable() {
            public void run() {
                try {
                    final T r = task.run();
                    app.main.post(new Runnable() { public void run() { if (!destroyed && done != null) done.done(r); } });
                } catch (final ApiException e) {
                    app.main.post(new Runnable() {
                        public void run() {
                            if (destroyed) return;
                            if (e.status == 401) { toLogin(); return; }
                            if (fail != null) fail.fail(e); else toast(e.getMessage());
                        }
                    });
                }
            }
        });
    }

    protected <T> void bg(Task<T> task, Done<T> done) { bg(task, done, null); }

    public void toast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show();
    }

    protected void toLogin() {
        app.prefs.token(null);
        Intent i = new Intent(this, AuthActivity.class);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        startActivity(i);
        finish();
    }

    /** Top bar with an optional back arrow. */
    protected LinearLayout topBar(String title, boolean back) {
        LinearLayout bar = Ui.hbox(this);
        int p = Ui.dp(this, 10);
        bar.setPadding(p, p, p, p);
        if (back) {
            TextView b = Ui.text(this, "‹", 30, pal.text, false);
            b.setPadding(Ui.dp(this, 8), 0, Ui.dp(this, 14), Ui.dp(this, 4));
            b.setContentDescription("Назад");
            b.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { onBackPressed(); } });
            bar.addView(b);
        }
        TextView t = Ui.text(this, title, 19, pal.text, true);
        t.setSingleLine(true);
        bar.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        return bar;
    }

    protected FrameLayout decor() {
        return (FrameLayout) getWindow().getDecorView();
    }
}
