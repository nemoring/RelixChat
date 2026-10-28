package luckypit;

import java.io.DataInputStream;
import java.io.InputStream;
import java.util.Vector;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/**
 * Proportional bitmap font with Cyrillic. The white glyph sheet is recoloured
 * once at start-up into a few palette colours, so drawing is just one
 * drawRegion per character and never allocates.
 */
public final class PixelFont {
    public static final int CREAM = 0, GOLD = 1, RED = 2, GRAY = 3, DARK = 4, GREEN = 5, WHITE = 6, CYANISH = 7;
    private static final int[] RGB = {0xF0E2C0, 0xF0C850, 0xF05A46, 0x9A9092, 0x0B0708, 0x8CF070, 0xFFF8E8, 0x8CDCF0};
    public static final int HEIGHT = 11;
    public static final int LINE = 12;

    private static Image[] sheet = new Image[RGB.length];
    private static char[] codes;
    private static short[] gx;
    private static byte[] gy, gw;
    /** Direct lookup for code points below 0x460 (Latin + Cyrillic). */
    private static short[] table = new short[0x460];
    private static int qIdx;
    private static final char[] NUM = new char[12];

    private PixelFont() {
    }

    public static void init() {
        try {
            InputStream is = PixelFont.class.getResourceAsStream("/font.bin");
            DataInputStream in = new DataInputStream(is);
            int n = in.readUnsignedShort();
            codes = new char[n];
            gx = new short[n];
            gy = new byte[n];
            gw = new byte[n];
            for (int i = 0; i < table.length; i++) {
                table[i] = -1;
            }
            for (int i = 0; i < n; i++) {
                codes[i] = (char) in.readUnsignedShort();
                gx[i] = (short) in.readUnsignedShort();
                gy[i] = (byte) in.readUnsignedByte();
                gw[i] = (byte) in.readUnsignedByte();
                if (codes[i] < table.length) {
                    table[codes[i]] = (short) i;
                }
            }
            in.close();
            qIdx = table['?'];
            Image src = Image.createImage("/font.png");
            int w = src.getWidth(), h = src.getHeight();
            int[] px = new int[w * h];
            src.getRGB(px, 0, w, 0, 0, w, h);
            src = null;
            for (int c = 0; c < RGB.length; c++) {
                int[] out = new int[w * h];
                int col = 0xFF000000 | RGB[c];
                for (int i = 0; i < px.length; i++) {
                    out[i] = (px[i] >>> 24) > 0x7F ? col : 0;
                }
                sheet[c] = Image.createRGBImage(out, w, h, true);
            }
        } catch (Throwable t) {
            codes = new char[0];
        }
    }

    private static int glyph(char ch) {
        if (ch < table.length) {
            int i = table[ch];
            return i >= 0 ? i : qIdx;
        }
        for (int i = codes.length - 1; i >= 0; i--) {
            if (codes[i] == ch) {
                return i;
            }
        }
        return qIdx;
    }

    public static int charWidth(char ch) {
        if (ch == ' ') {
            return 3;
        }
        int i = glyph(ch);
        return i < 0 ? 4 : gw[i] + 1;
    }

    public static int width(String s) {
        int w = 0;
        for (int i = 0, n = s.length(); i < n; i++) {
            w += charWidth(s.charAt(i));
        }
        return w > 0 ? w - 1 : 0;
    }

    private static int width(char[] s, int off, int len) {
        int w = 0;
        for (int i = 0; i < len; i++) {
            w += charWidth(s[off + i]);
        }
        return w > 0 ? w - 1 : 0;
    }

    /** anchor: Graphics.LEFT / HCENTER / RIGHT; y is the top of the line. */
    public static void draw(Graphics g, String s, int x, int y, int color, int anchor) {
        if (s == null) {
            return;
        }
        if ((anchor & Graphics.HCENTER) != 0) {
            x -= width(s) / 2;
        } else if ((anchor & Graphics.RIGHT) != 0) {
            x -= width(s);
        }
        Image im = sheet[color];
        if (im == null) {
            return;
        }
        for (int i = 0, n = s.length(); i < n; i++) {
            char ch = s.charAt(i);
            if (ch == ' ') {
                x += 3;
                continue;
            }
            int gi = glyph(ch);
            if (gi < 0) {
                continue;
            }
            int w = gw[gi];
            g.drawRegion(im, gx[gi], gy[gi], w, HEIGHT, 0, x, y, Graphics.TOP | Graphics.LEFT);
            x += w + 1;
        }
    }

    private static void drawChars(Graphics g, char[] s, int off, int len, int x, int y, int color) {
        Image im = sheet[color];
        if (im == null) {
            return;
        }
        for (int i = 0; i < len; i++) {
            char ch = s[off + i];
            if (ch == ' ') {
                x += 3;
                continue;
            }
            int gi = glyph(ch);
            int w = gw[gi];
            g.drawRegion(im, gx[gi], gy[gi], w, HEIGHT, 0, x, y, Graphics.TOP | Graphics.LEFT);
            x += w + 1;
        }
    }

    /** Text with a 1px dark drop shadow. */
    public static void shadow(Graphics g, String s, int x, int y, int color, int anchor) {
        draw(g, s, x + 1, y + 1, DARK, anchor);
        draw(g, s, x, y, color, anchor);
    }

    /** Dark outline all around (for text over busy art). */
    public static void outline(Graphics g, String s, int x, int y, int color, int anchor) {
        draw(g, s, x - 1, y, DARK, anchor);
        draw(g, s, x + 1, y, DARK, anchor);
        draw(g, s, x, y - 1, DARK, anchor);
        draw(g, s, x, y + 1, DARK, anchor);
        draw(g, s, x, y, color, anchor);
    }

    /** Draws an integer without allocating. prefix/suffix chars optional (0 = none). */
    public static int num(Graphics g, int v, char prefix, char suffix, int x, int y, int color, int anchor) {
        int len = fmt(v, prefix, suffix);
        int off = NUM.length - len;
        int w = width(NUM, off, len);
        if ((anchor & Graphics.HCENTER) != 0) {
            x -= w / 2;
        } else if ((anchor & Graphics.RIGHT) != 0) {
            x -= w;
        }
        drawChars(g, NUM, off, len, x, y, color);
        return w;
    }

    public static int numShadow(Graphics g, int v, char prefix, char suffix, int x, int y, int color, int anchor) {
        num(g, v, prefix, suffix, x + 1, y + 1, DARK, anchor);
        return num(g, v, prefix, suffix, x, y, color, anchor);
    }

    private static int fmt(int v, char prefix, char suffix) {
        int p = NUM.length;
        if (suffix != 0) {
            NUM[--p] = suffix;
        }
        boolean neg = v < 0;
        long u = neg ? -(long) v : v;
        do {
            NUM[--p] = (char) ('0' + (int) (u % 10));
            u /= 10;
        } while (u > 0 && p > 1);
        if (neg) {
            NUM[--p] = '-';
        }
        if (prefix != 0 && p > 0) {
            NUM[--p] = prefix;
        }
        return NUM.length - p;
    }

    /** Word-wraps text to a pixel width. '\n' forces a break. */
    public static String[] wrap(String text, int maxW) {
        Vector lines = new Vector();
        int start = 0;
        int n = text.length();
        while (start < n) {
            int lineEnd = start;
            int lastSpace = -1;
            int w = 0;
            int i = start;
            boolean hardBreak = false;
            while (i < n) {
                char ch = text.charAt(i);
                if (ch == '\n') {
                    hardBreak = true;
                    break;
                }
                int cw = charWidth(ch);
                if (w + cw - 1 > maxW && i > start) {
                    break;
                }
                if (ch == ' ') {
                    lastSpace = i;
                }
                w += cw;
                i++;
            }
            if (i >= n || hardBreak) {
                lineEnd = i;
                lines.addElement(text.substring(start, lineEnd));
                start = hardBreak ? i + 1 : i;
                continue;
            }
            if (lastSpace > start) {
                lineEnd = lastSpace;
                lines.addElement(text.substring(start, lineEnd));
                start = lastSpace + 1;
            } else {
                lineEnd = i;
                lines.addElement(text.substring(start, lineEnd));
                start = i;
            }
        }
        String[] out = new String[lines.size()];
        lines.copyInto(out);
        return out;
    }

    /** Draws pre-wrapped lines. */
    public static void lines(Graphics g, String[] ls, int x, int y, int color, int maxLines) {
        int n = ls.length < maxLines ? ls.length : maxLines;
        for (int i = 0; i < n; i++) {
            draw(g, ls[i], x, y + i * LINE, color, Graphics.LEFT);
        }
    }

    /** Short number form: 12345 -> 12.3K. */
    public static String shortNum(int v) {
        if (v < 10000) {
            return Integer.toString(v);
        }
        if (v < 1000000) {
            return (v / 1000) + "." + ((v / 100) % 10) + "K";
        }
        return (v / 1000000) + "." + ((v / 100000) % 10) + "M";
    }
}
