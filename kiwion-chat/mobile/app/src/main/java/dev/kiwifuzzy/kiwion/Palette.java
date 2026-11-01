package dev.kiwifuzzy.kiwion;

import android.content.Context;
import android.content.res.Configuration;

/** Brand colors for the light and dark themes. */
public final class Palette {
    public final boolean dark;
    public final int bg, surface, surface2, text, muted, border, green, greenStrong, greenSoft, greenInk, danger, warn, onGreen;

    private Palette(boolean dark) {
        this.dark = dark;
        if (dark) {
            bg = 0xFF0F1410; surface = 0xFF171D17; surface2 = 0xFF1F271F; text = 0xFFE6EEE2; muted = 0xFF9AA894;
            border = 0xFF2B362A; green = 0xFF5DBB63; greenStrong = 0xFF8BD450; greenSoft = 0xFF1D2B1C; greenInk = 0xFFB9EAA0;
        } else {
            bg = 0xFFF6F8F3; surface = 0xFFFFFFFF; surface2 = 0xFFF0F4EC; text = 0xFF1C2419; muted = 0xFF66705F;
            border = 0xFFDFE6D8; green = 0xFF4CAF50; greenStrong = 0xFF2E8B3E; greenSoft = 0xFFE8F5E1; greenInk = 0xFF1F5F2A;
        }
        danger = 0xFFD64545;
        warn = 0xFFC98A12;
        onGreen = 0xFFFFFFFF;
    }

    public static Palette of(Context c) {
        String pref = KiwionApp.get().prefs.theme();
        boolean dark;
        if ("dark".equals(pref)) dark = true;
        else if ("light".equals(pref)) dark = false;
        else dark = (c.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        return new Palette(dark);
    }
}
