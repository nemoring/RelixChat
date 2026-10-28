package luckypit;

/**
 * Turns owned cards, family set bonuses, upgrades and event modifiers into a
 * flat {@link Mods} snapshot that the slot machine reads during a spin.
 * The snapshot object is reused to avoid garbage in the game loop.
 */
public final class EffectManager {

    public static final int BASE_COMBO = 25;
    public static final int L = 16;

    /** Aggregated modifiers for one spin / one shop visit. */
    public static final class Mods {
        public final int[] valAdd = new int[Symbol.COUNT];
        public final int[] symMul = new int[Symbol.COUNT];
        public final int[] weight = new int[Symbol.COUNT];
        public final int[] perSymMult = new int[Symbol.COUNT];
        public final int[] perSymCoin = new int[Symbol.COUNT];
        public final int[] tripleFlat = new int[Symbol.COUNT];
        /** Slots whose effects relate to a symbol (for trigger flashes). */
        public final int[] symMask = new int[Symbol.COUNT];
        public final int[] lineGroup = new int[6];
        public int lineGroupMask;

        public int mult, lastSpin, firstSpin, preDeadline, jackpot, nearJackpot;
        public int skullWard;
        public boolean ward;
        public int lossStreak, winStreak, pairs, scatterReduce, scatterAdd, bellSpinMax, cloverToken;
        public int debtCut, debtAdd, sellBonus, discount, freeReroll, deadlineCoins, roundCoins, minPay;
        public int interest, tokensRound, spins, eyeBonus, freeSpin, shopSlots, lucky, combo;
        public int chaos, wildChance, copyRow;
        public int reviveSlot;
        public int staticMask, streakMask, timeMask, wardMask, chaosMask, wildMask, copyMask, freeMask,
                pairsMask, eyeMask, minPayMask, jackpotMask, nearMask, scatterMask, bellMask, cloverMask;
        public int setBits;

        // per-slot effect lists
        public int nN;
        public final int[] nSlot = new int[L], nEvery = new int[L], nPct = new int[L];
        public int dN;
        public final int[] dSlot = new int[L], dMin = new int[L], dMax = new int[L];
        public int gN;
        public final int[] gSlot = new int[L], gPct = new int[L];
        public int hN;
        public final int[] hSlot = new int[L], hThr = new int[L], hPct = new int[L];
        public int tN;
        public final int[] tSlot = new int[L], tFrom = new int[L], tTo = new int[L], tChance = new int[L];
        public int ltN;
        public final int[] ltSlot = new int[L], ltEvery = new int[L];
        public int grN;
        public final int[] grSlot = new int[L], grSym = new int[L];

        void reset() {
            for (int i = 0; i < Symbol.COUNT; i++) {
                valAdd[i] = symMul[i] = weight[i] = perSymMult[i] = perSymCoin[i] = tripleFlat[i] = 0;
                symMask[i] = 0;
            }
            for (int i = 0; i < 6; i++) {
                lineGroup[i] = 0;
            }
            lineGroupMask = 0;
            mult = lastSpin = firstSpin = preDeadline = jackpot = nearJackpot = 0;
            skullWard = 0;
            ward = false;
            lossStreak = winStreak = pairs = scatterReduce = scatterAdd = bellSpinMax = cloverToken = 0;
            debtCut = debtAdd = sellBonus = discount = freeReroll = deadlineCoins = roundCoins = minPay = 0;
            interest = tokensRound = spins = eyeBonus = freeSpin = shopSlots = lucky = 0;
            combo = BASE_COMBO;
            chaos = wildChance = copyRow = 0;
            reviveSlot = -1;
            staticMask = streakMask = timeMask = wardMask = chaosMask = wildMask = copyMask = freeMask = 0;
            pairsMask = eyeMask = minPayMask = jackpotMask = nearMask = scatterMask = bellMask = cloverMask = 0;
            setBits = 0;
            nN = dN = gN = hN = tN = ltN = grN = 0;
        }
    }

    private EffectManager() {
    }

    /** Card definition that executes in a slot (mirrors copy the right neighbour). */
    public static Card execCard(GameState g, int slot, int k) {
        int id = g.cards[slot];
        if (id < 0) {
            return null;
        }
        Card c = CardManager.get(id);
        if (c.op[k] == Op.MIRROR) {
            if (slot + 1 < GameState.MAX_SLOTS && g.cards[slot + 1] >= 0) {
                return CardManager.get(g.cards[slot + 1]);
            }
            return null;
        }
        return c;
    }

    /** Builds the snapshot. spinIndex/spinsRound decide first/last spin bonuses. */
    public static void compute(GameState g, Mods m) {
        m.reset();
        int k1 = g.deadline + 1;
        int owned = 0;
        int famMask = 0;
        int[] famCount = TMP_FAM;
        for (int f = 0; f < Card.FAMILIES; f++) {
            famCount[f] = 0;
        }
        for (int s = 0; s < GameState.MAX_SLOTS; s++) {
            if (g.cards[s] >= 0) {
                owned++;
                Card c = CardManager.get(g.cards[s]);
                famCount[c.family]++;
                famMask |= 1 << c.family;
            }
        }
        int cap = CardManager.capacity(g);

        for (int s = 0; s < GameState.MAX_SLOTS; s++) {
            if (g.cards[s] < 0) {
                continue;
            }
            Card own = CardManager.get(g.cards[s]);
            for (int k = 0; k < 2; k++) {
                if (own.op[k] == 0) {
                    continue;
                }
                if (own.op[k] == Op.MIRROR) {
                    Card t = execCard(g, s, k);
                    if (t != null && !t.has(Op.MIRROR)) {
                        for (int kk = 0; kk < 2; kk++) {
                            if (t.op[kk] != 0 && t.op[kk] != Op.SLOTS && t.op[kk] != Op.REVIVE) {
                                apply(g, m, s, t.op[kk], t.a[kk], t.b[kk], t.c[kk], k1, owned, cap, famCount, famMask);
                            }
                        }
                    }
                } else {
                    apply(g, m, s, own.op[k], own.a[k], own.b[k], own.c[k], k1, owned, cap, famCount, famMask);
                }
            }
        }

        // family set bonuses
        for (int f = 0; f < Card.FAMILIES; f++) {
            if (famCount[f] >= 2) {
                m.setBits |= 1 << (f * 2);
                setBonus(m, f, false);
            }
            if (famCount[f] >= 4) {
                m.setBits |= 1 << (f * 2 + 1);
                setBonus(m, f, true);
            }
        }

        // machine upgrades
        int gild = g.upg[GameState.U_GILD];
        for (int i = 0; i < Symbol.EYE; i++) {
            m.valAdd[i] += gild;
        }
        m.combo += 15 * g.upg[GameState.U_COMBO];
        m.interest += 3 * g.upg[GameState.U_SAFE];
        m.weight[Symbol.SKULL] -= g.upg[GameState.U_SKULLF];
        m.weight[Symbol.EYE] += g.upg[GameState.U_MAGNET];
        m.spins += g.upg[GameState.U_SPIN];
        m.mult += 20 * g.upg[GameState.U_OIL];

        // events
        if (g.evSym >= 0) {
            m.weight[g.evSym] += g.evSymAdd;
        }
        m.mult += g.evMult;

        // time-based bonuses
        boolean last = g.spinsLeft == 1;
        boolean first = g.spinIndex == 0;
        if (last && m.lastSpin != 0) {
            m.mult += m.lastSpin;
        }
        if (first && m.firstSpin != 0) {
            m.mult += m.firstSpin;
        }
        if (g.roundInDl == GameState.ROUNDS_PER_DEADLINE - 1 && m.preDeadline != 0) {
            m.mult += m.preDeadline;
        }
        if (m.interest > 30) {
            m.interest = 30;
        }
        if (m.discount > 60) {
            m.discount = 60;
        }
    }

    private static final int[] TMP_FAM = new int[Card.FAMILIES];

    private static void setBonus(Mods m, int f, boolean four) {
        switch (f) {
            case 0:
                if (four) {
                    m.symMul[Symbol.CHERRY] += 100;
                    m.symMul[Symbol.LEMON] += 100;
                } else {
                    m.valAdd[Symbol.CHERRY] += 1;
                    m.valAdd[Symbol.LEMON] += 1;
                }
                break;
            case 1:
                if (four) {
                    m.weight[Symbol.EYE] += 3;
                    m.tokensRound += 1;
                } else {
                    m.weight[Symbol.CLOVER] += 4;
                    m.weight[Symbol.HORSESHOE] += 4;
                }
                break;
            case 2:
                if (four) {
                    m.scatterReduce += 1;
                    m.symMul[Symbol.DIAMOND] += 100;
                } else {
                    m.valAdd[Symbol.STAR] += 2;
                    m.valAdd[Symbol.DIAMOND] += 2;
                }
                break;
            case 3:
                if (four) {
                    m.symMul[Symbol.SEVEN] += 150;
                    m.jackpot += 100;
                } else {
                    m.weight[Symbol.SEVEN] += 2;
                }
                break;
            case 4:
                if (four) {
                    m.ward = true;
                    if (m.skullWard < 30) {
                        m.skullWard = 30;
                    }
                } else {
                    m.mult += 25;
                }
                break;
            case 5:
                if (four) {
                    m.lastSpin += 200;
                } else {
                    m.spins += 1;
                }
                break;
            case 6:
                if (four) {
                    m.debtCut += 10;
                } else {
                    m.interest += 3;
                }
                break;
            default:
                if (four) {
                    m.wildChance += 100;
                } else {
                    m.weight[Symbol.EYE] += 2;
                }
                break;
        }
    }

    private static void apply(GameState g, Mods m, int s, int op, int a, int b, int c, int k1,
                              int owned, int cap, int[] famCount, int famMask) {
        int bit = 1 << s;
        switch (op) {
            case Op.VAL_ADD: m.valAdd[a] += b; m.symMask[a] |= bit; break;
            case Op.VAL_MUL: m.symMul[a] += b; m.symMask[a] |= bit; break;
            case Op.WEIGHT: m.weight[a] += b; break;
            case Op.MULT: m.mult += a; m.staticMask |= bit; break;
            case Op.PER_SYM_MULT: m.perSymMult[a] += b; m.symMask[a] |= bit; break;
            case Op.PER_SYM_COIN: m.perSymCoin[a] += b; m.symMask[a] |= bit; break;
            case Op.LAST_SPIN: m.lastSpin += a; m.timeMask |= bit; break;
            case Op.FIRST_SPIN: m.firstSpin += a; m.timeMask |= bit; break;
            case Op.NTH_WIN:
                if (m.nN < L) {
                    m.nSlot[m.nN] = s; m.nEvery[m.nN] = a; m.nPct[m.nN] = b; m.nN++;
                }
                break;
            case Op.CHAOS: m.chaos += a; m.chaosMask |= bit; break;
            case Op.JACKPOT: m.jackpot += a; m.jackpotMask |= bit; break;
            case Op.TRIPLE_FLAT: m.tripleFlat[a] += b; m.symMask[a] |= bit; break;
            case Op.DEBT_ADD: m.debtAdd += a; break;
            case Op.SPINS: m.spins += a; break;
            case Op.INTEREST: m.interest += a; break;
            case Op.TOKENS_ROUND: m.tokensRound += a; break;
            case Op.SKULL_WARD:
                m.ward = true;
                if (a > m.skullWard) {
                    m.skullWard = a;
                }
                m.wardMask |= bit;
                break;
            case Op.LOSS_STREAK: m.lossStreak += a; m.streakMask |= bit; break;
            case Op.WIN_STREAK: m.winStreak += a; m.streakMask |= bit; break;
            case Op.EMPTY_SLOT: {
                int empty = cap - owned;
                if (empty > 0) {
                    m.mult += a * empty;
                    m.staticMask |= bit;
                }
                break;
            }
            case Op.PER_CARD: m.mult += a * owned; m.staticMask |= bit; break;
            case Op.PER_RARITY: {
                int n = CardManager.countRarity(g, a);
                if (n > 0) {
                    m.mult += b * n;
                    m.staticMask |= bit;
                }
                break;
            }
            case Op.RICH: {
                int per = a * k1;
                int p = per > 0 ? g.coins / per : 0;
                if (p > b) {
                    p = b;
                }
                if (p > 0) {
                    m.mult += p;
                    m.staticMask |= bit;
                }
                break;
            }
            case Op.LINE_GROUP: m.lineGroup[a] += b; m.lineGroupMask |= bit; break;
            case Op.PAIRS: m.pairs += a; m.pairsMask |= bit; break;
            case Op.STAR_SCATTER: m.scatterReduce += a; m.scatterAdd += b; m.scatterMask |= bit; break;
            case Op.BELL_SPIN: m.bellSpinMax += a; m.bellMask |= bit; break;
            case Op.CLOVER_TOKEN: m.cloverToken += a; m.cloverMask |= bit; break;
            case Op.DEBT_CUT: m.debtCut += a; break;
            case Op.SELL_BONUS: m.sellBonus += a; break;
            case Op.DISCOUNT: m.discount += a; break;
            case Op.FREE_REROLL: m.freeReroll += a; break;
            case Op.DEADLINE_COINS: m.deadlineCoins += a; break;
            case Op.GROW_SYM:
                m.symMul[a] += b * g.cardCounter[s];
                m.symMask[a] |= bit;
                if (m.grN < L) {
                    m.grSlot[m.grN] = s; m.grSym[m.grN] = a; m.grN++;
                }
                break;
            case Op.ROUND_COINS: m.roundCoins += a; break;
            case Op.DICE:
                if (m.dN < L) {
                    m.dSlot[m.dN] = s; m.dMin[m.dN] = a; m.dMax[m.dN] = b; m.dN++;
                }
                break;
            case Op.TRANSFORM:
                if (m.tN < L) {
                    m.tSlot[m.tN] = s; m.tFrom[m.tN] = a; m.tTo[m.tN] = b; m.tChance[m.tN] = c; m.tN++;
                }
                break;
            case Op.MIN_PAY: m.minPay += a; m.minPayMask |= bit; break;
            case Op.LOSS_TOKEN:
                if (m.ltN < L) {
                    m.ltSlot[m.ltN] = s; m.ltEvery[m.ltN] = a; m.ltN++;
                }
                break;
            case Op.WILD_CELL: m.wildChance += a; m.wildMask |= bit; break;
            case Op.GAMBLE:
                if (m.gN < L) {
                    m.gSlot[m.gN] = s; m.gPct[m.gN] = a; m.gN++;
                }
                break;
            case Op.TOKEN_MULT:
                if (g.tokens > 0) {
                    m.mult += a * g.tokens;
                    m.staticMask |= bit;
                }
                break;
            case Op.DEADLINE_MULT:
                if (g.deadline > 0) {
                    m.mult += a * g.deadline;
                    m.staticMask |= bit;
                }
                break;
            case Op.SLOTS: break;
            case Op.PRE_DEADLINE: m.preDeadline += a; m.timeMask |= bit; break;
            case Op.EYE_BONUS: m.eyeBonus += a; m.eyeMask |= bit; break;
            case Op.FREE_SPIN: m.freeSpin += a; m.freeMask |= bit; break;
            case Op.NEAR_JACKPOT: m.nearJackpot += a; m.nearMask |= bit; break;
            case Op.ON_BUY_COINS: break;
            case Op.ON_BUY_TOKENS: break;
            case Op.INVEST: break;
            case Op.HIGH_ROLLER:
                if (m.hN < L) {
                    m.hSlot[m.hN] = s; m.hThr[m.hN] = a; m.hPct[m.hN] = b; m.hN++;
                }
                break;
            case Op.FAMILY_BOOST:
                if (famCount[a] > 0) {
                    m.mult += b * famCount[a];
                    m.staticMask |= bit;
                }
                break;
            case Op.GROW_MULT:
                if (g.cardAge[s] > 0) {
                    m.mult += a * g.cardAge[s];
                    m.staticMask |= bit;
                }
                break;
            case Op.COPY_ROW: m.copyRow += a; m.copyMask |= bit; break;
            case Op.SHOP_SLOTS: m.shopSlots += a; break;
            case Op.LUCKY_RARITY: m.lucky += a; break;
            case Op.COMBO: m.combo += a; m.staticMask |= bit; break;
            case Op.FAMILY_VARIETY: {
                int n = 0;
                for (int f = 0; f < Card.FAMILIES; f++) {
                    if ((famMask & (1 << f)) != 0) {
                        n++;
                    }
                }
                m.mult += a * n;
                m.staticMask |= bit;
                break;
            }
            case Op.REVIVE:
                if (m.reviveSlot < 0) {
                    m.reviveSlot = s;
                }
                break;
            default:
                break;
        }
    }
}
