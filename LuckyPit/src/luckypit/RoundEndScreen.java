package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Round summary, deadline payment, early payoff. */
public final class RoundEndScreen extends Screen {
    private static final int S_SUMMARY = 0, S_PAYING = 1, S_RESULT = 2;
    private int state;
    private int sel;
    private boolean deadline, canEarly;
    private int result = -1;
    private int coinsBefore, due, paidShown;
    private int newDebt;

    private boolean inited;

    public void enter() {
        if (inited) {
            return;
        }
        inited = true;
        GameState g = mm.game;
        EffectManager.compute(g, mm.mods);
        deadline = DebtManager.deadlineNow(g);
        canEarly = DebtManager.canPayEarly(g, mm.mods);
        due = DebtManager.due(g, mm.mods);
        coinsBefore = g.coins;
        state = S_SUMMARY;
        sel = 0;
        if (deadline) {
            mm.sfx(SoundManager.DEBT);
        }
    }

    public void update(int dt) {
        super.update(dt);
        if (state == S_PAYING) {
            int dur = 1100;
            paidShown = (int) ((long) due * Math.min(time, dur) / dur);
            if (time >= dur) {
                finishPayment();
            }
        }
    }

    private void startPayment(boolean early) {
        GameState g = mm.game;
        coinsBefore = g.coins;
        due = DebtManager.due(g, mm.mods);
        result = DebtManager.settle(g, mm.mods, early);
        if (result != DebtManager.R_LOST && result != DebtManager.R_WON) {
            // decide what comes next now, so a reload never settles twice
            if (!EventManager.roll(g)) {
                Shop.open(g, mm.mods);
            }
        }
        if (result == DebtManager.R_NEXT_ROUND) {
            mm.save();
            mm.flow();
            return;
        }
        state = S_PAYING;
        time = 0;
        if (result == DebtManager.R_PAID || result == DebtManager.R_WON) {
            mm.sfx(SoundManager.BUY);
            Fx.coins(120, 120, 18, 200, 70);
        } else if (result == DebtManager.R_LOST) {
            mm.sfx(SoundManager.CURSE);
            Fx.shake(3, 500);
        } else {
            mm.sfx(SoundManager.MAGIC);
        }
        if (result == DebtManager.R_PAID || result == DebtManager.R_REVIVED) {
            newDebt = DebtManager.due(g, mm.mods);
        }
        mm.save();
        SaveManager.saveStats(mm.stats);
    }

    private void finishPayment() {
        state = S_RESULT;
        time = 0;
        if (result == DebtManager.R_PAID || result == DebtManager.R_REVIVED) {
            mm.sfx(SoundManager.DEBT);
            Fx.flash(0x200008, 200);
        } else if (result == DebtManager.R_WON) {
            mm.sfx(SoundManager.JACKPOT);
        }
    }

    private void proceed() {
        mm.save();
        mm.flow();
    }

    public void paint(Graphics g) {
        GameState gs = mm.game;
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, Fx.shakeX(time), 0, Gfx.TL);
        }
        PixelFont.shadow(g, deadline || state != S_SUMMARY ? "СРОК ОПЛАТЫ" : "РАУНД ОКОНЧЕН", 120, 6,
                PixelFont.GOLD, Graphics.HCENTER);
        int y = 40;
        PixelFont.shadow(g, "Итоги раунда", 120, y, PixelFont.GOLD, Graphics.HCENTER);
        y += 18;
        row(g, y, "Проценты по монетам", "+" + gs.lastRoundInterest + "¢");
        y += 14;
        row(g, y, "Доход карт", "+" + gs.lastRoundCoins + "¢");
        y += 14;
        row(g, y, "Жетоны", "+" + gs.lastRoundTokens + "♦");
        y += 14;
        row(g, y, "Выигрыш за забег", gs.runWon + "¢");
        y += 22;
        g.setColor(0x6B4A1A);
        g.drawLine(16, y - 6, 224, y - 6);

        if (state == S_SUMMARY) {
            if (deadline) {
                PixelFont.shadow(g, "Пора платить долг!", 120, y, PixelFont.RED, Graphics.HCENTER);
                y += 16;
                row(g, y, "Долг", due + "¢");
                y += 14;
                row(g, y, "У вас", gs.coins + "¢");
                y += 20;
                PixelFont.shadow(g, gs.coins >= due ? "Монет хватает." : "Монет не хватает…", 120, y,
                        gs.coins >= due ? PixelFont.GREEN : PixelFont.RED, Graphics.HCENTER);
                Gfx.button(g, "Заплатить", 120, 236, true, true);
            } else {
                int left = GameState.ROUNDS_PER_DEADLINE - 1 - gs.roundInDl;
                PixelFont.shadow(g, "До срока: " + left + (left == 1 ? " раунд" : " раунда"), 120, y,
                        PixelFont.CREAM, Graphics.HCENTER);
                y += 16;
                row(g, y, "Долг", due + "¢");
                y += 14;
                row(g, y, "У вас", gs.coins + "¢");
                Gfx.button(g, "Продолжить", 120, 220, sel == 0, true);
                if (canEarly) {
                    Gfx.button(g, "Погасить досрочно +" + (2 + left) + "♦", 120, 246, sel == 1, true);
                } else {
                    PixelFont.draw(g, "Досрочно можно, когда монет хватит", 120, 250, PixelFont.GRAY,
                            Graphics.HCENTER);
                }
            }
        } else {
            boolean ok = result != DebtManager.R_LOST;
            row(g, y, "Списано", paidShownText());
            y += 14;
            int now = coinsBefore - (result == DebtManager.R_LOST || result == DebtManager.R_REVIVED ? 0 : paidShown);
            row(g, y, "Осталось монет", now + "¢");
            y += 24;
            if (state == S_RESULT) {
                String stamp;
                int col;
                if (result == DebtManager.R_LOST) {
                    stamp = "НЕ ХВАТАЕТ МОНЕТ";
                    col = PixelFont.RED;
                } else if (result == DebtManager.R_REVIVED) {
                    stamp = "АНГЕЛ-ХРАНИТЕЛЬ СПАС!";
                    col = PixelFont.CYANISH;
                } else {
                    stamp = "ОПЛАЧЕНО";
                    col = PixelFont.GREEN;
                }
                Gfx.panel(g, 30, y - 6, 180, 24);
                PixelFont.shadow(g, stamp, 120, y, col, Graphics.HCENTER);
                y += 30;
                if (ok && result != DebtManager.R_WON) {
                    PixelFont.shadow(g, "Срок " + (gs.deadline + 1) + " из 8. Новый долг:", 120, y, PixelFont.CREAM,
                            Graphics.HCENTER);
                    y += 14;
                    PixelFont.shadow(g, newDebt + "¢", 120, y, PixelFont.RED, Graphics.HCENTER);
                    y += 14;
                    PixelFont.draw(g, "Награда: +жетоны ♦", 120, y, PixelFont.CYANISH, Graphics.HCENTER);
                } else if (result == DebtManager.R_WON) {
                    PixelFont.shadow(g, "Последний долг выплачен!", 120, y, PixelFont.GOLD, Graphics.HCENTER);
                }
                if (((time / 400) & 1) == 0) {
                    PixelFont.draw(g, "5 — дальше", 120, 270, PixelFont.GOLD, Graphics.HCENTER);
                }
            }
        }
        Fx.paint(g, time);
        Fx.paintFlash(g);
        Gfx.softkeys(g, state == S_PAYING ? null : "Дальше", "Карты");
    }

    private String paidShownText() {
        if (result == DebtManager.R_LOST || result == DebtManager.R_REVIVED) {
            return "0¢";
        }
        return paidShown + "¢";
    }

    private void row(Graphics g, int y, String a, String b) {
        PixelFont.draw(g, a, 18, y, PixelFont.CREAM, Graphics.LEFT);
        PixelFont.draw(g, b, 222, y, PixelFont.GOLD, Graphics.RIGHT);
    }

    public void key(int k) {
        switch (k) {
            case K_UP:
            case K_DOWN:
                if (state == S_SUMMARY && !deadline && canEarly) {
                    sel = 1 - sel;
                    mm.sfx(SoundManager.MOVE);
                }
                break;
            case K_FIRE:
            case K_LSOFT:
            case K_7:
                if (state == S_SUMMARY) {
                    mm.sfx(SoundManager.OK);
                    startPayment(!deadline && sel == 1);
                } else if (state == S_RESULT) {
                    mm.sfx(SoundManager.OK);
                    proceed();
                } else {
                    time = 2000;
                }
                break;
            case K_RSOFT:
            case K_1:
                if (state != S_PAYING) {
                    mm.open(new CardsScreen(false), this);
                }
                break;
            case K_3:
                if (state != S_PAYING) {
                    mm.open(new InfoScreen(), this);
                }
                break;
            case K_9:
                if (state != S_PAYING) {
                    mm.open(new StatsScreen(), this);
                }
                break;
            case K_0:
                if (state != S_PAYING) {
                    mm.open(new HelpScreen(), this);
                }
                break;
            default:
                break;
        }
    }
}
