package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Title splash with the virtual-coins notice. */
public final class SplashScreen extends Screen {
    private String[] note;

    public void enter() {
        note = PixelFont.wrap("Игра только на виртуальные монеты. Никаких реальных ставок, платежей и выигрышей.", 200);
    }

    public void update(int dt) {
        super.update(dt);
        if (time > 3200) {
            mm.go(mm.mainMenu);
        }
    }

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_menu.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        for (int i = 0; i < 3; i++) {
            ResourceManager.symbol(g, i == 0 ? Symbol.CHERRY : (i == 1 ? Symbol.SEVEN : Symbol.CLOVER),
                    66 + i * 38, 140 + ((time / 200 + i) % 2), false);
        }
        PixelFont.shadow(g, "Яма удачи", 120, 190, PixelFont.CREAM, Graphics.HCENTER);
        for (int i = 0; i < note.length; i++) {
            PixelFont.shadow(g, note[i], 120, 226 + i * PixelFont.LINE, PixelFont.GRAY, Graphics.HCENTER);
        }
        if (((time / 400) & 1) == 0) {
            PixelFont.shadow(g, "Нажмите любую клавишу", 120, 284, PixelFont.GOLD, Graphics.HCENTER);
        }
    }

    public void key(int k) {
        if (time > 300) {
            mm.sfx(SoundManager.OK);
            mm.go(mm.mainMenu);
        }
    }
}
