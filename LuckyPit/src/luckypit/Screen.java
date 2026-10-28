package luckypit;

import javax.microedition.lcdui.Graphics;

/** Base class of every screen. */
public abstract class Screen {
    // logical keys
    public static final int K_UP = 1, K_DOWN = 2, K_LEFT = 3, K_RIGHT = 4, K_FIRE = 5, K_LSOFT = 6, K_RSOFT = 7,
            K_1 = 8, K_3 = 9, K_7 = 10, K_9 = 11, K_0 = 12, K_STAR = 13, K_POUND = 14;

    protected MenuManager mm;
    protected int time;

    public void enter() {
    }

    public void leave() {
    }

    public void update(int dt) {
        time += dt;
    }

    public abstract void paint(Graphics g);

    public abstract void key(int k);

    /** Called by the confirmation dialog when the player answers "yes". */
    public void confirmed(int action) {
    }

    /** True if the screen wants the lounge music. */
    public boolean music() {
        return true;
    }
}
