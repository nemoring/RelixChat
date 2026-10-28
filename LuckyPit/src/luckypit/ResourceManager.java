package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/**
 * Loads and caches images. Sprite sheets stay resident (they are small);
 * full-screen backgrounds are kept one at a time; card illustrations live in
 * a small LRU cache, plus an integer-scaled 2x cache for big card views.
 */
public final class ResourceManager {
    public static Image sym, symBlur, frames, slots, cursor, icons, coin, lamps, lever, button, panel,
            banner, glint;

    public static final int I_COIN = 0, I_TOKEN = 1, I_DEBT = 2, I_SPIN = 3, I_CARD = 4, I_LOCK = 5,
            I_STAR = 6, I_CLOCK = 7, I_CHECK = 8, I_CROSS = 9, I_LEFT = 10, I_RIGHT = 11, I_SKULL = 12,
            I_BELL = 13;

    private static String bgName;
    private static Image bgImg;

    private static final int ART_CACHE = 24;
    private static final int[] artId = new int[ART_CACHE];
    private static final Image[] artImg = new Image[ART_CACHE];
    private static final int[] artUse = new int[ART_CACHE];
    private static final int BIG_CACHE = 8;
    private static final int[] bigId = new int[BIG_CACHE];
    private static final Image[] bigImg = new Image[BIG_CACHE];
    private static final int[] bigUse = new int[BIG_CACHE];
    private static int useClock;
    private static int[] scaleBuf;

    private ResourceManager() {
    }

    public static Image load(String name) {
        try {
            return Image.createImage("/" + name);
        } catch (Throwable t) {
            return null;
        }
    }

    public static void init() {
        sym = load("sym.png");
        symBlur = load("symb.png");
        frames = load("frames.png");
        slots = load("slots.png");
        cursor = load("cursor.png");
        icons = load("icons.png");
        coin = load("coin.png");
        lamps = load("lamps.png");
        lever = load("lever.png");
        button = load("button.png");
        panel = load("panel.png");
        banner = load("banner.png");
        glint = load("glint.png");
        for (int i = 0; i < ART_CACHE; i++) {
            artId[i] = -1;
        }
        for (int i = 0; i < BIG_CACHE; i++) {
            bigId[i] = -1;
        }
    }

    /** Returns the background, loading it and dropping the previous one. */
    public static Image bg(String name) {
        if (name.equals(bgName) && bgImg != null) {
            return bgImg;
        }
        bgImg = null;
        bgName = null;
        System.gc();
        bgImg = load(name);
        bgName = name;
        return bgImg;
    }

    public static Image art(int id) {
        int free = 0;
        int oldest = Integer.MAX_VALUE;
        for (int i = 0; i < ART_CACHE; i++) {
            if (artId[i] == id && artImg[i] != null) {
                artUse[i] = ++useClock;
                return artImg[i];
            }
            if (artUse[i] < oldest) {
                oldest = artUse[i];
                free = i;
            }
        }
        artImg[free] = null;
        Image im = load("c/" + id + ".png");
        artId[free] = id;
        artImg[free] = im;
        artUse[free] = ++useClock;
        return im;
    }

    /** 2x nearest-neighbour scaled illustration (48x48). */
    public static Image artBig(int id) {
        int free = 0;
        int oldest = Integer.MAX_VALUE;
        for (int i = 0; i < BIG_CACHE; i++) {
            if (bigId[i] == id && bigImg[i] != null) {
                bigUse[i] = ++useClock;
                return bigImg[i];
            }
            if (bigUse[i] < oldest) {
                oldest = bigUse[i];
                free = i;
            }
        }
        Image src = art(id);
        if (src == null) {
            return null;
        }
        int w = src.getWidth(), h = src.getHeight();
        if (scaleBuf == null || scaleBuf.length < w * h * 5) {
            scaleBuf = new int[w * h * 5];
        }
        int[] buf = scaleBuf;
        src.getRGB(buf, 0, w, 0, 0, w, h);
        int ow = w * 2, oh = h * 2;
        int[] out = new int[ow * oh];
        for (int y = 0; y < oh; y++) {
            int sr = (y >> 1) * w;
            int dr = y * ow;
            for (int x = 0; x < ow; x++) {
                out[dr + x] = buf[sr + (x >> 1)];
            }
        }
        bigImg[free] = null;
        Image im = Image.createRGBImage(out, ow, oh, true);
        bigId[free] = id;
        bigImg[free] = im;
        bigUse[free] = ++useClock;
        return im;
    }

    public static void icon(Graphics g, int idx, int x, int y) {
        if (icons != null) {
            g.drawRegion(icons, idx * 12, 0, 12, 12, 0, x, y, Graphics.TOP | Graphics.LEFT);
        }
    }

    public static void symbol(Graphics g, int s, int x, int y, boolean blur) {
        Image im = blur && symBlur != null ? symBlur : sym;
        if (im != null) {
            g.drawRegion(im, s * 36, 0, 36, 36, 0, x, y, Graphics.TOP | Graphics.LEFT);
        }
    }

    /** Releases caches before memory-hungry work. */
    public static void trim() {
        for (int i = 0; i < BIG_CACHE; i++) {
            bigImg[i] = null;
            bigId[i] = -1;
        }
        System.gc();
    }
}
