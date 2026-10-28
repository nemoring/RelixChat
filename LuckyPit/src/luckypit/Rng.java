package luckypit;

/**
 * Small deterministic xorshift32 generator. Its whole state is one int so it
 * can be saved with the run: reloading a save never re-rolls a spin.
 */
public final class Rng {
    private int s;

    public Rng(int seed) {
        setState(seed);
    }

    public void setState(int seed) {
        s = seed == 0 ? 0x2545F491 : seed;
    }

    public int getState() {
        return s;
    }

    public int next() {
        int x = s;
        x ^= x << 13;
        x ^= x >>> 17;
        x ^= x << 5;
        s = x;
        return x;
    }

    /** Uniform integer in [0, n). */
    public int nextInt(int n) {
        if (n <= 1) {
            return 0;
        }
        return (int) (((long) (next() >>> 1)) % n);
    }

    /** True with probability pct/100. */
    public boolean chance(int pct) {
        return pct > 0 && (pct >= 100 || nextInt(100) < pct);
    }
}
