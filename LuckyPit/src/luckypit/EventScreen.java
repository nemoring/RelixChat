package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** A random event with two choices. */
public final class EventScreen extends Screen {
    private int sel;
    private String[] text;
    private String detail;
    private String outcome;
    private String[] outLines;
    private int id;
    private int artId = -1;

    public void enter() {
        if (text != null) {
            return;
        }
        GameState g = mm.game;
        id = g.eventId;
        if (id < 0) {
            Shop.open(g, mm.mods);
            mm.flow();
            return;
        }
        text = PixelFont.wrap(EventManager.TEXT[id], 196);
        artId = CardManager.find(EventManager.ART[id]);
        detail = EventManager.detail(g);
        mm.sfx(SoundManager.MAGIC);
    }

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        PixelFont.shadow(g, "СОБЫТИЕ", 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        if (text == null) {
            return;
        }
        Gfx.banner(g, EventManager.TITLE[id], 36);
        // illustration: a card back / motif per event
        if (artId >= 0) {
            Gfx.cardBig(g, artId, 94, 62, true);
        }
        for (int i = 0; i < text.length; i++) {
            PixelFont.shadow(g, text[i], 120, 122 + i * PixelFont.LINE, PixelFont.CREAM, Graphics.HCENTER);
        }
        int y = 124 + text.length * PixelFont.LINE + 4;
        if (detail != null && detail.length() > 0) {
            PixelFont.shadow(g, detail, 120, y, PixelFont.GOLD, Graphics.HCENTER);
        }
        if (outcome == null) {
            Gfx.button(g, EventManager.OPT_A[id], 120, 230, sel == 0, true);
            if (EventManager.hasB(id)) {
                Gfx.button(g, EventManager.OPT_B[id], 120, 256, sel == 1, true);
            }
        } else {
            Gfx.panel(g, 16, 222, 208, 20 + outLines.length * PixelFont.LINE);
            for (int i = 0; i < outLines.length; i++) {
                PixelFont.shadow(g, outLines[i], 120, 232 + i * PixelFont.LINE, PixelFont.GOLD, Graphics.HCENTER);
            }
        }
        Fx.paint(g, time);
        Gfx.softkeys(g, outcome == null ? "Выбрать" : "Дальше", outcome == null ? "Карты" : null);
    }

    public void key(int k) {
        GameState g = mm.game;
        if (text == null) {
            return;
        }
        if (outcome != null) {
            if (k == K_FIRE || k == K_LSOFT || k == K_7) {
                mm.sfx(SoundManager.OK);
                mm.flow();
            }
            return;
        }
        switch (k) {
            case K_UP:
            case K_DOWN:
                if (EventManager.hasB(id)) {
                    sel = 1 - sel;
                    mm.sfx(SoundManager.MOVE);
                }
                break;
            case K_FIRE:
            case K_LSOFT:
                outcome = EventManager.choose(g, sel == 0);
                outLines = PixelFont.wrap(outcome, 196);
                Shop.open(g, mm.mods);
                mm.save();
                mm.sfx(SoundManager.BUY);
                Fx.sparks(120, 230, 14, 0xF0C850);
                break;
            case K_RSOFT:
            case K_1:
                mm.open(new CardsScreen(false), this);
                break;
            case K_0:
                mm.open(new HelpScreen(), this);
                break;
            default:
                break;
        }
    }
}
