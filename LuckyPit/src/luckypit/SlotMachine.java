package luckypit;

/**
 * The 3x3 machine. A spin is fully resolved here before any animation runs:
 * the grid is rolled from the weighted table, card effects that alter the
 * grid are applied as recorded steps, then lines are scored. The reels only
 * replay this precomputed result.
 */
public final class SlotMachine {
    /** Cells are row*3+col. */
    public static final int[][] LINES = {
            {0, 1, 2}, {3, 4, 5}, {6, 7, 8},   // rows
            {0, 4, 8}, {6, 4, 2},              // diagonals
            {0, 4, 2}, {6, 4, 8},              // V and inverted V
            {0, 3, 6}, {1, 4, 7}, {2, 5, 8}};  // columns
    /** Group of each line: 0 rows, 1 diags, 2 V-lines, 3 columns. */
    public static final int[] LINE_GROUP = {0, 0, 0, 1, 1, 2, 2, 3, 3, 3};
    public static final String[] LINE_NAME = {"Верх", "Центр", "Низ", "Диагональ 1", "Диагональ 2",
            "Галочка V", "Галочка Λ", "Колонна 1", "Колонна 2", "Колонна 3"};

    public static final int JACKPOT_MULT = 10;
    public static final int MAX_STEPS = 16;
    public static final int MAX_WINS = 12;

    /** Result of one spin. Reused between spins. */
    public static final class SpinResult {
        public final int[] grid = new int[9];
        public final int[] start = new int[9];
        public int steps;
        public final int[] stepCell = new int[MAX_STEPS];
        public final int[] stepTo = new int[MAX_STEPS];
        public final int[] stepSlot = new int[MAX_STEPS];
        public int wins;
        public final int[] winLine = new int[MAX_WINS];
        public final int[] winSym = new int[MAX_WINS];
        public final int[] winAmount = new int[MAX_WINS];
        public final boolean[] winPair = new boolean[MAX_WINS];
        public int scatterCount, scatterWin;
        public int base, flat, multPct, total;
        public boolean jackpot, nearJackpot, cursed, warded, consolation, freeSpin, nthFired, diceFired,
                gambleWon, gambleLost;
        public int tokens, extraSpins;
        public int trig;
        public int curseLine;
        public int effMultX100;

        void reset() {
            steps = wins = 0;
            scatterCount = scatterWin = base = flat = multPct = total = 0;
            jackpot = nearJackpot = cursed = warded = consolation = freeSpin = nthFired = diceFired = false;
            gambleWon = gambleLost = false;
            tokens = extraSpins = 0;
            trig = 0;
            curseLine = -1;
            effMultX100 = 100;
        }
    }

    private final int[] w = new int[Symbol.COUNT];
    private final int[] cnt = new int[Symbol.COUNT];

    /** Current effective weights (for the info screen). */
    public void weights(EffectManager.Mods m, int[] out) {
        for (int s = 0; s < Symbol.COUNT; s++) {
            int v = Symbol.BASE_WEIGHT[s] + m.weight[s];
            int min = (s == Symbol.SKULL || s == Symbol.EYE) ? 0 : 1;
            out[s] = v < min ? min : v;
        }
    }

    private int roll(Rng rng, int total) {
        int r = rng.nextInt(total);
        int s = 0;
        while (r >= w[s]) {
            r -= w[s];
            s++;
        }
        return s;
    }

    private void step(SpinResult r, int cell, int to, int slot) {
        if (r.grid[cell] == to) {
            return;
        }
        r.grid[cell] = to;
        if (r.steps < MAX_STEPS) {
            r.stepCell[r.steps] = cell;
            r.stepTo[r.steps] = to;
            r.stepSlot[r.steps] = slot;
            r.steps++;
        }
        if (slot >= 0) {
            r.trig |= 1 << slot;
        }
    }

    /** Value of a symbol including flat bonuses. */
    public static int value(EffectManager.Mods m, int s) {
        int v = Symbol.BASE_VALUE[s] + m.valAdd[s];
        return v < 0 ? 0 : v;
    }

    /**
     * Resolves and applies a spin to the state. Coins, tokens and counters are
     * updated immediately so a save right after is consistent.
     */
    public void spin(GameState g, EffectManager.Mods m, SpinResult r) {
        Rng rng = g.rng;
        r.reset();
        weights(m, w);
        int total = 0;
        for (int s = 0; s < Symbol.COUNT; s++) {
            total += w[s];
        }
        for (int i = 0; i < 9; i++) {
            r.grid[i] = roll(rng, total);
            r.start[i] = r.grid[i];
        }

        // ---- grid altering effects, in slot order
        for (int t = 0; t < m.tN; t++) {
            for (int i = 0; i < 9; i++) {
                if (r.grid[i] == m.tFrom[t] && rng.chance(m.tChance[t])) {
                    step(r, i, m.tTo[t], m.tSlot[t]);
                }
            }
        }
        if (m.copyRow > 0 && rng.chance(m.copyRow)) {
            int slot = lowestBit(m.copyMask);
            for (int c = 0; c < 3; c++) {
                step(r, 6 + c, r.grid[3 + c], slot);
            }
        }
        for (int k = 0; k < m.chaos; k++) {
            int cell = rng.nextInt(9);
            step(r, cell, roll(rng, total), lowestBit(m.chaosMask));
        }
        int wc = m.wildChance;
        while (wc > 0) {
            if (rng.chance(wc)) {
                int cell = rng.nextInt(9);
                int slot = m.wildMask != 0 ? lowestBit(m.wildMask) : -1;
                step(r, cell, Symbol.EYE, slot);
            }
            wc -= 100;
        }

        // ---- lines
        int k1 = g.deadline + 1;
        int winLines = 0;
        int base = 0;
        int flat = 0;
        boolean curse = false;
        for (int li = 0; li < LINES.length; li++) {
            if (!g.lineActive(li)) {
                continue;
            }
            int a = r.grid[LINES[li][0]], b = r.grid[LINES[li][1]], c = r.grid[LINES[li][2]];
            if (a == Symbol.SKULL && b == Symbol.SKULL && c == Symbol.SKULL) {
                if (m.ward) {
                    r.warded = true;
                    r.trig |= m.wardMask;
                    if (m.skullWard > 0) {
                        addWin(r, li, Symbol.SKULL, m.skullWard * k1, false);
                        base += m.skullWard * k1;
                        winLines++;
                    }
                } else {
                    curse = true;
                    r.curseLine = li;
                }
                continue;
            }
            if (a == Symbol.SKULL || b == Symbol.SKULL) {
                continue;
            }
            int s = a != Symbol.EYE ? a : (b != Symbol.EYE ? b : c);
            if (s == Symbol.SKULL) {
                s = Symbol.EYE; // wilds then skull: no line
                if (c == Symbol.SKULL) {
                    continue;
                }
            }
            boolean ma = a == s || a == Symbol.EYE;
            boolean mb = b == s || b == Symbol.EYE;
            boolean mc = c == s || c == Symbol.EYE;
            int pct = 100 + m.symMul[s] + m.lineGroup[LINE_GROUP[li]];
            if (li == 1) {
                pct += m.lineGroup[4];
            } else if (li == 0 || li == 2) {
                pct += m.lineGroup[5];
            }
            if (ma && mb && mc) {
                int wilds = (a == Symbol.EYE ? 1 : 0) + (b == Symbol.EYE ? 1 : 0) + (c == Symbol.EYE ? 1 : 0);
                if (s != Symbol.EYE && wilds > 0 && m.eyeBonus > 0) {
                    pct += m.eyeBonus * wilds;
                    r.trig |= m.eyeMask;
                }
                int v = (int) ((long) value(m, s) * pct / 100);
                if (v < 1 && value(m, s) > 0) {
                    v = 1;
                }
                base += v;
                winLines++;
                addWin(r, li, s, v, false);
                r.trig |= m.symMask[s];
                if (m.lineGroup[LINE_GROUP[li]] != 0) {
                    r.trig |= m.lineGroupMask;
                }
                if (m.tripleFlat[s] > 0) {
                    flat += m.tripleFlat[s] * k1;
                }
                if (s == Symbol.CLOVER) {
                    r.tokens += 1 + m.cloverToken;
                    r.trig |= m.cloverMask;
                }
                if (s == Symbol.BELL && g.bellSpinsUsed < m.bellSpinMax) {
                    g.bellSpinsUsed++;
                    r.extraSpins++;
                    r.trig |= m.bellMask;
                }
                for (int q = 0; q < m.grN; q++) {
                    if (m.grSym[q] == s) {
                        g.cardCounter[m.grSlot[q]]++;
                    }
                }
            } else if (m.pairs > 0 && ma && mb && s != Symbol.EYE) {
                int v = value(m, s) * m.pairs * pct / 10000;
                if (v < 1) {
                    v = 1;
                }
                base += v;
                addWin(r, li, s, v, true);
                r.trig |= m.pairsMask;
            }
        }

        // ---- grid-wide counts
        for (int s = 0; s < Symbol.COUNT; s++) {
            cnt[s] = 0;
        }
        for (int i = 0; i < 9; i++) {
            cnt[r.grid[i]]++;
        }
        int need = 3 - m.scatterReduce;
        if (need < 2) {
            need = 2;
        }
        if (cnt[Symbol.STAR] >= need) {
            r.scatterCount = cnt[Symbol.STAR];
            r.scatterWin = r.scatterCount * (value(m, Symbol.STAR) + m.scatterAdd);
            base += r.scatterWin;
            r.trig |= m.scatterMask | m.symMask[Symbol.STAR];
        }
        int multPct = 100 + m.mult;
        if (winLines > 1) {
            multPct += (winLines - 1) * m.combo;
        }
        for (int s = 0; s < Symbol.COUNT; s++) {
            if (cnt[s] > 0) {
                if (m.perSymMult[s] != 0) {
                    multPct += m.perSymMult[s] * cnt[s];
                    r.trig |= m.symMask[s];
                }
                if (m.perSymCoin[s] != 0) {
                    flat += m.perSymCoin[s] * cnt[s] * k1;
                    r.trig |= m.symMask[s];
                }
            }
        }
        // jackpot: all nine cells the same symbol (wilds count), never skulls
        int best = 0;
        for (int s = 0; s < Symbol.EYE; s++) {
            int n = cnt[s] + cnt[Symbol.EYE];
            if (cnt[s] > 0 && n > best) {
                best = n;
            }
        }
        if (cnt[Symbol.EYE] == 9) {
            best = 9;
        }
        r.jackpot = best == 9;
        r.nearJackpot = !r.jackpot && best >= 7;

        boolean won = base + flat > 0;
        if (won) {
            if (m.winStreak > 0 && g.winStreak > 0) {
                multPct += m.winStreak * g.winStreak;
                r.trig |= m.streakMask;
            }
            if (m.lossStreak > 0 && g.lossStreak > 0) {
                multPct += m.lossStreak * g.lossStreak;
                r.trig |= m.streakMask;
            }
            if (r.nearJackpot && m.nearJackpot > 0) {
                multPct += m.nearJackpot;
                r.trig |= m.nearMask;
            }
            if ((g.spinsLeft == 1 && m.lastSpin != 0) || (g.spinIndex == 0 && m.firstSpin != 0)
                    || (g.roundInDl == 2 && m.preDeadline != 0)) {
                r.trig |= m.timeMask;
            }
            r.trig |= m.staticMask;
        }
        if (multPct < 10) {
            multPct = 10;
        }
        long tot = (long) (base + flat) * multPct / 100;
        if (won) {
            if (r.jackpot) {
                tot = tot * JACKPOT_MULT * (100 + m.jackpot) / 100;
                r.trig |= m.jackpotMask;
            }
            for (int q = 0; q < m.nN; q++) {
                int s = m.nSlot[q];
                g.cardCounter[s]++;
                if (m.nEvery[q] > 0 && g.cardCounter[s] % m.nEvery[q] == 0) {
                    tot = tot * (100 + m.nPct[q]) / 100;
                    r.nthFired = true;
                    r.trig |= 1 << s;
                }
            }
            for (int q = 0; q < m.dN; q++) {
                int span = m.dMax[q] - m.dMin[q];
                int p = m.dMin[q] + (span > 0 ? rng.nextInt(span + 1) : 0);
                tot = tot * p / 100;
                r.diceFired = true;
                r.trig |= 1 << m.dSlot[q];
            }
            for (int q = 0; q < m.gN; q++) {
                if (rng.chance(m.gPct[q])) {
                    tot = tot * 2;
                    r.gambleWon = true;
                } else {
                    tot = tot / 2;
                    r.gambleLost = true;
                }
                r.trig |= 1 << m.gSlot[q];
            }
            for (int q = 0; q < m.hN; q++) {
                if (tot >= (long) m.hThr[q] * k1) {
                    tot = tot * (100 + m.hPct[q]) / 100;
                    r.trig |= 1 << m.hSlot[q];
                }
            }
            if (tot < 1) {
                tot = 1;
            }
        }
        if (tot > 1000000000L) {
            tot = 1000000000L;
        }
        r.base = base;
        r.flat = flat;
        r.multPct = multPct;
        r.total = (int) tot;
        if (base + flat > 0) {
            r.effMultX100 = (int) (tot * 100 / (base + flat));
        }

        if (curse) {
            r.cursed = true;
            r.total = 0;
            r.tokens = 0;
            r.extraSpins = 0;
            won = false;
            g.stats.curses++;
        }

        // ---- apply to the run
        if (won) {
            g.winStreak++;
            g.lossStreak = 0;
        } else {
            g.lossStreak++;
            g.winStreak = 0;
            for (int q = 0; q < m.ltN; q++) {
                int s = m.ltSlot[q];
                g.cardCounter[s]++;
                if (m.ltEvery[q] > 0 && g.cardCounter[s] >= m.ltEvery[q]) {
                    g.cardCounter[s] = 0;
                    r.tokens++;
                    r.trig |= 1 << s;
                }
            }
            if (m.minPay > 0 && !curse) {
                r.total = m.minPay * k1;
                r.consolation = true;
                r.trig |= m.minPayMask;
            }
        }
        g.addCoins(r.total);
        g.tokens += r.tokens;
        g.runWon += r.total;
        g.stats.totalWon += r.total;
        if (r.total > g.runBestWin) {
            g.runBestWin = r.total;
        }
        if (r.total > g.stats.biggestWin) {
            g.stats.biggestWin = r.total;
        }
        if (r.jackpot) {
            g.runJackpots++;
            g.stats.jackpots++;
        }
        g.runSpins++;
        g.stats.totalSpins++;

        if (m.freeSpin > 0 && rng.chance(m.freeSpin)) {
            r.freeSpin = true;
            r.trig |= m.freeMask;
        } else {
            g.spinsLeft--;
        }
        g.spinsLeft += r.extraSpins;
        g.spinIndex++;
    }

    private void addWin(SpinResult r, int line, int sym, int amount, boolean pair) {
        if (r.wins < MAX_WINS) {
            r.winLine[r.wins] = line;
            r.winSym[r.wins] = sym;
            r.winAmount[r.wins] = amount;
            r.winPair[r.wins] = pair;
            r.wins++;
        }
    }

    private static int lowestBit(int mask) {
        for (int i = 0; i < 32; i++) {
            if ((mask & (1 << i)) != 0) {
                return i;
            }
        }
        return -1;
    }
}
