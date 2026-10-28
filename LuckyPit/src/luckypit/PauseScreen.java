package luckypit;

import javax.microedition.lcdui.Graphics;

/** In-game pause menu drawn over the machine. */
public final class PauseScreen extends Screen {
    Screen under;
    private int sel;
    private static final String[] ITEMS = {"Продолжить", "Мои карты", "Об автомате", "Настройки", "Справка",
            "В главное меню"};

    public boolean music() {
        return false;
    }

    public void paint(Graphics g) {
        if (under != null) {
            under.paint(g);
        }
        Gfx.dim(g);
        Gfx.panel(g, 26, 62, 188, 184);
        Gfx.banner(g, "Пауза", 52);
        for (int i = 0; i < ITEMS.length; i++) {
            Gfx.button(g, ITEMS[i], 120, 80 + i * 26, i == sel, true);
        }
        PixelFont.draw(g, "Прогресс сохраняется сам", 120, 250, PixelFont.GRAY, Graphics.HCENTER);
        Gfx.softbar(g);
        Gfx.softkeys(g, "Выбрать", "Назад");
    }

    public void key(int k) {
        switch (k) {
            case K_UP:
                sel = (sel + ITEMS.length - 1) % ITEMS.length;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_DOWN:
                sel = (sel + 1) % ITEMS.length;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_RSOFT:
                mm.switchTo(under);
                break;
            case K_FIRE:
            case K_LSOFT:
                mm.sfx(SoundManager.OK);
                switch (sel) {
                    case 0:
                        mm.switchTo(under);
                        break;
                    case 1:
                        mm.open(new CardsScreen(false), under);
                        break;
                    case 2:
                        mm.open(new InfoScreen(), under);
                        break;
                    case 3:
                        mm.open(new SettingsScreen(), under);
                        break;
                    case 4:
                        mm.open(new HelpScreen(), under);
                        break;
                    default:
                        mm.save();
                        mm.go(mm.mainMenu);
                        break;
                }
                break;
            default:
                break;
        }
    }
}
