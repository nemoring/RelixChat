import luckypit.*;

/**
 * Headless balance simulator. Runs the real game logic classes with simple
 * bots and prints win rates and how far runs get.
 *   java Sim [runs] [strategy]   strategy: 0 passive, 1 random, 2 greedy, 3 smart
 */
public class Sim {
    static int[] reached = new int[GameState.DEADLINES + 2];

    public static void main(String[] a) {
        CardManager.load();
        int runs = a.length > 0 ? Integer.parseInt(a[0]) : 1000;
        int strat = a.length > 1 ? Integer.parseInt(a[1]) : 3;
        boolean verbose = a.length > 2 && a[2].equals("v");
        DebtManager.godMode = a.length > 2 && a[2].equals("g");
        long[] dlWon = new long[8]; long[] dlSp = new long[8];
        int wins = 0;
        int[] endings = new int[5];
        long spins = 0, won = 0;
        int[] lostAt = new int[GameState.DEADLINES];
        for (int r = 0; r < runs; r++) {
            Stats st = new Stats();
            GameState g = new GameState(st);
            EffectManager.Mods m = new EffectManager.Mods();
            SlotMachine sm = new SlotMachine();
            SlotMachine.SpinResult res = new SlotMachine.SpinResult();
            DebtManager.newRun(g, 12345 + r * 7919);
            ema = 2;
            java.util.Random br = new java.util.Random(r);
            int guard = 0;
            while (g.active && guard++ < 10000) {
                switch (g.phase) {
                    case GameState.PH_PREP: {
                        boolean shortShift = false;
                        if (strat == 4) {
                            EffectManager.compute(g, m);
                            shortShift = g.coins >= DebtManager.due(g, m) + 2 * expected(g) && g.roundInDl < 2;
                        }
                        if (strat == 3) {
                            EffectManager.compute(g, m);
                            // short shift when debt is already covered
                            shortShift = g.coins >= DebtManager.due(g, m) * 2 && g.roundInDl < 2;
                        }
                        DebtManager.startRound(g, m, shortShift);
                        break;
                    }
                    case GameState.PH_PLAY:
                        EffectManager.compute(g, m);
                        sm.spin(g, m, res);
                        spins++; dlWon[g.deadline] += res.total; dlSp[g.deadline]++;
                        won += res.total;
                        ema = ema * 0.85 + res.total * 0.15;
                        if (verbose && r == 0) {
                            System.out.println("dl" + g.deadline + " r" + g.roundInDl + " win " + res.total + " coins " + g.coins);
                        }
                        if (g.spinsLeft <= 0) {
                            DebtManager.endRound(g, m);
                        }
                        break;
                    case GameState.PH_ROUND_END: {
                        boolean early = strat >= 3 && DebtManager.canPayEarly(g, m)
                                && g.coins >= DebtManager.due(g, m) * 3;
                        int res2 = DebtManager.settle(g, m, early);
                        if (res2 == DebtManager.R_LOST) {
                            lostAt[g.deadline]++;
                            break;
                        }
                        if (res2 == DebtManager.R_WON) {
                            break;
                        }
                        if (!EventManager.roll(g)) {
                            Shop.open(g, m);
                        }
                        break;
                    }
                    case GameState.PH_EVENT: {
                        boolean choice = strat == 1 ? br.nextBoolean() : eventChoice(g);
                        EventManager.choose(g, choice || !EventManager.hasB(g.eventId) );
                        Shop.open(g, m);
                        break;
                    }
                    case GameState.PH_SHOP:
                        shop(g, m, strat, br);
                        g.phase = GameState.PH_PREP;
                        break;
                    default:
                        g.active = false;
                }
            }
            reached[g.deadline + (g.phase == GameState.PH_WON ? 1 : 0)]++;
            if (g.phase == GameState.PH_WON) {
                wins++;
                endings[g.ending]++;
            }
            if (verbose && r < 3) {
                System.out.print("run " + r + " end dl=" + g.deadline + " coins=" + g.coins + " cards:");
                for (int s = 0; s < 8; s++) if (g.cards[s] >= 0) System.out.print(" " + CardManager.get(g.cards[s]).name);
                System.out.print(" upg:");
                for (int u = 0; u < GameState.UPGRADES; u++) System.out.print(g.upg[u]);
                System.out.println();
            }
        }
        System.out.println("strategy " + strat + ": wins " + wins + "/" + runs + " = " + (wins * 100 / runs) + "%");
        System.out.print("lost at deadline:");
        for (int i = 0; i < lostAt.length; i++) System.out.print(" " + lostAt[i]);
        System.out.println();
        System.out.println("endings freedom/owner/cursed: " + endings[1] + "/" + endings[2] + "/" + endings[3]);
        for (int i = 0; i < 8; i++) System.out.print(" dl" + i + ":" + (dlSp[i] > 0 ? dlWon[i] / dlSp[i] : 0) + "(debt " + DebtManager.DEBT[i] + ", per-dl " + (dlSp[i] > 0 ? dlWon[i] / runs : 0) + ")");
        System.out.println();
        System.out.println("avg win per spin " + (won * 100 / Math.max(1, spins)) / 100.0);
    }

    static boolean eventChoice(GameState g) {
        switch (g.eventId) {
            case 0: return g.coins > g.offerPrice[0] * 2;
            case 1: return true;
            case 2: return false;
            case 4: return false;
            case 5: return true;
            case 6: return false;
            case 7: return false;
            case 8: return g.tokens >= 4;
            case 10: return true;
            default: return true;
        }
    }

    static int score(GameState g, Card c) {
        int s = c.rarity == Card.CURSED ? 2 : c.rarity * 3 + 2;
        for (int k = 0; k < 2; k++) {
            int op = c.op[k];
            if (op == Op.MULT || op == Op.VAL_MUL || op == Op.PER_SYM_MULT || op == Op.INTEREST || op == Op.SPINS
                    || op == Op.FAMILY_BOOST || op == Op.PER_CARD || op == Op.DICE || op == Op.GROW_SYM) s += 3;
            if (op == Op.DEBT_CUT) s += 3;
            if (op == Op.DEBT_ADD) s -= 3;
            if (op == Op.WEIGHT && c.a[k] == Symbol.SKULL && c.b[k] > 0) s -= 2;
        }
        // family synergy
        s += CardManager.countFamily(g, c.family) * 2;
        return s;
    }

    static void shop(GameState g, EffectManager.Mods m, int strat, java.util.Random br) {
        if (strat == 0) return;
        if (strat == 4) {
            mcShop(g, m);
            return;
        }
        if (strat == 1) {
            for (int i = 0; i < g.offerCount; i++) {
                if (br.nextInt(3) == 0) Shop.buy(g, m, i);
            }
            int u = br.nextInt(GameState.UPGRADES);
            Shop.buyUpgrade(g, m, u);
            return;
        }
        // upgrades by priority
        int[] pri = {GameState.U_SLOT, GameState.U_VLINES, GameState.U_SPIN, GameState.U_COLS,
                GameState.U_GILD, GameState.U_OIL, GameState.U_COMBO, GameState.U_SAFE, GameState.U_MAGNET, GameState.U_SKULLF};
        for (int it = 0; it < 4; it++) {
            for (int i = 0; i < pri.length; i++) {
                if (pri[i] == GameState.U_SLOT && CardManager.ownedCount(g) < CardManager.capacity(g)) continue;
                if (Shop.buyUpgrade(g, m, pri[i]) == Shop.R_OK) break;
            }
        }
        EffectManager.compute(g, m);
        int due = DebtManager.due(g, m);
        int roundsLeft = GameState.ROUNDS_PER_DEADLINE - g.roundInDl;
        int reserve = strat == 3 ? Math.max(0, due - roundsLeft * expected(g)) : 0;
        for (int pass = 0; pass < 2; pass++) {
            int best = -1, bs = -999;
            for (int i = 0; i < g.offerCount; i++) {
                if (g.offer[i] < 0) continue;
                Card c = CardManager.get(g.offer[i]);
                int s = score(g, c);
                if (g.coins - g.offerPrice[i] < reserve) continue;
                if (s > bs) { bs = s; best = i; }
            }
            if (best < 0) break;
            if (CardManager.ownedCount(g) >= CardManager.capacity(g)) {
                // replace weakest
                if (strat != 3) break;
                int ws = 999, wsl = -1;
                for (int s = 0; s < 8; s++) {
                    if (g.cards[s] < 0) continue;
                    Card c = CardManager.get(g.cards[s]);
                    if (c.rarity == Card.CURSED) continue;
                    int sc = score(g, c);
                    if (sc < ws) { ws = sc; wsl = s; }
                }
                if (wsl < 0 || ws + 3 >= bs) break;
                Shop.sell(g, m, wsl);
            }
            Shop.buy(g, m, best);
        }
    }

    static double ema = 2;

    static GameState clone(GameState g) {
        try {
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            g.write(new java.io.DataOutputStream(bo));
            GameState c = new GameState(new Stats());
            c.read(new java.io.DataInputStream(new java.io.ByteArrayInputStream(bo.toByteArray())));
            return c;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    static SlotMachine msm = new SlotMachine();
    static SlotMachine.SpinResult mres = new SlotMachine.SpinResult();

    /** Average coins per round over n simulated rounds. */
    static double evalRound(GameState g0, int n) {
        GameState g = clone(g0);
        g.rng.setState(777);
        EffectManager.Mods m = new EffectManager.Mods();
        long tot = 0;
        for (int i = 0; i < n; i++) {
            int c0 = g.coins;
            DebtManager.startRound(g, m, false);
            int guard = 0;
            while (g.spinsLeft > 0 && guard++ < 60) {
                EffectManager.compute(g, m);
                msm.spin(g, m, mres);
            }
            DebtManager.endRound(g, m);
            tot += g.coins - c0;
            g.coins = c0;
            g.roundInDl = Math.min(g.roundInDl, 2);
        }
        return tot / (double) n;
    }

    static void mcShop(GameState g, EffectManager.Mods m) {
        int[] pri = {GameState.U_VLINES, GameState.U_SPIN, GameState.U_COLS, GameState.U_OIL,
                GameState.U_GILD, GameState.U_COMBO, GameState.U_SAFE, GameState.U_MAGNET, GameState.U_SKULLF};
        if (CardManager.ownedCount(g) >= CardManager.capacity(g)) Shop.buyUpgrade(g, m, GameState.U_SLOT);
        for (int it = 0; it < 5; it++) {
            for (int i = 0; i < pri.length; i++) {
                if (Shop.buyUpgrade(g, m, pri[i]) == Shop.R_OK) break;
            }
        }
        for (int pass = 0; pass < 3; pass++) {
            EffectManager.compute(g, m);
            double base = evalRound(g, 12);
            int due = DebtManager.due(g, m);
            int roundsLeft = GameState.ROUNDS_PER_DEADLINE - g.roundInDl - (g.phase == GameState.PH_SHOP && !g.freePick ? 0 : 0);
            int best = -1; double bv = base * 1.04; int bestSell = -1;
            boolean full = CardManager.ownedCount(g) >= CardManager.capacity(g);
            for (int i = 0; i < g.offerCount; i++) {
                if (g.offer[i] < 0) continue;
                int price = g.offerPrice[i];
                if (g.coins < price) continue;
                for (int sl = full ? 0 : -1; sl < (full ? 8 : 0); sl++) {
                    GameState c = clone(g);
                    int sellGain = 0;
                    if (sl >= 0) {
                        if (c.cards[sl] < 0) continue;
                        if (CardManager.get(c.cards[sl]).rarity == Card.CURSED) continue;
                        int before = c.coins;
                        Shop.sell(c, m, sl);
                        sellGain = c.coins - before;
                    }
                    if (Shop.buy(c, m, i) != Shop.R_OK) continue;
                    double v = evalRound(c, 12);
                    double proj = v * roundsLeft * 0.75;
                    if (c.coins + proj < due * 1.05) continue;
                    // value: gain over remaining run, minus price
                    double gain = (v - base) * 4 - (price - sellGain);
                    if (v > bv && gain > 0) { bv = v; best = i; bestSell = sl; }
                }
            }
            if (best < 0) break;
            if (bestSell >= 0) Shop.sell(g, m, bestSell);
            Shop.buy(g, m, best);
        }
    }
    static int expected(GameState g) {
        EffectManager.Mods m = new EffectManager.Mods();
        EffectManager.compute(g, m);
        int spins = GameState.BASE_SPINS + m.spins;
        return (int) (ema * spins * 0.7);
    }
}
