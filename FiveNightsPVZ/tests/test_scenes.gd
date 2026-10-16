extends TestSuite
## Запуск сцен: меню и каждая ночь собираются без ошибок.


func test_main_menu_loads() -> void:
	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	check(packed != null, "main_menu.tscn не загружается")
	var m: Node = packed.instantiate()
	tree().root.add_child(m)
	await frames(5)
	check(m.get("level") != null, "в меню нет фонового уровня")
	m.queue_free()
	await frames(2)


func test_each_night_starts() -> void:
	for n in range(1, 7):
		var g := await start_game(n)
		check(g.level != null and g.player != null, "ночь %d: нет уровня/игрока" % n)
		check(g.night.running, "ночь %d: смена не запустилась" % n)
		eq(g.night_index, n, "номер ночи")
		eq(g.entities.size(), 5, "ночь %d: сущностей" % n)
		await stop_game(g)


func test_level_structure() -> void:
	var g := await start_game(1)
	var lv := g.level
	eq(lv.cam_mount_nodes.size(), 8, "камер должно быть 8")
	for id in ["warehouse", "workstation", "hall", "corridor", "tech", "utility", "toilet", "cab_a", "cab_b", "vestibule"]:
		check(lv.room_areas.has(id), "нет помещения " + id)
	for d in ["front", "tech", "wh_cor", "ws_cor", "util", "toilet", "wh_ws"]:
		check(lv.doors.has(d), "нет двери " + d)
	check(lv.doors["tech"].locked, "техническая должна быть заперта")
	check(lv.doors["front"].locked, "входная дверь должна быть заблокирована")
	check(lv.cells.size() >= 16, "мало ячеек хранения")
	check(lv.hide_spots.size() >= 3, "мало укрытий")
	check(lv.cabins.size() == 2, "две примерочные")
	# Освещение не превышает разумного числа источников.
	var lights := 0
	for n in lv.find_children("*", "Light3D", true, false):
		lights += 1
	check(lights <= 24, "слишком много источников света: %d" % lights)
	await stop_game(g)


func test_quality_presets_apply() -> void:
	var g := await start_game(1)
	for q in 3:
		GameState.settings["quality"] = q
		GameState.apply_settings()
		await frames(2)
		var shadowed := 0
		for f in g.level.find_children("*", "OmniLight3D", true, false):
			if (f as OmniLight3D).shadow_enabled:
				shadowed += 1
		if q == 0:
			eq(shadowed, 0, "низкое качество: тени выключены")
		if q == 2:
			check(shadowed >= 4, "высокое качество: тени включены")
	GameState.settings["quality"] = 1
	GameState.apply_settings()
	await stop_game(g)
