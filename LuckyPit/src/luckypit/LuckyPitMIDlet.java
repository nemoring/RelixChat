package luckypit;

import javax.microedition.lcdui.Display;
import javax.microedition.midlet.MIDlet;

/** Entry point. Handles the MIDlet life cycle (calls, minimising, exit). */
public final class LuckyPitMIDlet extends MIDlet {
    private GameCanvas canvas;
    private boolean started;

    protected void startApp() {
        if (!started) {
            started = true;
            canvas = new GameCanvas(this);
            Display.getDisplay(this).setCurrent(canvas);
            canvas.start();
        } else {
            Display.getDisplay(this).setCurrent(canvas);
            canvas.resumeFromPause();
        }
    }

    protected void pauseApp() {
        if (canvas != null) {
            canvas.pauseFromSystem();
        }
    }

    protected void destroyApp(boolean unconditional) {
        if (canvas != null) {
            canvas.shutdown();
        }
    }

    /** Exit requested from the menu. */
    void quit() {
        destroyApp(true);
        notifyDestroyed();
    }
}
