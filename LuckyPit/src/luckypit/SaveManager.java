package luckypit;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;

import javax.microedition.rms.RecordStore;

/**
 * RMS persistence with integrity checks.
 *
 * Record 1 holds statistics and settings, records 2 and 3 are two alternating
 * slots for the current run. Every blob is "LPIT" + sequence + length +
 * payload + CRC32. The newest slot that verifies is loaded, so a write torn by
 * a dead battery falls back to the previous save instead of losing the run.
 * Writes happen on a background thread from an already serialised snapshot.
 */
public final class SaveManager implements Runnable {
    private static final String STORE = "LuckyPit";
    private static final int MAGIC = 0x4C504954; // "LPIT"
    private static final int REC_STATS = 1, REC_A = 2, REC_B = 3;
    private static int[] crcTable;

    private static SaveManager inst;
    private byte[] pendingRun, pendingStats;
    private int seq;
    private int nextSlot = REC_A;
    private boolean running = true;
    private boolean writing;
    public static String lastError;

    private SaveManager() {
    }

    public static void init() {
        inst = new SaveManager();
        new Thread(inst).start();
    }

    // ------------------------------------------------------------- CRC32
    public static int crc32(byte[] b, int off, int len) {
        if (crcTable == null) {
            crcTable = new int[256];
            for (int n = 0; n < 256; n++) {
                int c = n;
                for (int k = 0; k < 8; k++) {
                    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
                }
                crcTable[n] = c;
            }
        }
        int c = 0xFFFFFFFF;
        for (int i = off; i < off + len; i++) {
            c = crcTable[(c ^ b[i]) & 0xFF] ^ (c >>> 8);
        }
        return ~c;
    }

    private static byte[] wrap(byte[] payload, int sequence) throws Exception {
        ByteArrayOutputStream bo = new ByteArrayOutputStream(payload.length + 16);
        DataOutputStream o = new DataOutputStream(bo);
        o.writeInt(MAGIC);
        o.writeInt(sequence);
        o.writeInt(payload.length);
        o.write(payload);
        o.flush();
        byte[] head = bo.toByteArray();
        // CRC covers sequence, length and payload
        o.writeInt(crc32(head, 4, head.length - 4));
        o.flush();
        return bo.toByteArray();
    }

    /** Returns payload if the blob verifies, else null. Sequence goes to out[0]. */
    private static byte[] unwrap(byte[] blob, int[] seqOut) {
        try {
            if (blob == null || blob.length < 16) {
                return null;
            }
            DataInputStream in = new DataInputStream(new ByteArrayInputStream(blob));
            if (in.readInt() != MAGIC) {
                return null;
            }
            int s = in.readInt();
            int len = in.readInt();
            if (len < 0 || len != blob.length - 16) {
                return null;
            }
            byte[] p = new byte[len];
            in.readFully(p);
            int crc = in.readInt();
            if (crc != crc32(blob, 4, blob.length - 8)) {
                return null;
            }
            seqOut[0] = s;
            return p;
        } catch (Exception e) {
            return null;
        }
    }

    private static RecordStore open() throws Exception {
        RecordStore rs = RecordStore.openRecordStore(STORE, true);
        while (rs.getNumRecords() < 3) {
            rs.addRecord(new byte[0], 0, 0);
        }
        return rs;
    }

    private static byte[] read(RecordStore rs, int id) {
        try {
            return rs.getRecord(id);
        } catch (Exception e) {
            return null;
        }
    }

    // ------------------------------------------------------------- stats
    public static boolean loadStats(Stats s) {
        RecordStore rs = null;
        try {
            rs = open();
            int[] sq = new int[1];
            byte[] p = unwrap(read(rs, REC_STATS), sq);
            if (p == null) {
                return false;
            }
            s.read(new DataInputStream(new ByteArrayInputStream(p)));
            return true;
        } catch (Exception e) {
            lastError = "stats: " + e;
            return false;
        } finally {
            closeQuiet(rs);
        }
    }

    public static void saveStats(Stats s) {
        try {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            s.write(new DataOutputStream(bo));
            byte[] blob = wrap(bo.toByteArray(), 0);
            synchronized (inst) {
                inst.pendingStats = blob;
                inst.notify();
            }
        } catch (Exception e) {
            lastError = "stats: " + e;
        }
    }

    // ------------------------------------------------------------- run
    /** Loads the newest valid run into g. Returns false if none or corrupt. */
    public static boolean loadRun(GameState g) {
        RecordStore rs = null;
        try {
            rs = open();
            int[] sa = new int[1], sb = new int[1];
            byte[] a = unwrap(read(rs, REC_A), sa);
            byte[] b = unwrap(read(rs, REC_B), sb);
            byte[] first = a, second = b;
            int fs = sa[0];
            if (a == null || (b != null && sb[0] > sa[0])) {
                first = b;
                second = a;
                fs = sb[0];
            }
            if (tryRead(g, first)) {
                inst.seq = fs;
                inst.nextSlot = first == a ? REC_B : REC_A;
                return g.active;
            }
            if (tryRead(g, second)) {
                inst.seq = fs;
                inst.nextSlot = second == a ? REC_B : REC_A;
                return g.active;
            }
            return false;
        } catch (Exception e) {
            lastError = "run: " + e;
            return false;
        } finally {
            closeQuiet(rs);
        }
    }

    private static boolean tryRead(GameState g, byte[] p) {
        if (p == null) {
            return false;
        }
        try {
            g.read(new DataInputStream(new ByteArrayInputStream(p)));
            return true;
        } catch (Exception e) {
            g.clear();
            return false;
        }
    }

    public static boolean hasRun(GameState probe) {
        return loadRun(probe);
    }

    /** Serialises now, writes in the background. */
    public static void saveRun(GameState g) {
        try {
            ByteArrayOutputStream bo = new ByteArrayOutputStream(400);
            g.write(new DataOutputStream(bo));
            synchronized (inst) {
                inst.seq++;
                inst.pendingRun = wrap(bo.toByteArray(), inst.seq);
                inst.notify();
            }
        } catch (Exception e) {
            lastError = "run: " + e;
        }
    }

    /** Clears both run slots (after defeat/victory or new game). */
    public static void clearRun() {
        synchronized (inst) {
            inst.pendingRun = new byte[0];
            inst.notify();
        }
    }

    /** Writes everything pending on the calling thread (used on exit/pause). */
    public static void flush() {
        if (inst != null) {
            inst.writePending();
        }
    }

    public static void shutdown() {
        flush();
        synchronized (inst) {
            inst.running = false;
            inst.notify();
        }
    }

    public void run() {
        while (true) {
            synchronized (this) {
                if (!running) {
                    return;
                }
                if (pendingRun == null && pendingStats == null) {
                    try {
                        wait();
                    } catch (InterruptedException e) {
                        // ignore
                    }
                }
            }
            writePending();
        }
    }

    private void writePending() {
        byte[] r, s;
        int slot;
        synchronized (this) {
            while (writing) {
                try {
                    wait(50);
                } catch (InterruptedException e) {
                    // ignore
                }
            }
            r = pendingRun;
            s = pendingStats;
            pendingRun = null;
            pendingStats = null;
            if (r == null && s == null) {
                return;
            }
            writing = true;
            slot = nextSlot;
            if (r != null && r.length > 0) {
                nextSlot = slot == REC_A ? REC_B : REC_A;
            }
        }
        RecordStore rs = null;
        try {
            rs = open();
            if (s != null) {
                rs.setRecord(REC_STATS, s, 0, s.length);
            }
            if (r != null) {
                if (r.length == 0) {
                    rs.setRecord(REC_A, r, 0, 0);
                    rs.setRecord(REC_B, r, 0, 0);
                } else {
                    rs.setRecord(slot, r, 0, r.length);
                }
            }
        } catch (Exception e) {
            lastError = "write: " + e;
        } finally {
            closeQuiet(rs);
            synchronized (this) {
                writing = false;
                notifyAll();
            }
        }
    }

    private static void closeQuiet(RecordStore rs) {
        if (rs != null) {
            try {
                rs.closeRecordStore();
            } catch (Exception e) {
                // ignore
            }
        }
    }

    /** Deletes the whole store (settings reset). */
    public static void wipe() {
        try {
            RecordStore.deleteRecordStore(STORE);
        } catch (Exception e) {
            // nothing to delete
        }
    }
}
