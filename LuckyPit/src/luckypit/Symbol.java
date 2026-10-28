package luckypit;

/** Reel symbols and their base tables. */
public final class Symbol {
    public static final int CHERRY = 0, LEMON = 1, HORSESHOE = 2, BELL = 3, CLOVER = 4,
            STAR = 5, DIAMOND = 6, SEVEN = 7, EYE = 8, SKULL = 9;
    public static final int COUNT = 10;

    /** Coins paid by a line of three. */
    public static final int[] BASE_VALUE = {3, 3, 4, 5, 4, 6, 10, 15, 25, 0};
    /** Relative drop weights of the stock machine. */
    public static final int[] BASE_WEIGHT = {28, 26, 16, 12, 10, 8, 5, 3, 3, 3};

    public static final String[] NAME = {"Вишня", "Лимон", "Подкова", "Колокол", "Клевер",
            "Звезда", "Алмаз", "Семёрка", "Око", "Череп"};

    public static final String[] NOTE = {
            "Частая и дешёвая.",
            "Частый и дешёвый.",
            "Надёжная середина.",
            "Звонкий: карты дают за него прокрутки.",
            "Линия клеверов приносит жетон ♦.",
            "Россыпь: 3+ звезды платят где угодно.",
            "Редкий и дорогой.",
            "Самый ценный символ.",
            "Дикий: заменяет любой символ, кроме черепа.",
            "Линия из трёх черепов — проклятие: выигрыш сгорает."};

    private Symbol() {
    }
}
