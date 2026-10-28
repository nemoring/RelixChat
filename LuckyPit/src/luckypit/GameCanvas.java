package luckypit;

import javax.microedition.lcdui.Graphics;

/**
 * Full-screen double-buffered canvas and the game loop thread (~25 FPS).
 * Key events are queued from the UI thread and consumed by the loop, so all
 * game logic runs on a single thread.
 */
public final class GameCanvas extends javax.microedition.lcdui.game.GameCanvas implements Runnable {
    private static final int FRAME_MS = 40;

    private final MenuManager mm;
    private Thread thread;
    private volatile boolean running;
    private volatile boolean paused;
    private volatile boolean hideReq, showReq;
    private volatile boolean ready;
    private final int[] keyq = new int[16];
    private int qHead, qTail;
    public static int fps;
    private int pausedTicks;
    /** Logs frame rate and lifecycle events to the console (emulator only). */
    public static final boolean DEBUG = BuildConfig.DEBUG;

    public GameCanvas(LuckyPitMIDlet m) {
        super(false);
        setFullScreenMode(true);
        mm = new MenuManager(m);
    }

    public void start() {
        running = true;
        thread = new Thread(this);
        thread.start();
    }

    public void run() {
        Graphics g = getGraphics();
        // splash while loading
        g.setColor(0x0B0708);
        g.fillRect(0, 0, getWidth(), getHeight());
        g.setColor(0xC8A050);
        g.drawString("Lucky Pit...", getWidth() / 2, getHeight() / 2, Graphics.TOP | Graphics.HCENTER);
        flushGraphics();
        try {
            ResourceManager.init();
            PixelFont.init();
            Gfx.init();
            SaveManager.init();
            mm.init();
            SoundManager.init(mm.stats);
            if (mm.current() != null) {
                SoundManager.get().music(mm.current().music());
            }
        } catch (Throwable t) {
            g.setColor(0xFF0000);
            g.drawString("Ошибка: " + t, 2, 2, Graphics.TOP | Graphics.LEFT);
            flushGraphics();
            return;
        }
        ready = true;
        long last = System.currentTimeMillis();
        int frames = 0;
        long fpsT = last;
        while (running) {
            long now = System.currentTimeMillis();
            int dt = (int) (now - last);
            last = now;
            if (dt < 0) {
                dt = 0;
            }
            if (dt > 100) {
                dt = 100;
            }
            if (DEBUG && (hideReq || showReq)) {
                System.out.println("hide " + hideReq + " show " + showReq);
            }
            if (hideReq) {
                hideReq = false;
                mm.onHide();
                paused = true;
            }
            if (showReq) {
                showReq = false;
                paused = false;
                mm.onShow();
                last = System.currentTimeMillis();
            }
            if (paused) {
                // some VMs skip showNotify after a call; resume once visible
                if (isShown() && ++pausedTicks > 5) {
                    showReq = true;
                }
                sleep(100);
                continue;
            }
            pausedTicks = 0;
            while (true) {
                int k;
                synchronized (keyq) {
                    if (qHead == qTail) {
                        break;
                    }
                    k = keyq[qHead];
                    qHead = (qHead + 1) % keyq.length;
                }
                try {
                    mm.key(k);
                } catch (Throwable t) {
                    // never let a UI bug kill the loop
                    report(t);
                }
            }
            try {
                mm.update(dt);
                mm.paint(g);
            } catch (Throwable t) {
                g.setClip(0, 0, getWidth(), getHeight());
                report(t);
            }
            flushGraphics();
            frames++;
            if (now - fpsT >= 1000) {
                if (DEBUG) {
                    System.out.println("fps " + frames + " screen " + mm.current() + " mem " + Runtime.getRuntime().freeMemory());
                }
                fps = frames;
                frames = 0;
                fpsT = now;
            }
            long spent = System.currentTimeMillis() - now;
            sleep((int) (FRAME_MS - spent < 5 ? 5 : FRAME_MS - spent));
        }
    }

    private static int reports;

    private static void report(Throwable t) {
        if (reports++ < 20) {
            System.out.println("LuckyPit error: " + t);
            t.printStackTrace();
        }
    }

    private static void sleep(int ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            // ignore
        }
    }

    private void push(int k) {
        synchronized (keyq) {
            int n = (qTail + 1) % keyq.length;
            if (n != qHead) {
                keyq[qTail] = k;
                qTail = n;
            }
        }
    }

    private int map(int code) {
        switch (code) {
            case KEY_NUM2: return Screen.K_UP;
            case KEY_NUM8: return Screen.K_DOWN;
            case KEY_NUM4: return Screen.K_LEFT;
            case KEY_NUM6: return Screen.K_RIGHT;
            case KEY_NUM5: return Screen.K_FIRE;
            case KEY_NUM1: return Screen.K_1;
            case KEY_NUM3: return Screen.K_3;
            case KEY_NUM7: return Screen.K_7;
            case KEY_NUM9: return Screen.K_9;
            case KEY_NUM0: return Screen.K_0;
            case KEY_STAR: return Screen.K_STAR;
            case KEY_POUND: return Screen.K_POUND;
            case -6: case -21: case 21: return Screen.K_LSOFT;   // left soft key (Nokia, Motorola)
            case -7: case -22: case 22: return Screen.K_RSOFT;   // right soft key
            case -8: return Screen.K_RSOFT;                      // C / clear = back
            case -5: return Screen.K_FIRE;                       // navi centre
            default: break;
        }
        try {
            switch (getGameAction(code)) {
                case UP: return Screen.K_UP;
                case DOWN: return Screen.K_DOWN;
                case LEFT: return Screen.K_LEFT;
                case RIGHT: return Screen.K_RIGHT;
                case FIRE: return Screen.K_FIRE;
                default: break;
            }
        } catch (Throwable t) {
            // unknown key code
        }
        return 0;
    }

    protected void keyPressed(int code) {
        if (!ready) {
            return;
        }
        int k = map(code);
        if (k != 0) {
            push(k);
        }
    }

    protected void keyRepeated(int code) {
        if (!ready) {
            return;
        }
        int k = map(code);
        if (k == Screen.K_UP || k == Screen.K_DOWN || k == Screen.K_LEFT || k == Screen.K_RIGHT) {
            push(k);
        }
    }

    protected void hideNotify() {
        if (ready) {
            hideReq = true;
        }
    }

    protected void showNotify() {
        if (ready) {
            showReq = true;
        }
    }

    void pauseFromSystem() {
        if (ready) {
            hideReq = true;
        }
    }

    void resumeFromPause() {
        if (ready) {
            showReq = true;
        }
    }

    /** Synchronous save and stop (destroyApp). */
    void shutdown() {
        running = false;
        if (ready) {
            try {
                if (mm.current() == mm.gameScreen) {
                    mm.gameScreen.finishAnimations();
                }
                mm.save();
                SaveManager.saveStats(mm.stats);
                SaveManager.shutdown();
            } catch (Throwable t) {
                // best effort
            }
            if (SoundManager.get() != null) {
                SoundManager.get().shutdown();
            }
        }
    }
}
