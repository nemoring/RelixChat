package dev.kiwifuzzy.kiwion;

import android.animation.TimeAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.View;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Random;

/** Lightweight particle system for green confetti and floating hearts (pure Canvas). */
public class ParticleLayer extends View {
    private static final class P {
        float x, y, vx, vy, size, life, age;
        int color;
        boolean heart;
    }

    private final List<P> items = new ArrayList<>();
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path heart = new Path();
    private final Random rnd = new Random();
    private final TimeAnimator ticker = new TimeAnimator();
    private final float density;
    public boolean reducedMotion;

    public ParticleLayer(Context c) {
        super(c);
        density = c.getResources().getDisplayMetrics().density;
        ticker.setTimeListener(new TimeAnimator.TimeListener() {
            public void onTimeUpdate(TimeAnimator a, long total, long dtMs) { step(Math.min(dtMs, 48) / 1000f); }
        });
    }

    public void burst(float cx, float cy, int n) {
        int[] colors = {0xFF8BD450, 0xFF4CAF50, 0xFFB6E07A, 0xFF2E8B3E, 0xFFD7F5B0};
        for (int i = 0; i < n; i++) {
            P p = new P();
            double ang = 2 * Math.PI * i / n + rnd.nextFloat() * 0.4;
            float speed = (180 + rnd.nextFloat() * 160) * density;
            p.x = cx; p.y = cy;
            p.vx = (float) Math.cos(ang) * speed;
            p.vy = (float) Math.sin(ang) * speed - 60 * density;
            p.size = (3 + rnd.nextFloat() * 4) * density;
            p.life = 1.4f + rnd.nextFloat() * 0.5f;
            p.color = colors[i % colors.length];
            items.add(p);
        }
        start();
    }

    public void hearts(float cx, float cy, float spread, int n) {
        for (int i = 0; i < n; i++) {
            P p = new P();
            p.heart = true;
            p.x = cx + (rnd.nextFloat() - .5f) * spread;
            p.y = cy;
            p.vx = reducedMotion ? 0 : (rnd.nextFloat() - .5f) * 40 * density;
            p.vy = reducedMotion ? 0 : -(70 + rnd.nextFloat() * 50) * density;
            p.size = (9 + rnd.nextFloat() * 4) * density;
            p.life = 1.8f + rnd.nextFloat() * 0.6f;
            p.age = -i * 0.14f;   // staggered start
            p.color = i % 3 == 2 ? 0xFF5DBB63 : 0xFFE84A5F;
            items.add(p);
        }
        start();
    }

    private void start() {
        if (!ticker.isStarted()) ticker.start();
    }

    public void stop() {
        ticker.cancel();
        items.clear();
        invalidate();
    }

    private void step(float dt) {
        Iterator<P> it = items.iterator();
        while (it.hasNext()) {
            P p = it.next();
            p.age += dt;
            if (p.age < 0) continue;
            if (p.age > p.life) { it.remove(); continue; }
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            if (!p.heart) { p.vx *= 0.97f; p.vy = p.vy * 0.97f + 260 * density * dt; }
        }
        if (items.isEmpty()) ticker.cancel();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas c) {
        for (P p : items) {
            if (p.age < 0) continue;
            float t = p.age / p.life;
            int alpha = (int) (255 * (t < 0.2f && p.heart ? t / 0.2f : 1 - Math.max(0, (t - 0.6f) / 0.4f)));
            paint.setColor(p.color);
            paint.setAlpha(Math.max(0, Math.min(255, alpha)));
            if (p.heart) drawHeart(c, p.x, p.y, p.size);
            else c.drawCircle(p.x, p.y, p.size, paint);
        }
    }

    private void drawHeart(Canvas c, float x, float y, float s) {
        heart.reset();
        heart.moveTo(x, y + s * 0.9f);
        heart.cubicTo(x - s * 1.6f, y - s * 0.1f, x - s * 0.7f, y - s * 1.3f, x, y - s * 0.45f);
        heart.cubicTo(x + s * 0.7f, y - s * 1.3f, x + s * 1.6f, y - s * 0.1f, x, y + s * 0.9f);
        heart.close();
        c.drawPath(heart, paint);
    }
}
