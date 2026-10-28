package luckypit;

/** Immutable definition of one collectible card (loaded from cards.dat). */
public final class Card {
    public static final int COMMON = 0, UNCOMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4, CURSED = 5;
    public static final String[] RARITY = {"Обычная", "Необычная", "Редкая", "Эпическая",
            "Легендарная", "Проклятая"};
    public static final String[] FAMILY = {"Фрукты", "Удача", "Блеск", "Семёрки", "Кровь",
            "Время", "Банк", "Хаос"};
    public static final int FAMILIES = 8;

    public final int id;
    public final int rarity;
    public final int family;
    public final int price;
    /** Up to two effects: op, a, b, c. op == 0 means unused. */
    public final int[] op = new int[2];
    public final int[] a = new int[2];
    public final int[] b = new int[2];
    public final int[] c = new int[2];
    public final String name;
    public final String desc;

    Card(int id, int rarity, int family, int price, String name, String desc) {
        this.id = id;
        this.rarity = rarity;
        this.family = family;
        this.price = price;
        this.name = name;
        this.desc = desc;
    }

    public boolean has(int opcode) {
        return op[0] == opcode || op[1] == opcode;
    }
}
