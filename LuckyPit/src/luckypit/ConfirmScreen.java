package luckypit;

import javax.microedition.lcdui.Graphics;

/** Yes/No dialog drawn over the screen that asked. */
public final class ConfirmScreen extends Screen {
    String text;
    Screen owner;
    int action;
    int sel;
    private String[] lines;
    private String wrapped;

    public void paint(Graphics g) {
        if (owner != null) {
            owner.paint(g);
        }
        Gfx.dim(g);
        if (wrapped != text) {
            lines = PixelFont.wrap(text, 180);
            wrapped = text;
        }
        int h = 52 + lines.length * PixelFont.LINE;
        int y = 160 - h / 2;
        Gfx.panel(g, 20, y, 200, h);
        for (int i = 0; i < lines.length; i++) {
            PixelFont.shadow(g, lines[i], 120, y + 12 + i * PixelFont.LINE, PixelFont.CREAM, Graphics.HCENTER);
        }
        int by = y + h - 28;
        drawBtn(g, "Да", 74, by, sel == 0);
        drawBtn(g, "Нет", 166, by, sel == 1);
        Gfx.softbar(g);
        Gfx.softkeys(g, "Выбрать", "Нет");
    }

    private void drawBtn(Graphics g, String s, int cx, int y, boolean on) {
        g.setColor(on ? 0xB0262C : 0x3A2416);
        g.fillRect(cx - 34, y, 68, 18);
        g.setColor(on ? 0xF0D282 : 0x96702C);
        g.drawRect(cx - 34, y, 67, 17);
        PixelFont.shadow(g, s, cx, y + 4, on ? PixelFont.WHITE : PixelFont.CREAM, Graphics.HCENTER);
    }

    public void key(int k) {
        switch (k) {
            case K_LEFT:
            case K_RIGHT:
            case K_UP:
            case K_DOWN:
                sel = 1 - sel;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_FIRE:
            case K_LSOFT:
                mm.resume(owner);
                if (sel == 0) {
                    owner.confirmed(action);
                } else {
                    mm.sfx(SoundManager.MOVE);
                }
                break;
            case K_RSOFT:
                mm.sfx(SoundManager.MOVE);
                mm.resume(owner);
                break;
            default:
                break;
        }
    }
}
