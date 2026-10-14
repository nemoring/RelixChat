extends Node
## Сквозной тест: новая игра → новелла (бот) → раннер (бот уклоняется) →
## выживание (перенос предметов, постройки, сохранение и загрузка, таймер НЛО).
## Запуск: godot --headless --path . res://tests/flow_test.tscn [-- difficulty=N]

var failed := 0
var difficulty := 0

func check(cond: bool, what: String) -> void:
	printerr(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		failed += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("difficulty="):
			difficulty = int(a.substr(11))
	await get_tree().process_frame
	# Тест не должен быть текущей сценой — иначе SceneManager освободит его при переходе.
	var dummy := Node.new()
	dummy.name = "Dummy"
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	GameManager.new_game(difficulty)
	await _wait_scene("Novel", 20.0)
	await _play_novel()
	await _wait_scene("Runner", 30.0)
	await _play_runner()
	await _wait_scene("Survival", 60.0)
	await _check_survival()
	printerr("FLOW: %s" % ("OK" if failed == 0 else "FAILED (%d)" % failed))
	Engine.time_scale = 1.0
	get_tree().quit(1 if failed > 0 else 0)

func _wait_scene(name: String, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		var cs := get_tree().current_scene
		if cs and cs.name == name and not SceneManager.is_busy():
			check(true, "сцена %s загружена" % name)
			await get_tree().create_timer(0.3).timeout
			return
		await get_tree().process_frame
		t += get_process_delta_time()
	check(false, "сцена %s загружена (таймаут)" % name)

# ------------------------------------------------------------------ Новелла

func _drive_dialogue(novel) -> void:
	if not is_instance_valid(novel):
		return
	var dlg: DialogueBox = novel.dialogue
	if dlg._choosing:
		var pick := -1
		# Предпочитаем «хорошие» варианты: окно, всё забрать, покормить, вежливые ответы.
		var prefer := ["Убежать через окно", "Забрать всё", "Покормить", "Здравствуйте", "пряник", "лес далеко", "Встать"]
		for p in prefer:
			for i in dlg._choice_buttons.size():
				var b := dlg._choice_buttons[i]
				if not b.disabled and b.text.find(p) != -1:
					pick = i
					break
			if pick != -1:
				break
		if pick == -1:
			for i in dlg._choice_buttons.size():
				if not dlg._choice_buttons[i].disabled:
					pick = i
					break
		dlg._pick(pick, false)
	elif dlg.box.visible:
		dlg.tap_advance()

func _settle(novel, max_t := 30.0) -> void:
	var t := 0.0
	await get_tree().process_frame
	while novel._busy and t < max_t:
		_drive_dialogue(novel)
		await get_tree().create_timer(0.05).timeout
		t += 0.05

func _play_novel() -> void:
	var novel = get_tree().current_scene
	await _settle(novel)
	var plan := [
		["hot", "phone"], ["hot", "wardrobe"], ["hot", "chair"],
		["go", "corridor"], ["hot", "spravka"], ["go", "kitchen"],
		["hot", "fridge"], ["hot", "pryaniki"], ["hot", "drawer"], ["hot", "tv"],
		["go", "balcony"], ["hot", "bwindow"], ["hot", "pigeon"],
		["go", "kitchen"], ["go", "corridor"], ["go", "entrance"],
		["hot", "zina"], ["hot", "bike"], ["go", "yard"], ["hot", "tolya"],
		["go", "entrance"], ["go", "corridor"],
	]
	for step in plan:
		if step[0] == "hot":
			var script_name: String = _script_for(novel, step[1])
			novel._on_hotspot(script_name)
		else:
			novel._on_exit(step[1])
		await _settle(novel)
	var f: Dictionary = GameManager.state.flags
	check(f.has_backpack and f.has_phone and f.has_spravka, "собраны рюкзак, телефон, справка")
	check(f.pigeon_friend, "голубь стал другом")
	check(f.has_bicycle, "велосипед получен")
	check(f.balcony_open, "окно на балконе открыто")
	check(f.knock_pending, "после возвращения домой ожидается стук")
	check(int(GameManager.state.carry_items.get("sandwich", 0)) >= 2, "бутерброды перенесутся в лес")
	# Ждём стука и выбираем побег через окно
	var t := 0.0
	while is_instance_valid(novel) and get_tree().current_scene == novel and t < 120.0:
		_drive_dialogue(novel)
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	check(f.knock_done, "сцена стука завершена")
	check(f.runner_head_start, "побег через окно дал фору в раннере")

func _script_for(novel, hotspot_id: String) -> String:
	var story = novel.Story
	for loc in story.LOCATIONS:
		for h in story.LOCATIONS[loc].hotspots:
			if h.id == hotspot_id:
				return h.script
	return hotspot_id

# ------------------------------------------------------------------ Раннер

func _play_runner() -> void:
	var r = get_tree().current_scene
	check(r.has_bike, "велосипед из новеллы есть в раннере")
	check(r.has_helmet, "шлем за удачный побег")
	check(r.target == DifficultyManager.p("runner_target"), "цель раннера %d" % r.target)
	Engine.time_scale = 3.0
	var t := 0.0
	var swipe_cd := 0.0
	var max_score := 0.0
	while is_instance_valid(r) and get_tree().current_scene == r and t < 400.0:
		var dt := get_process_delta_time()
		t += dt
		swipe_cd -= dt
		max_score = maxf(max_score, r.score)
		if r.state == r.State.CAUGHT:
			check(false, "бот пойман (очки %d)" % int(r.score))
			break
		if r.state == r.State.RUN:
			_runner_bot(r, swipe_cd)
			if swipe_cd <= 0.0:
				swipe_cd = 0.09
		await get_tree().process_frame
	Engine.time_scale = 1.0
	check(max_score >= DifficultyManager.p("runner_target"), "набрано очков: %d" % int(max_score))
	check(r == null or not is_instance_valid(r) or r.hits_taken <= DifficultyManager.p("runner_lives"), "столкновения в пределах лимита")

func _runner_bot(r, swipe_cd: float) -> void:
	var lane: int = r.lane
	var next_row = null
	for row in r.rows:
		if row.z < -0.6 and row.z > -45.0:
			if next_row == null or row.z > next_row.z:
				next_row = row
	if next_row == null:
		return
	var cells: Array = next_row.cells
	var cur: int = cells[lane]
	if cur == RunnerGenerator.BLOCK or (cur != RunnerGenerator.NONE and next_row.z < -10.0):
		var best := lane
		var best_score := 99
		for l in 3:
			var c: int = cells[l]
			var sc: int = absi(l - lane) * 2 + (0 if c == RunnerGenerator.NONE else (3 if c != RunnerGenerator.BLOCK else 99))
			if sc < best_score:
				best_score = sc
				best = l
		if best != lane and swipe_cd <= 0.0 and r.buffer.size() == 0:
			r._on_swipe(Vector2i(signi(best - lane), 0))
		return
	var reach: float = r.speed * 0.32
	if cur == RunnerGenerator.LOW and next_row.z > -reach and r.grounded:
		r._on_swipe(Vector2i(0, -1))
	elif cur == RunnerGenerator.HIGH and next_row.z > -reach and r.slide_t <= 0.0 and r.grounded:
		r._on_swipe(Vector2i(0, 1))

# ------------------------------------------------------------------ Выживание

func _check_survival() -> void:
	var g = get_tree().current_scene
	await get_tree().create_timer(4.0).timeout
	check(g.inventory.count("sandwich") >= 2, "бутерброды из новеллы в инвентаре")
	check(g.inventory.count("pryanik") >= 2, "пряники из новеллы в инвентаре")
	check(g.inventory.capacity() == 30, "рюкзак увеличил инвентарь до 30")
	var first_raid: float = g.ufo_manager.next_raid
	check(first_raid - g.time_min > 2100.0, "первый налёт через 1,5–2 дня")
	# Строим базу
	g.inventory.add("wood", 60)
	g.inventory.add("stone", 20)
	g.inventory.add("fabric", 5)
	var p: Vector3 = g.player.global_position + g.player.forward() * 5.0
	for id in ["foundation", "campfire", "crate", "bed"]:
		g.buildings.start_placement(id)
		await get_tree().process_frame
		g.buildings.ghost_pos = Vector3(p.x, g.terrain.height(p.x, p.z), p.z)
		g.buildings.ghost_valid = true
		check(g.buildings.confirm(), "построено: %s" % id)
		p += Vector3(2.5, 0, 0)
	g.buildings.cancel()
	g.buildings.crates()[0].inv.add("wood", 7)
	g.time_min += 100.0
	var snap_time: float = g.time_min
	check(GameManager.save_game("2"), "сохранение в слот 2")
	GameManager.load_game("2")
	await _wait_scene("Survival", 30.0)
	var g2 = get_tree().current_scene
	await get_tree().create_timer(1.0).timeout
	check(g2 != g, "сцена перезагружена")
	check(g2.buildings.buildings.size() == 4, "постройки восстановлены (%d)" % g2.buildings.buildings.size())
	check(g2.buildings.crates()[0].inv.count("wood") == 7, "содержимое ящика восстановлено")
	check(absf(g2.ufo_manager.next_raid - first_raid) < 0.01, "таймер НЛО восстановлен")
	check(absf(g2.time_min - snap_time) < 5.0, "время суток восстановлено")
	check(DifficultyManager.level() == difficulty, "сложность из сохранения")
	# Налёт во время сохранения: восстанавливается вместе с попаданиями
	g2.ufo_manager.start_raid(false, {"state": 3, "hits": 3})
	await get_tree().create_timer(0.5).timeout
	check(GameManager.save_game("2"), "сохранение во время налёта")
	GameManager.load_game("2")
	await _wait_scene("Survival", 30.0)
	var g3 = get_tree().current_scene
	await get_tree().create_timer(1.0).timeout
	check(g3.ufo_manager.is_raid_active(), "налёт восстановлен после загрузки")
	if g3.ufo_manager.is_raid_active():
		check(g3.ufo_manager.ufo.health.hits == 3, "попадания по кабине восстановлены")
	SaveManager.delete_slot("2")
