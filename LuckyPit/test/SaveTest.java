import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.lang.reflect.Method;

import luckypit.*;

/**
 * Save integrity tests (Java SE): state round trip, CRC catches every
 * single-byte corruption, truncated/garbage blobs are rejected, and a corrupt
 * payload with a valid CRC still fails range validation instead of loading.
 */
public class SaveTest {
    public static void main(String[] a) throws Exception {
        CardManager.load();
        Method wrap = SaveManager.class.getDeclaredMethod("wrap", byte[].class, int.class);
        Method unwrap = SaveManager.class.getDeclaredMethod("unwrap", byte[].class, int[].class);
        wrap.setAccessible(true);
        unwrap.setAccessible(true);

        // play a little to get a non-trivial state
        Stats st = new Stats();
        GameState g = new GameState(st);
        EffectManager.Mods m = new EffectManager.Mods();
        DebtManager.newRun(g, 4242);
        Shop.buy(g, m, 0);
        g.phase = GameState.PH_PREP;
        DebtManager.startRound(g, m, false);
        SlotMachine sm = new SlotMachine();
        SlotMachine.SpinResult r = new SlotMachine.SpinResult();
        for (int i = 0; i < 4; i++) {
            EffectManager.compute(g, m);
            sm.spin(g, m, r);
        }
        byte[] payload = bytes(g);
        byte[] blob = (byte[]) wrap.invoke(null, payload, 7);

        // 1. round trip
        int[] seq = new int[1];
        byte[] back = (byte[]) unwrap.invoke(null, blob, seq);
        check(back != null && seq[0] == 7, "unwrap valid blob");
        GameState g2 = new GameState(new Stats());
        g2.read(new DataInputStream(new ByteArrayInputStream(back)));
        check(java.util.Arrays.equals(bytes(g2), payload), "state round trip is identical");
        check(g2.coins == g.coins && g2.spinsLeft == g.spinsLeft && g2.cards[0] == g.cards[0], "fields restored");
        check(g2.rng.getState() == g.rng.getState(), "rng restored (no re-rolls after reload)");

        // 2. every single-byte corruption is detected
        int detected = 0;
        for (int i = 0; i < blob.length; i++) {
            byte[] c = (byte[]) blob.clone();
            c[i] ^= 0x5A;
            if (unwrap.invoke(null, c, seq) == null) {
                detected++;
            }
        }
        check(detected == blob.length, "all " + blob.length + " single-byte corruptions rejected (" + detected + ")");

        // 3. truncated and garbage blobs
        for (int len = 0; len < blob.length; len += 7) {
            byte[] c = new byte[len];
            System.arraycopy(blob, 0, c, 0, len);
            check(unwrap.invoke(null, c, seq) == null, "truncated blob " + len + " rejected");
        }
        check(unwrap.invoke(null, null, seq) == null, "null blob rejected");

        // 4. payload that passes CRC but holds impossible values must not load
        byte[] bad = (byte[]) payload.clone();
        bad[5] = 99; // phase byte (after version int + active boolean)
        boolean threw = false;
        try {
            new GameState(new Stats()).read(new DataInputStream(new ByteArrayInputStream(bad)));
        } catch (java.io.IOException e) {
            threw = true;
        }
        check(threw, "out-of-range phase rejected by validation");

        // 5. stats round trip
        st.discover(100);
        st.fx = false;
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        st.write(new DataOutputStream(bo));
        Stats s2 = new Stats();
        s2.read(new DataInputStream(new ByteArrayInputStream(bo.toByteArray())));
        check(s2.isDiscovered(100) && !s2.fx && s2.runs == st.runs, "stats and settings round trip");

        System.out.println("SaveTest: all checks passed");
    }

    static byte[] bytes(GameState g) throws Exception {
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        g.write(new DataOutputStream(bo));
        return bo.toByteArray();
    }

    static void check(boolean ok, String what) {
        if (!ok) {
            System.out.println("FAIL: " + what);
            System.exit(1);
        }
        System.out.println("ok   " + what);
    }
}
