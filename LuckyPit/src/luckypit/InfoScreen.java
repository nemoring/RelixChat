package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Machine information: payouts and odds, lines, current modifiers. */
public final class InfoScreen extends BackScreen {
    private static final String[] TABS = {"Выплаты", "Линии", "Автомат"};
    private int tab;
    private final int[] w = new int[Symbol.COUNT];
    private int sel;

    public void enter() {
        EffectManager.compute(mm.game, mm.mods);
        mm.machine.weights(mm.mods, w);
    }

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        PixelFont.shadow(g, "ОБ АВТОМАТЕ", 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        for (int i = 0; i < 3; i++) {
            int x = 8 + i * 76;
            boolean on = i == tab;
            g.setColor(on ? 0x7E1C24 : 0x2A1A12);
            g.fillRect(x, 30, 72, 15);
            g.setColor(on ? 0xF0D282 : 0x6B4A1A);
            g.drawRect(x, 30, 71, 14);
            PixelFont.draw(g, TABS[i], x + 36, 32, on ? PixelFont.WHITE : PixelFont.GRAY, Graphics.HCENTER);
        }
        switch (tab) {
            case 0:
                paintPay(g);
                break;
            case 1:
                paintLines(g);
                break;
            default:
                paintMods(g);
                break;
        }
        Gfx.softkeys(g, "# вкладка", "Назад");
    }

    private void paintPay(Graphics g) {
        EffectManager.Mods m = mm.mods;
        int total = 0;
        for (int s = 0; s < Symbol.COUNT; s++) {
            total += w[s];
        }
        for (int s = 0; s < Symbol.COUNT; s++) {
            int col = s / 5, row = s % 5;
            int x = 8 + col * 114, y = 50 + row * 42;
            if (s == sel) {
                g.setColor(0x3A1A14);
                g.fillRect(x - 2, y - 2, 112, 40);
            }
            ResourceManager.symbol(g, s, x, y, false);
            PixelFont.draw(g, Symbol.NAME[s], x + 40, y + 2, PixelFont.GOLD, Graphics.LEFT);
            if (s == Symbol.SKULL) {
                PixelFont.draw(g, "проклятие", x + 40, y + 13, PixelFont.RED, Graphics.LEFT);
            } else {
                PixelFont.draw(g, "×3: " + SlotMachine.value(m, s) + "¢", x + 40, y + 13, PixelFont.CREAM,
                        Graphics.LEFT);
            }
            int pm = total > 0 ? w[s] * 1000 / total : 0;
            PixelFont.draw(g, "шанс " + (pm / 10) + "." + (pm % 10) + "%", x + 40, y + 24, PixelFont.GRAY,
                    Graphics.LEFT);
        }
        String[] l = PixelFont.wrap(Symbol.NOTE[sel], 220);
        PixelFont.lines(g, l, 10, 262, PixelFont.CREAM, 3);
    }

    private void paintLines(Graphics g) {
        GameState gs = mm.game;
        for (int i = 0; i < SlotMachine.LINES.length; i++) {
            int col = i % 5, row = i / 5;
            int x = 14 + col * 44, y = 54 + row * 66;
            boolean on = gs.lineActive(i);
            for (int c = 0; c < 9; c++) {
                g.setColor(0x2A1A12);
                g.fillRect(x + (c % 3) * 10, y + (c / 3) * 10, 9, 9);
            }
            int[] cells = SlotMachine.LINES[i];
            g.setColor(on ? 0xF0C850 : 0x5E5658);
            for (int k = 0; k < 3; k++) {
                g.fillRect(x + (cells[k] % 3) * 10, y + (cells[k] / 3) * 10, 9, 9);
            }
            if (!on) {
                ResourceManager.icon(g, ResourceManager.I_LOCK, x + 9, y + 9);
            }
            PixelFont.draw(g, Integer.toString(i + 1), x + 14, y + 34, on ? PixelFont.CREAM : PixelFont.GRAY,
                    Graphics.HCENTER);
        }
        String[] l = PixelFont.wrap("Активно линий: " + gs.activeLines() + " из 10. Линии — три одинаковых символа "
                + "слева направо или сверху вниз. «Око» заменяет любой символ, кроме черепа. "
                + "V-линии и колонны открываются в магазине (вкладка «Автомат"
                + "»). Все 9 одинаковых — ДЖЕКПОТ ×10.", 216);
        PixelFont.lines(g, l, 12, 196, PixelFont.CREAM, 8);
    }

    private void paintMods(Graphics g) {
        GameState gs = mm.game;
        EffectManager.Mods m = mm.mods;
        int y = 52;
        y = row(g, y, "Активных линий", gs.activeLines() + "");
        y = row(g, y, "Прокруток за раунд", (GameState.BASE_SPINS + m.spins) + "");
        y = row(g, y, "Множитель (постоянный)", "+" + m.mult + "%");
        y = row(g, y, "Комбо за доп. линию", "+" + m.combo + "%");
        y = row(g, y, "Проценты в конце раунда", m.interest + "%");
        y = row(g, y, "Слоты для карт", CardManager.capacity(gs) + "");
        y = row(g, y, "Джекпот", "×" + SlotMachine.JACKPOT_MULT + (m.jackpot > 0 ? " +" + m.jackpot + "%" : ""));
        int need = 3 - m.scatterReduce;
        y = row(g, y, "Россыпь звёзд", "от " + (need < 2 ? 2 : need));
        y = row(g, y, "Защита от черепов", m.ward ? "есть" : "нет");
        y = row(g, y, "Скидка в магазине", m.discount + "%");
        y = row(g, y, "Долг меньше на", m.debtCut + "%");
        y = row(g, y, "Новый долг больше на", m.debtAdd + "%");
        y += 6;
        PixelFont.draw(g, "Улучшения:", 12, y, PixelFont.GOLD, Graphics.LEFT);
        y += 12;
        StringBuffer sb = new StringBuffer();
        for (int u = 0; u < GameState.UPGRADES; u++) {
            if (gs.upg[u] > 0) {
                sb.append(Shop.UPG_NAME[u]).append(' ').append(gs.upg[u]).append(", ");
            }
        }
        String s = sb.length() == 0 ? "пока нет" : sb.toString().substring(0, sb.length() - 2);
        PixelFont.lines(g, PixelFont.wrap(s, 216), 12, y, PixelFont.CREAM, 4);
    }

    private int row(Graphics g, int y, String a, String b) {
        PixelFont.draw(g, a, 12, y, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.draw(g, b, 228, y, PixelFont.GOLD, Graphics.RIGHT);
        return y + 13;
    }

    public void key(int k) {
        switch (k) {
            case K_RSOFT:
                goBack();
                break;
            case K_POUND:
            case K_LSOFT:
                tab = (tab + 1) % 3;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_UP:
                sel = (sel + Symbol.COUNT - 1) % Symbol.COUNT;
                break;
            case K_DOWN:
                sel = (sel + 1) % Symbol.COUNT;
                break;
            case K_LEFT:
            case K_RIGHT:
                sel = (sel + 5) % Symbol.COUNT;
                break;
            default:
                break;
        }
    }
}
