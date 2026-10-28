package luckypit;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

/** Complete state of a run (everything the save file stores). */
public final class GameState {
    public static final int MAX_SLOTS = 8;
    public static final int BASE_SLOTS = 4;
    public static final int DEADLINES = 8;
    public static final int ROUNDS_PER_DEADLINE = 3;
    public static final int START_COINS = 15;
    public static final int BASE_SPINS = 7;
    public static final int SHORT_SPINS = 3;
    public static final int SHORT_TOKENS = 2;
    public static final int MAX_OFFERS = 6;

    // phases
    public static final int PH_PREP = 0, PH_PLAY = 1, PH_ROUND_END = 2, PH_EVENT = 3, PH_SHOP = 4,
            PH_OVER = 5, PH_WON = 6;

    // upgrades
    public static final int U_VLINES = 0, U_COLS = 1, U_SLOT = 2, U_SPIN = 3, U_GILD = 4, U_COMBO = 5,
            U_SAFE = 6, U_SKULLF = 7, U_MAGNET = 8, U_OIL = 9;
    public static final int UPGRADES = 10;
    public static final int[][] UPG_COST = {
            {4}, {6}, {2, 3, 4, 5}, {3, 4, 6}, {4, 6, 8}, {2, 3, 4}, {3, 4, 5}, {2, 3, 4}, {4, 6}, {3, 5, 7}};

    // endings
    public static final int END_NONE = 0, END_FREEDOM = 1, END_OWNER = 2, END_CURSED = 3, END_LOST = 4;

    public final Stats stats;
    public final Rng rng = new Rng(1);

    public boolean active;
    public int phase;
    public int coins, tokens;
    public int deadline, roundInDl, roundsPlayed;
    public int debtBase;          // debt fixed when the deadline started (with DEBT_ADD applied)
    public int spinsLeft, spinsRound, spinIndex;
    public final int[] cards = new int[MAX_SLOTS];
    public final int[] cardCounter = new int[MAX_SLOTS];
    public final int[] cardPaid = new int[MAX_SLOTS];
    public final int[] cardAge = new int[MAX_SLOTS];
    public final int[] upg = new int[UPGRADES];
    /** Grid shown after the last spin (restored on load). */
    public final int[] lastGrid = new int[9];

    // spin counters
    public int winStreak, lossStreak, lossTokenCounter, bellSpinsUsed;

    // random event modifiers for the next round
    public int evSym = -1, evSymAdd, evSpins, evMult;

    // shop
    public final int[] offer = new int[MAX_OFFERS];
    public final int[] offerPrice = new int[MAX_OFFERS];
    public int offerCount, freeRerolls, rerolls;
    /** Starter gift: the shop offers are free, only one may be taken. */
    public boolean freePick;
    public int eventId = -1;
    public int ending;

    // run statistics
    public int runBestWin, runJackpots, runSpins, runWon;
    public int lastRoundInterest, lastRoundCoins, lastRoundTokens, lastPaid;

    public GameState(Stats s) {
        stats = s;
        clear();
    }

    public void clear() {
        active = false;
        phase = PH_PREP;
        coins = tokens = 0;
        deadline = roundInDl = roundsPlayed = 0;
        debtBase = 0;
        spinsLeft = spinsRound = spinIndex = 0;
        for (int i = 0; i < MAX_SLOTS; i++) {
            cards[i] = -1;
            cardCounter[i] = cardPaid[i] = cardAge[i] = 0;
        }
        for (int i = 0; i < UPGRADES; i++) {
            upg[i] = 0;
        }
        for (int i = 0; i < 9; i++) {
            lastGrid[i] = i % 8;
        }
        winStreak = lossStreak = lossTokenCounter = bellSpinsUsed = 0;
        evSym = -1;
        evSymAdd = evSpins = evMult = 0;
        offerCount = freeRerolls = rerolls = 0;
        freePick = false;
        for (int i = 0; i < MAX_OFFERS; i++) {
            offer[i] = -1;
        }
        eventId = -1;
        ending = END_NONE;
        runBestWin = runJackpots = runSpins = runWon = 0;
        lastRoundInterest = lastRoundCoins = lastRoundTokens = lastPaid = 0;
    }

    public void addCoins(int v) {
        long n = (long) coins + v;
        if (n > 2000000000L) {
            n = 2000000000L;
        }
        if (n < 0) {
            n = 0;
        }
        coins = (int) n;
        if (coins > stats.maxCoins) {
            stats.maxCoins = coins;
        }
    }

    public int upgCost(int u) {
        int lvl = upg[u];
        if (lvl >= UPG_COST[u].length) {
            return -1;
        }
        return UPG_COST[u][lvl];
    }

    public boolean lineActive(int line) {
        if (line <= 2) {
            return true;
        }
        if (line <= 4) {
            return true;
        }
        if (line <= 6) {
            return upg[U_VLINES] > 0;
        }
        return upg[U_COLS] > 0;
    }

    public int activeLines() {
        int n = 0;
        for (int i = 0; i < SlotMachine.LINES.length; i++) {
            if (lineActive(i)) {
                n++;
            }
        }
        return n;
    }

    // ---------------------------------------------------------------- save
    public static final int VERSION = 4;

    public void write(DataOutputStream o) throws IOException {
        o.writeInt(VERSION);
        o.writeBoolean(active);
        o.writeByte(phase);
        o.writeInt(coins); o.writeInt(tokens);
        o.writeByte(deadline); o.writeByte(roundInDl); o.writeShort(roundsPlayed);
        o.writeInt(debtBase);
        o.writeShort(spinsLeft); o.writeShort(spinsRound); o.writeShort(spinIndex);
        for (int i = 0; i < MAX_SLOTS; i++) {
            o.writeShort(cards[i]); o.writeInt(cardCounter[i]); o.writeInt(cardPaid[i]); o.writeShort(cardAge[i]);
        }
        for (int i = 0; i < UPGRADES; i++) {
            o.writeByte(upg[i]);
        }
        o.writeShort(winStreak); o.writeShort(lossStreak); o.writeShort(lossTokenCounter); o.writeShort(bellSpinsUsed);
        o.writeByte(evSym); o.writeShort(evSymAdd); o.writeShort(evSpins); o.writeShort(evMult);
        for (int i = 0; i < MAX_OFFERS; i++) {
            o.writeShort(offer[i]); o.writeInt(offerPrice[i]);
        }
        o.writeByte(offerCount); o.writeByte(freeRerolls); o.writeShort(rerolls);
        o.writeBoolean(freePick);
        o.writeByte(eventId);
        o.writeByte(ending);
        o.writeInt(runBestWin); o.writeInt(runJackpots); o.writeInt(runSpins); o.writeInt(runWon);
        o.writeInt(lastRoundInterest); o.writeInt(lastRoundCoins); o.writeInt(lastRoundTokens); o.writeInt(lastPaid);
        o.writeInt(rng.getState());
        for (int i = 0; i < 9; i++) {
            o.writeByte(lastGrid[i]);
        }
    }

    /** Reads a run. Throws on any inconsistency so the caller can fall back. */
    public void read(DataInputStream in) throws IOException {
        if (in.readInt() != VERSION) {
            throw new IOException("ver");
        }
        active = in.readBoolean();
        phase = in.readByte();
        coins = in.readInt(); tokens = in.readInt();
        deadline = in.readByte(); roundInDl = in.readByte(); roundsPlayed = in.readShort();
        debtBase = in.readInt();
        spinsLeft = in.readShort(); spinsRound = in.readShort(); spinIndex = in.readShort();
        int n = CardManager.count();
        for (int i = 0; i < MAX_SLOTS; i++) {
            cards[i] = in.readShort(); cardCounter[i] = in.readInt(); cardPaid[i] = in.readInt(); cardAge[i] = in.readShort();
            if (cards[i] < -1 || cards[i] >= n) {
                throw new IOException("card");
            }
        }
        for (int i = 0; i < UPGRADES; i++) {
            upg[i] = in.readByte();
            if (upg[i] < 0 || upg[i] > UPG_COST[i].length) {
                throw new IOException("upg");
            }
        }
        winStreak = in.readShort(); lossStreak = in.readShort(); lossTokenCounter = in.readShort(); bellSpinsUsed = in.readShort();
        evSym = in.readByte(); evSymAdd = in.readShort(); evSpins = in.readShort(); evMult = in.readShort();
        for (int i = 0; i < MAX_OFFERS; i++) {
            offer[i] = in.readShort(); offerPrice[i] = in.readInt();
            if (offer[i] < -1 || offer[i] >= n) {
                throw new IOException("offer");
            }
        }
        offerCount = in.readByte(); freeRerolls = in.readByte(); rerolls = in.readShort();
        freePick = in.readBoolean();
        eventId = in.readByte();
        ending = in.readByte();
        runBestWin = in.readInt(); runJackpots = in.readInt(); runSpins = in.readInt(); runWon = in.readInt();
        lastRoundInterest = in.readInt(); lastRoundCoins = in.readInt(); lastRoundTokens = in.readInt(); lastPaid = in.readInt();
        rng.setState(in.readInt());
        for (int i = 0; i < 9; i++) {
            lastGrid[i] = in.readByte();
            if (lastGrid[i] < 0 || lastGrid[i] >= Symbol.COUNT) {
                throw new IOException("grid");
            }
        }
        if (phase < PH_PREP || phase > PH_WON || deadline < 0 || deadline >= DEADLINES
                || roundInDl < 0 || roundInDl >= ROUNDS_PER_DEADLINE || coins < 0 || tokens < 0
                || spinsLeft < 0 || spinsLeft > 99 || offerCount < 0 || offerCount > MAX_OFFERS) {
            throw new IOException("range");
        }
    }
}
