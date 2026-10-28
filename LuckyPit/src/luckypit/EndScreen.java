package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Victory endings and defeat. */
public final class EndScreen extends Screen {
    private static final String[] TITLE = {"", "СВОБОДА", "ВЛАДЕЛЕЦ ЯМЫ", "ПРОКЛЯТЫЙ ХОЗЯИН", "ЯМА ПОГЛОТИЛА ВАС"};
    private static final String[] TEXT = {"",
            "Последний долг оплачен. Ржавая дверь со скрипом открывается, и вы выходите на рассвет с "
                    + "пустыми карманами, но свободным.",
            "Вы не просто расплатились — у вас осталось вдвое больше, чем весь последний долг. Вы выкупаете "
                    + "Яму вместе с автоматом. Теперь долги платят вам.",
            "Долги выплачены, но проклятые карты вросли в ладони. Вы садитесь за стойку вместо прежнего "
                    + "хозяина. Автомат ласково звенит: он нашёл нового сторожа.",
            "Монет не хватило. Пол под автоматом проваливается, и Яма забирает ещё одну душу. "
                    + "Может быть, в следующий раз удача будет на вашей стороне."};
    private String[] lines;
    private int ending;

    private boolean inited;

    public void enter() {
        if (inited) {
            return;
        }
        inited = true;
        ending = mm.game.ending;
        if (ending < 1 || ending > 4) {
            ending = 4;
        }
        lines = PixelFont.wrap(TEXT[ending], 210);
        mm.sfx(ending == GameState.END_LOST ? SoundManager.CURSE : SoundManager.JACKPOT);
        SaveManager.saveStats(mm.stats);
        mm.hasSave = false;
    }

    public void update(int dt) {
        super.update(dt);
        if (ending != GameState.END_LOST && ending != GameState.END_CURSED && (time % 600) < dt) {
            Fx.coins(20 + (time / 7) % 200, 330, 4, 120, 40);
        }
    }

    public void paint(Graphics g) {
        boolean lose = ending == GameState.END_LOST || ending == GameState.END_CURSED;
        Image bg = ResourceManager.bg(lose ? "bg_lose.png" : "bg_win.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        Fx.paint(g, time);
        Gfx.banner(g, TITLE[ending], 16);
        Gfx.panel(g, 10, 44, 220, 22 + lines.length * PixelFont.LINE);
        for (int i = 0; i < lines.length; i++) {
            PixelFont.draw(g, lines[i], 120, 54 + i * PixelFont.LINE, PixelFont.CREAM, Graphics.HCENTER);
        }
        GameState gs = mm.game;
        int y = 66 + lines.length * PixelFont.LINE + 10;
        Gfx.panel(g, 30, y, 180, 82);
        y += 10;
        row(g, y, "Сроков оплачено", gs.ending == GameState.END_LOST ? gs.deadline : GameState.DEADLINES);
        row(g, y + 13, "Прокруток", gs.runSpins);
        row(g, y + 26, "Выиграно", gs.runWon);
        row(g, y + 39, "Лучшая прокрутка", gs.runBestWin);
        row(g, y + 52, "Джекпотов", gs.runJackpots);
        if (((time / 500) & 1) == 0) {
            PixelFont.outline(g, "5 — новый забег", 120, 280, PixelFont.GOLD, Graphics.HCENTER);
        }
        Gfx.softkeys(g, "Заново", "Меню");
    }

    private void row(Graphics g, int y, String a, int v) {
        PixelFont.draw(g, a, 40, y, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.num(g, v, (char) 0, (char) 0, 200, y, PixelFont.GOLD, Graphics.RIGHT);
    }

    public void key(int k) {
        if (time < 600) {
            return;
        }
        if (k == K_FIRE || k == K_LSOFT) {
            mm.sfx(SoundManager.OK);
            mm.newRun();
        } else if (k == K_RSOFT) {
            mm.go(mm.mainMenu);
        } else if (k == K_9) {
            mm.open(new StatsScreen(), this);
        }
    }
}
