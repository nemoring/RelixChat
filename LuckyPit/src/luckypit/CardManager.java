package luckypit;

import java.io.DataInputStream;
import java.io.InputStream;

/**
 * Card database plus operations on the cards a run owns: buying, selling,
 * moving and drawing random shop offers.
 */
public final class CardManager {
    private static Card[] defs;

    /** Set-bonus thresholds per family: 2 and 4 cards. */
    public static final String[] SET2 = {
            "«Вишня» и «Лимон» +1 к ценности",
            "«Клевер» и «Подкова» чаще (+4)",
            "«Звезда» и «Алмаз» +2 к ценности",
            "«Семёрка» чаще (+2)",
            "Множитель +25%",
            "+1 прокрутка за раунд",
            "Проценты +3%",
            "«Око» чаще (+2)"};
    public static final String[] SET4 = {
            "Линии фруктов ×2",
            "«Око» чаще (+3), +1♦ за раунд",
            "Россыпь от 2 звёзд, линии «Алмаз» ×2",
            "Линии «Семёрка» +150%, джекпот ×2",
            "Линия «Череп» платит 30¢×срок",
            "Последняя прокрутка +200%",
            "Каждый долг на 10% меньше",
            "Каждую прокрутку одна клетка — «Око»"};

    private CardManager() {
    }

    public static synchronized void load() {
        if (defs != null) {
            return;
        }
        DataInputStream in = null;
        try {
            InputStream is = CardManager.class.getResourceAsStream("/cards.dat");
            in = new DataInputStream(is);
            int n = in.readUnsignedShort();
            Card[] d = new Card[n];
            for (int i = 0; i < n; i++) {
                int rar = in.readUnsignedByte();
                int fam = in.readUnsignedByte();
                int price = in.readUnsignedShort();
                int[] op = new int[2], a = new int[2], b = new int[2], c = new int[2];
                for (int k = 0; k < 2; k++) {
                    op[k] = in.readUnsignedByte();
                    a[k] = in.readShort();
                    b[k] = in.readShort();
                    c[k] = in.readByte();
                }
                String name = readStr(in);
                String desc = readStr(in);
                Card cd = new Card(i, rar, fam, price, name, desc);
                for (int k = 0; k < 2; k++) {
                    cd.op[k] = op[k];
                    cd.a[k] = a[k];
                    cd.b[k] = b[k];
                    cd.c[k] = c[k];
                }
                d[i] = cd;
            }
            defs = d;
        } catch (Exception e) {
            defs = new Card[0];
        } finally {
            try {
                if (in != null) {
                    in.close();
                }
            } catch (Exception e) {
                // ignore
            }
        }
    }

    private static String readStr(DataInputStream in) throws java.io.IOException {
        int len = in.readUnsignedShort();
        byte[] buf = new byte[len];
        in.readFully(buf);
        return new String(buf, "UTF-8");
    }

    public static int count() {
        return defs.length;
    }

    /** Card id by name, or -1. */
    public static int find(String name) {
        for (int i = 0; i < defs.length; i++) {
            if (defs[i].name.equals(name)) {
                return i;
            }
        }
        return -1;
    }

    public static Card get(int id) {
        if (id < 0 || id >= defs.length) {
            return null;
        }
        return defs[id];
    }

    // ------------------------------------------------------------- run ops

    public static int ownedCount(GameState g) {
        int n = 0;
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (g.cards[i] >= 0) {
                n++;
            }
        }
        return n;
    }

    public static boolean owns(GameState g, int id) {
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (g.cards[i] == id) {
                return true;
            }
        }
        return false;
    }

    public static int countRarity(GameState g, int rarity) {
        int n = 0;
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (g.cards[i] >= 0 && defs[g.cards[i]].rarity == rarity) {
                n++;
            }
        }
        return n;
    }

    public static int countFamily(GameState g, int fam) {
        int n = 0;
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (g.cards[i] >= 0 && defs[g.cards[i]].family == fam) {
                n++;
            }
        }
        return n;
    }

    /** Slots usable right now (base + upgrades + slot cards). */
    public static int capacity(GameState g) {
        int cap = GameState.BASE_SLOTS + g.upg[GameState.U_SLOT];
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (g.cards[i] >= 0) {
                Card c = defs[g.cards[i]];
                for (int k = 0; k < 2; k++) {
                    if (c.op[k] == Op.SLOTS) {
                        cap += c.a[k];
                    }
                }
            }
        }
        return cap > GameState.MAX_SLOTS ? GameState.MAX_SLOTS : cap;
    }

    /** Adds a card into the first free slot. Returns slot or -1. */
    public static int add(GameState g, int id, int paid) {
        if (ownedCount(g) >= capacity(g)) {
            return -1;
        }
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (g.cards[i] < 0) {
                g.cards[i] = id;
                g.cardCounter[i] = 0;
                g.cardPaid[i] = paid;
                g.cardAge[i] = 0;
                compact(g);
                Card c = defs[id];
                // one-shot purchase effects
                for (int k = 0; k < 2; k++) {
                    if (c.op[k] == Op.ON_BUY_COINS) {
                        g.addCoins(c.a[k] * (g.deadline + 1));
                    } else if (c.op[k] == Op.ON_BUY_TOKENS) {
                        g.tokens += c.a[k];
                    }
                }
                g.stats.discover(id);
                return i;
            }
        }
        return -1;
    }

    /** Sale value of the card in slot (cursed cards cost tokens instead). */
    public static int sellValue(GameState g, int slot, EffectManager.Mods m) {
        int id = g.cards[slot];
        if (id < 0) {
            return 0;
        }
        Card c = defs[id];
        if (c.rarity == Card.CURSED) {
            return 0;
        }
        int v = g.cardPaid[slot] / 2;
        for (int k = 0; k < 2; k++) {
            if (c.op[k] == Op.INVEST) {
                v += c.a[k] * (g.deadline + 1) * g.cardAge[slot];
            }
        }
        v = v * (100 + m.sellBonus) / 100;
        return v < 1 ? 1 : v;
    }

    /** Tokens needed to get rid of a cursed card. */
    public static final int CURSE_REMOVE_COST = 3;

    public static void remove(GameState g, int slot) {
        g.cards[slot] = -1;
        compact(g);
        // slots may shrink (sold a wallet) - overflowing cards stay but count
    }

    /** Swap two slots (for ordering mirrors). */
    public static void swap(GameState g, int i, int j) {
        if (i < 0 || j < 0 || i >= GameState.MAX_SLOTS || j >= GameState.MAX_SLOTS) {
            return;
        }
        int t = g.cards[i]; g.cards[i] = g.cards[j]; g.cards[j] = t;
        t = g.cardCounter[i]; g.cardCounter[i] = g.cardCounter[j]; g.cardCounter[j] = t;
        t = g.cardPaid[i]; g.cardPaid[i] = g.cardPaid[j]; g.cardPaid[j] = t;
        t = g.cardAge[i]; g.cardAge[i] = g.cardAge[j]; g.cardAge[j] = t;
    }

    /** Move cards left so owned cards are contiguous. */
    public static void compact(GameState g) {
        int w = 0;
        for (int r = 0; r < GameState.MAX_SLOTS; r++) {
            if (g.cards[r] >= 0) {
                if (w != r) {
                    swap(g, w, r);
                }
                w++;
            }
        }
    }

    /**
     * Picks a random card id that is not owned and not in the exclude list,
     * using rarity odds that improve as deadlines pass.
     */
    public static int rollOffer(GameState g, Rng rng, int[] exclude, int exN, int lucky) {
        int k = g.deadline;
        int[] w = new int[6];
        w[Card.COMMON] = 520 - 40 * k;
        w[Card.UNCOMMON] = 280;
        w[Card.RARE] = 120 + 25 * k;
        w[Card.EPIC] = 35 + 18 * k;
        w[Card.LEGENDARY] = 8 + 9 * k;
        w[Card.CURSED] = 40;
        if (lucky > 0) {
            w[Card.RARE] += w[Card.RARE] * lucky / 100;
            w[Card.EPIC] += w[Card.EPIC] * lucky / 100;
            w[Card.LEGENDARY] += w[Card.LEGENDARY] * lucky / 100;
        }
        for (int attempt = 0; attempt < 40; attempt++) {
            int total = 0;
            for (int i = 0; i < 6; i++) {
                total += w[i];
            }
            int r = rng.nextInt(total);
            int rar = 0;
            while (r >= w[rar]) {
                r -= w[rar];
                rar++;
            }
            // count candidates of this rarity
            int n = 0;
            for (int i = 0; i < defs.length; i++) {
                if (defs[i].rarity == rar && ok(g, i, exclude, exN)) {
                    n++;
                }
            }
            if (n == 0) {
                w[rar] = 0;
                continue;
            }
            int pick = rng.nextInt(n);
            for (int i = 0; i < defs.length; i++) {
                if (defs[i].rarity == rar && ok(g, i, exclude, exN)) {
                    if (pick-- == 0) {
                        return i;
                    }
                }
            }
        }
        return -1;
    }

    private static boolean ok(GameState g, int id, int[] ex, int exN) {
        if (owns(g, id)) {
            return false;
        }
        for (int i = 0; i < exN; i++) {
            if (ex[i] == id) {
                return false;
            }
        }
        return true;
    }

    /** Random cursed card id not yet owned, or -1. */
    public static int randomOfRarity(GameState g, Rng rng, int rarity) {
        int n = 0;
        for (int i = 0; i < defs.length; i++) {
            if (defs[i].rarity == rarity && !owns(g, i)) {
                n++;
            }
        }
        if (n == 0) {
            return -1;
        }
        int pick = rng.nextInt(n);
        for (int i = 0; i < defs.length; i++) {
            if (defs[i].rarity == rarity && !owns(g, i)) {
                if (pick-- == 0) {
                    return i;
                }
            }
        }
        return -1;
    }
}
