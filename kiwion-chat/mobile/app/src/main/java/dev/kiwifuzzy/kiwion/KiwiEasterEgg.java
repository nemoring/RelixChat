package dev.kiwifuzzy.kiwion;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.AnimatorSet;
import android.animation.Keyframe;
import android.animation.ObjectAnimator;
import android.animation.PropertyValuesHolder;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * Secret "Fluffy Kiwi" easter egg: Settings → О приложении → Версия приложения, 5 quick taps.
 * Implemented with framework animators only; works offline, can be replayed, can be closed at any
 * time, and respects the system "remove animations" setting.
 */
public final class KiwiEasterEgg {
    private final Activity activity;
    private final Palette pal;
    private FrameLayout overlay;
    private KiwiView bird;
    private TextView title, happy;
    private Button pet;
    private ParticleLayer particles;
    private final List<Animator> running = new ArrayList<>();
    private final List<Runnable> scheduled = new ArrayList<>();
    private boolean reduced, petting;
    private final Runnable idleBlink = new Runnable() {
        public void run() {
            if (overlay == null) return;
            if (!petting) blink(null);
            later(this, 2600);
        }
    };

    public KiwiEasterEgg(Activity a, Palette p) {
        activity = a;
        pal = p;
    }

    public boolean isOpen() { return overlay != null; }

    public static boolean animationsReduced(Activity a) {
        float scale = Settings.Global.getFloat(a.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        return scale == 0f;
    }

    private int dp(float v) { return Ui.dp(activity, v); }

    public void open() {
        if (overlay != null) return;
        reduced = animationsReduced(activity);
        FrameLayout decor = (FrameLayout) activity.getWindow().getDecorView();
        overlay = new FrameLayout(activity);
        overlay.setClickable(true);            // the app below is untouchable only while the egg is open
        overlay.setBackgroundColor(Color.TRANSPARENT);
        overlay.setContentDescription("Fluffy Kiwi");
        overlay.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { close(); } });

        particles = new ParticleLayer(activity);
        particles.reducedMotion = reduced;
        overlay.addView(particles, new FrameLayout.LayoutParams(-1, -1));

        bird = new KiwiView(activity);
        bird.setShadow(true);
        bird.setClickable(true);   // tapping the bird must not close the overlay
        FrameLayout.LayoutParams blp = new FrameLayout.LayoutParams(dp(230), dp(210), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        blp.bottomMargin = dp(150);
        overlay.addView(bird, blp);
        bird.setPivotX(dp(115));
        bird.setPivotY(dp(200));

        title = new TextView(activity);
        title.setText("You've found the Fluffy Kiwi! 🥝");
        title.setTextColor(0xFF1F5F2A);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 19);
        title.setBackground(Ui.round(Color.WHITE, dp(16)));
        title.setPadding(dp(16), dp(10), dp(16), dp(10));
        title.setElevation(dp(6));
        title.setAlpha(0f);
        FrameLayout.LayoutParams tlp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        tlp.bottomMargin = dp(380);
        overlay.addView(title, tlp);

        happy = Ui.text(activity, "Kiwi is happy!", 21, Color.WHITE, true);
        happy.setShadowLayer(8, 0, 2, 0x99000000);
        happy.setAlpha(0f);
        FrameLayout.LayoutParams hlp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        hlp.bottomMargin = dp(440);
        overlay.addView(happy, hlp);

        pet = Ui.button(activity, pal, "Погладить киви", true);
        pet.setAlpha(0f);
        pet.setEnabled(false);
        pet.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { pet(); } });
        FrameLayout.LayoutParams plp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        plp.bottomMargin = dp(70);
        overlay.addView(pet, plp);

        TextView close = Ui.text(activity, "×", 26, 0xFF1C2419, false);
        close.setGravity(Gravity.CENTER);
        close.setBackground(Ui.round(0xEEFFFFFF, dp(24)));
        close.setContentDescription("Закрыть");
        close.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { close(); } });
        FrameLayout.LayoutParams clp = new FrameLayout.LayoutParams(dp(46), dp(46), Gravity.TOP | Gravity.END);
        clp.topMargin = dp(36);
        clp.rightMargin = dp(16);
        overlay.addView(close, clp);

        decor.addView(overlay, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        run();
    }

    public void close() {
        if (overlay == null) return;
        for (Animator a : new ArrayList<>(running)) a.cancel();
        running.clear();
        for (Runnable r : scheduled) overlay.removeCallbacks(r);
        overlay.removeCallbacks(idleBlink);
        scheduled.clear();
        particles.stop();
        ((ViewGroup) overlay.getParent()).removeView(overlay);
        overlay = null;
        petting = false;
    }

    private void later(Runnable r, long ms) {
        if (overlay == null) return;
        scheduled.add(r);
        overlay.postDelayed(r, ms);
    }

    private <T extends Animator> T track(T a) {
        running.add(a);
        a.addListener(new AnimatorListenerAdapter() {
            @Override public void onAnimationEnd(Animator x) { running.remove(x); }
        });
        return a;
    }

    private void run() {
        // 4. dim the screen
        ValueAnimator dim = track(ValueAnimator.ofArgb(0x00000000, 0x8C08100A));
        dim.setDuration(reduced ? 0 : 500);
        dim.addUpdateListener(new ValueAnimator.AnimatorUpdateListener() {
            public void onAnimationUpdate(ValueAnimator a) { if (overlay != null) overlay.setBackgroundColor((Integer) a.getAnimatedValue()); }
        });
        dim.start();
        if (reduced) {
            // Reduced motion: the kiwi and the label simply appear, no jumps or spins.
            title.setAlpha(1f);
            showPet();
            return;
        }
        bird.setTranslationY(activity.getResources().getDisplayMetrics().heightPixels);
        later(new Runnable() { public void run() { jumpIn(); } }, 250);
    }

    private void jumpIn() {
        float h = activity.getResources().getDisplayMetrics().heightPixels;
        // 5. jumps out from the bottom of the screen, 6. lands with a squash
        PropertyValuesHolder ty = PropertyValuesHolder.ofKeyframe(View.TRANSLATION_Y,
                Keyframe.ofFloat(0f, h), Keyframe.ofFloat(.65f, -dp(70)), Keyframe.ofFloat(.88f, 0f), Keyframe.ofFloat(1f, 0f));
        PropertyValuesHolder sx = PropertyValuesHolder.ofKeyframe(View.SCALE_X,
                Keyframe.ofFloat(0f, .9f), Keyframe.ofFloat(.65f, .95f), Keyframe.ofFloat(.88f, 1.12f), Keyframe.ofFloat(1f, 1f));
        PropertyValuesHolder sy = PropertyValuesHolder.ofKeyframe(View.SCALE_Y,
                Keyframe.ofFloat(0f, 1.1f), Keyframe.ofFloat(.65f, 1.05f), Keyframe.ofFloat(.88f, .86f), Keyframe.ofFloat(1f, 1f));
        ObjectAnimator jump = track(ObjectAnimator.ofPropertyValuesHolder(bird, ty, sx, sy));
        jump.setDuration(1100);
        jump.setInterpolator(new DecelerateInterpolator(1.2f));
        jump.addListener(new AnimatorListenerAdapter() {
            boolean cancelled;
            @Override public void onAnimationCancel(Animator a) { cancelled = true; }
            @Override public void onAnimationEnd(Animator a) { if (!cancelled) lookAtUser(); }
        });
        jump.start();
    }

    private void lookAtUser() {
        // blinks twice and looks at the user
        blink(new Runnable() {
            public void run() {
                later(new Runnable() {
                    public void run() {
                        blink(new Runnable() {
                            public void run() {
                                ObjectAnimator tilt = track(ObjectAnimator.ofFloat(bird, "headTilt", 0f, -8f, 0f));
                                tilt.setDuration(700);
                                tilt.setInterpolator(new AccelerateDecelerateInterpolator());
                                tilt.start();
                                later(new Runnable() { public void run() { hopAndFlap(); } }, 700);
                            }
                        });
                    }
                }, 180);
            }
        });
    }

    private void blink(final Runnable then) {
        if (overlay == null) return;
        bird.setEyesClosed(true);
        later(new Runnable() {
            public void run() {
                bird.setEyesClosed(petting);
                if (then != null) then.run();
            }
        }, 120);
    }

    private void hopAndFlap() {
        // 7. funny hops while flapping the tiny wings
        ObjectAnimator flap = track(ObjectAnimator.ofFloat(bird, "wingAngle", 0f, 55f));
        flap.setDuration(160);
        flap.setRepeatCount(13);
        flap.setRepeatMode(ValueAnimator.REVERSE);
        flap.start();
        // 8. the label above the bird
        title.setScaleX(.6f);
        title.setScaleY(.6f);
        AnimatorSet pop = track(new AnimatorSet());
        pop.playTogether(ObjectAnimator.ofFloat(title, View.ALPHA, 0f, 1f),
                ObjectAnimator.ofFloat(title, View.SCALE_X, .6f, 1.08f, 1f),
                ObjectAnimator.ofFloat(title, View.SCALE_Y, .6f, 1.08f, 1f));
        pop.setDuration(500);
        pop.start();
        PropertyValuesHolder ty = PropertyValuesHolder.ofKeyframe(View.TRANSLATION_Y,
                Keyframe.ofFloat(0f, 0f), Keyframe.ofFloat(.45f, -dp(46)), Keyframe.ofFloat(.85f, 0f), Keyframe.ofFloat(1f, 0f));
        PropertyValuesHolder sx = PropertyValuesHolder.ofKeyframe(View.SCALE_X,
                Keyframe.ofFloat(0f, 1.08f), Keyframe.ofFloat(.45f, .96f), Keyframe.ofFloat(.85f, 1.1f), Keyframe.ofFloat(1f, 1f));
        PropertyValuesHolder sy = PropertyValuesHolder.ofKeyframe(View.SCALE_Y,
                Keyframe.ofFloat(0f, .92f), Keyframe.ofFloat(.45f, 1.04f), Keyframe.ofFloat(.85f, .9f), Keyframe.ofFloat(1f, 1f));
        ObjectAnimator hops = track(ObjectAnimator.ofPropertyValuesHolder(bird, ty, sx, sy));
        hops.setDuration(520);
        hops.setRepeatCount(2);
        hops.addListener(new AnimatorListenerAdapter() {
            boolean cancelled;
            @Override public void onAnimationCancel(Animator a) { cancelled = true; }
            @Override public void onAnimationEnd(Animator a) { if (!cancelled) spin(); }
        });
        hops.start();
    }

    private void spin() {
        // 9. happy spin with green particles around
        int[] loc = new int[2], oloc = new int[2];
        bird.getLocationInWindow(loc);
        overlay.getLocationInWindow(oloc);
        particles.burst(loc[0] - oloc[0] + bird.getWidth() / 2f, loc[1] - oloc[1] + bird.getHeight() / 2f, 30);
        AnimatorSet set = track(new AnimatorSet());
        set.playTogether(ObjectAnimator.ofFloat(bird, View.ROTATION, 0f, 360f),
                ObjectAnimator.ofFloat(bird, View.TRANSLATION_Y, 0f, -dp(30), 0f));
        set.setDuration(1000);
        set.setInterpolator(new AccelerateDecelerateInterpolator());
        set.start();
        later(idleBlink, 1800);
        // 10. a few seconds later the "pet the kiwi" button appears
        later(new Runnable() { public void run() { showPet(); } }, 2800);
    }

    private void showPet() {
        pet.setEnabled(true);
        pet.setTranslationY(dp(12));
        pet.animate().alpha(1f).translationY(0).setDuration(reduced ? 0 : 400).start();
    }

    private void pet() {
        if (overlay == null || petting) return;
        petting = true;
        bird.setEyesClosed(true);                 // closes the eyes
        ChirpSound.play();                        // cute sound
        happy.setTranslationY(reduced ? 0 : dp(10));
        happy.animate().alpha(1f).translationY(0).setDuration(reduced ? 0 : 400).start();
        int[] loc = new int[2], oloc = new int[2];
        bird.getLocationInWindow(loc);
        overlay.getLocationInWindow(oloc);
        particles.hearts(loc[0] - oloc[0] + bird.getWidth() * 0.62f, loc[1] - oloc[1] + dp(20), bird.getWidth() * 0.5f, reduced ? 3 : 7);
        if (!reduced) {
            ObjectAnimator squish = track(ObjectAnimator.ofPropertyValuesHolder(bird,
                    PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 1.06f, 1f),
                    PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, .94f, 1f)));
            squish.setDuration(600);
            squish.setRepeatCount(1);
            squish.start();
        }
        later(new Runnable() {
            public void run() {
                petting = false;
                bird.setEyesClosed(false);
            }
        }, 2400);
    }
}
