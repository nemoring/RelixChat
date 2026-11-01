import dev.kiwifuzzy.kiwion.Pow;
import dev.kiwifuzzy.kiwion.TapCounter;

/** Plain-JVM tests for Android logic that does not depend on the Android framework. */
public class MobileLogicTest {
    static long now = 0;

    static void check(boolean cond, String msg) {
        if (!cond) throw new AssertionError(msg);
        System.out.println("ok - " + msg);
    }

    public static void main(String[] args) {
        TapCounter t = new TapCounter(5, 1500, new TapCounter.Clock() { public long now() { return now; } });
        // five quick taps fire on the fifth
        for (int i = 0; i < 4; i++) { now += 300; check(!t.tap(), "tap " + (i + 1) + " does not fire"); }
        now += 300;
        check(t.tap(), "5th quick tap fires the easter egg");
        // works repeatedly
        for (int i = 0; i < 4; i++) { now += 200; t.tap(); }
        now += 200;
        check(t.tap(), "fires again on the next 5 taps");
        // a pause longer than 1.5 s resets the counter
        for (int i = 0; i < 4; i++) { now += 300; t.tap(); }
        now += 1501;
        check(!t.tap(), "pause > 1.5 s resets (this tap counts as the 1st)");
        check(t.count() == 1, "counter restarted at 1");
        for (int i = 0; i < 3; i++) { now += 1500; check(!t.tap(), "gap of exactly 1.5 s keeps counting"); }
        now += 1500;
        check(t.tap(), "5 taps with 1.5 s gaps fire");

        // proof of work: same algorithm as the server (sha256(challenge:nonce) leading zero bits)
        String nonce = Pow.solve("1700000000.abcdef.0123456789abcdef", 12);
        System.out.println("NONCE=" + nonce);
        check(Pow.leadingZeroBits(new byte[]{0, 0, (byte) 0x10}) == 19, "leading zero bits");
    }
}
