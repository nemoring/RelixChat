class_name QuestManager
extends Node
## Сюжетные задания выживания (12 этапов), проверка выполнения, цели на карте.

signal quest_completed(index: int)
signal quest_started(index: int)

const QUESTS := [
	{"id": "safe_place", "title": "Найти безопасное место", "desc": "Выберись из кустов и дойди до поляны с указателем."},
	{"id": "gather", "title": "Собрать дерево и камень", "desc": "Руби деревья (кнопка «Удар») и подбирай камни."},
	{"id": "shelter", "title": "Построить убежище", "desc": "Стройка → фундамент, 2 стены, крыша и костёр."},
	{"id": "first_night", "title": "Пережить первую ночь", "desc": "Дождись утра. Кровать позволит проспать ночь (Стройка → Кровать)."},
	{"id": "village", "title": "Найти заброшенную деревню", "desc": "Иди на северо-запад. Там кто-то живёт."},
	{"id": "map", "title": "Получить карту", "desc": "Поговори с дедом Михалычем. Он любит поесть."},
	{"id": "radio_find", "title": "Найти радиостанцию", "desc": "Красная вышка на холмах к северу."},
	{"id": "parts", "title": "Собрать детали", "desc": "Антенна — на заводе за рекой, радиолампа — в пещере, катушка — в лодке на болоте."},
	{"id": "generator", "title": "Починить генератор", "desc": "Принеси к генератору металл, электронику и верёвку."},
	{"id": "radio", "title": "Восстановить радиосвязь", "desc": "Включи радиостанцию и настрой частоту."},
	{"id": "final_event", "title": "Пережить финальное событие", "desc": "ТЦК засекло сигнал! Отбейся или переживи налёт у радиостанции."},
	{"id": "finish", "title": "Завершить игру", "desc": "Выйди на связь по радио."},
]

var game
var index := 0
var quest_start_time := 0.0
var flags := {}
var _check_t := 0.0

func setup(g, saved := {}) -> void:
	game = g
	index = int(saved.get("index", 0))
	quest_start_time = float(saved.get("start", 0.0))
	flags = saved.get("flags", {}).duplicate()

func save_data() -> Dictionary:
	return {"index": index, "start": quest_start_time, "flags": flags.duplicate()}

func current() -> Dictionary:
	if index >= QUESTS.size():
		return {}
	return QUESTS[index]

func is_done(id: String) -> bool:
	for i in mini(index, QUESTS.size()):
		if QUESTS[i].id == id:
			return true
	return false

func _process(delta: float) -> void:
	if game == null or index >= QUESTS.size():
		return
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.5
	if _check(QUESTS[index].id):
		_complete()

func _gather_req() -> Dictionary:
	return {"wood": 8, "stone": 5}

func _shelter_req() -> Dictionary:
	return {"foundation": 1, "wall": 2, "roof": 1, "campfire": 1}

func _check(id: String) -> bool:
	var p: Vector3 = game.player.global_position
	match id:
		"safe_place":
			return Vector2(p.x, p.z).distance_to(SurvivalTerrain.REGIONS.clearing.c) < 12.0
		"gather":
			var r := _gather_req()
			return game.inventory.count("wood") >= r.wood and game.inventory.count("stone") >= r.stone
		"shelter":
			var r2 := _shelter_req()
			for k in r2:
				var c: int = game.buildings.count(k)
				if k == "wall":
					c += game.buildings.count("door") + game.buildings.count("window")
				if c < r2[k]:
					return false
			return true
		"first_night":
			return game.time_min >= DayNight.next_morning(quest_start_time) or (DayNight.time_of_day(quest_start_time) < 360.0 and game.time_min >= quest_start_time + 60.0 and not DayNight.is_night(game.time_min))
		"village":
			return Vector2(p.x, p.z).distance_to(SurvivalTerrain.REGIONS.village.c) < 34.0
		"map":
			return game.inventory.count("map") > 0
		"radio_find":
			return Vector2(p.x, p.z).distance_to(SurvivalTerrain.REGIONS.radio.c) < 16.0
		"parts":
			return game.inventory.count("antenna") > 0 and game.inventory.count("radio_lamp") > 0 and game.inventory.count("coil") > 0
		"generator":
			return game.pois.generator_fixed
		"radio":
			return game.pois.radio_fixed
		"final_event":
			return game.ufo_manager.final_done
		"finish":
			return flags.get("finished", false)
	return false

func _complete() -> void:
	var q: Dictionary = QUESTS[index]
	AudioManager.play_sfx("quest_done")
	GameManager.toast("Задание выполнено: %s" % q.title, UIStyle.GOOD, 2.5)
	quest_completed.emit(index)
	index += 1
	quest_start_time = game.time_min
	if index < QUESTS.size():
		quest_started.emit(index)

## Текст прогресса текущего задания.
func progress_text() -> String:
	if index >= QUESTS.size():
		return "Все задания выполнены"
	var q: Dictionary = QUESTS[index]
	match q.id:
		"gather":
			var r := _gather_req()
			return "Дерево %d/%d · Камень %d/%d" % [mini(game.inventory.count("wood"), r.wood), r.wood, mini(game.inventory.count("stone"), r.stone), r.stone]
		"shelter":
			var r2 := _shelter_req()
			var walls: int = game.buildings.count("wall") + game.buildings.count("door") + game.buildings.count("window")
			return "Фундамент %d/1 · Стены %d/2 · Крыша %d/1 · Костёр %d/1" % [mini(game.buildings.count("foundation"), 1), mini(walls, 2), mini(game.buildings.count("roof"), 1), mini(game.buildings.count("campfire"), 1)]
		"first_night":
			var left := maxf(0.0, DayNight.next_morning(quest_start_time) - game.time_min)
			return "До утра: %d ч %02d мин" % [int(left / 60.0), int(fmod(left, 60.0))]
		"parts":
			return "Антенна %s · Радиолампа %s · Катушка %s" % ["да" if game.inventory.count("antenna") > 0 else "нет", "да" if game.inventory.count("radio_lamp") > 0 else "нет", "да" if game.inventory.count("coil") > 0 else "нет"]
		"generator":
			var cost: Dictionary = game.generator_cost()
			var parts := []
			for k in cost:
				parts.append("%s %d/%d" % [ItemDB.item_name(k), mini(game.inventory.count(k), cost[k]), cost[k]])
			return " · ".join(parts)
	return q.desc

## Координаты цели для указателя (или Vector3.INF).
func target_pos() -> Vector3:
	if index >= QUESTS.size():
		return Vector3.INF
	match QUESTS[index].id:
		"safe_place":
			return _reg("clearing")
		"village", "map":
			return _reg("village")
		"radio_find", "generator", "radio", "final_event", "finish":
			return _reg("radio")
		"parts":
			if game.inventory.count("antenna") == 0:
				return _reg("factory")
			if game.inventory.count("radio_lamp") == 0:
				return _reg("cave")
			if game.inventory.count("coil") == 0:
				return _reg("swamp")
	return Vector3.INF

func _reg(k: String) -> Vector3:
	var c: Vector2 = SurvivalTerrain.REGIONS[k].c
	return Vector3(c.x, game.terrain.height(c.x, c.y), c.y)
