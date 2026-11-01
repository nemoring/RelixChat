package dev.kiwifuzzy.kiwion;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/** Solves the registration proof-of-work challenge (anti-bot), same algorithm as the server. */
public final class Pow {
    private Pow() {}

    public static int leadingZeroBits(byte[] d) {
        int bits = 0;
        for (byte b : d) {
            int x = b & 0xFF;
            if (x == 0) { bits += 8; continue; }
            bits += Integer.numberOfLeadingZeros(x) - 24;
            break;
        }
        return bits;
    }

    public static String solve(String challenge, int difficulty) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            for (long n = 0; ; n++) {
                byte[] d = md.digest((challenge + ":" + n).getBytes(StandardCharsets.UTF_8));
                if (leadingZeroBits(d) >= difficulty) return Long.toString(n);
            }
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
