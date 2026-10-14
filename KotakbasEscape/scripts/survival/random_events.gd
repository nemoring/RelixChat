class_name RandomEvents
extends Node
## Случайные юмористические события. Не мешают основным заданиям:
## только сообщения, звуки и мелкие эффекты.

var game
var next_event := 180.0 # игровые минуты
var xp_spawned := false
var xp_used := false
var _xp_node: Node3D
var _last_weather := ""

func setup(g, saved := {}) -> void:
	game = g
	next_event = float(saved.get("next_event", 180.0))
	xp_used = saved.get("xp_used", false)

func save_data() -> Dictionary:
	return {"next_event": next_event, "xp_used": xp_used}

func tick(dt_min: float) -> void:
	next_event -= dt_min * float(DifficultyManager.p("event_rate"))
	if next_event > 0.0:
		return
	next_event = randf_range(150.0, 330.0)
	if game.ufo_manager.is_raid_active() or game.is_sleeping:
		return
	var options := ["pigeon_food", "night_sounds", "story", "xp", "chair_hint"]
	match options.pick_random():
		"pigeon_food":
			pigeon_steals_food()
		"night_sounds":
			if game.is_night():
				AudioManager.play_sfx("night_weird", -2.0)
				game.subtitle(["[Странный звук] Где-то в лесу кто-то... мычит?", "[Странный звук] Из темноты: «Ку-ку». Это была не кукушка.", "[Странный звук] Хруст веток. Потом тишина. Потом опять хруст."].pick_random())
			else:
				pigeon_steals_food()
		"story":
			game.subtitle(["Котакбас: Интересно, а дома телевизор выключил?", "Котакбас: Если меня спросят, я тут грибы собираю.", "Котакбас: Лес, тишина, никто не ищет. Подозрительно спокойно."].pick_random())
		"xp":
			spawn_xp_computer()
		"chair_hint":
			if game.buildings.count("workbench") > 0:
				chair_fall()
			else:
				pigeon_steals_food()

func on_weather(kind: String) -> void:
	if kind == "storm" and _last_weather != "storm":
		game.subtitle(["Котакбас: Ну конечно, гроза. Классика. Спасибо, погода.", "Котакбас: Гром гремит, НЛО летает, я под дождём. Понедельник продолжается.", "Котакбас: Вот бы сейчас домой, под одеяло... А, точно. Дома ТЦК."].pick_random())
	_last_weather = kind

func pigeon_steals_food() -> void:
	var foods := []
	for e in game.inventory.stealable_slots():
		if ItemDB.get_item(e[1]).type == "food":
			foods.append(e)
	if foods.is_empty():
		return
	var pick: Array = foods.pick_random()
	game.inventory.remove_from_slot(int(pick[0]), 1)
	AudioManager.play_sfx("pigeon")
	var nm := ItemDB.item_name(pick[1])
	if GameManager.flag("pigeon_friend", false) and randf() < 0.5:
		game.inventory.add(pick[1], 1)
		game.subtitle("Голубь стащил «%s»... но это был Гоша. Он вернул. Почти не надкусанным." % nm)
	else:
		game.subtitle("Голубь украл «%s» и улетел! Наглость — второе счастье." % nm)

func chair_fall() -> void:
	game.subtitle("Котакбас присел на табуретку у верстака... и упал. Табуретка тоже.")
	AudioManager.play_sfx("thud")
	game.camera_shake(0.6)
	GameManager.unlock_achievement("chair")

func spawn_xp_computer() -> void:
	if xp_used or is_instance_valid(_xp_node):
		return
	var p: Vector3 = game.player.global_position + game.player.forward() * 14.0
	var h: float = game.terrain.height(p.x, p.z)
	if h < SurvivalTerrain.WATER_LEVEL:
		return
	_xp_node = Node3D.new()
	game.add_child(_xp_node)
	_xp_node.global_position = Vector3(p.x, h, p.z)
	MK.box(_xp_node, Vector3(1.2, 0.08, 0.7), Color(0.55, 0.4, 0.25), Vector3(0, 0.75, 0))
	for lp in [Vector3(-0.5, 0.37, -0.3), Vector3(0.5, 0.37, -0.3), Vector3(-0.5, 0.37, 0.3), Vector3(0.5, 0.37, 0.3)]:
		MK.box(_xp_node, Vector3(0.06, 0.75, 0.06), Color(0.45, 0.3, 0.2), lp)
	MK.box(_xp_node, Vector3(0.6, 0.5, 0.5), Color(0.9, 0.88, 0.8), Vector3(0, 1.05, 0))
	MK.add(_xp_node, MK.box_mesh(Vector3(0.48, 0.36, 0.02)), Color(0.25, 0.55, 0.95), Vector3(0, 1.07, 0.26), Vector3.ZERO, true, 1.0)
	MK.box(_xp_node, Vector3(0.5, 0.04, 0.2), Color(0.85, 0.85, 0.8), Vector3(0, 0.81, 0.15))
	var lbl := Label3D.new()
	lbl.text = "Windows XP"
	lbl.font_size = 32
	lbl.pixel_size = 0.004
	lbl.position = Vector3(0, 1.07, 0.28)
	_xp_node.add_child(lbl)
	var it := Interactable.new()
	it.position.y = 1.0
	it.label = "Компьютер в лесу?!"
	it.action = _use_xp
	_xp_node.add_child(it)
	game.subtitle("Котакбас: Это что... компьютер? Посреди леса? С Windows XP?!")
	AudioManager.play_sfx_3d("xp_startup", _xp_node.global_position)

func _use_xp() -> void:
	if xp_used:
		return
	xp_used = true
	AudioManager.play_sfx("xp_startup")
	GameManager.unlock_achievement("xp")
	game.subtitle("На экране: «Обнаружено новое устройство: Котакбас». Компьютер радостно пищит и разваливается на детали.")
	game.drop_or_add({"electronics": 3, "scrap": 2})
	var n := _xp_node
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(n):
			AudioManager.play_sfx("xp_error")
			n.queue_free())
