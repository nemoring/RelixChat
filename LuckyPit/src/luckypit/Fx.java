package luckypit;

import javax.microedition.lcdui.Graphics;

/**
 * Pooled particles (coins, sparks), floating labels, screen flash and shake.
 * Fixed-size arrays only: nothing is allocated while effects run.
 */
public final class Fx {
    public static final int P_COIN = 0, P_SPARK = 1, P_STAR = 2;
    private static final int MAX = 48;
    private static final int[] px = new int[MAX], py = new int[MAX], vx = new int[MAX], vy = new int[MAX];
    private static final int[] life = new int[MAX], type = new int[MAX], color = new int[MAX], tx = new int[MAX],
            ty = new int[MAX];
    private static int n;

    private static final int LMAX = 6;
    private static final String[] lText = new String[LMAX];
    private static final int[] lx = new int[LMAX], ly = new int[LMAX], lLife = new int[LMAX], lCol = new int[LMAX];

    public static int flashMs, flashRgb;
    public static int shakeMs, shakeAmp;
    private static final Rng rng = new Rng(0x1234567);
    public static boolean enabled = true;

    private Fx() {
    }

    public static void clear() {
        n = 0;
        for (int i = 0; i < LMAX; i++) {
            lLife[i] = 0;
        }
        flashMs = shakeMs = 0;
    }

    /** Burst of coins flying toward (toX,toY) after a short spray. */
    public static void coins(int x, int y, int count, int toX, int toY) {
        if (!enabled) {
            return;
        }
        for (int i = 0; i < count && n < MAX; i++) {
            int k = n++;
            px[k] = x << 8;
            py[k] = y << 8;
            vx[k] = (rng.nextInt(512) - 256) * 3;
            vy[k] = -(rng.nextInt(400) + 300) * 3;
            life[k] = 900 + rng.nextInt(400);
            type[k] = P_COIN;
            tx[k] = toX;
            ty[k] = toY;
            color[k] = rng.nextInt(6);
        }
    }

    public static void sparks(int x, int y, int count, int rgb) {
        if (!enabled) {
            return;
        }
        for (int i = 0; i < count && n < MAX; i++) {
            int k = n++;
            px[k] = x << 8;
            py[k] = y << 8;
            vx[k] = (rng.nextInt(512) - 256) * 2;
            vy[k] = (rng.nextInt(512) - 300) * 2;
            life[k] = 300 + rng.nextInt(300);
            type[k] = rng.nextInt(3) == 0 ? P_STAR : P_SPARK;
            color[k] = rgb;
            tx[k] = ty[k] = 0;
        }
    }

    public static void label(String s, int x, int y, int col) {
        int best = 0;
        for (int i = 0; i < LMAX; i++) {
            if (lLife[i] <= 0) {
                best = i;
                break;
            }
            if (lLife[i] < lLife[best]) {
                best = i;
            }
        }
        lText[best] = s;
        lx[best] = x;
        ly[best] = y;
        lLife[best] = 1100;
        lCol[best] = col;
    }

    public static void flash(int rgb, int ms) {
        if (!enabled) {
            return;
        }
        flashRgb = rgb;
        flashMs = ms;
    }

    public static void shake(int amp, int ms) {
        if (!enabled) {
            return;
        }
        shakeAmp = amp;
        shakeMs = ms;
    }

    public static int shakeX(int t) {
        if (shakeMs <= 0) {
            return 0;
        }
        return ((t / 30) & 1) == 0 ? shakeAmp : -shakeAmp;
    }

    public static void update(int dt) {
        for (int i = 0; i < n; i++) {
            life[i] -= dt;
            if (life[i] <= 0) {
                n--;
                px[i] = px[n]; py[i] = py[n]; vx[i] = vx[n]; vy[i] = vy[n];
                life[i] = life[n]; type[i] = type[n]; color[i] = color[n]; tx[i] = tx[n]; ty[i] = ty[n];
                i--;
                continue;
            }
            if (type[i] == P_COIN && life[i] < 600) {
                // home toward the counter
                int dx = (tx[i] << 8) - px[i];
                int dy = (ty[i] << 8) - py[i];
                px[i] += dx * dt / 160;
                py[i] += dy * dt / 160;
                if (dx > -600 && dx < 600 && dy > -600 && dy < 600) {
                    life[i] = 0;
                }
            } else {
                px[i] += vx[i] * dt / 1000;
                py[i] += vy[i] * dt / 1000;
                vy[i] += 1400 * dt / 1000 * (type[i] == P_COIN ? 2 : 1);
            }
        }
        for (int i = 0; i < LMAX; i++) {
            if (lLife[i] > 0) {
                lLife[i] -= dt;
            }
        }
        if (flashMs > 0) {
            flashMs -= dt;
        }
        if (shakeMs > 0) {
            shakeMs -= dt;
        }
    }

    public static void paint(Graphics g, int t) {
        for (int i = 0; i < n; i++) {
            int x = px[i] >> 8, y = py[i] >> 8;
            switch (type[i]) {
                case P_COIN:
                    if (ResourceManager.coin != null) {
                        int f = ((t / 70) + color[i]) % 6;
                        g.drawRegion(ResourceManager.coin, f * 8, 0, 8, 8, 0, x - 4, y - 4, Gfx.TL);
                    }
                    break;
                case P_STAR:
                    g.setColor(color[i]);
                    g.drawLine(x - 2, y, x + 2, y);
                    g.drawLine(x, y - 2, x, y + 2);
                    break;
                default:
                    g.setColor(life[i] > 200 ? 0xFFF4C0 : color[i]);
                    g.fillRect(x, y, 2, 2);
                    break;
            }
        }
        for (int i = 0; i < LMAX; i++) {
            if (lLife[i] > 0 && lText[i] != null) {
                int rise = (1100 - lLife[i]) / 40;
                PixelFont.outline(g, lText[i], lx[i], ly[i] - rise, lCol[i], Graphics.HCENTER);
            }
        }
    }

    /** Full-screen flash drawn as sparse scanlines (cheap, no alpha). */
    public static void paintFlash(Graphics g) {
        if (flashMs > 0) {
            g.setColor(flashRgb);
            int step = flashMs > 120 ? 2 : 4;
            for (int y = 0; y < Gfx.H; y += step) {
                g.drawLine(0, y, Gfx.W, y);
            }
        }
    }

    public static boolean busy() {
        return n > 0;
    }
}
