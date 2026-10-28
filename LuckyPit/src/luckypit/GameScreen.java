package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** The slot machine: round preparation, spinning and win presentation. */
public final class GameScreen extends Screen {
    private static final int ST_IDLE = 0, ST_SPIN = 1, ST_STEPS = 2, ST_WINS = 3, ST_COUNT = 4, ST_END = 5;
    private static final int[] REEL_X = {36, 86, 136};
    private static final int STRIP_Y = 250;
    private static final int LCD_Y = 202;

    private final Reel[] reels = new Reel[3];
    private final SlotMachine.SpinResult res = new SlotMachine.SpinResult();
    private boolean hasResult;
    private int st;
    private int t;
    private final int[] stopAt = new int[3];
    private final boolean[] stopped = new boolean[3];
    private int stepIdx;
    private boolean stepBegun, stepSwapped;
    private int winIdx;
    private boolean lineShown;
    private int shownCoins, shownTokens, countFrom;
    private int leverT = -1;
    private final int[] flash = new int[GameState.MAX_SLOTS];
    private int prepSel;
    private boolean detail;
    private int hintMode;
    private String lcd = "";
    private int lcdColor = PixelFont.GREEN;
    private String lcd2;
    private int lampMode;
    private int glintX = -60;
    private int endDelay;
    private boolean tease;
    private String[] detailLines;
    private final int[] weightsTmp = new int[Symbol.COUNT];

    public GameScreen() {
        resetReels();
    }

    /** Re-creates reels showing the saved grid. */
    public void resetReels() {
        int seed = (int) System.currentTimeMillis();
        for (int i = 0; i < 3; i++) {
            reels[i] = new Reel(REEL_X[i], seed + i * 7777, Symbol.BASE_WEIGHT);
        }
        hasResult = false;
        st = ST_IDLE;
    }

    public boolean music() {
        return false;
    }

    public void enter() {
        GameState g = mm.game;
        EffectManager.compute(g, mm.mods);
        if (st == ST_IDLE) {
            for (int i = 0; i < 3; i++) {
                if (reels[i].idle()) {
                    reels[i].show(g.lastGrid[i], g.lastGrid[3 + i], g.lastGrid[6 + i]);
                }
            }
            shownCoins = g.coins;
            shownTokens = g.tokens;
            idleLcd();
        }
        detail = false;
        prepSel = 0;
    }

    private void idleLcd() {
        GameState g = mm.game;
        lcdColor = PixelFont.GREEN;
        lcd2 = null;
        if (g.phase == GameState.PH_PREP) {
            lcd = "ВЫБЕРИТЕ СМЕНУ";
        } else if (g.spinsLeft > 0) {
            lcd = "КРУТИТЬ — КНОПКА 5";
        } else {
            lcd = "РАУНД ОКОНЧЕН";
        }
    }

    // ------------------------------------------------------------ actions
    private void spin() {
        GameState g = mm.game;
        if (g.phase != GameState.PH_PLAY || g.spinsLeft <= 0) {
            return;
        }
        countFrom = g.coins;
        shownCoins = g.coins;
        shownTokens = g.tokens;
        EffectManager.compute(g, mm.mods);
        mm.machine.spin(g, mm.mods, res);
        hasResult = true;
        detailLines = null;
        for (int i = 0; i < 9; i++) {
            g.lastGrid[i] = res.grid[i];
        }
        mm.save();
        int base = mm.stats.fastReels ? 380 : 650;
        int gap = mm.stats.fastReels ? 160 : 280;
        for (int i = 0; i < 3; i++) {
            reels[i].start(i * 60);
            stopAt[i] = base + i * gap;
            stopped[i] = false;
        }
        tease = anticipation(g);
        if (tease) {
            stopAt[2] += mm.stats.fastReels ? 350 : 700;
        }
        leverT = 0;
        st = ST_SPIN;
        t = 0;
        lcd = "...";
        lcd2 = null;
        lampMode = 1;
        mm.sfx(SoundManager.SPIN);
    }

    /** True when the first two reels already promise a line (third reel slows down). */
    private boolean anticipation(GameState g) {
        for (int li = 0; li < 7; li++) {
            if (!g.lineActive(li)) {
                continue;
            }
            int a = res.start[SlotMachine.LINES[li][0]], b = res.start[SlotMachine.LINES[li][1]];
            if (a == Symbol.SKULL || b == Symbol.SKULL) {
                continue;
            }
            if (a == b || a == Symbol.EYE || b == Symbol.EYE) {
                return true;
            }
        }
        return false;
    }

    private void hurry() {
        if (st == ST_SPIN) {
            for (int i = 0; i < 3; i++) {
                int want = t + i * 90;
                if (stopAt[i] > want) {
                    stopAt[i] = want;
                }
            }
        } else if (st == ST_STEPS || st == ST_WINS || st == ST_COUNT) {
            finishAnimations();
        }
    }

    /** Jumps to the end of the current spin presentation. */
    public void finishAnimations() {
        if (!hasResult || st == ST_IDLE || st == ST_END) {
            return;
        }
        for (int i = 0; i < 3; i++) {
            reels[i] = new Reel(REEL_X[i], t + i, Symbol.BASE_WEIGHT);
            reels[i].show(res.grid[i], res.grid[3 + i], res.grid[6 + i]);
        }
        shownCoins = mm.game.coins;
        shownTokens = mm.game.tokens;
        showTotalLcd();
        lampMode = 0;
        st = ST_END;
        endDelay = 0;
    }

    private void showTotalLcd() {
        if (res.cursed) {
            lcd = "ПРОКЛЯТИЕ!";
            lcdColor = PixelFont.RED;
            lcd2 = null;
        } else if (res.total > 0) {
            lcd = "+" + res.total + "¢";
            lcdColor = res.consolation ? PixelFont.CREAM : PixelFont.GREEN;
            if (res.jackpot) {
                lcd = "ДЖЕКПОТ +" + res.total + "¢";
                lcdColor = PixelFont.GOLD;
            }
            lcd2 = res.consolation ? "утешение" : mult(res.effMultX100);
        } else {
            lcd = "ПУСТО";
            lcdColor = PixelFont.GRAY;
            lcd2 = null;
        }
    }

    private static String mult(int x100) {
        return "×" + (x100 / 100) + "." + ((x100 / 10) % 10);
    }

    // ------------------------------------------------------------ update
    public void update(int dt) {
        super.update(dt);
        GameState g = mm.game;
        t += dt;
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            if (flash[i] > 0) {
                flash[i] -= dt;
            }
        }
        if (leverT >= 0) {
            leverT += dt;
            if (leverT > 420) {
                leverT = -1;
            }
        }
        if (mm.stats.fx) {
            glintX += dt / 12;
            if (glintX > 400) {
                glintX = -80;
            }
        }
        switch (st) {
            case ST_SPIN:
                for (int i = 0; i < 3; i++) {
                    if (!stopped[i] && t >= stopAt[i]) {
                        stopped[i] = true;
                        reels[i].stop(res.start[i], res.start[3 + i], res.start[6 + i]);
                    }
                }
                if (tease && stopped[1] && !stopped[2] && reels[1].idle()) {
                    lcd = "!!!";
                    lcdColor = PixelFont.GOLD;
                    lampMode = 2;
                }
                boolean all = true;
                for (int i = 0; i < 3; i++) {
                    if (reels[i].update(dt)) {
                        mm.sfx(SoundManager.STOP);
                        Fx.sparks(REEL_X[i] + 23, Reel.Y0 + 126, 4, 0xC8A050);
                    }
                    if (!reels[i].idle()) {
                        all = false;
                    }
                }
                if (all) {
                    stepIdx = 0;
                    stepBegun = false;
                    t = 0;
                    st = res.steps > 0 ? ST_STEPS : ST_WINS;
                    winIdx = -1;
                }
                break;
            case ST_STEPS:
                if (stepIdx >= res.steps) {
                    st = ST_WINS;
                    t = 0;
                    winIdx = -1;
                    break;
                }
                if (!stepBegun) {
                    stepBegun = true;
                    stepSwapped = false;
                    t = 0;
                    int slot = res.stepSlot[stepIdx];
                    if (slot >= 0) {
                        flash[slot] = 500;
                    }
                    int cell = res.stepCell[stepIdx];
                    Fx.sparks(REEL_X[cell % 3] + 23, Reel.cellY(cell / 3) + 21, 10, 0xB070D8);
                    mm.sfx(SoundManager.MAGIC);
                    lcd = "ЭФФЕКТ КАРТЫ";
                    lcdColor = PixelFont.CYANISH;
                }
                if (t >= 200 && !stepSwapped) {
                    stepSwapped = true;
                    int cell = res.stepCell[stepIdx];
                    reels[cell % 3].setVisible(cell / 3, res.stepTo[stepIdx]);
                }
                if (t >= 420) {
                    stepIdx++;
                    stepBegun = false;
                }
                break;
            case ST_WINS:
                updateWins();
                break;
            case ST_COUNT: {
                int dur = 700;
                if (t >= dur) {
                    shownCoins = g.coins;
                    shownTokens = g.tokens;
                    st = ST_END;
                    endDelay = 0;
                    lampMode = 0;
                } else {
                    shownCoins = countFrom + (int) ((long) (g.coins - countFrom) * t / dur);
                }
                break;
            }
            case ST_IDLE:
                // a run reloaded right after its last spin still has to end the round
                if (g.phase == GameState.PH_PLAY && g.spinsLeft <= 0) {
                    st = ST_END;
                    endDelay = 0;
                }
                break;
            case ST_END:
                endDelay += dt;
                if (endDelay > 250) {
                    st = ST_IDLE;
                    if (g.spinsLeft <= 0 && g.phase == GameState.PH_PLAY) {
                        st = ST_END;
                        if (endDelay > 900) {
                            st = ST_IDLE;
                            hasResult = false;
                            DebtManager.endRound(g, mm.mods);
                            mm.save();
                            mm.flow();
                        }
                    }
                }
                break;
            default:
                break;
        }
    }

    private void updateWins() {
        GameState g = mm.game;
        if (winIdx == -1) {
            // presentation start
            winIdx = 0;
            lineShown = false;
            t = 0;
            if (res.cursed) {
                mm.sfx(SoundManager.CURSE);
                Fx.flash(0xB0101C, 260);
                Fx.shake(3, 400);
                lampMode = 3;
                showTotalLcd();
                return;
            }
            if (res.total <= 0) {
                showTotalLcd();
                st = ST_COUNT;
                t = 700;
                return;
            }
        }
        if (res.cursed) {
            if (t > 1300) {
                st = ST_COUNT;
                t = 700;
            }
            return;
        }
        int per = mm.stats.fastReels ? 260 : 380;
        int n = res.wins;
        if (winIdx < n) {
            if (!lineShown) {
                lineShown = true;
                announceLine(winIdx);
            }
            if (t >= per) {
                winIdx++;
                t = 0;
                lineShown = false;
            }
            return;
        }
        if (winIdx == n) {
            // totals
            winIdx++;
            t = 0;
            if (res.scatterWin > 0) {
                Fx.label("Россыпь +" + res.scatterWin, 110, 150, PixelFont.GOLD);
            }
            int trig = res.trig;
            for (int s = 0; s < GameState.MAX_SLOTS; s++) {
                if ((trig & (1 << s)) != 0 && g.cards[s] >= 0) {
                    flash[s] = 600;
                }
            }
            showTotalLcd();
            if (res.jackpot) {
                mm.sfx(SoundManager.JACKPOT);
                Fx.flash(0xF0D070, 300);
                Fx.shake(4, 700);
                Fx.coins(110, 210, 40, 12, 8);
                lampMode = 2;
            } else if (res.effMultX100 >= 300 || res.wins >= 3 || res.total >= 40 * (g.deadline + 1)) {
                mm.sfx(SoundManager.BIG);
                Fx.coins(110, 210, 22, 12, 8);
                lampMode = 2;
            } else if (!res.consolation) {
                mm.sfx(SoundManager.WIN);
                Fx.coins(110, 210, 8, 12, 8);
            } else {
                mm.sfx(SoundManager.COIN);
            }
            if (res.tokens > 0) {
                Fx.label("+" + res.tokens + "♦", 104, 30, PixelFont.CYANISH);
            }
            if (res.extraSpins > 0) {
                Fx.label("+" + res.extraSpins + " прокр.", 200, 30, PixelFont.GOLD);
            }
            if (res.freeSpin) {
                Fx.label("Бесплатно!", 200, 42, PixelFont.GREEN);
            }
            countFrom = shownCoins;
            st = ST_COUNT;
            t = 0;
        }
    }

    private void announceLine(int i) {
        int line = res.winLine[i];
        int[] cells = SlotMachine.LINES[line];
        int c = cells[2];
        int x = REEL_X[c % 3] + 23;
        int y = Reel.cellY(c / 3) + 8;
        Fx.label("+" + res.winAmount[i], x, y, res.winPair[i] ? PixelFont.CREAM : PixelFont.GOLD);
        Fx.sparks(x, y + 12, 6, 0xF0C850);
        mm.sfx(SoundManager.COIN);
    }

    // ------------------------------------------------------------ input
    public void key(int k) {
        GameState g = mm.game;
        if (BuildConfig.DEBUG && cheat(k)) {
            return;
        }
        if (detail) {
            if (k == K_STAR || k == K_RSOFT || k == K_FIRE) {
                detail = false;
            }
            return;
        }
        if (g.phase == GameState.PH_PREP && st == ST_IDLE) {
            switch (k) {
                case K_UP:
                case K_DOWN:
                    prepSel = 1 - prepSel;
                    mm.sfx(SoundManager.MOVE);
                    return;
                case K_FIRE:
                case K_LSOFT:
                    DebtManager.startRound(g, mm.mods, prepSel == 1);
                    shownTokens = g.tokens;
                    mm.save();
                    mm.sfx(SoundManager.OK);
                    idleLcd();
                    return;
                default:
                    break;
            }
        }
        switch (k) {
            case K_FIRE:
            case K_LSOFT:
                if (st == ST_IDLE) {
                    spin();
                } else {
                    hurry();
                }
                break;
            case K_RSOFT: {
                finishAnimations();
                PauseScreen p = new PauseScreen();
                p.under = this;
                mm.switchTo(p);
                break;
            }
            case K_1:
                if (st == ST_IDLE) {
                    mm.open(new CardsScreen(false), this);
                }
                break;
            case K_3:
                if (st == ST_IDLE) {
                    mm.open(new InfoScreen(), this);
                }
                break;
            case K_7:
                Fx.label("Магазин — после раунда", 120, 160, PixelFont.CREAM);
                mm.sfx(SoundManager.ERR);
                break;
            case K_9:
                if (st == ST_IDLE) {
                    mm.open(new StatsScreen(), this);
                }
                break;
            case K_0:
                if (st == ST_IDLE) {
                    mm.open(new HelpScreen(), this);
                }
                break;
            case K_STAR:
                if (hasResult && st == ST_IDLE) {
                    detail = true;
                    buildDetail();
                }
                break;
            case K_POUND:
                hintMode = (hintMode + 1) % 3;
                mm.sfx(SoundManager.MOVE);
                break;
            default:
                break;
        }
    }

    private int cheatSeq;

    /** Debug builds only: #,#,# then 5 gives money, 7 drains it, 1 ends the round. */
    private boolean cheat(int k) {
        GameState g = mm.game;
        if (k == K_POUND) {
            cheatSeq++;
            return false;
        }
        boolean used = false;
        if (cheatSeq >= 3) {
            used = true;
            if (k == K_FIRE) {
                g.addCoins(500 * (g.deadline + 1));
                g.tokens += 10;
            } else if (k == K_7) {
                g.coins = 0;
            } else if (k == K_1) {
                g.spinsLeft = 1;
            } else {
                used = false;
            }
            shownCoins = g.coins;
            shownTokens = g.tokens;
        }
        cheatSeq = 0;
        return used;
    }

    private void buildDetail() {
        if (detailLines != null) {
            return;
        }
        StringBuffer sb = new StringBuffer();
        if (res.wins == 0 && res.scatterWin == 0) {
            sb.append("Выигрышных линий нет.\n");
        }
        for (int i = 0; i < res.wins; i++) {
            sb.append(SlotMachine.LINE_NAME[res.winLine[i]]).append(": ").append(Symbol.NAME[res.winSym[i]])
                    .append(res.winPair[i] ? " (пара)" : "").append(" +").append(res.winAmount[i]).append('\n');
        }
        if (res.scatterWin > 0) {
            sb.append("Россыпь ×").append(res.scatterCount).append(": +").append(res.scatterWin).append('\n');
        }
        if (res.flat > 0) {
            sb.append("Бонусы карт: +").append(res.flat).append('\n');
        }
        sb.append("Множитель: ").append(res.multPct).append("%\n");
        if (res.jackpot) {
            sb.append("Джекпот ×").append(SlotMachine.JACKPOT_MULT).append("!\n");
        }
        if (res.nthFired) {
            sb.append("Сработал счётчик выигрышей\n");
        }
        if (res.diceFired) {
            sb.append("Брошены кости\n");
        }
        if (res.gambleWon) {
            sb.append("Риск: удвоение!\n");
        }
        if (res.gambleLost) {
            sb.append("Риск: половина\n");
        }
        if (res.cursed) {
            sb.append("Три черепа: выигрыш сгорел.\n");
        }
        if (res.warded) {
            sb.append("Проклятие отражено картой.\n");
        }
        if (res.consolation) {
            sb.append("Утешительная выплата.\n");
        }
        sb.append("Итого: ").append(res.total).append("¢");
        if (res.tokens > 0) {
            sb.append("  +").append(res.tokens).append("♦");
        }
        detailLines = PixelFont.wrap(sb.toString(), 196);
    }

    // ------------------------------------------------------------ paint
    public void paint(Graphics g) {
        GameState gs = mm.game;
        int sx = Fx.shakeX(time);
        Image bg = ResourceManager.bg("bg_game.png");
        if (bg != null) {
            g.drawImage(bg, sx, 0, Gfx.TL);
        } else {
            g.setColor(0x3A0E14);
            g.fillRect(0, 0, Gfx.W, Gfx.H);
        }
        for (int i = 0; i < 3; i++) {
            reels[i].paint(g, sx);
        }
        paintWinLines(g, sx);
        if (mm.stats.fx && ResourceManager.glint != null && st == ST_IDLE) {
            g.setClip(32, 64, 150, 126);
            g.drawImage(ResourceManager.glint, glintX, 60, Gfx.TL);
            g.setClip(0, 0, Gfx.W, Gfx.H);
        }
        paintLamps(g);
        paintLever(g);
        paintHud(g);
        paintLcd(g);
        paintStrip(g);
        Fx.paint(g, time);
        Fx.paintFlash(g);
        if (gs.phase == GameState.PH_PREP && st == ST_IDLE) {
            paintPrep(g);
        }
        if (detail) {
            paintDetail(g);
        }
        Gfx.softbar(g);
        String left;
        if (detail) {
            left = null;
        } else if (gs.phase == GameState.PH_PREP) {
            left = "Начать";
        } else if (st == ST_IDLE) {
            left = gs.spinsLeft > 0 ? "Крутить" : null;
        } else {
            left = "Быстрее";
        }
        Gfx.softkeys(g, left, detail ? "Закрыть" : "Меню");
    }

    private void paintWinLines(Graphics g, int sx) {
        if (!hasResult) {
            return;
        }
        if (st == ST_WINS || st == ST_COUNT || st == ST_END || (st == ST_IDLE && hasResult)) {
            boolean blink = ((time / 160) & 1) == 0;
            if (res.cursed && res.curseLine >= 0) {
                drawLine(g, res.curseLine, 0xE0302E, blink, sx);
                return;
            }
            int upto = st == ST_WINS ? Math.min(winIdx, res.wins - 1) : res.wins - 1;
            if (st == ST_IDLE) {
                // after presentation keep lines faint
                for (int i = 0; i < res.wins; i++) {
                    drawLine(g, res.winLine[i], 0x806020, false, sx);
                }
                return;
            }
            for (int i = 0; i <= upto && i < res.wins; i++) {
                int col = res.winPair[i] ? 0xC8B48C : 0xF0C850;
                drawLine(g, res.winLine[i], col, i == upto ? blink : false, sx);
            }
            if (res.scatterWin > 0 && st != ST_WINS) {
                for (int c = 0; c < 9; c++) {
                    if (res.grid[c] == Symbol.STAR) {
                        cellBox(g, c, 0x8CDCF0, sx);
                    }
                }
            }
        }
    }

    private void drawLine(Graphics g, int line, int rgb, boolean thick, int sx) {
        int[] cells = SlotMachine.LINES[line];
        g.setColor(0x000000);
        for (int i = 0; i < 2; i++) {
            int a = cells[i], b = cells[i + 1];
            int x1 = REEL_X[a % 3] + 23 + sx, y1 = Reel.cellY(a / 3) + 21;
            int x2 = REEL_X[b % 3] + 23 + sx, y2 = Reel.cellY(b / 3) + 21;
            g.setColor(0x000000);
            g.drawLine(x1, y1 + 2, x2, y2 + 2);
            g.setColor(rgb);
            g.drawLine(x1, y1, x2, y2);
            g.drawLine(x1, y1 + 1, x2, y2 + 1);
            if (thick) {
                g.drawLine(x1, y1 - 1, x2, y2 - 1);
            }
        }
        for (int i = 0; i < 3; i++) {
            cellBox(g, cells[i], rgb, sx);
        }
    }

    private void cellBox(Graphics g, int c, int rgb, int sx) {
        int x = REEL_X[c % 3] + 1 + sx, y = Reel.cellY(c / 3) + 1;
        g.setColor(rgb);
        g.drawRect(x, y, 43, 39);
        g.drawRect(x + 1, y + 1, 41, 37);
    }

    private void paintLamps(Graphics g) {
        Image l = ResourceManager.lamps;
        if (l == null) {
            return;
        }
        for (int i = 0; i < 12; i++) {
            int x = 22 + i * 16, y = 31;
            int f;
            switch (lampMode) {
                case 1:
                    f = ((i + time / 70) % 4 == 0) ? 1 : 0;
                    break;
                case 2:
                    f = ((time / 90 + i) & 1) == 0 ? 4 : 3;
                    break;
                case 3:
                    f = ((time / 120) & 1) == 0 ? 3 : 2;
                    break;
                default:
                    f = ((i + time / 220) % 3 == 0) ? 1 : 0;
                    break;
            }
            g.drawRegion(l, f * 6, 0, 6, 6, 0, x, y, Gfx.TL);
        }
        // payline tab lamps for winning rows
        if (hasResult && st >= ST_WINS) {
            for (int i = 0; i < res.wins; i++) {
                int line = res.winLine[i];
                if (line <= 2) {
                    int y = Reel.Y0 + line * Reel.CELL + 18;
                    g.drawRegion(l, 6, 0, 6, 6, 0, 20, y, Gfx.TL);
                    g.drawRegion(l, 6, 0, 6, 6, 0, 198, y, Gfx.TL);
                }
            }
        }
    }

    private void paintLever(Graphics g) {
        Image lv = ResourceManager.lever;
        if (lv == null) {
            return;
        }
        int f = 0;
        if (leverT >= 0) {
            if (leverT < 120) {
                f = leverT * 4 / 120;
            } else {
                f = 3 - (leverT - 120) * 4 / 300;
            }
            if (f < 0) {
                f = 0;
            }
            if (f > 3) {
                f = 3;
            }
        }
        g.drawRegion(lv, f * 24, 0, 24, 110, 0, 213, 64, Gfx.TL);
    }

    private void paintHud(Graphics g) {
        GameState gs = mm.game;
        ResourceManager.icon(g, ResourceManager.I_COIN, 5, 3);
        PixelFont.numShadow(g, shownCoins, (char) 0, (char) 0, 20, 4, PixelFont.GOLD, Graphics.LEFT);
        ResourceManager.icon(g, ResourceManager.I_TOKEN, 84, 3);
        PixelFont.numShadow(g, shownTokens, (char) 0, (char) 0, 99, 4, PixelFont.CYANISH, Graphics.LEFT);
        int due = DebtManager.due(gs, mm.mods);
        ResourceManager.icon(g, ResourceManager.I_DEBT, 138, 3);
        PixelFont.draw(g, "Долг", 152, 4, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.numShadow(g, due, (char) 0, '¢', 233, 4, shownCoins >= due ? PixelFont.GREEN : PixelFont.RED,
                Graphics.RIGHT);
        // second row
        PixelFont.draw(g, "Срок", 5, 17, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.num(g, gs.deadline + 1, (char) 0, (char) 0, 31, 17, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.draw(g, "/8", 37, 17, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.draw(g, "Раунд", 60, 17, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.num(g, gs.roundInDl + 1, (char) 0, (char) 0, 93, 17, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.draw(g, "/3", 99, 17, PixelFont.GRAY, Graphics.LEFT);
        ResourceManager.icon(g, ResourceManager.I_SPIN, 160, 15);
        PixelFont.draw(g, "Прокр.", 175, 17, PixelFont.GRAY, Graphics.LEFT);
        PixelFont.num(g, gs.spinsLeft, (char) 0, (char) 0, 233, 17,
                gs.spinsLeft <= 1 ? PixelFont.RED : PixelFont.CREAM, Graphics.RIGHT);
    }

    private void paintLcd(Graphics g) {
        if (lcd2 != null) {
            PixelFont.draw(g, lcd, 40, LCD_Y, lcdColor, Graphics.LEFT);
            PixelFont.draw(g, lcd2, 180, LCD_Y, PixelFont.GOLD, Graphics.RIGHT);
        } else {
            PixelFont.draw(g, lcd, 110, LCD_Y, lcdColor, Graphics.HCENTER);
        }
    }

    private void paintStrip(Graphics g) {
        GameState gs = mm.game;
        int cap = CardManager.capacity(gs);
        for (int i = 0; i < GameState.MAX_SLOTS; i++) {
            int x = 4 + i * 29;
            int y = STRIP_Y;
            if (gs.cards[i] >= 0) {
                int lift = flash[i] > 0 ? 3 : 0;
                Gfx.card(g, gs.cards[i], x, y - lift);
                if (flash[i] > 0 && ((time / 80) & 1) == 0) {
                    g.setColor(0xFFF8E8);
                    g.drawRect(x - 1, y - lift - 1, 29, 29);
                }
            } else {
                Gfx.emptySlot(g, x, y, i >= cap);
            }
        }
        int hy = 283;
        if (hintMode == 0) {
            PixelFont.draw(g, "1 карты  3 автомат  * итог  0 помощь", 120, hy, PixelFont.GRAY, Graphics.HCENTER);
            PixelFont.draw(g, "# сеты", 120, hy + 10, PixelFont.GRAY, Graphics.HCENTER);
        } else if (hintMode == 1) {
            int bits = mm.mods.setBits;
            StringBuffer sb = new StringBuffer("Сеты: ");
            boolean any = false;
            for (int f = 0; f < Card.FAMILIES; f++) {
                int c = CardManager.countFamily(gs, f);
                if (c >= 2) {
                    sb.append(Card.FAMILY[f]).append(' ').append(c).append((bits & (1 << (f * 2 + 1))) != 0 ? "★ " : " ");
                    any = true;
                }
            }
            if (!any) {
                sb.append("нет (2+ карт одной семьи)");
            }
            PixelFont.draw(g, sb.toString(), 120, hy + 4, PixelFont.CREAM, Graphics.HCENTER);
        } else {
            EffectManager.Mods m = mm.mods;
            PixelFont.draw(g, "Множ. +" + m.mult + "%  Комбо " + m.combo + "%  Линий " + gs.activeLines(), 120,
                    hy + 4, PixelFont.CREAM, Graphics.HCENTER);
        }
    }

    private void paintPrep(Graphics g) {
        GameState gs = mm.game;
        Gfx.dim(g);
        Gfx.panel(g, 14, 70, 212, 160);
        Gfx.banner(g, "Срок " + (gs.deadline + 1) + " · Раунд " + (gs.roundInDl + 1) + " из 3", 60);
        int due = DebtManager.due(gs, mm.mods);
        PixelFont.shadow(g, "Долг к концу срока: " + due + "¢", 120, 92, PixelFont.CREAM, Graphics.HCENTER);
        int left = GameState.ROUNDS_PER_DEADLINE - gs.roundInDl;
        PixelFont.shadow(g, "Осталось раундов: " + left + "   У вас: " + gs.coins + "¢", 120, 105,
                PixelFont.GRAY, Graphics.HCENTER);
        int spins = GameState.BASE_SPINS + mm.mods.spins + gs.evSpins;
        int sspins = GameState.SHORT_SPINS + mm.mods.spins + gs.evSpins;
        if (spins < 1) {
            spins = 1;
        }
        if (sspins < 1) {
            sspins = 1;
        }
        Gfx.button(g, "Полная смена: " + spins + " прокр.", 120, 126, prepSel == 0, true);
        Gfx.button(g, "Короткая: " + sspins + " прокр. +" + GameState.SHORT_TOKENS + "♦", 120, 152, prepSel == 1, true);
        String tip = prepSel == 0 ? "Больше прокруток — больше монет." : "Жетоны ♦ тратятся на улучшения.";
        PixelFont.draw(g, tip, 120, 180, PixelFont.GRAY, Graphics.HCENTER);
        if (gs.evSym >= 0 || gs.evSpins != 0) {
            PixelFont.draw(g, "Действует событие прошлого раунда", 120, 194, PixelFont.GOLD, Graphics.HCENTER);
        }
        PixelFont.draw(g, "2/8 — выбор, 5 — начать", 120, 210, PixelFont.GRAY, Graphics.HCENTER);
    }

    private void paintDetail(Graphics g) {
        Gfx.dim(g);
        int n = detailLines == null ? 0 : detailLines.length;
        if (n > 18) {
            n = 18;
        }
        int h = 40 + n * PixelFont.LINE;
        int y = 160 - h / 2;
        Gfx.panel(g, 12, y, 216, h);
        PixelFont.shadow(g, "Последняя прокрутка", 120, y + 8, PixelFont.GOLD, Graphics.HCENTER);
        for (int i = 0; i < n; i++) {
            PixelFont.draw(g, detailLines[i], 22, y + 24 + i * PixelFont.LINE, PixelFont.CREAM, Graphics.LEFT);
        }
    }

    /** Weights for the info screen. */
    public int[] weights() {
        mm.machine.weights(mm.mods, weightsTmp);
        return weightsTmp;
    }
}
