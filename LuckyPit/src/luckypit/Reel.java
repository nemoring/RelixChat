package luckypit;

import javax.microedition.lcdui.Graphics;

/**
 * One vertical reel. It only animates: the three symbols it lands on are
 * handed over by {@link SlotMachine} before it starts to slow down, and filler
 * symbols that scroll past come from a separate visual RNG so they never
 * affect the game result.
 */
public final class Reel {
    public static final int CELL = 42;
    public static final int Y0 = 64;
    public static final int W = 46;
    private static final int FP = 256;
    private static final int SPEED = 300;        // px*256 per ms at full speed
    private static final int ACCEL_MS = 180;
    private static final int WINDUP_MS = 90;
    private static final int BOUNCE = 6 * FP;
    private static final int BOUNCE_MS = 110;

    public static final int IDLE = 0, WINDUP = 1, SPIN = 2, STOPPING = 3, BOUNCING = 4;

    public final int x;
    private final int[] ring = new int[64];
    private int pos;        // fixed point pixels
    private int filled;
    public int state;
    private int t;
    private int speed;
    private int startPos, target, dur;
    private int top;        // index shown in the top row when stopped
    private final Rng vis;
    private final int[] wts;
    private int wTotal;

    public Reel(int x, int seed, int[] weights) {
        this.x = x;
        vis = new Rng(seed);
        wts = weights;
        for (int i = 0; i < wts.length; i++) {
            wTotal += wts[i];
        }
        for (int i = 0; i < ring.length; i++) {
            ring[i] = filler();
        }
        top = 2;
        filled = 3;
        pos = top * CELL * FP;
    }

    private int filler() {
        int r = vis.nextInt(wTotal);
        int s = 0;
        while (r >= wts[s]) {
            r -= wts[s];
            s++;
        }
        return s;
    }

    /** Shows a fixed column (top, middle, bottom) while idle. */
    public void show(int s0, int s1, int s2) {
        ring[top & 63] = s0;
        ring[(top - 1) & 63] = s1;
        ring[(top - 2) & 63] = s2;
    }

    public int visible(int row) {
        return ring[(top - row) & 63];
    }

    public void setVisible(int row, int s) {
        ring[(top - row) & 63] = s;
    }

    public void start(int delay) {
        state = WINDUP;
        t = -delay;
        speed = 0;
        startPos = pos;
    }

    /** Schedules the landing on the given column. */
    public void stop(int s0, int s1, int s2) {
        if (state != SPIN && state != WINDUP) {
            return;
        }
        if (state == WINDUP) {
            state = SPIN;
            speed = SPEED;
        }
        int base = pos / (CELL * FP);
        int kt = base + 5;
        while (filled < kt - 3) {
            filled++;
            ring[filled & 63] = filler();
        }
        ring[(kt - 2) & 63] = s2;
        ring[(kt - 1) & 63] = s1;
        ring[kt & 63] = s0;
        filled = kt;
        top = kt;
        startPos = pos;
        target = kt * CELL * FP;
        int d = target + BOUNCE - pos;
        int v = speed < 60 ? 60 : speed;
        dur = 2 * d / v;
        if (dur < 120) {
            dur = 120;
        }
        t = 0;
        state = STOPPING;
    }

    /** Returns true at the moment the reel lands (for the click sound). */
    public boolean update(int dt) {
        boolean landed = false;
        switch (state) {
            case WINDUP:
                t += dt;
                if (t > 0) {
                    if (t < WINDUP_MS) {
                        pos = startPos - (6 * FP) * t / WINDUP_MS;
                    } else {
                        state = SPIN;
                        t = 0;
                    }
                }
                break;
            case SPIN:
                t += dt;
                speed = t < ACCEL_MS ? SPEED * t / ACCEL_MS : SPEED;
                if (speed < 20) {
                    speed = 20;
                }
                pos += speed * dt;
                break;
            case STOPPING: {
                t += dt;
                if (t >= dur) {
                    pos = target + BOUNCE;
                    state = BOUNCING;
                    t = 0;
                    landed = true;
                } else {
                    int u = (t << 10) / dur;          // 0..1024
                    int inv = 1024 - u;
                    int e = 1024 - ((inv * inv) >> 10); // ease-out quad
                    pos = startPos + (int) ((long) (target + BOUNCE - startPos) * e >> 10);
                    speed = (int) ((long) 2 * (target + BOUNCE - startPos) * inv / (1024L * dur));
                }
                break;
            }
            case BOUNCING:
                t += dt;
                if (t >= BOUNCE_MS) {
                    pos = target;
                    state = IDLE;
                    speed = 0;
                } else {
                    pos = target + BOUNCE - BOUNCE * t / BOUNCE_MS;
                }
                break;
            default:
                break;
        }
        // lazily fill symbols entering at the top
        int need = pos / (CELL * FP) + 1;
        while (filled < need) {
            filled++;
            ring[filled & 63] = filler();
        }
        return landed;
    }

    public boolean idle() {
        return state == IDLE;
    }

    public boolean spinning() {
        return state == SPIN || state == WINDUP;
    }

    public void paint(Graphics g, int shakeX) {
        g.setClip(x + shakeX, Y0, W, CELL * 3);
        int p = pos / FP;
        int base = p / CELL;
        if (p < 0) {
            base = -1;
        }
        boolean blur = speed > 150;
        for (int n = base + 1; n >= base - 3; n--) {
            int y = Y0 + p - n * CELL;
            if (y >= Y0 + CELL * 3 || y <= Y0 - CELL) {
                continue;
            }
            ResourceManager.symbol(g, ring[n & 63], x + 5 + shakeX, y + 3, blur);
        }
        g.setClip(0, 0, Gfx.W, Gfx.H);
    }

    /** Screen-space top-left of a row cell (when idle). */
    public static int cellY(int row) {
        return Y0 + row * CELL;
    }
}
