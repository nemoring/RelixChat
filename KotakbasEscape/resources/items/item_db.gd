class_name ItemDB
extends RefCounted
## База предметов выживания. key=true — сюжетный предмет: НЛО его не крадёт,
## его нельзя выбросить. throwable — метательный (камень).

const ITEMS := {
	"wood": {"name": "Дерево", "desc": "Брёвна и ветки. Основа любой стройки.", "stack": 50, "type": "resource"},
	"stone": {"name": "Камень", "desc": "Обычный камень. Строительный материал и лучшее ПВО против НЛО ТЦК: выбери на панели и зажми кнопку броска.", "stack": 40, "type": "resource", "throwable": true},
	"metal": {"name": "Металл", "desc": "Переплавленный металл. Для генератора и серьёзных построек.", "stack": 30, "type": "resource"},
	"scrap": {"name": "Металлолом", "desc": "Ржавые железки. Переплавь в печи, получишь металл.", "stack": 30, "type": "resource"},
	"fabric": {"name": "Ткань", "desc": "Старые тряпки. Бинты, верёвки, кровать.", "stack": 30, "type": "resource"},
	"rope": {"name": "Верёвка", "desc": "Крепкая верёвка. Связывать всё со всем.", "stack": 30, "type": "resource"},
	"electronics": {"name": "Электронные компоненты", "desc": "Платы, транзисторы, провода. Нужны для генератора.", "stack": 20, "type": "resource"},
	"berries": {"name": "Ягоды", "desc": "Лесные ягоды. Немного еды и воды.", "stack": 20, "type": "food", "food": {"hunger": 12, "thirst": 5}},
	"mushroom": {"name": "Грибы", "desc": "Вроде съедобные. Вроде.", "stack": 20, "type": "food", "food": {"hunger": 14, "health": -2}},
	"meat_raw": {"name": "Сырое мясо", "desc": "Лучше пожарить на костре.", "stack": 10, "type": "food", "food": {"hunger": 10, "health": -6}},
	"meat_cooked": {"name": "Жареное мясо", "desc": "Сытно и вкусно.", "stack": 10, "type": "food", "food": {"hunger": 38, "health": 5}},
	"water_dirty": {"name": "Грязная вода", "desc": "Вода из реки. Лучше вскипятить на костре.", "stack": 10, "type": "food", "food": {"thirst": 22, "health": -5}},
	"water_clean": {"name": "Чистая вода", "desc": "Кипячёная вода. Утоляет жажду.", "stack": 10, "type": "food", "food": {"thirst": 42}},
	"canned": {"name": "Тушёнка", "desc": "Из холодильника. Очень сытно.", "stack": 10, "type": "food", "food": {"hunger": 50, "health": 5}},
	"sandwich": {"name": "Бутерброд", "desc": "Помятый, но родной.", "stack": 10, "type": "food", "food": {"hunger": 28}},
	"pryanik": {"name": "Тульский пряник", "desc": "Стратегический запас. Даёт силы и бодрость.", "stack": 10, "type": "food", "food": {"hunger": 16, "stamina": 40}},
	"axe": {"name": "Каменный топор", "desc": "Рубит деревья быстрее и бьёт больнее.", "stack": 1, "type": "tool", "damage": 15, "tree_mult": 2.0},
	"pickaxe": {"name": "Каменная кирка", "desc": "Добывает камень быстрее, иногда находит металлолом.", "stack": 1, "type": "tool", "damage": 12, "rock_mult": 2.0},
	"spear": {"name": "Копьё", "desc": "Против волков и гусей. Особенно гусей.", "stack": 1, "type": "tool", "damage": 26},
	"bandage": {"name": "Бинт", "desc": "Восстанавливает здоровье.", "stack": 10, "type": "medical", "food": {"health": 30}},
	"map": {"name": "Карта местности", "desc": "Карта от деда Михалыча. Показывает важные места.", "stack": 1, "type": "key", "key": true},
	"antenna": {"name": "Антенна", "desc": "Деталь радиостанции. Найдена на старом заводе.", "stack": 1, "type": "key", "key": true},
	"radio_lamp": {"name": "Радиолампа", "desc": "Деталь радиостанции. Найдена в пещере.", "stack": 1, "type": "key", "key": true},
	"coil": {"name": "Катушка", "desc": "Деталь радиостанции. Найдена на болоте.", "stack": 1, "type": "key", "key": true},
	"ufo_part": {"name": "Обломок НЛО ТЦК", "desc": "Редкая деталь, выпавшая из тарелки. На верстаке разбирается на электронику.", "stack": 10, "type": "resource"},
}

static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "desc": "", "stack": 1, "type": "resource"})

static func item_name(id: String) -> String:
	return get_item(id).name

static func is_key(id: String) -> bool:
	return get_item(id).get("key", false)

static func stack_size(id: String) -> int:
	return int(get_item(id).get("stack", 1))

static func icon(id: String) -> Texture2D:
	var path := "res://assets/textures/icons/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null
