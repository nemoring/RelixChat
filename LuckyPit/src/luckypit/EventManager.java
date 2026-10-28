package luckypit;

/** Random events between rounds. Each offers two choices. */
public final class EventManager {
    public static final int COUNT = 12;
    public static final String[] TITLE = {
            "Бродячий торговец", "Сбой автомата", "Сборщик долгов", "Счастливая монетка",
            "Тёмная сделка", "Механик", "Шулер", "Ночная смена",
            "Пожар в подсобке", "Клеверный дождь", "Налоговая", "Старый игрок"};
    public static final String[] TEXT = {
            "Сутулый человек раскрывает чемодан с картами. «Для тебя — скидка».",
            "Автомат искрит и гудит. Семёрки мелькают чаще… как и черепа.",
            "Сборщик предлагает отсрочку: больше прокруток сейчас, но долг подрастёт.",
            "Под автоматом блестит монетка. Похоже, сегодня везёт.",
            "Голос из темноты шепчет: «Возьми карту. Цена — пустяк».",
            "Механик готов подкрутить автомат. Не бесплатно.",
            "Шулер предлагает сыграть в напёрстки на жетоны. Шансы честные.",
            "Хозяин ямы предлагает остаться на ночь: больше прокруток, больше долг.",
            "В подсобке пожар! Одна из ваших карт может сгореть.",
            "С потолка сыплются сухие листья клевера. Хороший знак.",
            "Инспектор требует налог: монетами или картой.",
            "Седой игрок делится секретами и дарит жетон."};
    /** Card whose illustration pictures the event. */
    public static final String[] ART = {
            "Перекупщик", "Машина хаоса", "Кредитная линия", "Медная монетка", "Сделка с тенью", "Часовщик",
            "Игральные кости", "Ночная смена", "Списание долга", "Четырёхлистник", "Ростовщик", "Лепрекон"};
    public static final String[] OPT_A = {
            "Купить карту −40%", "Рискнуть", "Принять отсрочку", "Взять монетку",
            "Взять карту", "Заплатить 25% монет", "Сыграть на 3♦", "Остаться",
            "Потушить за 2♦", "Собрать листья", "Заплатить 10%", "Поблагодарить"};
    public static final String[] OPT_B = {
            "Уйти", "Выключить сбой", "Отказаться", "", "Отказаться", "Отказаться", "Отказаться", "Уйти домой",
            "Пусть горит", "", "Отдать карту", ""};

    /** Card offered by the merchant / dark deal (stored in g.offer[0] while the event is open). */
    private EventManager() {
    }

    /** Rolls whether an event happens and which. Sets g.eventId, returns true if any. */
    public static boolean roll(GameState g) {
        if (g.roundsPlayed < 1 || !g.rng.chance(33)) {
            g.eventId = -1;
            return false;
        }
        for (int t = 0; t < 10; t++) {
            int id = g.rng.nextInt(COUNT);
            if (valid(g, id)) {
                g.eventId = id;
                prepare(g, id);
                g.phase = GameState.PH_EVENT;
                return true;
            }
        }
        g.eventId = -1;
        return false;
    }

    private static boolean valid(GameState g, int id) {
        int owned = CardManager.ownedCount(g);
        switch (id) {
            case 0: return owned < CardManager.capacity(g);
            case 4: return owned < CardManager.capacity(g);
            case 5: return g.coins > 10;
            case 6: return g.tokens >= 3;
            case 8: return owned > 0;
            case 10: return owned > 0 && g.coins > 10;
            default: return true;
        }
    }

    private static void prepare(GameState g, int id) {
        g.offerCount = 0;
        if (id == 0) {
            int[] ex = new int[0];
            int c = CardManager.rollOffer(g, g.rng, ex, 0, 100);
            g.offer[0] = c;
            EffectManager.Mods m = new EffectManager.Mods();
            EffectManager.compute(g, m);
            g.offerPrice[0] = c >= 0 ? Shop.priceOf(g, m, c) * 60 / 100 : 0;
        } else if (id == 4) {
            g.offer[0] = CardManager.randomOfRarity(g, g.rng, Card.CURSED);
        }
    }

    public static boolean hasB(int id) {
        return OPT_B[id].length() > 0;
    }

    /** Extra line shown under the text (prices, the offered card). */
    public static String detail(GameState g) {
        int id = g.eventId;
        if ((id == 0 || id == 4) && g.offer[0] >= 0) {
            Card c = CardManager.get(g.offer[0]);
            if (id == 0) {
                return c.name + " — " + g.offerPrice[0] + "¢";
            }
            return c.name + " +3♦";
        }
        if (id == 5) {
            return "Цена: " + (g.coins / 4) + "¢ за случайное улучшение";
        }
        if (id == 10) {
            return "Налог: " + (g.coins / 10) + "¢";
        }
        return "";
    }

    /** Applies the choice. Returns a short result message. */
    public static String choose(GameState g, boolean a) {
        int id = g.eventId;
        g.eventId = -1;
        Rng r = g.rng;
        switch (id) {
            case 0:
                if (a) {
                    int c = g.offer[0];
                    if (c >= 0 && g.coins >= g.offerPrice[0]) {
                        g.coins -= g.offerPrice[0];
                        CardManager.add(g, c, g.offerPrice[0]);
                        g.stats.cardsBought++;
                        return "Карта ваша: " + CardManager.get(c).name;
                    }
                    return "Не хватает монет.";
                }
                return "Торговец растворился в дыму.";
            case 1:
                if (a) {
                    g.evSym = Symbol.SEVEN;
                    g.evSymAdd = 5;
                    g.evMult = 0;
                    return "Семёрки чаще в следующем раунде. Черепа тоже не дремлют.";
                }
                return "Автомат затих.";
            case 2:
                if (a) {
                    g.evSpins = 3;
                    g.debtBase = g.debtBase * 115 / 100;
                    return "+3 прокрутки в раунде. Долг +15%.";
                }
                return "Сборщик хмыкнул и ушёл.";
            case 3: {
                int v = (5 + r.nextInt(11)) * (g.deadline + 1);
                g.addCoins(v);
                return "+" + v + "¢";
            }
            case 4:
                if (a && g.offer[0] >= 0) {
                    CardManager.add(g, g.offer[0], 0);
                    g.tokens += 3;
                    return "Проклятая карта получена. +3♦";
                }
                return "Голос затих.";
            case 5:
                if (a) {
                    int cost = g.coins / 4;
                    int[] can = new int[GameState.UPGRADES];
                    int n = 0;
                    for (int u = 0; u < GameState.UPGRADES; u++) {
                        if (g.upgCost(u) >= 0) {
                            can[n++] = u;
                        }
                    }
                    if (n == 0) {
                        return "Улучшать уже нечего.";
                    }
                    g.coins -= cost;
                    int u = can[r.nextInt(n)];
                    g.upg[u]++;
                    return "Улучшено: " + Shop.UPG_NAME[u];
                }
                return "Механик пожал плечами.";
            case 6:
                if (a) {
                    if (r.chance(50)) {
                        g.tokens += 3;
                        return "Победа! +3♦";
                    }
                    g.tokens -= 3;
                    return "Шулер оказался ловчее. −3♦";
                }
                return "Шулер зевнул.";
            case 7:
                if (a) {
                    g.evSpins = 4;
                    g.debtBase = g.debtBase * 110 / 100;
                    return "+4 прокрутки в раунде. Долг +10%.";
                }
                return "Вы ушли спать.";
            case 8: {
                if (a && g.tokens >= 2) {
                    g.tokens -= 2;
                    return "Пожар потушен.";
                }
                int n = CardManager.ownedCount(g);
                if (n > 0) {
                    int s = r.nextInt(n);
                    String nm = CardManager.get(g.cards[s]).name;
                    CardManager.remove(g, s);
                    return "Сгорела карта: " + nm;
                }
                return "Огонь погас сам.";
            }
            case 9:
                g.evSym = Symbol.CLOVER;
                g.evSymAdd = 8;
                return "«Клевер» чаще в следующем раунде.";
            case 10:
                if (a) {
                    int t = g.coins / 10;
                    g.coins -= t;
                    return "Уплачено " + t + "¢";
                } else {
                    int n = CardManager.ownedCount(g);
                    int s = r.nextInt(n);
                    String nm = CardManager.get(g.cards[s]).name;
                    CardManager.remove(g, s);
                    return "Отдана карта: " + nm;
                }
            default:
                g.tokens += 1;
                return "+1♦ и пара хитростей.";
        }
    }
}
