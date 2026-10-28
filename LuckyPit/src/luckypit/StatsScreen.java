package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Lifetime statistics and the current run. */
public final class StatsScreen extends BackScreen {
    private static final String[] END_NAME = {"", "Свобода", "Владелец Ямы", "Проклятый хозяин", "Поглощён Ямой"};

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        PixelFont.shadow(g, "СТАТИСТИКА", 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        Stats s = mm.stats;
        int y = 36;
        y = row(g, y, "Забегов начато", s.runs);
        y = row(g, y, "Побед", s.wins);
        y = row(g, y, "Поражений", s.losses);
        y = row(g, y, "Лучший срок", s.bestDeadline);
        y = row(g, y, "Всего прокруток", s.totalSpins);
        y = row(g, y, "Джекпотов", s.jackpots);
        y = row(g, y, "Крупнейший выигрыш", s.biggestWin);
        y = row(g, y, "Больше всего монет", s.maxCoins);
        y = row(g, y, "Выиграно всего", s.totalWon);
        y = row(g, y, "Куплено карт", s.cardsBought);
        y = row(g, y, "Проклятий черепов", s.curses);
        y = row(g, y, "Открыто карт", s.discoveredCount());
        y += 4;
        PixelFont.draw(g, "Концовки:", 12, y, PixelFont.GOLD, Graphics.LEFT);
        y += 12;
        for (int e = 1; e <= 4; e++) {
            boolean got = (s.endings & (1 << e)) != 0;
            PixelFont.draw(g, (got ? "★ " : "· ") + (got ? END_NAME[e] : "???"), 20 + ((e - 1) % 2) * 106,
                    y + ((e - 1) / 2) * 12, got ? PixelFont.CREAM : PixelFont.GRAY, Graphics.LEFT);
        }
        y += 28;
        GameState gs = mm.game;
        if (gs.active) {
            PixelFont.draw(g, "Текущий забег: срок " + (gs.deadline + 1) + ", прокруток " + gs.runSpins,
                    12, y, PixelFont.GRAY, Graphics.LEFT);
        }
        Gfx.softkeys(g, null, "Назад");
    }

    private int row(Graphics g, int y, String a, int v) {
        PixelFont.draw(g, a, 12, y, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.num(g, v, (char) 0, (char) 0, 228, y, PixelFont.GOLD, Graphics.RIGHT);
        return y + 13;
    }

    public void key(int k) {
        if (k == K_RSOFT || k == K_FIRE || k == K_9) {
            goBack();
        }
    }
}
