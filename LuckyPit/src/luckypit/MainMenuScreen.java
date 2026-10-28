package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Main menu. */
public final class MainMenuScreen extends Screen {
    private static final int A_CONTINUE = 0, A_NEW = 1, A_ALMANAC = 2, A_STATS = 3, A_SETTINGS = 4, A_HELP = 5,
            A_EXIT = 6;
    private static final String[] LABEL = {"Продолжить", "Новая игра", "Альманах карт", "Статистика", "Настройки",
            "Справка", "Выход"};
    private final int[] items = new int[7];
    private int count, sel;

    public void enter() {
        count = 0;
        if (mm.hasSave && mm.game.active) {
            items[count++] = A_CONTINUE;
        }
        for (int a = A_NEW; a <= A_EXIT; a++) {
            items[count++] = a;
        }
        if (sel >= count) {
            sel = 0;
        }
    }

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_menu.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        // twinkling marquee bulbs around the logo
        Image l = ResourceManager.lamps;
        if (l != null) {
            for (int i = 0; i < 10; i++) {
                int x = 44 + i * 17;
                int f = ((i + time / 180) % 3 == 0) ? 1 : 0;
                g.drawRegion(l, f * 6, 0, 6, 6, 0, x, 24, Gfx.TL);
                g.drawRegion(l, (1 - f) * 6, 0, 6, 6, 0, x, 108, Gfx.TL);
            }
        }
        int y0 = 124;
        for (int i = 0; i < count; i++) {
            Gfx.button(g, LABEL[items[i]], 120, y0 + i * 24, i == sel, true);
        }
        Gfx.softkeys(g, "Выбрать", "Выход");
        PixelFont.draw(g, "v1.0", 236, 292, PixelFont.GRAY, Graphics.RIGHT);
    }

    public void key(int k) {
        switch (k) {
            case K_UP:
                sel = (sel + count - 1) % count;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_DOWN:
                sel = (sel + 1) % count;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_FIRE:
            case K_LSOFT:
                act(items[sel]);
                break;
            case K_RSOFT:
                mm.confirm("Выйти из игры?", this, A_EXIT);
                break;
            case K_9:
                mm.open(new StatsScreen(), this);
                break;
            case K_0:
                mm.open(new HelpScreen(), this);
                break;
            case K_1:
                mm.open(new CardsScreen(true), this);
                break;
            default:
                break;
        }
    }

    private void act(int a) {
        mm.sfx(SoundManager.OK);
        switch (a) {
            case A_CONTINUE:
                mm.gameScreen.resetReels();
                mm.flow();
                break;
            case A_NEW:
                if (mm.hasSave && mm.game.active) {
                    mm.confirm("Начать заново? Текущий забег будет потерян.", this, A_NEW);
                } else {
                    mm.newRun();
                }
                break;
            case A_ALMANAC:
                mm.open(new CardsScreen(true), this);
                break;
            case A_STATS:
                mm.open(new StatsScreen(), this);
                break;
            case A_SETTINGS:
                mm.open(new SettingsScreen(), this);
                break;
            case A_HELP:
                mm.open(new HelpScreen(), this);
                break;
            default:
                mm.exit();
                break;
        }
    }

    public void confirmed(int action) {
        if (action == A_NEW) {
            mm.stats.losses++;
            mm.newRun();
        } else if (action == A_EXIT) {
            mm.exit();
        }
    }
}
