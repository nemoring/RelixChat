package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Sound, music, effects, reel speed, progress reset. */
public final class SettingsScreen extends BackScreen {
    private static final String[] ITEMS = {"Звук", "Музыка", "Эффекты", "Барабаны", "Сбросить прогресс"};
    private int sel;

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        PixelFont.shadow(g, "НАСТРОЙКИ", 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        Stats s = mm.stats;
        for (int i = 0; i < ITEMS.length; i++) {
            int y = 50 + i * 30;
            String v;
            switch (i) {
                case 0: v = s.sound ? "Вкл" : "Выкл"; break;
                case 1: v = s.music ? "Вкл" : "Выкл"; break;
                case 2: v = s.fx ? "Вкл" : "Выкл"; break;
                case 3: v = s.fastReels ? "Быстрые" : "Обычные"; break;
                default: v = ""; break;
            }
            Gfx.button(g, v.length() > 0 ? ITEMS[i] + ": " + v : ITEMS[i], 120, y, i == sel, true);
        }
        String[] tips = {"Звуковые эффекты автомата.", "Фоновая музыка в меню и магазине.",
                "Частицы, вспышки, тряска и шторки. Выключите, если телефон тормозит.",
                "Скорость остановки барабанов.", "Удаляет статистику, альманах и текущий забег."};
        String[] tl = PixelFont.wrap(tips[sel], 210);
        PixelFont.lines(g, tl, 16, 210, PixelFont.CREAM, 3);
        if (SoundManager.get() != null) {
            PixelFont.draw(g, "Аудио: " + SoundManager.get().describe(), 16, 260, PixelFont.GRAY, Graphics.LEFT);
        }
        PixelFont.draw(g, "Память: " + (Runtime.getRuntime().freeMemory() / 1024) + "K своб. / "
                + (Runtime.getRuntime().totalMemory() / 1024) + "K", 16, 274, PixelFont.GRAY, Graphics.LEFT);
        Gfx.softkeys(g, "Изменить", "Назад");
    }

    public void key(int k) {
        Stats s = mm.stats;
        switch (k) {
            case K_UP:
                sel = (sel + ITEMS.length - 1) % ITEMS.length;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_DOWN:
                sel = (sel + 1) % ITEMS.length;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_FIRE:
            case K_LSOFT:
            case K_LEFT:
            case K_RIGHT:
                switch (sel) {
                    case 0: s.sound = !s.sound; break;
                    case 1:
                        s.music = !s.music;
                        SoundManager.get().music(true);
                        break;
                    case 2:
                        s.fx = !s.fx;
                        Fx.enabled = s.fx;
                        if (!s.fx) {
                            Fx.clear();
                        }
                        break;
                    case 3: s.fastReels = !s.fastReels; break;
                    default:
                        if (k == K_FIRE || k == K_LSOFT) {
                            mm.confirm("Стереть весь прогресс и статистику?", this, 1);
                        }
                        return;
                }
                mm.sfx(SoundManager.OK);
                SaveManager.saveStats(s);
                break;
            case K_RSOFT:
                goBack();
                break;
            default:
                break;
        }
    }

    public void confirmed(int action) {
        mm.stats.resetProgress();
        mm.game.clear();
        mm.hasSave = false;
        SaveManager.clearRun();
        SaveManager.saveStats(mm.stats);
        mm.sfx(SoundManager.DEBT);
        back = mm.mainMenu;
    }
}
