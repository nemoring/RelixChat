package luckypit;

import javax.microedition.lcdui.Graphics;

/**
 * Owns the shared game objects and the screen stack; runs curtain
 * transitions and maps the run phase to the right screen.
 */
public final class MenuManager {
    public final Stats stats = new Stats();
    public final GameState game = new GameState(stats);
    public final EffectManager.Mods mods = new EffectManager.Mods();
    public final SlotMachine machine = new SlotMachine();
    public final LuckyPitMIDlet midlet;
    public boolean hasSave;

    private Screen cur, next;
    private int trans;
    private boolean closing;
    private static final int TRANS = 200;
    private int clock;

    // screens
    public GameScreen gameScreen;
    public final MainMenuScreen mainMenu = new MainMenuScreen();
    private final ConfirmScreen confirm = new ConfirmScreen();

    public MenuManager(LuckyPitMIDlet m) {
        midlet = m;
    }

    public void init() {
        CardManager.load();
        SaveManager.loadStats(stats);
        Fx.enabled = stats.fx;
        hasSave = SaveManager.loadRun(game);
        gameScreen = new GameScreen();
        switchTo(new SplashScreen());
    }

    public Screen current() {
        return cur;
    }

    /** Transition to a screen (curtain unless effects are off). */
    public void go(Screen s) {
        if (closing && trans > 0) {
            next = s;
            return;
        }
        if (!stats.fx || cur == null) {
            switchTo(s);
            return;
        }
        next = s;
        closing = true;
        trans = TRANS;
    }

    /** Immediate switch (overlays). */
    public void switchTo(Screen s) {
        if (cur != null) {
            cur.leave();
        }
        cur = s;
        s.mm = this;
        s.time = 0;
        s.enter();
        if (SoundManager.get() != null) {
            SoundManager.get().music(s.music());
        }
    }

    /** Opens an info-style screen that returns to `back`. */
    public void open(BackScreen s, Screen back) {
        s.back = back;
        go(s);
    }

    public void confirm(String text, Screen owner, int action) {
        confirm.text = text;
        confirm.owner = owner;
        confirm.action = action;
        confirm.sel = 1;
        confirm.mm = this;
        cur = confirm;
        confirm.time = 0;
    }

    /** Return from an overlay without enter() side effects. */
    public void resume(Screen s) {
        cur = s;
    }

    /** Screen matching the current run phase. */
    public void flow() {
        switch (game.phase) {
            case GameState.PH_ROUND_END:
                go(new RoundEndScreen());
                break;
            case GameState.PH_EVENT:
                go(new EventScreen());
                break;
            case GameState.PH_SHOP:
                go(new ShopScreen());
                break;
            case GameState.PH_OVER:
            case GameState.PH_WON:
                go(new EndScreen());
                break;
            default:
                go(gameScreen);
                break;
        }
    }

    public void newRun() {
        int seed = (int) System.currentTimeMillis() ^ (stats.runs * 0x9E3779B9);
        DebtManager.newRun(game, seed);
        hasSave = true;
        gameScreen.resetReels();
        save();
        SaveManager.saveStats(stats);
        flow();
    }

    public void save() {
        if (game.active) {
            SaveManager.saveRun(game);
        } else {
            SaveManager.clearRun();
            hasSave = false;
        }
    }

    public void sfx(int id) {
        if (SoundManager.get() != null) {
            SoundManager.get().play(id);
        }
    }

    public void update(int dt) {
        clock += dt;
        if (trans > 0) {
            trans -= dt;
            if (trans <= 0) {
                if (closing) {
                    closing = false;
                    trans = TRANS;
                    switchTo(next);
                    next = null;
                } else {
                    trans = 0;
                }
            }
        }
        Fx.update(dt);
        if (cur != null) {
            cur.update(dt);
        }
    }

    public void paint(Graphics g) {
        if (cur != null) {
            cur.paint(g);
        }
        if (trans > 0) {
            int k = closing ? (TRANS - trans) : trans;
            int h = 161 * k / TRANS;
            g.setColor(0x0B0708);
            g.fillRect(0, 0, Gfx.W, h);
            g.fillRect(0, Gfx.H - h, Gfx.W, h);
            g.setColor(0xC8A050);
            g.drawLine(0, h, Gfx.W, h);
            g.drawLine(0, Gfx.H - h - 1, Gfx.W, Gfx.H - h - 1);
            g.setColor(0x6B4A1A);
            g.drawLine(0, h + 1, Gfx.W, h + 1);
            g.drawLine(0, Gfx.H - h - 2, Gfx.W, Gfx.H - h - 2);
        }
    }

    public void key(int k) {
        if (trans > 0 || cur == null) {
            return;
        }
        cur.key(k);
    }

    /** Called when the phone hides the app (call, minimise). */
    public void onHide() {
        if (cur == gameScreen) {
            gameScreen.finishAnimations();
            PauseScreen p = new PauseScreen();
            p.under = gameScreen;
            switchTo(p);
        }
        save();
        SaveManager.saveStats(stats);
        SaveManager.flush();
        if (SoundManager.get() != null) {
            SoundManager.get().suspend();
        }
    }

    public void onShow() {
        if (SoundManager.get() != null) {
            SoundManager.get().resume();
            if (cur != null) {
                SoundManager.get().music(cur.music());
            }
        }
    }

    public void exit() {
        if (cur == gameScreen) {
            gameScreen.finishAnimations();
        }
        save();
        SaveManager.saveStats(stats);
        midlet.quit();
    }

    public int clock() {
        return clock;
    }
}
