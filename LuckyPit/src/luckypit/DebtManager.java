package luckypit;

/**
 * Debt schedule and the run flow between rounds: starting rounds, round-end
 * income, deadline payment, early payoff, defeat and the three endings.
 */
public final class DebtManager {
    /** Debt due at the end of each deadline (before card modifiers). */
    public static final int[] DEBT = {20, 45, 90, 170, 300, 520, 900, 1500};

    /** Balance-test hook: debts are always considered paid. Never set in game. */
    public static boolean godMode;

    private DebtManager() {
    }

    public static void newRun(GameState g, int seed) {
        g.clear();
        g.rng.setState(seed);
        g.active = true;
        g.coins = GameState.START_COINS;
        g.tokens = 1;
        g.stats.runs++;
        EffectManager.Mods m = new EffectManager.Mods();
        startDeadline(g, m);
        Shop.openStarter(g, m);
    }

    /** Fixes the debt of the current deadline ("each new debt +x%" applies here). */
    public static void startDeadline(GameState g, EffectManager.Mods m) {
        EffectManager.compute(g, m);
        long d = (long) DEBT[g.deadline] * (100 + m.debtAdd) / 100;
        g.debtBase = (int) d;
        g.roundInDl = 0;
    }

    /** Debt currently due, after reductions. */
    public static int due(GameState g, EffectManager.Mods m) {
        int cut = m.debtCut > 50 ? 50 : m.debtCut;
        return (int) ((long) g.debtBase * (100 - cut) / 100);
    }

    /** Starts a round: short=true trades spins for tokens. */
    public static void startRound(GameState g, EffectManager.Mods m, boolean shortShift) {
        EffectManager.compute(g, m);
        int spins = (shortShift ? GameState.SHORT_SPINS : GameState.BASE_SPINS) + m.spins + g.evSpins;
        if (spins < 1) {
            spins = 1;
        }
        if (shortShift) {
            g.tokens += GameState.SHORT_TOKENS;
        }
        g.spinsLeft = spins;
        g.spinsRound = spins;
        g.spinIndex = 0;
        g.bellSpinsUsed = 0;
        g.phase = GameState.PH_PLAY;
    }

    /** Round-end income. Leaves phase at PH_ROUND_END. */
    public static void endRound(GameState g, EffectManager.Mods m) {
        EffectManager.compute(g, m);
        int k1 = g.deadline + 1;
        int interest = (int) ((long) g.coins * m.interest / 100);
        int cap = 40 * k1 * k1;
        if (interest > cap) {
            interest = cap;
        }
        int rc = m.roundCoins * k1;
        int tk = 1 + m.tokensRound;
        if (tk < 0) {
            tk = 0;
        }
        g.addCoins(interest + rc);
        g.tokens += tk;
        if (g.tokens > 99) {
            g.tokens = 99;
        }
        g.lastRoundInterest = interest;
        g.lastRoundCoins = rc;
        g.lastRoundTokens = tk;
        for (int s = 0; s < GameState.MAX_SLOTS; s++) {
            if (g.cards[s] >= 0) {
                g.cardAge[s]++;
            }
        }
        g.roundsPlayed++;
        // event modifiers last one round
        g.evSym = -1;
        g.evSymAdd = 0;
        g.evSpins = 0;
        g.evMult = 0;
        g.phase = GameState.PH_ROUND_END;
    }

    public static boolean deadlineNow(GameState g) {
        return g.roundInDl == GameState.ROUNDS_PER_DEADLINE - 1;
    }

    /** True when an early payoff is possible right now. */
    public static boolean canPayEarly(GameState g, EffectManager.Mods m) {
        EffectManager.compute(g, m);
        return !deadlineNow(g) && g.coins >= due(g, m);
    }

    public static final int R_NEXT_ROUND = 0, R_PAID = 1, R_WON = 2, R_LOST = 3, R_REVIVED = 4;

    /**
     * Called after round-end. Either advances to the next round of the same
     * deadline, or settles the deadline. early=true pays before the last round.
     */
    public static int settle(GameState g, EffectManager.Mods m, boolean early) {
        EffectManager.compute(g, m);
        if (!early && !deadlineNow(g)) {
            g.roundInDl++;
            return R_NEXT_ROUND;
        }
        int d = due(g, m);
        if (godMode && g.coins < d) {
            g.coins = d;
        }
        if (g.coins >= d) {
            int skipped = GameState.ROUNDS_PER_DEADLINE - 1 - g.roundInDl;
            g.coins -= d;
            g.lastPaid = d;
            g.tokens += 2 + skipped;
            g.addCoins(m.deadlineCoins * (g.deadline + 1));
            if (g.deadline + 1 > g.stats.bestDeadline) {
                g.stats.bestDeadline = g.deadline + 1;
            }
            if (g.deadline == GameState.DEADLINES - 1) {
                finish(g, d);
                return R_WON;
            }
            g.deadline++;
            startDeadline(g, m);
            return R_PAID;
        }
        if (m.reviveSlot >= 0) {
            // guardian angel: debt is forgiven once, the card burns
            CardManager.remove(g, m.reviveSlot);
            g.lastPaid = 0;
            if (g.deadline == GameState.DEADLINES - 1) {
                finish(g, d);
                return R_WON;
            }
            g.deadline++;
            startDeadline(g, m);
            return R_REVIVED;
        }
        g.phase = GameState.PH_OVER;
        g.ending = GameState.END_LOST;
        g.active = false;
        g.stats.losses++;
        g.stats.endings |= 1 << GameState.END_LOST;
        return R_LOST;
    }

    private static void finish(GameState g, int lastDebt) {
        int cursed = CardManager.countRarity(g, Card.CURSED);
        if (cursed >= 3) {
            g.ending = GameState.END_CURSED;
        } else if (g.coins >= lastDebt * 2) {
            g.ending = GameState.END_OWNER;
        } else {
            g.ending = GameState.END_FREEDOM;
        }
        g.phase = GameState.PH_WON;
        g.active = false;
        g.stats.wins++;
        g.stats.endings |= 1 << g.ending;
    }
}
