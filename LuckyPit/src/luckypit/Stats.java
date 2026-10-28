package luckypit;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

/** Persistent statistics, card discovery and settings (survive runs). */
public final class Stats {
    public int runs, wins, losses, bestDeadline, maxCoins, totalSpins, jackpots, biggestWin;
    public int cardsBought, endings, totalWon, curses;
    public final byte[] discovered = new byte[32];

    // settings
    public boolean sound = true, music = true, fx = true, fastReels = false;

    public void discover(int id) {
        if (id >= 0 && id < discovered.length * 8) {
            discovered[id >> 3] |= (byte) (1 << (id & 7));
        }
    }

    public boolean isDiscovered(int id) {
        return id >= 0 && id < discovered.length * 8 && (discovered[id >> 3] & (1 << (id & 7))) != 0;
    }

    public int discoveredCount() {
        int n = 0;
        for (int i = 0; i < discovered.length * 8; i++) {
            if (isDiscovered(i)) {
                n++;
            }
        }
        return n;
    }

    public void write(DataOutputStream o) throws IOException {
        o.writeInt(runs); o.writeInt(wins); o.writeInt(losses); o.writeInt(bestDeadline);
        o.writeInt(maxCoins); o.writeInt(totalSpins); o.writeInt(jackpots); o.writeInt(biggestWin);
        o.writeInt(cardsBought); o.writeInt(endings); o.writeInt(totalWon); o.writeInt(curses);
        o.write(discovered);
        o.writeBoolean(sound); o.writeBoolean(music); o.writeBoolean(fx); o.writeBoolean(fastReels);
    }

    public void read(DataInputStream i) throws IOException {
        runs = i.readInt(); wins = i.readInt(); losses = i.readInt(); bestDeadline = i.readInt();
        maxCoins = i.readInt(); totalSpins = i.readInt(); jackpots = i.readInt(); biggestWin = i.readInt();
        cardsBought = i.readInt(); endings = i.readInt(); totalWon = i.readInt(); curses = i.readInt();
        i.readFully(discovered);
        sound = i.readBoolean(); music = i.readBoolean(); fx = i.readBoolean(); fastReels = i.readBoolean();
    }

    public void resetProgress() {
        runs = wins = losses = bestDeadline = maxCoins = totalSpins = jackpots = biggestWin = 0;
        cardsBought = endings = totalWon = curses = 0;
        for (int k = 0; k < discovered.length; k++) {
            discovered[k] = 0;
        }
    }
}
