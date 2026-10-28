package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Owned cards with details, or the almanac of every card. */
public final class CardsScreen extends BackScreen {
    private final boolean almanac;
    private int sel;
    private int scroll;
    private int filter = -1;      // almanac family filter, -1 = all
    private boolean setsTab;
    private final int[] list = new int[256];
    private int listN;
    private String[] desc;
    private int descFor = -2;

    public CardsScreen(boolean almanac) {
        this.almanac = almanac;
    }

    public void enter() {
        rebuild();
    }

    private void rebuild() {
        listN = 0;
        int n = CardManager.count();
        for (int i = 0; i < n && listN < list.length; i++) {
            if (filter < 0 || CardManager.get(i).family == filter) {
                list[listN++] = i;
            }
        }
        if (sel >= listN) {
            sel = 0;
        }
    }

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        if (almanac) {
            paintAlmanac(g);
        } else if (setsTab) {
            paintSets(g);
        } else {
            paintOwned(g);
        }
        Gfx.softkeys(g, null, "Назад");
    }

    private void paintOwned(Graphics g) {
        GameState gs = mm.game;
        PixelFont.shadow(g, "МОИ КАРТЫ", 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        int cap = CardManager.capacity(gs);
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            int x = 4 + i * 29;
            if (gs.cards[i] >= 0) {
                Gfx.card(g, gs.cards[i], x, 36);
            } else {
                Gfx.emptySlot(g, x, 36, i >= cap);
            }
            if (i == sel) {
                Gfx.cursor(g, x, 36, time);
            }
        }
        PixelFont.draw(g, "Слоты: " + CardManager.ownedCount(gs) + "/" + cap + "   # — сеты", 120, 70,
                PixelFont.GRAY, Graphics.HCENTER);
        int id = gs.cards[sel];
        if (id < 0) {
            PixelFont.shadow(g, sel < cap ? "Пустой слот" : "Закрытый слот", 120, 130, PixelFont.GRAY,
                    Graphics.HCENTER);
            return;
        }
        Card c = CardManager.get(id);
        Gfx.cardBig(g, id, 14, 88, true);
        PixelFont.shadow(g, c.name, 74, 92, Gfx.RARITY_FONT[c.rarity], Graphics.LEFT);
        PixelFont.draw(g, Card.RARITY[c.rarity], 74, 106, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.draw(g, "Семья: " + Card.FAMILY[c.family], 74, 118, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.draw(g, "Слот " + (sel + 1) + " · раундов у вас: " + gs.cardAge[sel], 74, 130, PixelFont.GRAY,
                Graphics.LEFT);
        if (descFor != id) {
            desc = PixelFont.wrap(c.desc, 210);
            descFor = id;
        }
        PixelFont.lines(g, desc, 14, 150, PixelFont.CREAM, 6);
        int y = 150 + Math.min(6, desc.length) * PixelFont.LINE + 8;
        if (c.has(Op.GROW_SYM) || c.has(Op.NTH_WIN) || c.has(Op.LOSS_TOKEN)) {
            PixelFont.draw(g, "Счётчик: " + gs.cardCounter[sel], 14, y, PixelFont.GOLD, Graphics.LEFT);
            y += 12;
        }
        if (c.has(Op.MIRROR)) {
            int right = sel + 1 < GameState.MAX_SLOTS ? gs.cards[sel + 1] : -1;
            PixelFont.draw(g, right >= 0 ? "Копирует: " + CardManager.get(right).name : "Справа пусто — нечего копировать",
                    14, y, PixelFont.CYANISH, Graphics.LEFT);
            y += 12;
        }
        String sv = c.rarity == Card.CURSED ? "Не продаётся (снятие " + CardManager.CURSE_REMOVE_COST + "♦ в магазине)"
                : "Продажа в магазине: " + CardManager.sellValue(gs, sel, mm.mods) + "¢";
        PixelFont.draw(g, sv, 14, y, PixelFont.GRAY, Graphics.LEFT);
    }

    private void paintSets(Graphics g) {
        GameState gs = mm.game;
        PixelFont.shadow(g, "СЕТЫ СЕМЕЙ", 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        for (int f = 0; f < Card.FAMILIES; f++) {
            int y = 34 + f * 32;
            int c = CardManager.countFamily(gs, f);
            PixelFont.shadow(g, Card.FAMILY[f] + ": " + c + " карт", 14, y, c >= 2 ? PixelFont.GOLD : PixelFont.CREAM,
                    Graphics.LEFT);
            PixelFont.draw(g, "2: " + CardManager.SET2[f], 20, y + 11, c >= 2 ? PixelFont.GREEN : PixelFont.GRAY,
                    Graphics.LEFT);
            PixelFont.draw(g, "4: " + CardManager.SET4[f], 20, y + 20, c >= 4 ? PixelFont.GREEN : PixelFont.GRAY,
                    Graphics.LEFT);
        }
    }

    private void paintAlmanac(Graphics g) {
        Stats s = mm.stats;
        PixelFont.shadow(g, "АЛЬМАНАХ " + s.discoveredCount() + "/" + CardManager.count(), 120, 6, PixelFont.GOLD,
                Graphics.HCENTER);
        PixelFont.draw(g, "# фильтр: " + (filter < 0 ? "все семьи" : Card.FAMILY[filter]), 120, 30, PixelFont.GRAY,
                Graphics.HCENTER);
        int cols = 7;
        int rows = 5;
        int row = sel / cols;
        if (row < scroll) {
            scroll = row;
        }
        if (row >= scroll + rows) {
            scroll = row - rows + 1;
        }
        for (int i = scroll * cols; i < listN && i < (scroll + rows) * cols; i++) {
            int r = i / cols - scroll, c = i % cols;
            int x = 10 + c * 32, y = 44 + r * 32;
            int id = list[i];
            if (s.isDiscovered(id)) {
                Gfx.card(g, id, x, y);
            } else {
                Gfx.emptySlot(g, x, y, false);
                PixelFont.draw(g, "?", x + 14, y + 9, PixelFont.GRAY, Graphics.HCENTER);
            }
            if (i == sel) {
                Gfx.cursor(g, x, y, time);
            }
        }
        // scrollbar
        int totalRows = (listN + cols - 1) / cols;
        if (totalRows > rows) {
            int bh = 160 * rows / totalRows;
            int by = 44 + (160 - bh) * scroll / (totalRows - rows);
            g.setColor(0x3A2416);
            g.fillRect(232, 44, 3, 160);
            g.setColor(0xC8A050);
            g.fillRect(232, by, 3, bh);
        }
        if (listN == 0) {
            return;
        }
        int id = list[sel];
        Card c = CardManager.get(id);
        int y = 214;
        if (s.isDiscovered(id)) {
            PixelFont.shadow(g, c.name, 14, y, Gfx.RARITY_FONT[c.rarity], Graphics.LEFT);
            PixelFont.draw(g, Gfx.kind(c), 14, y + 13, PixelFont.GRAY, Graphics.LEFT);
            if (descFor != id) {
                desc = PixelFont.wrap(c.desc, 210);
                descFor = id;
            }
            PixelFont.lines(g, desc, 14, y + 27, PixelFont.CREAM, 4);
        } else {
            PixelFont.shadow(g, "Карта № " + (id + 1) + " не открыта", 14, y, PixelFont.GRAY, Graphics.LEFT);
            PixelFont.draw(g, Card.RARITY[c.rarity] + " · купите её, чтобы открыть", 14, y + 13, PixelFont.GRAY,
                    Graphics.LEFT);
        }
    }

    public void key(int k) {
        switch (k) {
            case K_RSOFT:
                goBack();
                return;
            case K_POUND:
                mm.sfx(SoundManager.MOVE);
                if (almanac) {
                    filter = filter + 1 >= Card.FAMILIES ? -1 : filter + 1;
                    sel = 0;
                    scroll = 0;
                    rebuild();
                } else {
                    setsTab = !setsTab;
                }
                return;
            default:
                break;
        }
        int n = almanac ? listN : GameState.MAX_SLOTS;
        int step = almanac ? 7 : 4;
        switch (k) {
            case K_LEFT:
                sel = (sel + n - 1) % n;
                break;
            case K_RIGHT:
                sel = (sel + 1) % n;
                break;
            case K_UP:
                sel = sel - step >= 0 ? sel - step : sel;
                break;
            case K_DOWN:
                sel = sel + step < n ? sel + step : sel;
                break;
            default:
                return;
        }
        mm.sfx(SoundManager.MOVE);
    }
}
