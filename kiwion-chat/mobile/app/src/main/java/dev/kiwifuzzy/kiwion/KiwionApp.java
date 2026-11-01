package dev.kiwifuzzy.kiwion;

import android.app.Application;
import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class KiwionApp extends Application {
    private static KiwionApp instance;
    public Prefs prefs;
    public Api api;
    public final ExecutorService io = Executors.newFixedThreadPool(4);
    public final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        prefs = new Prefs(this);
        api = new Api(prefs);
    }

    public static KiwionApp get() { return instance; }
}
