package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Shop between rounds: cards, machine upgrades and your own cards. */
public final class ShopScreen extends Screen {
    private static final int T_CARDS = 0, T_UPG = 1, T_MINE = 2;
    private static final String[] TABS = {"Карты", "Автомат", "Мои карты"};
    private static final int A_SELL = 1, A_SKIP = 2;
    private int tab;
    private int sel, upSel, mySel;
    private int carry = -1;
    private String[] descLines;
    private int descFor = -2;
    private boolean sets;
    private String msg;
    private int msgT;

    public void enter() {
        EffectManager.compute(mm.game, mm.mods);
        descFor = -2;
        if (mm.game.freePick) {
            tab = T_CARDS;
        }
    }

    private void toast(String s) {
        msg = s;
        msgT = 1600;
    }

    public void update(int dt) {
        super.update(dt);
        if (msgT > 0) {
            msgT -= dt;
        }
    }

    // ----------------------------------------------------------- paint
    public void paint(Graphics g) {
        GameState gs = mm.game;
        Image bg = ResourceManager.bg("bg_shop.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        PixelFont.shadow(g, gs.freePick ? "ПОДАРОК" : "МАГАЗИН", 6, 6, PixelFont.GOLD, Graphics.LEFT);
        Gfx.money(g, gs.coins, gs.tokens, 234, 5);
        // tabs
        for (int i = 0; i < 3; i++) {
            int x = 8 + i * 76;
            boolean on = i == tab;
            g.setColor(on ? 0x7E1C24 : 0x2A1A12);
            g.fillRect(x, 27, 72, 15);
            g.setColor(on ? 0xF0D282 : 0x6B4A1A);
            g.drawRect(x, 27, 71, 14);
            PixelFont.draw(g, TABS[i], x + 36, 29, on ? PixelFont.WHITE : PixelFont.GRAY, Graphics.HCENTER);
        }
        switch (tab) {
            case T_CARDS:
                paintOffers(g);
                break;
            case T_UPG:
                paintUpgrades(g);
                break;
            default:
                paintMine(g);
                break;
        }
        if (sets) {
            paintSets(g);
        }
        if (msgT > 0 && msg != null) {
            Gfx.panel(g, 20, 140, 200, 26);
            PixelFont.shadow(g, msg, 120, 148, PixelFont.GOLD, Graphics.HCENTER);
        }
        Fx.paint(g, time);
        String left;
        if (tab == T_CARDS) {
            left = gs.freePick ? null : "Обновить " + (Shop.rerollCost(gs) == 0 ? "даром" : "1♦");
        } else if (tab == T_MINE) {
            left = "Продать";
        } else {
            left = "Купить";
        }
        Gfx.softkeys(g, left, "Далее");
    }

    private void paintOffers(Graphics g) {
        GameState gs = mm.game;
        if (gs.offerCount == 0) {
            PixelFont.shadow(g, "Витрина пуста", 120, 110, PixelFont.GRAY, Graphics.HCENTER);
        }
        for (int i = 0; i < gs.offerCount; i++) {
            int c = i % 3, r = i / 3;
            int x = 12 + c * 74 + 11;
            int y = 50 + r * 68;
            if (gs.offer[i] >= 0) {
                Gfx.cardBig(g, gs.offer[i], x, y, true);
                int price = gs.offerPrice[i];
                boolean afford = gs.coins >= price;
                PixelFont.numShadow(g, price, (char) 0, '¢', x + 26, y + 54, gs.freePick ? PixelFont.GREEN
                        : (afford ? PixelFont.GOLD : PixelFont.RED), Graphics.HCENTER);
            } else {
                g.setColor(0x0E2614);
                g.fillRect(x, y, 52, 52);
                PixelFont.draw(g, gs.freePick ? "—" : "ПРОДАНО", x + 26, y + 20, PixelFont.GRAY, Graphics.HCENTER);
            }
            if (i == sel) {
                int o = ((time / 200) & 1);
                g.setColor(0xFFF0B0);
                g.drawRect(x - 3 - o, y - 3 - o, 57 + 2 * o, 57 + 2 * o);
                g.drawRect(x - 2 - o, y - 2 - o, 55 + 2 * o, 55 + 2 * o);
            }
        }
        int id = sel < gs.offerCount ? gs.offer[sel] : -1;
        if (id >= 0) {
            paintCardInfo(g, id, gs.freePick ? "Бесплатно — 5 взять" : "Цена " + gs.offerPrice[sel] + "¢ · 5 купить");
        } else if (gs.freePick) {
            paintInfoText(g, "Подарок заведения", "Выберите одну карту бесплатно. Далее — начать первый раунд.");
        } else {
            paintInfoText(g, "Пусто", "Обновите витрину за жетон ♦ или идите дальше.");
        }
    }

    private void paintUpgrades(Graphics g) {
        GameState gs = mm.game;
        for (int i = 0; i < GameState.UPGRADES; i++) {
            int u = Shop.UPG_ORDER[i];
            int y = 48 + i * 13;
            boolean on = i == upSel;
            if (on) {
                g.setColor(0x7E1C24);
                g.fillRect(8, y - 1, 224, 13);
                g.setColor(0xF0D282);
                g.drawRect(8, y - 1, 223, 12);
            }
            PixelFont.draw(g, Shop.UPG_NAME[u], 12, y, on ? PixelFont.WHITE : PixelFont.CREAM, Graphics.LEFT);
            int max = GameState.UPG_COST[u].length;
            for (int p = 0; p < max; p++) {
                g.setColor(p < gs.upg[u] ? 0xF0C850 : 0x3A2A1A);
                g.fillRect(150 + p * 7, y + 3, 5, 5);
            }
            int cost = gs.upgCost(u);
            if (cost < 0) {
                PixelFont.draw(g, "МАКС", 228, y, PixelFont.GREEN, Graphics.RIGHT);
            } else {
                PixelFont.num(g, cost, (char) 0, '♦', 228, y, gs.tokens >= cost ? PixelFont.CYANISH : PixelFont.RED,
                        Graphics.RIGHT);
            }
        }
        int u = Shop.UPG_ORDER[upSel];
        int cost = gs.upgCost(u);
        paintInfoText(g, Shop.UPG_NAME[u] + "  (" + gs.upg[u] + "/" + GameState.UPG_COST[u].length + ")",
                Shop.UPG_DESC[u] + (cost < 0 ? " Уровень максимальный." : " Цена: " + cost + "♦. Жетоны ♦ дают раунды, "
                        + "короткие смены и сроки."));
    }

    private void paintMine(Graphics g) {
        GameState gs = mm.game;
        int cap = CardManager.capacity(gs);
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            int x = 4 + i * 29;
            int y = 56 - (carry == i ? 6 : 0);
            if (gs.cards[i] >= 0) {
                Gfx.card(g, gs.cards[i], x, y);
            } else {
                Gfx.emptySlot(g, x, y, i >= cap);
            }
            if (i == mySel) {
                Gfx.cursor(g, x, y, time);
            }
        }
        PixelFont.draw(g, carry >= 0 ? "4/6 — двигать, 5 — положить" : "5 — переставить (важно для «Зеркала»)",
                120, 92, PixelFont.GRAY, Graphics.HCENTER);
        // family summary: compact, two per row
        int shown = 0;
        for (int f = 0; f < Card.FAMILIES; f++) {
            int c = CardManager.countFamily(gs, f);
            if (c == 0) {
                continue;
            }
            int col = c >= 4 ? PixelFont.GOLD : (c >= 2 ? PixelFont.GREEN : PixelFont.GRAY);
            PixelFont.draw(g, Card.FAMILY[f] + " " + c + "/4" + (c >= 4 ? " ★★" : (c >= 2 ? " ★" : "")),
                    14 + (shown % 2) * 110, 108 + (shown / 2) * 13, col, Graphics.LEFT);
            shown++;
        }
        PixelFont.draw(g, shown == 0 ? "2 и 4 карты одной семьи дают бонусы." : "* — бонусы семей подробно",
                120, 166, PixelFont.GRAY, Graphics.HCENTER);
        int id = gs.cards[mySel];
        if (id >= 0) {
            Card c = CardManager.get(id);
            String act = c.rarity == Card.CURSED ? "Снять проклятие: " + CardManager.CURSE_REMOVE_COST + "♦"
                    : "Продать за " + CardManager.sellValue(gs, mySel, mm.mods) + "¢";
            paintCardInfo(g, id, act);
        } else {
            paintInfoText(g, mySel < cap ? "Свободный слот" : "Слот закрыт",
                    mySel < cap ? "Купите карту, чтобы занять его." : "Откройте улучшением «Слот для карты».");
        }
    }

    private void paintCardInfo(Graphics g, int id, String action) {
        Card c = CardManager.get(id);
        if (descFor != id) {
            descLines = PixelFont.wrap(c.desc, 220);
            descFor = id;
        }
        PixelFont.shadow(g, c.name, 12, 198, Gfx.RARITY_FONT[c.rarity], Graphics.LEFT);
        PixelFont.draw(g, Gfx.kind(c), 12, 211, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.lines(g, descLines, 12, 226, PixelFont.CREAM, 4);
        PixelFont.shadow(g, action, 228, 284, PixelFont.GOLD, Graphics.RIGHT);
        PixelFont.draw(g, "* сеты", 12, 284, PixelFont.GRAY, Graphics.LEFT);
    }

    private void paintInfoText(Graphics g, String title, String text) {
        PixelFont.shadow(g, title, 12, 198, PixelFont.GOLD, Graphics.LEFT);
        String[] l = PixelFont.wrap(text, 220);
        PixelFont.lines(g, l, 12, 214, PixelFont.CREAM, 5);
    }

    private void paintSets(Graphics g) {
        Gfx.dim(g);
        Gfx.panel(g, 6, 30, 228, 260);
        PixelFont.shadow(g, "Бонусы семей (2 / 4 карты)", 120, 38, PixelFont.GOLD, Graphics.HCENTER);
        GameState gs = mm.game;
        for (int f = 0; f < Card.FAMILIES; f++) {
            int y = 56 + f * 29;
            int c = CardManager.countFamily(gs, f);
            PixelFont.draw(g, Card.FAMILY[f] + " (" + c + ")", 14, y, c >= 2 ? PixelFont.GOLD : PixelFont.CREAM,
                    Graphics.LEFT);
            PixelFont.draw(g, "2: " + CardManager.SET2[f], 20, y + 10, c >= 2 ? PixelFont.GREEN : PixelFont.GRAY,
                    Graphics.LEFT);
            PixelFont.draw(g, "4: " + CardManager.SET4[f], 20, y + 19, c >= 4 ? PixelFont.GREEN : PixelFont.GRAY,
                    Graphics.LEFT);
        }
    }

    // ----------------------------------------------------------- input
    public void key(int k) {
        GameState gs = mm.game;
        if (sets) {
            if (k == K_STAR || k == K_RSOFT || k == K_FIRE) {
                sets = false;
            }
            return;
        }
        switch (k) {
            case K_POUND:
                if (!gs.freePick) {
                    tab = (tab + 1) % 3;
                    carry = -1;
                    mm.sfx(SoundManager.MOVE);
                }
                return;
            case K_STAR:
                sets = true;
                return;
            case K_RSOFT:
                if (gs.freePick && hasOffer()) {
                    mm.confirm("Отказаться от подарка?", this, A_SKIP);
                } else {
                    leave2();
                }
                return;
            case K_1:
                mm.open(new CardsScreen(false), this);
                return;
            case K_3:
                mm.open(new InfoScreen(), this);
                return;
            case K_9:
                mm.open(new StatsScreen(), this);
                return;
            case K_0:
                mm.open(new HelpScreen(), this);
                return;
            default:
                break;
        }
        if (tab == T_CARDS) {
            keyOffers(k);
        } else if (tab == T_UPG) {
            keyUpg(k);
        } else {
            keyMine(k);
        }
    }

    private boolean hasOffer() {
        GameState gs = mm.game;
        for (int i = 0; i < gs.offerCount; i++) {
            if (gs.offer[i] >= 0) {
                return true;
            }
        }
        return false;
    }

    private void leave2() {
        GameState gs = mm.game;
        gs.freePick = false;
        gs.phase = GameState.PH_PREP;
        mm.save();
        mm.sfx(SoundManager.OK);
        mm.go(mm.gameScreen);
    }

    private void keyOffers(int k) {
        GameState gs = mm.game;
        int n = gs.offerCount;
        switch (k) {
            case K_LEFT:
                if (n > 0) {
                    sel = (sel + n - 1) % n;
                }
                mm.sfx(SoundManager.MOVE);
                break;
            case K_RIGHT:
                if (n > 0) {
                    sel = (sel + 1) % n;
                }
                mm.sfx(SoundManager.MOVE);
                break;
            case K_UP:
            case K_DOWN:
                if (n > 3) {
                    sel = sel >= 3 ? sel - 3 : Math.min(n - 1, sel + 3);
                    mm.sfx(SoundManager.MOVE);
                }
                break;
            case K_FIRE: {
                int r = Shop.buy(gs, mm.mods, sel);
                if (r == Shop.R_OK) {
                    mm.sfx(SoundManager.BUY);
                    Fx.coins(120, 100, 10, 160, 10);
                    Fx.sparks(12 + (sel % 3) * 74 + 37, 76 + (sel / 3) * 68, 14, 0xF0C850);
                    toast("Карта куплена!");
                    mm.save();
                    if (!hasOffer() && gs.freePick == false && gs.offerCount == 3 && gs.rerolls == 0
                            && gs.cards[0] >= 0 && CardManager.ownedCount(gs) == 1) {
                        toast("Подарок получен!");
                    }
                } else {
                    mm.sfx(SoundManager.ERR);
                    toast(r == Shop.R_NO_MONEY ? "Не хватает монет" : (r == Shop.R_NO_SLOT
                            ? "Нет свободного слота" : "Пусто"));
                }
                break;
            }
            case K_LSOFT: {
                if (gs.freePick) {
                    break;
                }
                int r = Shop.reroll(gs, mm.mods);
                if (r == Shop.R_OK) {
                    mm.sfx(SoundManager.MAGIC);
                    sel = 0;
                    mm.save();
                } else {
                    mm.sfx(SoundManager.ERR);
                    toast("Нужен жетон ♦");
                }
                break;
            }
            default:
                break;
        }
    }

    private void keyUpg(int k) {
        GameState gs = mm.game;
        switch (k) {
            case K_UP:
                upSel = (upSel + GameState.UPGRADES - 1) % GameState.UPGRADES;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_DOWN:
                upSel = (upSel + 1) % GameState.UPGRADES;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_FIRE:
            case K_LSOFT: {
                int u = Shop.UPG_ORDER[upSel];
                int r = Shop.buyUpgrade(gs, mm.mods, u);
                if (r == Shop.R_OK) {
                    mm.sfx(SoundManager.BUY);
                    Fx.sparks(120, 54 + upSel * 13, 16, 0x8CDCF0);
                    toast(Shop.UPG_NAME[u] + "!");
                    mm.save();
                } else {
                    mm.sfx(SoundManager.ERR);
                    toast(r == Shop.R_MAXED ? "Уже максимум" : "Не хватает жетонов ♦");
                }
                break;
            }
            default:
                break;
        }
    }

    private void keyMine(int k) {
        GameState gs = mm.game;
        switch (k) {
            case K_LEFT:
            case K_RIGHT: {
                int d = k == K_LEFT ? -1 : 1;
                int nsel = mySel + d;
                if (nsel < 0 || nsel >= GameState.MAX_SLOTS) {
                    break;
                }
                if (carry >= 0) {
                    if (gs.cards[nsel] < 0) {
                        break;
                    }
                    CardManager.swap(gs, mySel, nsel);
                    carry = nsel;
                }
                mySel = nsel;
                mm.sfx(SoundManager.MOVE);
                break;
            }
            case K_FIRE:
                if (carry >= 0) {
                    carry = -1;
                    mm.save();
                    mm.sfx(SoundManager.OK);
                } else if (gs.cards[mySel] >= 0) {
                    carry = mySel;
                    mm.sfx(SoundManager.OK);
                }
                break;
            case K_LSOFT:
                if (gs.cards[mySel] >= 0) {
                    Card c = CardManager.get(gs.cards[mySel]);
                    mm.confirm(c.rarity == Card.CURSED ? "Снять «" + c.name + "» за "
                            + CardManager.CURSE_REMOVE_COST + "♦?" : "Продать «" + c.name + "»?", this, A_SELL);
                }
                break;
            default:
                break;
        }
    }

    public void confirmed(int action) {
        GameState gs = mm.game;
        if (action == A_SKIP) {
            leave2();
            return;
        }
        if (action == A_SELL) {
            int r = Shop.sell(gs, mm.mods, mySel);
            if (r == Shop.R_OK) {
                mm.sfx(SoundManager.BUY);
                Fx.coins(4 + mySel * 29 + 14, 70, 8, 160, 10);
                toast("Готово");
                carry = -1;
                mm.save();
            } else {
                mm.sfx(SoundManager.ERR);
                toast("Не хватает жетонов ♦");
            }
        }
    }
}
