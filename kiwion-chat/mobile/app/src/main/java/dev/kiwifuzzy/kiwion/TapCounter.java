package dev.kiwifuzzy.kiwion;

/**
 * Counts quick consecutive taps. Returns true on the N-th tap when every gap between
 * taps is at most maxGapMs; a longer pause silently resets the counter.
 * Pure Java so it can be unit-tested on the JVM (see tests/mobile/TapCounterTest.java).
 */
public final class TapCounter {
    public interface Clock { long now(); }

    private final int required;
    private final long maxGapMs;
    private final Clock clock;
    private int count;
    private long last = Long.MIN_VALUE / 2;

    public TapCounter(int required, long maxGapMs, Clock clock) {
        this.required = required;
        this.maxGapMs = maxGapMs;
        this.clock = clock;
    }

    public boolean tap() {
        long t = clock.now();
        if (t - last > maxGapMs) count = 0;
        last = t;
        count++;
        if (count >= required) {
            count = 0;
            last = Long.MIN_VALUE / 2;
            return true;
        }
        return false;
    }

    public int count() { return count; }
}
