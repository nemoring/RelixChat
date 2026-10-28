package luckypit;

/** Between-round shop: card offers (coins), machine upgrades (tokens), selling. */
public final class Shop {
    public static final String[] UPG_NAME = {
            "Галочки V и Λ", "Колонны", "Слот для карты", "Доп. прокрутка", "Позолота",
            "Пружина комбо", "Сейф", "Фильтр черепов", "Магнит удачи", "Машинное масло"};
    public static final String[] UPG_DESC = {
            "Открывает 2 линии: V и перевёрнутую V.",
            "Открывает 3 вертикальные линии.",
            "+1 слот для карт (до 8).",
            "+1 прокрутка в каждом раунде.",
            "+1 к ценности всех символов, кроме «Око» и «Череп».",
            "Комбо: +15% за каждую доп. выигрышную линию.",
            "+3% процентов на монеты в конце раунда.",
            "«Череп» выпадает реже (вес −1).",
            "«Око» выпадает чаще (вес +1).",
            "Множитель выигрыша +20%."};
    /** Display order of upgrades in the shop. */
    public static final int[] UPG_ORDER = {0, 2, 3, 1, 4, 9, 5, 6, 7, 8};

    public static final int R_OK = 0, R_NO_MONEY = 1, R_NO_SLOT = 2, R_MAXED = 3, R_EMPTY = 4;

    private static final int[] EX = new int[GameState.MAX_OFFERS];

    private Shop() {
    }

    public static int priceOf(GameState g, EffectManager.Mods m, int id) {
        Card c = CardManager.get(id);
        long p = (long) c.price * (100 + 40 * g.deadline) / 100;
        p = p * (100 - m.discount) / 100;
        return p < 1 ? 1 : (int) p;
    }

    /** Fresh offers for a new shop visit. */
    public static void open(GameState g, EffectManager.Mods m) {
        EffectManager.compute(g, m);
        g.freeRerolls = m.freeReroll;
        g.rerolls = 0;
        roll(g, m);
        g.phase = GameState.PH_SHOP;
    }

    /** Starter gift: three free common/uncommon cards, take one. */
    public static void openStarter(GameState g, EffectManager.Mods m) {
        int k = 0;
        for (int t = 0; t < 30 && k < 3; t++) {
            int id = CardManager.randomOfRarity(g, g.rng, t % 3 == 2 ? Card.UNCOMMON : Card.COMMON);
            boolean dup = false;
            for (int i = 0; i < k; i++) {
                if (EX[i] == id) {
                    dup = true;
                }
            }
            if (id >= 0 && !dup) {
                EX[k++] = id;
            }
        }
        g.offerCount = k;
        for (int i = 0; i < GameState.MAX_OFFERS; i++) {
            g.offer[i] = i < k ? EX[i] : -1;
            g.offerPrice[i] = 0;
        }
        g.freePick = true;
        g.freeRerolls = 0;
        g.phase = GameState.PH_SHOP;
    }

    private static void roll(GameState g, EffectManager.Mods m) {
        int n = 4 + m.shopSlots;
        if (n > GameState.MAX_OFFERS) {
            n = GameState.MAX_OFFERS;
        }
        int k = 0;
        for (int i = 0; i < n; i++) {
            int id = CardManager.rollOffer(g, g.rng, EX, k, m.lucky);
            if (id >= 0) {
                EX[k++] = id;
            }
        }
        g.offerCount = k;
        for (int i = 0; i < GameState.MAX_OFFERS; i++) {
            g.offer[i] = i < k ? EX[i] : -1;
            g.offerPrice[i] = i < k ? priceOf(g, m, EX[i]) : 0;
        }
    }

    public static int rerollCost(GameState g) {
        if (g.freePick) {
            return 99;
        }
        return g.freeRerolls > 0 ? 0 : 1;
    }

    public static int reroll(GameState g, EffectManager.Mods m) {
        int cost = rerollCost(g);
        if (g.tokens < cost) {
            return R_NO_MONEY;
        }
        if (cost == 0) {
            g.freeRerolls--;
        } else {
            g.tokens -= cost;
        }
        g.rerolls++;
        EffectManager.compute(g, m);
        roll(g, m);
        return R_OK;
    }

    public static int buy(GameState g, EffectManager.Mods m, int idx) {
        if (idx < 0 || idx >= g.offerCount || g.offer[idx] < 0) {
            return R_EMPTY;
        }
        int price = g.offerPrice[idx];
        if (g.coins < price) {
            return R_NO_MONEY;
        }
        if (CardManager.ownedCount(g) >= CardManager.capacity(g)) {
            return R_NO_SLOT;
        }
        g.coins -= price;
        CardManager.add(g, g.offer[idx], price);
        g.stats.cardsBought++;
        g.offer[idx] = -1;
        if (g.freePick) {
            g.freePick = false;
            for (int i = 0; i < GameState.MAX_OFFERS; i++) {
                g.offer[i] = -1;
            }
        }
        EffectManager.compute(g, m);
        return R_OK;
    }

    public static int buyUpgrade(GameState g, EffectManager.Mods m, int u) {
        int cost = g.upgCost(u);
        if (cost < 0) {
            return R_MAXED;
        }
        if (g.tokens < cost) {
            return R_NO_MONEY;
        }
        g.tokens -= cost;
        g.upg[u]++;
        EffectManager.compute(g, m);
        return R_OK;
    }

    /** Sells (or, for cursed cards, pays tokens to destroy) the card in a slot. */
    public static int sell(GameState g, EffectManager.Mods m, int slot) {
        int id = g.cards[slot];
        if (id < 0) {
            return R_EMPTY;
        }
        if (CardManager.get(id).rarity == Card.CURSED) {
            if (g.tokens < CardManager.CURSE_REMOVE_COST) {
                return R_NO_MONEY;
            }
            g.tokens -= CardManager.CURSE_REMOVE_COST;
        } else {
            g.addCoins(CardManager.sellValue(g, slot, m));
        }
        CardManager.remove(g, slot);
        EffectManager.compute(g, m);
        return R_OK;
    }
}
