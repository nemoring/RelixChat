# -*- coding: utf-8 -*-
"""Card database: effects, auto-generated Russian descriptions and art.

Outputs:
  res/cards.dat           binary card table read by CardManager
  res/c/<id>.png          24x24 illustration per card
  res/frames.png          rarity frames (28x28 x 6)
  src/luckypit/Op.java    effect opcode constants (single source of truth)
"""
import struct
import os
from pix import Pix, RAMP, vgrad
import motifs as M

# ------------------------------------------------------------- opcodes
OPS = [
    'VAL_ADD', 'VAL_MUL', 'WEIGHT', 'MULT', 'PER_SYM_MULT', 'PER_SYM_COIN', 'LAST_SPIN', 'FIRST_SPIN',
    'NTH_WIN', 'CHAOS', 'JACKPOT', 'TRIPLE_FLAT', 'DEBT_ADD', 'SPINS', 'INTEREST', 'TOKENS_ROUND',
    'SKULL_WARD', 'LOSS_STREAK', 'WIN_STREAK', 'EMPTY_SLOT', 'PER_CARD', 'PER_RARITY', 'RICH',
    'LINE_GROUP', 'PAIRS', 'STAR_SCATTER', 'BELL_SPIN', 'CLOVER_TOKEN', 'DEBT_CUT', 'SELL_BONUS',
    'DISCOUNT', 'FREE_REROLL', 'DEADLINE_COINS', 'GROW_SYM', 'ROUND_COINS', 'DICE', 'MIRROR',
    'TRANSFORM', 'MIN_PAY', 'LOSS_TOKEN', 'WILD_CELL', 'GAMBLE', 'TOKEN_MULT', 'DEADLINE_MULT',
    'SLOTS', 'PRE_DEADLINE', 'EYE_BONUS', 'FREE_SPIN', 'NEAR_JACKPOT', 'ON_BUY_COINS',
    'ON_BUY_TOKENS', 'INVEST', 'HIGH_ROLLER', 'FAMILY_BOOST', 'GROW_MULT', 'COPY_ROW',
    'SHOP_SLOTS', 'LUCKY_RARITY', 'COMBO', 'FAMILY_VARIETY', 'REVIVE',
]
OP = {n: i + 1 for i, n in enumerate(OPS)}

SYM = ['Вишня', 'Лимон', 'Подкова', 'Колокол', 'Клевер', 'Звезда', 'Алмаз', 'Семёрка', 'Око', 'Череп']
CH, LE, HO, BE, CL, ST, DI, SE, EY, SK = range(10)
FAM = ['Фрукты', 'Удача', 'Блеск', 'Семёрки', 'Кровь', 'Время', 'Банк', 'Хаос']
RAR = ['Обычная', 'Необычная', 'Редкая', 'Эпическая', 'Легендарная', 'Проклятая']
C, U, R, E, L, X = range(6)
GROUP = ['горизонталей', 'диагоналей', 'V-линий', 'вертикалей', 'средней линии', 'верхней и нижней линий']
PRICE = [10, 18, 30, 50, 80, 8]


def S(i):
    return '«' + SYM[i] + '»'


def pct_or_x(b):
    if b % 100 == 0:
        return '×' + str(1 + b // 100)
    return '+' + str(b) + '%'


def plural(n, one, few, many):
    n = abs(n)
    if n % 10 == 1 and n % 100 != 11:
        return one
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return few
    return many


def desc_of(op, a, b, c):
    o = OPS[op - 1]
    sg = lambda v: ('+' if v >= 0 else '') + str(v)
    if o == 'VAL_ADD': return '%s: ценность %s.' % (S(a), sg(b))
    if o == 'VAL_MUL': return 'Линии %s: %s к выигрышу.' % (S(a), pct_or_x(b))
    if o == 'WEIGHT': return '%s выпадает %s (вес %s).' % (S(a), 'чаще' if b > 0 else 'реже', sg(b))
    if o == 'MULT': return 'Множитель выигрыша %s%%.' % sg(a)
    if o == 'PER_SYM_MULT': return 'Каждый %s на поле: +%d%% к множителю.' % (S(a), b)
    if o == 'PER_SYM_COIN': return 'Каждый %s на поле: +%d¢×срок.' % (S(a), b)
    if o == 'LAST_SPIN': return 'Последняя прокрутка раунда: +%d%%.' % a
    if o == 'FIRST_SPIN': return 'Первая прокрутка раунда: +%d%%.' % a
    if o == 'NTH_WIN':
        return 'Каждый %d-й выигрыш %s.' % (a, 'удваивается' if b == 100 else 'получает +%d%%' % b)
    if o == 'CHAOS':
        return ('После остановки один случайный символ заменяется.' if a == 1 else
                'После остановки %d случайных символа заменяются.' % a)
    if o == 'JACKPOT': return 'Джекпот: +%d%%.' % a
    if o == 'TRIPLE_FLAT': return 'Каждая линия %s: +%d¢×срок.' % (S(a), b)
    if o == 'DEBT_ADD': return 'Каждый новый долг +%d%%.' % a
    if o == 'SPINS': return '%s %s за раунд.' % (sg(a), plural(a, 'прокрутка', 'прокрутки', 'прокруток'))
    if o == 'INTEREST': return 'Проценты в конце раунда +%d%%.' % a
    if o == 'TOKENS_ROUND': return '%s♦ в конце раунда.' % sg(a)
    if o == 'SKULL_WARD':
        return ('Линия %s не проклинает.' % S(SK)) if a == 0 else \
            'Линия %s не проклинает, а даёт %d¢×срок.' % (S(SK), a)
    if o == 'LOSS_STREAK': return 'Каждая пустая прокрутка подряд: +%d%% (до выигрыша).' % a
    if o == 'WIN_STREAK': return 'Каждый выигрыш подряд: +%d%% (до промаха).' % a
    if o == 'EMPTY_SLOT': return '+%d%% за каждый пустой слот карт.' % a
    if o == 'PER_CARD': return '+%d%% за каждую вашу карту.' % a
    if o == 'PER_RARITY': return '+%d%% за каждую карту редкости «%s».' % (b, RAR[a])
    if o == 'RICH': return '+1%% за каждые %d¢×срок в кармане (до +%d%%).' % (a, b)
    if o == 'LINE_GROUP': return 'Выигрыш %s +%d%%.' % (GROUP[a], b)
    if o == 'PAIRS': return 'Пары (2 одинаковых с начала линии) платят %d%% тройки.' % a
    if o == 'STAR_SCATTER':
        t = 'Россыпь %s' % S(ST)
        if a: t += ' уже от %d звёзд' % (3 - a)
        if b: t += ', +%d за звезду' % b
        return t + '.'
    if o == 'BELL_SPIN': return 'Линия %s: +1 прокрутка (до %d за раунд).' % (S(BE), a)
    if o == 'CLOVER_TOKEN': return 'Линия %s: +%d♦.' % (S(CL), a)
    if o == 'DEBT_CUT': return 'Каждый долг меньше на %d%%.' % a
    if o == 'SELL_BONUS': return 'Цена продажи карт +%d%%.' % a
    if o == 'DISCOUNT': return 'Скидка в магазине %d%%.' % a
    if o == 'FREE_REROLL': return '%d бесплатн. обновление витрины за визит.' % a
    if o == 'DEADLINE_COINS': return 'При оплате срока: +%d¢×срок.' % a
    if o == 'GROW_SYM': return 'Каждая линия %s навсегда усиливает их на %d%%.' % (S(a), b)
    if o == 'ROUND_COINS': return 'В конце раунда +%d¢×срок.' % a
    if o == 'DICE': return 'Выигрыш умножается на случайное от %d%% до %d%%.' % (a, b)
    if o == 'MIRROR': return 'Копирует эффект карты справа.'
    if o == 'TRANSFORM': return '%s с шансом %d%% становится %s.' % (S(a), c, S(b))
    if o == 'MIN_PAY': return 'Пустая прокрутка: +%d¢×срок.' % a
    if o == 'LOSS_TOKEN': return 'Каждые %d пустые прокрутки: +1♦.' % a
    if o == 'WILD_CELL': return '%d%%: случайная клетка становится %s.' % (a, S(EY))
    if o == 'GAMBLE': return 'Каждый выигрыш: %d%% — ×2, иначе ×0,5.' % a
    if o == 'TOKEN_MULT': return '+%d%% за каждый ваш жетон ♦.' % a
    if o == 'DEADLINE_MULT': return '+%d%% за каждый оплаченный срок.' % a
    if o == 'SLOTS': return '+%d %s для карт.' % (a, plural(a, 'слот', 'слота', 'слотов'))
    if o == 'PRE_DEADLINE': return 'Последний раунд перед сроком: +%d%%.' % a
    if o == 'EYE_BONUS': return 'Каждое %s в выигрышной линии: +%d%% к линии.' % (S(EY), a)
    if o == 'FREE_SPIN': return '%d%%: прокрутка не тратится.' % a
    if o == 'NEAR_JACKPOT': return '7-8 одинаковых символов на поле: +%d%%.' % a
    if o == 'ON_BUY_COINS': return 'При покупке: +%d¢×срок.' % a
    if o == 'ON_BUY_TOKENS': return 'При покупке: +%d♦.' % a
    if o == 'INVEST': return 'Цена продажи растёт на %d¢×срок каждый раунд.' % a
    if o == 'HIGH_ROLLER': return 'Выигрыш от %d¢×срок получает ещё +%d%%.' % (a, b)
    if o == 'FAMILY_BOOST': return '+%d%% за каждую карту семьи «%s».' % (b, FAM[a])
    if o == 'GROW_MULT': return 'Растёт: +%d%% за каждый раунд у вас.' % a
    if o == 'COPY_ROW': return '%d%%: нижняя линия копирует среднюю.' % a
    if o == 'SHOP_SLOTS': return 'В магазине +%d %s.' % (a, plural(a, 'карта', 'карты', 'карт'))
    if o == 'LUCKY_RARITY': return 'Редкие карты в магазине встречаются чаще.'
    if o == 'COMBO': return 'Комбо: +%d%% за каждую доп. линию.' % a
    if o == 'FAMILY_VARIETY': return '+%d%% за каждую разную семью ваших карт.' % a
    if o == 'REVIVE': return 'Один раз спасает от неоплаченного долга и сгорает.'
    raise ValueError(o)


def e(op, a=0, b=0, c=0):
    return (OP[op], a, b, c)


# name, rarity, family, effects, art(motif, ramp, second, badge)
CARDS = [
    # ---------------------------------------------------------- 0 Фрукты
    ('Вишнёвая косточка', C, 0, [e('VAL_ADD', CH, 1)], ('cherry', None, None, '+1')),
    ('Лимонная корка', C, 0, [e('VAL_ADD', LE, 1)], ('lemon', None, None, '+1')),
    ('Вишнёвый сад', C, 0, [e('WEIGHT', CH, 4)], ('cherry', None, 'clover', None)),
    ('Лимонная роща', C, 0, [e('WEIGHT', LE, 4)], ('lemon', None, 'clover', None)),
    ('Вишнёвый шторм', U, 0, [e('PER_SYM_MULT', CH, 10)], ('cherry', None, 'bolt', None)),
    ('Кислинка', U, 0, [e('PER_SYM_MULT', LE, 10)], ('lemon', None, 'bolt', None)),
    ('Компот', U, 0, [e('VAL_ADD', CH, 1), e('VAL_ADD', LE, 1)], ('goblet', 'red', 'cherry', None)),
    ('Фруктовый салат', U, 0, [e('PER_SYM_COIN', CH, 1), e('PER_SYM_COIN', LE, 1)], ('lemon', None, 'cherry', None)),
    ('Вишнёвый ликёр', R, 0, [e('VAL_MUL', CH, 100)], ('potion', 'red', 'cherry', None)),
    ('Лимонад', R, 0, [e('VAL_MUL', LE, 100)], ('potion', 'yellow', 'lemon', None)),
    ('Лимонное золото', R, 0, [e('TRANSFORM', LE, BE, 30)], ('lemon', 'gold', 'bell', None)),
    ('Вечная вишня', E, 0, [e('GROW_SYM', CH, 15)], ('cherry', 'purple', 'hourglass', None)),
    ('Королевская вишня', L, 0, [e('VAL_MUL', CH, 300), e('WEIGHT', CH, 4)], ('cherry', None, 'crown', None)),
    ('Вишнёвый сок', C, 0, [e('TRIPLE_FLAT', CH, 3)], ('goblet', None, 'cherry', None)),
    ('Засахаренный лимон', U, 0, [e('TRIPLE_FLAT', LE, 4)], ('lemon', 'orange', None, None)),
    ('Фруктовый взрыв', E, 0, [e('PER_SYM_MULT', CH, 20), e('PER_SYM_MULT', LE, 20)], ('cherry', None, 'flame', None)),
    ('Гнилое яблоко', X, 0, [e('WEIGHT', CH, 10), e('WEIGHT', SK, 3)], ('cherry', 'brown', 'skull', None)),
    ('Брожение', R, 0, [e('GROW_MULT', 4)], ('potion', 'orange', None, None)),
    ('Фруктовая лавка', R, 0, [e('FAMILY_BOOST', 0, 15)], ('bag', None, 'lemon', None)),
    ('Двойная косточка', C, 0, [e('VAL_ADD', CH, 2), e('WEIGHT', LE, -3)], ('cherry', None, None, '+2')),
    ('Цитрусовый пресс', U, 0, [e('VAL_ADD', LE, 3), e('WEIGHT', CH, -3)], ('lemon', None, 'gear', None)),
    # ---------------------------------------------------------- 1 Удача
    ('Четырёхлистник', C, 1, [e('WEIGHT', CL, 4)], ('clover', None, None, None)),
    ('Подкова на гвозде', C, 1, [e('WEIGHT', HO, 4)], ('horseshoe', None, None, None)),
    ('Клеверное поле', U, 1, [e('CLOVER_TOKEN', 1)], ('clover', None, 'ticket', None)),
    ('Ржавая подкова', C, 1, [e('VAL_ADD', HO, 2)], ('horseshoe', 'brown', None, '+2')),
    ('Счастливый клевер', U, 1, [e('VAL_ADD', CL, 3)], ('clover', None, 'star', None)),
    ('Кроличья лапка', R, 1, [e('WEIGHT', EY, 2)], ('paw', None, None, None)),
    ('Божья коровка', U, 1, [e('WEIGHT', SK, -2)], ('ladybug', None, None, None)),
    ('Счастливый билет', R, 1, [e('FREE_SPIN', 15)], ('ticket', None, None, None)),
    ('Подкова удачи', R, 1, [e('VAL_MUL', HO, 150)], ('horseshoe', 'gold', None, None)),
    ('Клеверный венец', E, 1, [e('PER_SYM_MULT', CL, 15), e('WEIGHT', CL, 3)], ('clover', None, 'crown', None)),
    ('Монетка на счастье', C, 1, [e('MIN_PAY', 2)], ('coin', None, 'clover', None)),
    ('Падающая звезда', U, 1, [e('LOSS_TOKEN', 4)], ('star', 'cyan', None, None)),
    ('Упрямство', U, 1, [e('LOSS_STREAK', 20)], ('horseshoe', 'red', None, None)),
    ('Ловец удачи', R, 1, [e('LUCKY_RARITY', 50)], ('orb', 'green', None, None)),
    ('Семь клеверов', L, 1, [e('CLOVER_TOKEN', 2), e('VAL_MUL', CL, 200)], ('clover', 'gold', None, '7')),
    ('Удачливый дурак', E, 1, [e('GAMBLE', 62)], ('mask', 'bone', 'clover', None)),
    ('Золотая подкова', E, 1, [e('TRIPLE_FLAT', HO, 10), e('WEIGHT', HO, 3)], ('horseshoe', 'gold', 'coin', None)),
    ('Подкова и клевер', R, 1, [e('FAMILY_BOOST', 1, 15)], ('horseshoe', None, 'clover', None)),
    ('Чёрная кошка', X, 1, [e('WEIGHT', SK, 4), e('MULT', 60)], ('cat', None, None, None)),
    ('Лепрекон', L, 1, [e('ROUND_COINS', 10), e('TOKENS_ROUND', 1)], ('tophat', None, 'coin', None)),
    ('Клевер в янтаре', U, 1, [e('WEIGHT', CL, 3), e('VAL_ADD', CL, 1)], ('clover', 'orange', None, None)),
    ('Счастливая подкова', U, 1, [e('PER_SYM_MULT', HO, 10)], ('horseshoe', None, 'bolt', None)),
    # ---------------------------------------------------------- 2 Блеск
    ('Огранка', C, 2, [e('VAL_ADD', DI, 2)], ('diamond', None, None, '+2')),
    ('Звёздная пыль', C, 2, [e('VAL_ADD', ST, 2)], ('star', None, None, '+2')),
    ('Россыпь', U, 2, [e('STAR_SCATTER', 1, 2)], ('star', None, 'star', None)),
    ('Шахтёр', C, 2, [e('WEIGHT', DI, 3)], ('pickaxe', None, 'diamond', None)),
    ('Звездопад', C, 2, [e('WEIGHT', ST, 3)], ('star', 'orange', 'star', None)),
    ('Бриллиантовая огранка', R, 2, [e('VAL_MUL', DI, 100)], ('diamond', 'blue', None, 'x2')),
    ('Созвездие', R, 2, [e('PER_SYM_MULT', ST, 15)], ('star', 'blue', 'star', None)),
    ('Призма', U, 2, [e('PER_SYM_COIN', DI, 2)], ('prism', None, None, None)),
    ('Алмазная жила', E, 2, [e('GROW_SYM', DI, 20)], ('pickaxe', 'gold', 'diamond', None)),
    ('Сверхновая', E, 2, [e('VAL_MUL', ST, 200), e('STAR_SCATTER', 0, 4)], ('sun', 'yellow', None, None)),
    ('Блеск софитов', U, 2, [e('LINE_GROUP', 0, 25)], ('sun', 'gold', None, None)),
    ('Хрустальная люстра', R, 2, [e('LINE_GROUP', 1, 60)], ('prism', 'cyan', 'candle', None)),
    ('Ювелир', R, 2, [e('SELL_BONUS', 50), e('DISCOUNT', 10)], ('diamond', None, 'scales', None)),
    ('Звезда шерифа', U, 2, [e('TRIPLE_FLAT', ST, 5)], ('star', 'gold', None, None)),
    ('Кровавый алмаз', X, 2, [e('VAL_MUL', DI, 300), e('DEBT_ADD', 10)], ('diamond', 'red', 'drop', None)),
    ('Корона', L, 2, [e('MULT', 100), e('PER_CARD', 5)], ('crown', None, None, None)),
    ('Полярная звезда', E, 2, [e('WEIGHT', ST, 4), e('PER_SYM_MULT', ST, 10)], ('star', 'cyan', 'moon', None)),
    ('Алмазная пыль', C, 2, [e('TRANSFORM', SK, DI, 20)], ('skull', None, 'diamond', None)),
    ('Витрина ювелира', R, 2, [e('FAMILY_BOOST', 2, 15)], ('diamond', None, 'star', None)),
    ('Сапфир', U, 2, [e('VAL_ADD', DI, 3), e('VAL_ADD', ST, 1)], ('diamond', 'blue', None, None)),
    ('Лунный камень', R, 2, [e('PER_SYM_MULT', DI, 20)], ('diamond', 'bone', 'moon', None)),
    # ---------------------------------------------------------- 3 Семёрки
    ('Золотая семёрка', R, 3, [e('VAL_MUL', SE, 200)], ('seven', 'gold', None, 'x3')),
    ('Король джекпота', E, 3, [e('TRIPLE_FLAT', SE, 25), e('JACKPOT', 100)], ('seven', None, 'crown', None)),
    ('Счастливая семёрка', C, 3, [e('WEIGHT', SE, 2)], ('seven', None, 'clover', None)),
    ('Семь ветров', U, 3, [e('VAL_ADD', SE, 5)], ('seven', 'cyan', None, '+5')),
    ('Тройная семёрка', U, 3, [e('PER_SYM_MULT', SE, 15)], ('seven', None, 'seven', None)),
    ('Мегаджекпот', L, 3, [e('JACKPOT', 400), e('NEAR_JACKPOT', 200)], ('coins', None, 'seven', None)),
    ('Почти джекпот', R, 3, [e('NEAR_JACKPOT', 150)], ('seven', 'orange', 'coins', None)),
    ('Счётчик семёрок', U, 3, [e('PER_SYM_COIN', SE, 3)], ('seven', None, 'coin', None)),
    ('Семёрка-оборотень', R, 3, [e('TRANSFORM', BE, SE, 20)], ('bell', None, 'seven', None)),
    ('Чёртова семёрка', X, 3, [e('VAL_MUL', SE, 300), e('SPINS', -1)], ('seven', 'blood', 'flame', None)),
    ('Табло джекпота', U, 3, [e('JACKPOT', 150)], ('seven', None, 'bolt', None)),
    ('Семь чудес', E, 3, [e('GROW_SYM', SE, 30)], ('seven', 'purple', 'star', None)),
    ('Барабан удачи', C, 3, [e('FIRST_SPIN', 50)], ('wheel', None, None, None)),
    ('Магнит семёрок', R, 3, [e('WEIGHT', SE, 3), e('WEIGHT', EY, 1)], ('seven', None, 'horseshoe', None)),
    ('Колесо фортуны', L, 3, [e('DICE', 50, 400)], ('wheel', 'gold', 'seven', None)),
    ('Счастливое число', C, 3, [e('VAL_ADD', SE, 3)], ('seven', None, None, '+3')),
    ('Клуб семёрок', R, 3, [e('FAMILY_BOOST', 3, 15)], ('seven', None, 'tophat', None)),
    ('Неоновая вывеска', U, 3, [e('LINE_GROUP', 4, 50)], ('seven', 'pink', None, None)),
    # ---------------------------------------------------------- 4 Кровь
    ('Кровавый контракт', X, 4, [e('MULT', 100), e('DEBT_ADD', 25)], ('contract', None, 'drop', None)),
    ('Жертва', R, 4, [e('PER_RARITY', X, 40)], ('knife', None, 'drop', None)),
    ('Ритуальный нож', U, 4, [e('MULT', 25), e('WEIGHT', SK, 2)], ('knife', None, None, None)),
    ('Некромант', E, 4, [e('SKULL_WARD', 20)], ('skull', None, 'book', None)),
    ('Вампир', R, 4, [e('WIN_STREAK', 25)], ('bat', None, None, None)),
    ('Кровавая луна', E, 4, [e('PER_SYM_MULT', SK, 30)], ('moon', 'red', None, None)),
    ('Чёрная метка', X, 4, [e('MULT', 150), e('TOKENS_ROUND', -1)], ('card', 'gray', 'skull', None)),
    ('Сделка с тенью', X, 4, [e('ON_BUY_TOKENS', 6), e('DEBT_ADD', 15)], ('mask', 'gray', None, None)),
    ('Пакт крови', L, 4, [e('PER_RARITY', X, 100), e('SKULL_WARD', 30)], ('goblet', None, 'skull', None)),
    ('Шрам', U, 4, [e('LOSS_STREAK', 25)], ('knife', 'red', None, None)),
    ('Багровый туз', R, 4, [e('HIGH_ROLLER', 30, 100)], ('card', None, 'drop', None)),
    ('Проклятая монета', X, 4, [e('ROUND_COINS', 15), e('WEIGHT', SK, 5)], ('coin', 'blood', None, None)),
    ('Оберег', C, 4, [e('WEIGHT', SK, -3)], ('eye', 'blue', None, None)),
    ('Кровопускание', U, 4, [e('MULT', 50), e('SPINS', -1)], ('drop', None, None, None)),
    ('Череп-копилка', R, 4, [e('PER_SYM_COIN', SK, 4)], ('skull', None, 'coin', None)),
    ('Палач', E, 4, [e('SKULL_WARD', 10), e('PER_SYM_MULT', SK, 20)], ('mask', 'blood', 'knife', None)),
    ('Алтарь', R, 4, [e('FAMILY_BOOST', 4, 15)], ('candle', None, 'skull', None)),
    ('Кровавая роза', U, 4, [e('MULT', 30)], ('rose', None, None, None)),
    ('Обсидиановый череп', L, 4, [e('SKULL_WARD', 60), e('WEIGHT', SK, 4)], ('skull', 'gray', 'diamond', None)),
    # ---------------------------------------------------------- 5 Время
    ('Последний шанс', U, 5, [e('LAST_SPIN', 150)], ('hourglass', None, None, None)),
    ('Песочные часы', C, 5, [e('SPINS', 1)], ('hourglass', 'orange', None, '+1')),
    ('Будильник', U, 5, [e('FIRST_SPIN', 100)], ('clock', 'red', None, None)),
    ('Двойные неприятности', R, 5, [e('NTH_WIN', 3, 100)], ('dice', None, 'dice', None)),
    ('Колокольный звон', U, 5, [e('BELL_SPIN', 2)], ('bell', None, 'clock', None)),
    ('Сверхурочные', R, 5, [e('SPINS', 2)], ('clock', None, 'coin', '+2')),
    ('Маятник', R, 5, [e('PRE_DEADLINE', 100)], ('clock', 'steel', None, None)),
    ('Часовщик', E, 5, [e('SPINS', 2), e('LAST_SPIN', 100)], ('gear', 'gold', 'clock', None)),
    ('Вечный двигатель', L, 5, [e('FREE_SPIN', 30), e('SPINS', 1)], ('gear', None, 'bolt', None)),
    ('Спешка', C, 5, [e('LAST_SPIN', 60)], ('hourglass', 'red', None, None)),
    ('Карманные часы', C, 5, [e('PRE_DEADLINE', 40)], ('clock', None, None, None)),
    ('Ночная смена', U, 5, [e('SPINS', 1), e('FIRST_SPIN', 30)], ('moon', None, 'clock', None)),
    ('Остановленное время', X, 5, [e('SPINS', 3), e('DEBT_ADD', 15)], ('hourglass', 'blood', 'chain', None)),
    ('Хронограф', E, 5, [e('NTH_WIN', 2, 75)], ('clock', 'cyan', 'gear', None)),
    ('Набат', R, 5, [e('VAL_MUL', BE, 150), e('BELL_SPIN', 1)], ('bell', 'red', None, None)),
    ('Медный колокол', C, 5, [e('VAL_ADD', BE, 2)], ('bell', 'orange', None, '+2')),
    ('Колокольня', U, 5, [e('WEIGHT', BE, 4)], ('tower', None, 'bell', None)),
    ('Часовая башня', R, 5, [e('FAMILY_BOOST', 5, 15)], ('tower', None, 'clock', None)),
    ('Старый маятник', U, 5, [e('GROW_MULT', 2)], ('clock', 'brown', None, None)),
    ('Второе дыхание', R, 5, [e('LAST_SPIN', 100), e('FIRST_SPIN', 100)], ('hourglass', 'cyan', None, None)),
    # ---------------------------------------------------------- 6 Банк
    ('Копилка', C, 6, [e('INTEREST', 3)], ('bag', None, None, '3%')),
    ('Сейф', U, 6, [e('INTEREST', 5)], ('safe', None, None, None)),
    ('Ростовщик', R, 6, [e('INTEREST', 8)], ('scales', None, 'coin', None)),
    ('Скряга', U, 6, [e('RICH', 4, 60)], ('coins', None, 'lock', None)),
    ('Счетовод', C, 6, [e('ROUND_COINS', 3)], ('book', 'brown', 'coin', None)),
    ('Бухгалтер', U, 6, [e('DEADLINE_COINS', 20)], ('book', 'green', None, None)),
    ('Кредитная линия', R, 6, [e('DEBT_CUT', 10)], ('contract', None, 'coin', None)),
    ('Списание долга', E, 6, [e('DEBT_CUT', 20)], ('contract', None, 'flame', None)),
    ('Инвестиция', U, 6, [e('INVEST', 3)], ('bars', None, None, None)),
    ('Жетонный автомат', U, 6, [e('TOKENS_ROUND', 1)], ('lever', None, 'ticket', None)),
    ('Купон', C, 6, [e('DISCOUNT', 15)], ('ticket', 'green', None, '-15')),
    ('Скупщик', U, 6, [e('SELL_BONUS', 100)], ('bag', None, 'card', None)),
    ('Перекупщик', C, 6, [e('FREE_REROLL', 1)], ('tophat', None, 'card', None)),
    ('Золотой слиток', R, 6, [e('ON_BUY_COINS', 40)], ('bars', 'gold', None, None)),
    ('Сберкнижка', E, 6, [e('TOKEN_MULT', 6)], ('book', 'blue', 'ticket', None)),
    ('Казначей', L, 6, [e('INTEREST', 10), e('DEBT_CUT', 10)], ('safe', 'gold', 'crown', None)),
    ('Долговая яма', X, 6, [e('ON_BUY_COINS', 60), e('DEBT_ADD', 20)], ('chain', None, 'coin', None)),
    ('Кожаный бумажник', U, 6, [e('SLOTS', 2)], ('bag', 'brown', None, '+2')),
    ('Витрина', U, 6, [e('SHOP_SLOTS', 1)], ('card', None, 'coin', '+1')),
    ('Минимализм', R, 6, [e('EMPTY_SLOT', 30)], ('card', 'gray', None, None)),
    ('Коллекционер', R, 6, [e('PER_CARD', 8)], ('book', None, 'card', None)),
    ('Банковское хранилище', R, 6, [e('FAMILY_BOOST', 6, 15)], ('safe', None, 'bars', None)),
    ('Процентщица', E, 6, [e('INTEREST', 6), e('RICH', 3, 80)], ('scales', 'gold', 'bag', None)),
    ('Сложный процент', L, 6, [e('DEADLINE_MULT', 25)], ('bars', None, 'clock', None)),
    # ---------------------------------------------------------- 7 Хаос
    ('Машина хаоса', U, 7, [e('CHAOS', 1)], ('gear', 'purple', 'spiral', None)),
    ('Игральные кости', R, 7, [e('DICE', 80, 200)], ('dice', None, None, None)),
    ('Джокер', E, 7, [e('WILD_CELL', 50)], ('mask', 'purple', 'eye', None)),
    ('Зеркало', E, 7, [e('MIRROR')], ('mirror', None, None, None)),
    ('Око бури', R, 7, [e('EYE_BONUS', 50)], ('eye', None, 'bolt', None)),
    ('Глаз казино', C, 7, [e('WEIGHT', EY, 1)], ('eye', None, None, '+1')),
    ('Близнецы', R, 7, [e('PAIRS', 30)], ('mask', None, 'mask', None)),
    ('Эхо', L, 7, [e('COPY_ROW', 35)], ('mirror', 'purple', 'spiral', None)),
    ('Перевёртыш', U, 7, [e('TRANSFORM', SK, EY, 25)], ('skull', 'purple', 'eye', None)),
    ('Хамелеон', E, 7, [e('TRANSFORM', LE, EY, 12)], ('lemon', 'purple', 'eye', None)),
    ('Краплёная колода', R, 7, [e('NTH_WIN', 4, 150)], ('card', 'red', None, None)),
    ('Ядро хаоса', L, 7, [e('CHAOS', 2), e('WILD_CELL', 100)], ('orb', 'purple', 'spiral', None)),
    ('Безумный механик', X, 7, [e('CHAOS', 3), e('MULT', 100)], ('gear', 'red', 'skull', None)),
    ('Калейдоскоп', U, 7, [e('COMBO', 20)], ('prism', 'purple', None, None)),
    ('Рулетка', C, 7, [e('DICE', 70, 150)], ('wheel', 'red', None, None)),
    ('Монета Януса', U, 7, [e('GAMBLE', 50)], ('coin', 'steel', 'mask', None)),
    ('Петля', U, 7, [e('LINE_GROUP', 2, 50)], ('spiral', 'gold', None, None)),
    ('Колонны', C, 7, [e('LINE_GROUP', 3, 30)], ('tower', 'steel', None, None)),
    ('Середина', C, 7, [e('LINE_GROUP', 4, 40)], ('eye', 'gold', None, None)),
    ('Края', C, 7, [e('LINE_GROUP', 5, 30)], ('mirror', 'steel', None, None)),
    ('Пирамида', R, 7, [e('COMBO', 40)], ('prism', 'gold', None, None)),
    ('Безумие', X, 7, [e('WEIGHT', EY, 4), e('SPINS', -1)], ('spiral', 'red', 'eye', None)),
    ('Дирижёр', E, 7, [e('FAMILY_VARIETY', 12)], ('tophat', 'purple', 'star', None)),
    ('Двойное зеркало', L, 7, [e('MIRROR'), e('MULT', 50)], ('mirror', 'gold', 'mirror', None)),
    ('Ангел-хранитель', L, 7, [e('REVIVE')], ('heart', 'bone', 'star', None)),
    ('Хрустальный шар', R, 7, [e('FAMILY_BOOST', 7, 15)], ('orb', None, None, None)),
    ('Ворон', U, 7, [e('TRANSFORM', SK, SE, 10)], ('raven', None, 'seven', None)),
    ('Карточный домик', U, 7, [e('PER_CARD', 5)], ('card', 'purple', 'card', None)),
    # ---------------------------------------------------------- extra mixed
    ('Пустой карман', C, 6, [e('EMPTY_SLOT', 15)], ('bag', 'gray', None, None)),
    ('Медная монетка', C, 6, [e('MIN_PAY', 1), e('ROUND_COINS', 1)], ('coin', 'orange', None, None)),
    ('Мелкая удача', C, 1, [e('WEIGHT', CL, 2), e('WEIGHT', HO, 2)], ('clover', None, 'horseshoe', None)),
    ('Ржавый рычаг', X, 5, [e('SPINS', -2), e('MULT', 120)], ('lever', 'brown', None, None)),
    ('Счастливая свеча', U, 1, [e('WEIGHT', SK, -1), e('MULT', 15)], ('candle', None, 'clover', None)),
    ('Старая колода', C, 7, [e('PAIRS', 15)], ('card', 'brown', None, None)),
    ('Золотой колокол', R, 5, [e('VAL_ADD', BE, 4), e('BELL_SPIN', 1)], ('bell', 'gold', None, '+4')),
    ('Неразменный рубль', E, 6, [e('INVEST', 6), e('ROUND_COINS', 5)], ('coin', 'cyan', None, None)),
    ('Счастливая звезда', C, 2, [e('PER_SYM_COIN', ST, 1)], ('star', None, 'coin', None)),
    ('Вишнёвая бомба', R, 0, [e('TRIPLE_FLAT', CH, 12)], ('cherry', 'orange', 'flame', None)),
    ('Зелёная полоса', U, 1, [e('WIN_STREAK', 15)], ('clover', None, 'bolt', None)),
    ('Тёмный ритуал', E, 4, [e('PER_RARITY', X, 60), e('MULT', 20)], ('book', 'blood', 'skull', None)),
    ('Хранитель ключей', R, 6, [e('SLOTS', 2), e('PER_CARD', 3)], ('key', None, None, None)),
    ('Ключ от ямы', L, 6, [e('SLOTS', 3), e('TOKENS_ROUND', 1)], ('key', 'gold', 'skull', None)),
    ('Кривое зеркало', X, 7, [e('MIRROR'), e('WEIGHT', SK, 4)], ('mirror', 'blood', None, None)),
]

ART_BG = {  # family -> (dark, mid, accent)
    0: ('maroon0', 'maroon1', 'red0'),
    1: ('green0', 'brown0', 'green1'),
    2: ('blue0', 'vdark', 'blue1'),
    3: ('vdark', 'maroon0', 'gold0'),
    4: ('black', 'blood0', 'blood1'),
    5: ('brown0', 'vdark', 'brown1'),
    6: ('brown0', 'gold0', 'brown2'),
    7: ('purple0', 'vdark', 'purple1'),
}

A = 24


def art(idx, card):
    name, rar, fam, effs, (motif, ramp, second, badge_txt) = card
    p = Pix(A, A)
    d, m, acc = ART_BG[fam]
    var = idx % 4
    # background
    for y in range(A):
        for x in range(A):
            dx, dy = x - 11.5, y - 11.5
            r2 = dx * dx + dy * dy
            if var == 0:
                c = acc if r2 < 60 else (m if r2 < 150 else d)
                if 60 <= r2 < 75 and (x + y) % 2: c = acc
                if 150 <= r2 < 170 and (x + y) % 2: c = m
            elif var == 1:
                import math
                a = math.atan2(dy, dx)
                c = m if int((a + 3.2) * 12 / 3.14159) % 2 == 0 else d
                if r2 < 40: c = acc
            elif var == 2:
                c = m if ((x + y) // 3) % 2 == 0 else d
                if r2 < 50: c = acc if (x + y) % 2 else m
            else:
                c = d
                if x % 4 == 1 and y % 4 == 1: c = acc
                if r2 < 80: c = m if (x + y) % 2 else d
            p.set(x, y, c)
    # main motif
    rp = ramp
    fn = M.MOTIFS[motif]
    main = fn(19 if second else 20, rp) if rp else fn(19 if second else 20)
    if second:
        p.paste(main, 0, 1)
        sec = M.MOTIFS[second](11)
        p.paste(sec, 13, 13)
    else:
        p.paste(main, 2, 2)
    if badge_txt:
        M.badge(p, badge_txt, 1, A - 8)
    return p


def frames():
    """Rarity frames 28x28 (art sits at 2,2)."""
    cols = [('steel1', 'steel2', 'steel3'), ('green1', 'green2', 'green3'), ('blue1', 'blue2', 'cyan2'),
            ('purple1', 'purple2', 'purple3'), ('gold1', 'gold2', 'gold4'), ('blood1', 'red1', 'red2')]
    out = Pix(28 * 6, 28)
    for i, (c0, c1, c2) in enumerate(cols):
        ox = i * 28
        out.frame(ox, 0, 28, 28, 'black')
        out.frame(ox + 1, 1, 26, 26, c1)
        out.hline(ox + 2, ox + 25, 1, c2)
        out.vline(ox + 1, 2, 25, c2)
        out.hline(ox + 1, ox + 26, 26, c0)
        out.vline(ox + 26, 1, 26, c0)
        for (x, y) in ((1, 1), (26, 1), (1, 26), (26, 26)):
            out.set(ox + x, y, c2 if i != 5 else 'red3')
        if i >= 3:  # ornate corners
            for (x, y) in ((0, 0), (27, 0), (0, 27), (27, 27)):
                out.set(ox + x, y, c2)
        # gems in corners for legendary/cursed
        if i in (4, 5):
            for (x, y) in ((2, 2), (25, 2), (2, 25), (25, 25)):
                pass
    return out


def write_java(path):
    lines = ['package luckypit;', '', '/** Card effect opcodes. Generated by tools/gen_cards.py - do not edit. */',
             'public interface Op {']
    for n, i in OP.items():
        lines.append('    int %s = %d;' % (n, i))
    lines.append('    int COUNT = %d;' % (len(OPS) + 1))
    lines.append('}')
    open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')


def build(resdir, srcdir):
    os.makedirs(resdir + '/c', exist_ok=True)
    names = set()
    data = bytearray()
    data += struct.pack('>H', len(CARDS))
    for i, card in enumerate(CARDS):
        name, rar, fam, effs, artspec = card
        assert name not in names, name
        names.add(name)
        assert 1 <= len(effs) <= 2
        desc = ' '.join(desc_of(*ef) for ef in effs)
        price = PRICE[rar]
        effs2 = list(effs) + [(0, 0, 0, 0)] * (2 - len(effs))
        data += struct.pack('>BBH', rar, fam, price)
        for (op, a, b, c) in effs2:
            data += struct.pack('>Bhhb', op, a, b, c)
        nb = name.encode('utf-8'); db = desc.encode('utf-8')
        data += struct.pack('>H', len(nb)) + nb
        data += struct.pack('>H', len(db)) + db
        art(i, card).save('%s/c/%d.png' % (resdir, i))
    open(resdir + '/cards.dat', 'wb').write(bytes(data))
    frames().save(resdir + '/frames.png')
    write_java(srcdir + '/Op.java')
    return len(CARDS)


if __name__ == '__main__':
    import sys
    from collections import Counter
    n = build(sys.argv[1], sys.argv[2])
    print('cards', n, Counter(c[1] for c in CARDS), Counter(c[2] for c in CARDS))
    for c in CARDS:
        d = ' '.join(desc_of(*ef) for ef in c[3])
        if len(d) > 150:
            print('LONG', c[0], len(d))
