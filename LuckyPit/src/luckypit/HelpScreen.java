package luckypit;

import javax.microedition.lcdui.Graphics;
import javax.microedition.lcdui.Image;

/** Paged help. */
public final class HelpScreen extends BackScreen {
    private static final String[] TITLE = {"Цель", "Управление", "Символы и линии", "Карты", "Долг и раунды",
            "Магазин", "Советы"};
    private static final String[] TEXT = {
            "Вы застряли в Яме удачи. Чтобы выбраться, выплатите 8 растущих долгов. Каждый срок — 3 раунда "
                    + "прокруток автомата. Не хватит монет к сроку — Яма заберёт вас.\n\n"
                    + "Монеты здесь только виртуальные: это игра, а не азартный сервис.",
            "2 4 6 8 — навигация\n5 — прокрутка / выбор\n1 — ваши карты\n3 — об автомате\n"
                    + "7 — магазин (между раундами)\n9 — статистика\n0 — справка\n* — подробности\n"
                    + "# — вкладки и сеты\nЛевая софт-клавиша — действие\nПравая софт-клавиша — назад / меню\n\n"
                    + "Во время прокрутки 5 останавливает барабаны быстрее.",
            "Поле 3×3. Выигрыш — три одинаковых символа на линии. Сначала активны 3 горизонтали и 2 диагонали, "
                    + "V-линии и колонны покупаются.\n«Око» — дикий символ. Три «Черепа» в линию — проклятие: "
                    + "весь выигрыш прокрутки сгорает. Россыпь: 3+ звезды платят в любом месте. "
                    + "Несколько линий сразу дают комбо. Все 9 одинаковых — джекпот ×10.",
            "Карты дают постоянные эффекты. Слотов сначала 4. Карты одной семьи дают бонус при 2 и 4 "
                    + "картах (смотрите # в магазине). «Зеркало» копирует карту справа — порядок важен.\n"
                    + "«¢×срок» — сумма растёт с номером срока. Проклятые карты сильны, но вредят и не продаются.",
            "Перед раундом выберите смену: полную (больше прокруток) или короткую (меньше прокруток, но +2♦). "
                    + "В конце раунда начисляются проценты и доходы карт. В конце 3-го раунда долг списывается "
                    + "сам. Если монет уже хватает, долг можно погасить досрочно и получить больше жетонов ♦.",
            "Карты покупаются за монеты ¢, улучшения автомата — за жетоны ♦. Обновить витрину стоит 1♦. "
                    + "Карту можно продать за половину цены. Помните: монеты нужны и для долга!",
            "Не тратьте всё — оставляйте запас к сроку. Ранние улучшения линий окупаются весь забег. "
                    + "Собирайте карты одной семьи. Ищите множители: они растут быстрее долгов. "
                    + "Три концовки ждут тех, кто выберется… и одна — тех, кто нет."};
    private int page;
    private String[] lines;
    private int linesFor = -1;
    private int scroll;

    public void paint(Graphics g) {
        Image bg = ResourceManager.bg("bg_room.png");
        if (bg != null) {
            g.drawImage(bg, 0, 0, Gfx.TL);
        }
        PixelFont.shadow(g, "СПРАВКА " + (page + 1) + "/" + TITLE.length, 120, 6, PixelFont.GOLD, Graphics.HCENTER);
        Gfx.banner(g, TITLE[page], 34);
        if (linesFor != page) {
            lines = PixelFont.wrap(TEXT[page], 214);
            linesFor = page;
            scroll = 0;
        }
        int max = 19;
        for (int i = 0; i < max && i + scroll < lines.length; i++) {
            PixelFont.draw(g, lines[i + scroll], 13, 60 + i * PixelFont.LINE, PixelFont.CREAM, Graphics.LEFT);
        }
        PixelFont.draw(g, "4/6 или # — страницы", 120, 292, PixelFont.GRAY, Graphics.HCENTER);
        Gfx.softkeys(g, null, "Назад");
    }

    public void key(int k) {
        switch (k) {
            case K_RSOFT:
            case K_0:
                goBack();
                break;
            case K_RIGHT:
            case K_POUND:
            case K_FIRE:
                page = (page + 1) % TITLE.length;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_LEFT:
                page = (page + TITLE.length - 1) % TITLE.length;
                mm.sfx(SoundManager.MOVE);
                break;
            case K_DOWN:
                if (lines != null && scroll + 19 < lines.length) {
                    scroll++;
                }
                break;
            case K_UP:
                if (scroll > 0) {
                    scroll--;
                }
                break;
            default:
                break;
        }
    }
}
