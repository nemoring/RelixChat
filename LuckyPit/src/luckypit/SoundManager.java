package luckypit;

import java.io.InputStream;

import javax.microedition.media.Manager;
import javax.microedition.media.Player;
import javax.microedition.media.control.VolumeControl;

/**
 * Sound effects (WAV) and lounge music (MIDI) through MMAPI (JSR-135).
 * Player creation can take ~100 ms on Series 40, so all media work happens on
 * a background thread; the game loop only drops an id into a queue.
 * Support for each content type is probed at start-up; when WAV playback is
 * unavailable, short tones from Manager.playTone are used instead.
 */
public final class SoundManager implements Runnable {
    public static final int SPIN = 0, STOP = 1, WIN = 2, BIG = 3, JACKPOT = 4, BUY = 5, DEBT = 6, CURSE = 7,
            COIN = 8, MOVE = 9, OK = 10, ERR = 11, MAGIC = 12;
    private static final String[] FILE = {"s_spin", "s_stop", "s_win", "s_big", "s_jackpot", "s_buy",
            "s_debt", "s_curse", "s_coin", "s_move", "s_ok", "s_err", "s_magic"};
    /** Tone fallback: midi note, duration ms. */
    private static final int[] TONE_NOTE = {48, 40, 79, 84, 88, 91, 33, 45, 96, 76, 81, 36, 93};
    private static final int[] TONE_MS = {120, 40, 160, 260, 500, 120, 400, 400, 30, 25, 50, 150, 80};
    private static final int CACHE = 4;
    private static final int QUEUE = 8;

    private static SoundManager inst;

    private final Player[] cache = new Player[CACHE];
    private final int[] cacheId = new int[CACHE];
    private final int[] cacheUse = new int[CACHE];
    private int clock;
    private final int[] queue = new int[QUEUE];
    private int qHead, qTail;
    private Player music;
    private boolean wantMusic;
    private boolean musicPlaying;
    private boolean running = true;
    private boolean wavOk, midiOk, mixing;
    private String wavType = "audio/x-wav";
    private int failures;
    private Stats stats;
    private boolean suspended;

    private SoundManager() {
    }

    public static SoundManager get() {
        return inst;
    }

    public static void init(Stats s) {
        inst = new SoundManager();
        inst.stats = s;
        for (int i = 0; i < CACHE; i++) {
            inst.cacheId[i] = -1;
        }
        inst.probe();
        Thread t = new Thread(inst);
        t.start();
    }

    private void probe() {
        try {
            String[] types = Manager.getSupportedContentTypes(null);
            for (int i = 0; i < types.length; i++) {
                String t = types[i].toLowerCase();
                if (t.equals("audio/x-wav") || t.equals("audio/wav")) {
                    wavOk = true;
                    wavType = types[i];
                }
                if (t.equals("audio/midi") || t.equals("audio/mid") || t.equals("audio/x-midi")) {
                    midiOk = true;
                }
            }
        } catch (Throwable e) {
            wavOk = midiOk = false;
        }
        String mix = null;
        try {
            mix = System.getProperty("supports.mixing");
        } catch (Throwable e) {
            mix = null;
        }
        mixing = mix != null && mix.toLowerCase().equals("true");
    }

    public String describe() {
        return "WAV:" + (wavOk ? "да" : "нет") + " MIDI:" + (midiOk ? "да" : "нет") + " микш:" + (mixing ? "да" : "нет");
    }

    /** Queues a sound effect. Never blocks. */
    public void play(int id) {
        if (!stats.sound || suspended) {
            return;
        }
        if (musicPlaying && !mixing) {
            return;
        }
        synchronized (this) {
            int next = (qTail + 1) % QUEUE;
            if (next == qHead) {
                return;
            }
            queue[qTail] = id;
            qTail = next;
            notify();
        }
    }

    /** Requests music on/off (actual start happens on the worker). */
    public void music(boolean on) {
        synchronized (this) {
            wantMusic = on;
            notify();
        }
    }

    public void suspend() {
        synchronized (this) {
            suspended = true;
            qHead = qTail = 0;
            notify();
        }
    }

    public void resume() {
        synchronized (this) {
            suspended = false;
            notify();
        }
    }

    public void shutdown() {
        synchronized (this) {
            running = false;
            notify();
        }
    }

    public void run() {
        while (true) {
            int id = -1;
            boolean musicWanted;
            synchronized (this) {
                if (!running) {
                    break;
                }
                if (qHead == qTail && (wantMusic && !suspended && stats.music) == musicPlaying) {
                    try {
                        wait(1000);
                    } catch (InterruptedException e) {
                        // ignore
                    }
                }
                if (qHead != qTail) {
                    id = queue[qHead];
                    qHead = (qHead + 1) % QUEUE;
                }
                musicWanted = wantMusic && !suspended && stats.music && running;
            }
            if (musicWanted != musicPlaying) {
                if (musicWanted) {
                    startMusic();
                } else {
                    stopMusic();
                }
            }
            if (id >= 0) {
                playNow(id);
            }
        }
        stopMusic();
        for (int i = 0; i < CACHE; i++) {
            close(cache[i]);
            cache[i] = null;
        }
    }

    private void playNow(int id) {
        if (!wavOk || failures > 4) {
            tone(id);
            return;
        }
        try {
            Player p = player(id);
            if (p == null) {
                tone(id);
                return;
            }
            if (p.getState() == Player.STARTED) {
                p.stop();
            }
            try {
                p.setMediaTime(0);
            } catch (Throwable e) {
                // some devices refuse; replay anyway
            }
            p.start();
            failures = 0;
        } catch (Throwable e) {
            failures++;
            tone(id);
        }
    }

    private Player player(int id) throws Exception {
        int slot = -1;
        int oldest = Integer.MAX_VALUE;
        int victim = 0;
        for (int i = 0; i < CACHE; i++) {
            if (cacheId[i] == id && cache[i] != null) {
                cacheUse[i] = ++clock;
                return cache[i];
            }
            if (cache[i] == null) {
                slot = i;
            }
            if (cacheUse[i] < oldest) {
                oldest = cacheUse[i];
                victim = i;
            }
        }
        if (slot < 0) {
            slot = victim;
            close(cache[slot]);
            cache[slot] = null;
        }
        InputStream is = getClass().getResourceAsStream("/" + FILE[id] + ".wav");
        if (is == null) {
            return null;
        }
        Player p = Manager.createPlayer(is, wavType);
        p.realize();
        p.prefetch();
        volume(p, 80);
        cache[slot] = p;
        cacheId[slot] = id;
        cacheUse[slot] = ++clock;
        return p;
    }

    private void tone(int id) {
        try {
            Manager.playTone(TONE_NOTE[id], TONE_MS[id], 60);
        } catch (Throwable e) {
            // no audio at all
        }
    }

    private void startMusic() {
        if (!midiOk) {
            musicPlaying = true;
            return;
        }
        try {
            if (music == null) {
                InputStream is = getClass().getResourceAsStream("/m_lounge.mid");
                music = Manager.createPlayer(is, "audio/midi");
                music.realize();
                music.setLoopCount(-1);
                volume(music, 55);
            }
            music.start();
        } catch (Throwable e) {
            close(music);
            music = null;
            midiOk = false;
        }
        musicPlaying = true;
    }

    private void stopMusic() {
        musicPlaying = false;
        if (music != null) {
            try {
                music.stop();
            } catch (Throwable e) {
                // ignore
            }
            close(music);
            music = null;
        }
    }

    private static void volume(Player p, int v) {
        try {
            VolumeControl vc = (VolumeControl) p.getControl("VolumeControl");
            if (vc != null) {
                vc.setLevel(v);
            }
        } catch (Throwable e) {
            // optional
        }
    }

    private static void close(Player p) {
        if (p != null) {
            try {
                p.close();
            } catch (Throwable e) {
                // ignore
            }
        }
    }
}
