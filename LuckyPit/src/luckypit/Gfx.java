package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Shared drawing helpers: panels, buttons, cards, soft key bar. */
public final class Gfx {
    public static final int W = 240, H = 320;
    public static final int TL = Graphics.TOP | Graphics.LEFT;
    public static final int[] RARITY_RGB = {0x9A9AA0, 0x5CBF5A, 0x4A90E0, 0xB070D8, 0xF0C850, 0xE0302E};
    public static final int[] RARITY_FONT = {PixelFont.GRAY, PixelFont.GREEN, PixelFont.WHITE, PixelFont.CREAM,
            PixelFont.GOLD, PixelFont.RED};

    private static Image dim;

    private Gfx() {
    }

    public static void init() {
        int[] px = new int[W * 8];
        for (int i = 0; i < px.length; i++) {
            px[i] = 0xA0080406;
        }
        dim = Image.createRGBImage(px, W, 8, true);
    }

    /** Darkens the whole screen (for overlays). */
    public static void dim(Graphics g) {
        if (dim == null) {
            return;
        }
        for (int y = 0; y < H; y += 8) {
            g.drawImage(dim, 0, y, TL);
        }
    }

    /** 9-slice gold panel. */
    public static void panel(Graphics g, int x, int y, int w, int h) {
        Image p = ResourceManager.panel;
        if (p == null) {
            g.setColor(0x1A0A0C);
            g.fillRect(x, y, w, h);
            g.setColor(0xC8A050);
            g.drawRect(x, y, w - 1, h - 1);
            return;
        }
        // fill centre
        g.setColor(0x1C0E10);
        g.fillRect(x + 4, y + 4, w - 8, h - 8);
        // edges (tile the 8px middle slice)
        for (int xx = x + 8; xx < x + w - 8; xx += 8) {
            int cw = Math.min(8, x + w - 8 - xx);
            g.drawRegion(p, 8, 0, cw, 8, 0, xx, y, TL);
            g.drawRegion(p, 8, 16, cw, 8, 0, xx, y + h - 8, TL);
        }
        for (int yy = y + 8; yy < y + h - 8; yy += 8) {
            int ch = Math.min(8, y + h - 8 - yy);
            g.drawRegion(p, 0, 8, 8, ch, 0, x, yy, TL);
            g.drawRegion(p, 16, 8, 8, ch, 0, x + w - 8, yy, TL);
        }
        g.drawRegion(p, 0, 0, 8, 8, 0, x, y, TL);
        g.drawRegion(p, 16, 0, 8, 8, 0, x + w - 8, y, TL);
        g.drawRegion(p, 0, 16, 8, 8, 0, x, y + h - 8, TL);
        g.drawRegion(p, 16, 16, 8, 8, 0, x + w - 8, y + h - 8, TL);
    }

    /** Red ribbon with a centred title. */
    public static void banner(Graphics g, String title, int cy) {
        Image b = ResourceManager.banner;
        if (b != null) {
            g.drawImage(b, W / 2, cy, Graphics.TOP | Graphics.HCENTER);
        }
        PixelFont.shadow(g, title, W / 2, cy + 4, PixelFont.GOLD, Graphics.HCENTER);
    }

    /** Menu button (168x20). */
    public static void button(Graphics g, String label, int cx, int y, boolean sel, boolean enabled) {
        Image b = ResourceManager.button;
        if (b != null) {
            g.drawRegion(b, 0, sel ? 20 : 0, 168, 20, 0, cx - 84, y, TL);
        }
        int c = !enabled ? PixelFont.GRAY : (sel ? PixelFont.WHITE : PixelFont.CREAM);
        PixelFont.shadow(g, label, cx, y + 5, c, Graphics.HCENTER);
    }

    /** Soft key labels on the bottom bar. */
    public static void softkeys(Graphics g, String left, String right) {
        if (left != null) {
            PixelFont.shadow(g, left, 4, 307, PixelFont.GOLD, Graphics.LEFT);
        }
        if (right != null) {
            PixelFont.shadow(g, right, W - 4, 307, PixelFont.GOLD, Graphics.RIGHT);
        }
    }

    public static void softbar(Graphics g) {
        g.setColor(0x0B0708);
        g.fillRect(0, 304, W, 16);
        g.setColor(0x966C28);
        g.drawLine(0, 303, W, 303);
    }

    /** Small card: rarity frame 28x28 with 24x24 art. */
    public static void card(Graphics g, int id, int x, int y) {
        Card c = CardManager.get(id);
        if (c == null) {
            return;
        }
        if (ResourceManager.frames != null) {
            g.drawRegion(ResourceManager.frames, c.rarity * 28, 0, 28, 28, 0, x, y, TL);
        }
        Image a = ResourceManager.art(id);
        if (a != null) {
            g.drawImage(a, x + 2, y + 2, TL);
        }
    }

    public static void emptySlot(Graphics g, int x, int y, boolean locked) {
        if (ResourceManager.slots != null) {
            g.drawRegion(ResourceManager.slots, locked ? 28 : 0, 0, 28, 28, 0, x, y, TL);
        }
    }

    /** Big card (52x52): 2x art inside a two-pixel rarity border. */
    public static void cardBig(Graphics g, int id, int x, int y, boolean known) {
        Card c = CardManager.get(id);
        if (c == null) {
            return;
        }
        int rgb = RARITY_RGB[c.rarity];
        g.setColor(0x000000);
        g.drawRect(x, y, 51, 51);
        g.setColor(rgb);
        g.drawRect(x + 1, y + 1, 49, 49);
        g.setColor(darker(rgb));
        g.drawRect(x + 2, y + 2, 47, 47);
        g.setColor(0x000000);
        g.fillRect(x + 3, y + 3, 46, 46);
        if (known) {
            Image a = ResourceManager.artBig(id);
            if (a != null) {
                g.setClip(x + 3, y + 3, 46, 46);
                g.drawImage(a, x + 2, y + 2, TL);
                g.setClip(0, 0, W, H);
            }
        } else {
            PixelFont.draw(g, "?", x + 26, y + 20, PixelFont.GRAY, Graphics.HCENTER);
        }
    }

    public static int darker(int rgb) {
        return ((rgb >> 1) & 0x7F7F7F);
    }

    public static void cursor(Graphics g, int x, int y, int t) {
        Image c = ResourceManager.cursor;
        if (c == null) {
            g.setColor(0xFFF0C0);
            g.drawRect(x - 2, y - 2, 31, 31);
            return;
        }
        int o = ((t >> 7) & 1);
        g.drawImage(c, x - 2 - o, y - 2 - o, TL);
        if (o == 1) {
            g.drawRegion(c, 16, 16, 16, 16, 0, x + 14 + o, y + 14 + o, TL);
        }
    }

    /** Coin and token counters. */
    public static void money(Graphics g, int coins, int tokens, int rx, int y) {
        int w = PixelFont.numShadow(g, tokens, (char) 0, (char) 0, rx, y + 1, PixelFont.CYANISH, Graphics.RIGHT);
        ResourceManager.icon(g, ResourceManager.I_TOKEN, rx - w - 14, y);
        int x2 = rx - w - 20;
        int w2 = PixelFont.numShadow(g, coins, (char) 0, (char) 0, x2, y + 1, PixelFont.GOLD, Graphics.RIGHT);
        ResourceManager.icon(g, ResourceManager.I_COIN, x2 - w2 - 14, y);
    }

    /** Rarity + family line. */
    public static String kind(Card c) {
        return Card.RARITY[c.rarity] + " · " + Card.FAMILY[c.family];
    }
}
