package dev.kiwifuzzy.kiwion;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.view.View;

/**
 * The Fluffy Kiwi mascot drawn with Canvas primitives (no images, no animation libraries).
 * Animatable parts: wings, eyes, head tilt. Whole-body motion uses normal View properties
 * (translationY, scaleX/Y, rotation) so it is cheap and hardware accelerated.
 */
public class KiwiView extends View {
    private static final float VW = 220f, VH = 200f;
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();
    private final RectF r = new RectF();
    private float wingAngle = 0f;
    private float headTilt = 0f;
    private boolean eyesClosed = false;
    private boolean shadow = true;
    private Shader bodyShader, headShader;

    public KiwiView(Context c) {
        super(c);
        setContentDescription("Fluffy Kiwi");
    }

    public void setWingAngle(float deg) { wingAngle = deg; invalidate(); }
    public float getWingAngle() { return wingAngle; }
    public void setHeadTilt(float deg) { headTilt = deg; invalidate(); }
    public void setEyesClosed(boolean closed) { eyesClosed = closed; invalidate(); }
    public boolean isEyesClosed() { return eyesClosed; }
    public void setShadow(boolean s) { shadow = s; invalidate(); }

    @Override
    protected void onMeasure(int wSpec, int hSpec) {
        int w = MeasureSpec.getSize(wSpec);
        if (MeasureSpec.getMode(wSpec) == MeasureSpec.UNSPECIFIED) w = Ui.dp(getContext(), 160);
        setMeasuredDimension(w, Math.round(w * VH / VW));
    }

    private void ellipse(Canvas c, float cx, float cy, float rx, float ry) {
        r.set(cx - rx, cy - ry, cx + rx, cy + ry);
        c.drawOval(r, p);
    }

    @Override
    protected void onDraw(Canvas c) {
        float s = Math.min(getWidth() / VW, getHeight() / VH);
        c.save();
        c.translate((getWidth() - VW * s) / 2f, (getHeight() - VH * s) / 2f);
        c.scale(s, s);
        if (bodyShader == null) {
            bodyShader = new RadialGradient(84, 98, 90, new int[]{0xFFB9875A, 0xFF94643C, 0xFF6E4627}, new float[]{0f, .6f, 1f}, Shader.TileMode.CLAMP);
            headShader = new RadialGradient(130, 80, 42, new int[]{0xFFB9875A, 0xFF94643C, 0xFF6E4627}, new float[]{0f, .6f, 1f}, Shader.TileMode.CLAMP);
        }
        p.setStyle(Paint.Style.FILL);
        p.setShader(null);
        if (shadow) {
            p.setColor(0x1F000000);
            ellipse(c, 104, 186, 58, 8);
        }
        // legs
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeCap(Paint.Cap.ROUND);
        p.setStrokeWidth(6);
        p.setColor(0xFFC98E4F);
        c.drawLine(86, 158, 82, 180, p); c.drawLine(82, 180, 70, 184, p); c.drawLine(82, 180, 84, 186, p); c.drawLine(82, 180, 92, 184, p);
        c.drawLine(118, 158, 120, 180, p); c.drawLine(120, 180, 108, 184, p); c.drawLine(120, 180, 122, 186, p); c.drawLine(120, 180, 131, 183, p);
        p.setStyle(Paint.Style.FILL);
        // fluffy back
        p.setColor(0xFF8A5B35);
        float[][] fluff = {{44, 112, 14}, {50, 92, 14}, {64, 76, 14}, {84, 66, 14}, {106, 62, 14}, {40, 132, 13},
                {48, 150, 13}, {66, 162, 13}, {90, 168, 13}, {116, 166, 13}, {138, 156, 13}};
        for (float[] f : fluff) c.drawCircle(f[0], f[1], f[2], p);
        // back wing
        c.save();
        c.rotate(-30 + wingAngle * 0.8f, 78, 72);
        p.setColor(0xFF6E4627);
        ellipse(c, 78, 86, 10, 17);
        c.restore();
        // body
        p.setShader(bodyShader);
        ellipse(c, 100, 118, 60, 52);
        p.setShader(null);
        p.setColor(0x80E2C29A);
        ellipse(c, 108, 134, 36, 28);
        // fur strokes
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(2);
        p.setColor(0x736B4425);
        float[][] fur = {{62, 104}, {70, 126}, {58, 140}, {90, 90}, {84, 150}};
        for (float[] f : fur) {
            path.reset();
            path.moveTo(f[0], f[1]);
            path.quadTo(f[0] + 6, f[1] - 4, f[0] + 10, f[1] + 2);
            c.drawPath(path, p);
        }
        p.setStyle(Paint.Style.FILL);
        // head
        c.save();
        c.rotate(headTilt, 128, 112);
        p.setShader(headShader);
        c.drawCircle(140, 92, 32, p);
        p.setShader(null);
        // sprout
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(3);
        p.setColor(0xFF3E8E37);
        path.reset(); path.moveTo(134, 62); path.quadTo(132, 52, 136, 46);
        c.drawPath(path, p);
        p.setStyle(Paint.Style.FILL);
        p.setColor(0xFF5DB544);
        path.reset(); path.moveTo(136, 48); path.quadTo(120, 40, 114, 52); path.quadTo(126, 58, 136, 48); path.close();
        c.drawPath(path, p);
        p.setColor(0xFF7CC94C);
        path.reset(); path.moveTo(136, 48); path.quadTo(148, 34, 160, 42); path.quadTo(150, 54, 136, 48); path.close();
        c.drawPath(path, p);
        // beak
        p.setColor(0xFFEBCB9C);
        path.reset(); path.moveTo(164, 96); path.quadTo(184, 102, 204, 130); path.quadTo(206, 134, 201, 133);
        path.quadTo(179, 113, 161, 107); path.close();
        c.drawPath(path, p);
        // blush
        p.setColor(0xB3F29B9B);
        ellipse(c, 152, 104, 7, 4.5f);
        // eye
        p.setColor(0xFF1E1410);
        if (eyesClosed) {
            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(2.6f);
            path.reset(); path.moveTo(143, 87); path.quadTo(150, 93, 157, 87);
            c.drawPath(path, p);
            p.setStyle(Paint.Style.FILL);
        } else {
            ellipse(c, 150, 86, 6, 7);
            p.setColor(0xFFFFFFFF);
            c.drawCircle(152, 83.5f, 2.2f, p);
        }
        c.restore();
        // front wing
        c.save();
        c.rotate(-18 - wingAngle, 96, 102);
        p.setColor(0xFF86562F);
        ellipse(c, 96, 120, 13, 20);
        c.restore();
        c.restore();
    }
}
