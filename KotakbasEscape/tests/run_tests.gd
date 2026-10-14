extends Node
## Автотесты логики игры. Запуск:
## godot --headless --path . res://tests/run_tests.tscn

var passed := 0
var failed := 0
var _section := ""

func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL [%s]: %s" % [_section, what])

func section(name: String) -> void:
	_section = name
	print("— " + name)

func _ready() -> void:
	test_difficulty()
	test_inventory()
	test_saves()
	test_runner_generator()
	test_ballistics()
	test_ufo_schedule()
	test_ufo_stealing()
	test_novel_story()
	test_daynight()
	test_data_integrity()
	test_stats()
	print("\nИТОГО: пройдено %d, провалено %d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func test_difficulty() -> void:
	section("Сложность")
	check(DifficultyManager.PROFILES.DATA.size() == 4, "4 уровня сложности")
	var targets := [2000, 5000, 10000, 20000]
	var speeds := [1.0, 1.35, 1.7, 2.2]
	var lives := [5, 3, 2, 1]
	var hits := [10, 13, 17, 20]
	for i in 4:
		check(DifficultyManager.p_for(i, "runner_target") == targets[i], "цель раннера %d" % i)
		check(is_equal_approx(DifficultyManager.p_for(i, "runner_speed_mult"), speeds[i]), "скорость раннера %d" % i)
		check(DifficultyManager.p_for(i, "runner_lives") == lives[i], "столкновения %d" % i)
		check(DifficultyManager.p_for(i, "ufo_hits") == hits[i], "попадания по НЛО %d" % i)
	check(DifficultyManager.p_for(0, "ufo_steal_fraction") < DifficultyManager.p_for(3, "ufo_steal_fraction"), "на лёгкой потери меньше")
	check(DifficultyManager.p_for(0, "hunger_rate") < DifficultyManager.p_for(3, "hunger_rate"), "голод быстрее на высокой")
	DifficultyManager.set_level_for_new_game(2)
	check(DifficultyManager.level() == 2 and DifficultyManager.is_locked(), "сложность фиксируется")
	var c := DifficultyManager.scaled_cost({"wood": 4}, "build")
	check(c.wood == 6, "стоимость стройки на сложной x1.35 (4 -> 6), получено %s" % c.wood)
	DifficultyManager.restore_level(1)

func test_inventory() -> void:
	section("Инвентарь")
	var inv := Inventory.new(4)
	check(inv.add("stone", 45) == 0, "камни помещаются (стопка 40 + 5)")
	check(inv.count("stone") == 45, "количество 45")
	check(inv.slots[0].n == 40 and inv.slots[1].n == 5, "стопки разделены по 40")
	var left := inv.add("wood", 200)
	check(left == 100, "излишек возвращается (%d)" % left)
	check(inv.remove("stone", 42) == 42 and inv.count("stone") == 3, "удаление")
	inv = Inventory.new(6)
	inv.add("wood", 10)
	check(inv.split(0) and inv.slots[0].n == 5 and inv.slots[1].n == 5, "разделение стопки")
	inv.move_to(1, inv, 0)
	check(inv.slots[0].n == 10 and inv.slots[1] == null, "объединение стопок")
	inv.add("stone", 3)
	inv.move_to(0, inv, 1)
	check(inv.slots[0].id == "stone" and inv.slots[1].id == "wood", "обмен ячеек")
	var crate := Inventory.new(12)
	inv.transfer_slot(1, crate)
	check(crate.count("wood") == 10 and inv.count("wood") == 0, "перенос в ящик")
	inv.add("map", 1)
	inv.add("berries", 2)
	var st := inv.stealable_slots()
	var has_key := false
	for e in st:
		if e[1] == "map":
			has_key = true
	check(not has_key, "сюжетные предметы не крадутся")
	var arr := inv.to_array()
	var inv2 := Inventory.new(6)
	inv2.from_array(JSON.parse_string(JSON.stringify(arr)))
	check(inv2.count("map") == 1 and inv2.count("stone") == 3, "сериализация")
	check(inv.has_all({"stone": 3, "berries": 2}) and not inv.has_all({"stone": 4}), "проверка стоимости")

func test_saves() -> void:
	section("Сохранения")
	var data := {"chapter": "survival", "difficulty": 2, "flags": {"a": 1}, "survival": {"time": 1234.5}}
	check(SaveManager.save_slot("3", data), "запись слота")
	var back := SaveManager.load_slot("3")
	check(back.get("chapter") == "survival" and int(back.difficulty) == 2, "чтение слота")
	check(is_equal_approx(float(back.survival.time), 1234.5), "вложенные данные")
	data.survival.time = 999.0
	SaveManager.save_slot("3", data)
	# Портим основной файл — должна загрузиться резервная копия.
	var f := FileAccess.open(SaveManager.slot_path("3"), FileAccess.WRITE)
	f.store_string("{сломано")
	f.close()
	var rec := SaveManager.load_slot("3")
	check(not rec.is_empty() and is_equal_approx(float(rec.survival.time), 1234.5), "восстановление из .bak")
	SaveManager.delete_slot("3")
	check(not SaveManager.has_slot("3"), "удаление слота")

func test_runner_generator() -> void:
	section("Генератор раннера")
	for dens in [0.4, 0.55, 0.7, 0.85, 1.0]:
		var g := RunnerGenerator.new(12345 + int(dens * 100), dens)
		var rows := []
		var safe_ok := true
		var max_blocks_ok := true
		for i in 4000:
			var r := g.next_row()
			rows.append(r)
			if r[g.safe_lane] == RunnerGenerator.BLOCK:
				safe_ok = false
			var blocks := 0
			for c in r:
				if c == RunnerGenerator.BLOCK:
					blocks += 1
			if blocks >= 3:
				max_blocks_ok = false
		check(safe_ok, "безопасная полоса не перекрыта (плотность %.2f)" % dens)
		check(max_blocks_ok, "нет рядов из трёх стен (плотность %.2f)" % dens)
		check(RunnerGenerator.is_sequence_passable(rows), "последовательность проходима (плотность %.2f)" % dens)
	check(not RunnerGenerator.is_sequence_passable([[1, 1, 0], [0, 1, 1]]), "детектор непроходимости работает")

func test_ballistics() -> void:
	section("Баллистика камня")
	var from := Vector3(0, 1.6, 0)
	for target in [Vector3(0, 10, -16), Vector3(5, 12, -20), Vector3(-3, 9.5, -13), Vector3(10, 2, 10)]:
		var sols := StoneProjectile.solve(from, target)
		check(sols.size() == 2, "есть решение для %s" % target)
		if sols.is_empty():
			continue
		var p := from
		var v: Vector3 = sols[0]
		var best := 999.0
		for i in 2000:
			v.y -= StoneProjectile.GRAVITY / 240.0
			p += v / 240.0
			best = minf(best, p.distance_to(target))
		check(best < 0.2, "низкая дуга попадает в цель (промах %.2f м)" % best)
	check(StoneProjectile.solve(from, Vector3(0, 0, -500)).is_empty(), "цель вне досягаемости")
	# Попадаемость кабины с типичной дистанции
	var ufo_xf := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 9, 0))
	var ok := 0
	for d in [13.0, 16.0, 20.0, 25.0]:
		var pl := Vector3(0, 1.6, -d)
		var aim := ufo_xf * UFOController.AIM_LOCAL
		for s in StoneProjectile.solve(pl, aim):
			if StoneProjectile.predict(pl, s, ufo_xf, UFOController.COCKPIT_C, UFOController.COCKPIT_R, UFOController.HULL_R, UFOController.HULL_Y, UFOController.HULL_H, 0.0) == "cockpit":
				ok += 1
				break
	check(ok == 4, "кабина досягаема с 13–25 м (%d/4)" % ok)
	var below := StoneProjectile.predict(Vector3(0, 1, 0), Vector3(0, 30, 0), Transform3D(Basis.IDENTITY, Vector3(0, 9, 0)), UFOController.COCKPIT_C, UFOController.COCKPIT_R, UFOController.HULL_R, UFOController.HULL_Y, UFOController.HULL_H, 0.0)
	check(below == "hull", "бросок снизу попадает в корпус, а не в кабину (%s)" % below)
	check(UFOController.is_cockpit_local(Vector3(0, 2.5, 0)), "купол засчитывается")
	check(not UFOController.is_cockpit_local(Vector3(0, -0.5, 0)), "низ корпуса не засчитывается")

func test_ufo_schedule() -> void:
	section("Расписание налётов НЛО")
	var lo := 1e9
	var hi := -1.0
	for i in 2000:
		var r := UFOSpawnManager.random_interval()
		lo = minf(lo, r)
		hi = maxf(hi, r)
	check(lo >= 1.5 * 1440.0 and hi <= 2.0 * 1440.0, "интервал 1,5–2 игровых дня (%.0f–%.0f мин)" % [lo, hi])
	check(DayNight.DAY_MIN / DayNight.MINUTES_PER_SECOND == 1440.0, "игровой день = 24 реальные минуты")
	var mgr := UFOSpawnManager.new()
	var warnings := []
	mgr.warning.connect(func(m): warnings.append(m))
	mgr.init_first(480.0)
	var first := mgr.next_raid
	check(first >= 480.0 + 2160.0 and first <= 480.0 + 2880.0, "первый налёт через 1,5–2 дня после появления")
	mgr.tick(first - 31.0)
	check(warnings.is_empty(), "нет раннего предупреждения")
	mgr.tick(first - 29.0)
	check(warnings == [30], "предупреждение за 30 игровых минут")
	mgr.tick(first - 9.0)
	check(warnings == [30, 10], "предупреждение за 10 игровых минут")
	# Сон: время перепрыгивает — предупреждения всё равно срабатывают по одному разу
	var mgr2 := UFOSpawnManager.new()
	var w2 := []
	mgr2.warning.connect(func(m): w2.append(m))
	mgr2.init_first(0.0)
	mgr2.tick(mgr2.next_raid - 5.0)
	check(w2 == [30, 10], "при ускорении времени оба предупреждения (%s)" % [w2])
	var saved := mgr.save_data()
	var mgr3 := UFOSpawnManager.new()
	mgr3.load_data(JSON.parse_string(JSON.stringify(saved)))
	mgr3.init_first(999999.0)
	check(is_equal_approx(mgr3.next_raid, first) and mgr3.warned30 and mgr3.warned10, "таймер налёта восстанавливается из сохранения")
	mgr.free()
	mgr2.free()
	mgr3.free()

class MockBuildings:
	var crate_list := []
	func crates() -> Array:
		return crate_list
	func is_protected(p: Vector3) -> bool:
		return p.x > 100.0

class MockGame extends Node:
	var buildings := MockBuildings.new()
	var inventory := Inventory.new(10)
	var player := Node3D.new()
	var stolen_log := []
	func on_resource_stolen(id: String, n: int) -> void:
		stolen_log.append([id, n])
	func subtitle(_t: String, _x := 0.0) -> void:
		pass

func test_ufo_stealing() -> void:
	section("Кража ресурсов НЛО")
	for level in [0, 3]:
		DifficultyManager.restore_level(level)
		var game := MockGame.new()
		add_child(game)
		game.add_child(game.player)
		var crate_inv := Inventory.new(12)
		crate_inv.add("wood", 30)
		crate_inv.add("antenna", 1)
		var bunker_inv := Inventory.new(12)
		bunker_inv.add("metal", 10)
		game.buildings.crate_list = [{"pos": Vector3.ZERO, "inv": crate_inv}, {"pos": Vector3(150, 0, 0), "inv": bunker_inv}]
		game.inventory.add("stone", 10)
		game.player.position = Vector3(50, 0, 0) # игрок вне луча
		var ufo := Node3D.new()
		game.add_child(ufo)
		var st := UFOResourceStealing.new()
		ufo.add_child(st)
		st.setup(game, ufo)
		st.begin()
		var expected := int(ceil(40.0 * float(DifficultyManager.p("ufo_steal_fraction"))))
		check(st.budget == expected, "бюджет кражи = доля от доступного (%d, ожидалось %d)" % [st.budget, expected])
		for i in 200:
			st.tick(UFOResourceStealing.TICK + 0.01, true, Vector3.ZERO)
		check(st.stolen_total == st.budget, "украдено не больше бюджета (%d/%d)" % [st.stolen_total, st.budget])
		check(crate_inv.count("antenna") == 1, "сюжетный предмет в ящике не украден")
		check(bunker_inv.count("metal") == 10, "ящик у бункера защищён")
		check(game.inventory.count("stone") == 10, "игрок вне луча не обворован")
		check(crate_inv.count("wood") == 30 - st.stolen_total, "кража реальна: ресурсы исчезли из ящика")
		game.queue_free()
	DifficultyManager.restore_level(0)
	var g2 := MockGame.new()
	add_child(g2)
	g2.add_child(g2.player)
	g2.inventory.add("wood", 20)
	var u2 := Node3D.new()
	g2.add_child(u2)
	var st2 := UFOResourceStealing.new()
	u2.add_child(st2)
	st2.setup(g2, u2)
	st2.begin()
	for i in 50:
		st2.tick(UFOResourceStealing.TICK + 0.01, true, Vector3.ZERO)
	check(st2.stolen_total > 0, "игрок в луче теряет ресурсы из инвентаря")
	g2.queue_free()
	DifficultyManager.restore_level(1)

func test_novel_story() -> void:
	section("Сценарий новеллы")
	var story = load("res://scripts/novel/novel_story.gd")
	var names := PackedStringArray()
	var values := []
	for k in story.DEFAULT_FLAGS:
		names.append(k)
		values.append(story.DEFAULT_FLAGS[k])
	names.append("lock")
	values.append(6)
	names.append("difficulty")
	values.append(1)
	var errors := []
	var visit := func(cmds: Array, sid: String, self_ref: Callable) -> void:
		for c in cmds:
			if c.has("goto") and not story.SCRIPTS.has(c["goto"]):
				errors.append("%s: goto %s" % [sid, c["goto"]])
			if c.has("s") and not Portrait.SPEAKERS.has(c.s):
				errors.append("%s: говорящий %s" % [sid, c.s])
			for key in ["if"]:
				if c.has(key) and typeof(c[key]) == TYPE_STRING:
					var e := Expression.new()
					if e.parse(c[key], names) != OK:
						errors.append("%s: условие %s" % [sid, c[key]])
			if c.has("choice"):
				if int(c.get("default", 0)) >= c.choice.size():
					errors.append("%s: default вне диапазона" % sid)
				for o in c.choice:
					if o.has("if"):
						var e2 := Expression.new()
						if e2.parse(o["if"], names) != OK:
							errors.append("%s: условие %s" % [sid, o["if"]])
					self_ref.call(o.get("do", []), sid, self_ref)
			if c.has("do"):
				self_ref.call(c["do"], sid, self_ref)
			if c.has("else"):
				self_ref.call(c["else"], sid, self_ref)
			if c.has("item") and not ItemDB.ITEMS.has(c.item) and c.item != "backpack":
				errors.append("%s: предмет %s" % [sid, c.item])
	for sid in story.SCRIPTS:
		visit.call(story.SCRIPTS[sid], sid, visit)
	for loc in story.LOCATIONS:
		for h in story.LOCATIONS[loc].hotspots:
			if not story.SCRIPTS.has(h.script):
				errors.append("локация %s: скрипт %s" % [loc, h.script])
		for e in story.LOCATIONS[loc].exits:
			if not story.LOCATIONS.has(e):
				errors.append("локация %s: выход %s" % [loc, e])
	for e in errors:
		print("    ", e)
	check(errors.is_empty(), "ссылки, условия и говорящие корректны (%d ошибок)" % errors.size())
	var knock: Array = story.SCRIPTS.knock
	var choice_cmd: Dictionary = {}
	for c in knock:
		if c.has("choice"):
			choice_cmd = c
	check(choice_cmd.choice.size() == 7, "при стуке в дверь 7 вариантов")
	var conditional := 0
	for o in choice_cmd.choice:
		if o.has("if"):
			conditional += 1
	check(conditional >= 3, "часть вариантов доступна только при условиях (%d)" % conditional)
	check(story.LOCATIONS.size() == 6, "6 локаций: спальня, кухня, коридор, балкон, подъезд, двор")

func test_daynight() -> void:
	section("Время суток")
	check(DayNight.clock_text(480.0) == "08:00", "часы 08:00")
	check(DayNight.day_number(1440.0 * 2 + 5) == 3, "номер дня")
	check(is_equal_approx(DayNight.next_morning(480.0), 1440.0 + 360.0), "следующее утро после 08:00")
	check(is_equal_approx(DayNight.next_morning(1440.0 + 100.0), 1440.0 + 360.0), "следующее утро после 01:40")
	check(DayNight.is_night(1440.0 + 60.0) and not DayNight.is_night(720.0), "ночь/день")

func test_data_integrity() -> void:
	section("Данные: предметы, рецепты, постройки, задания")
	for id in RecipeDB.RECIPES:
		var r: Dictionary = RecipeDB.RECIPES[id]
		check(ItemDB.ITEMS.has(r.result), "результат рецепта %s существует" % id)
		for k in r.cost:
			check(ItemDB.ITEMS.has(k), "ингредиент %s в %s" % [k, id])
		check(RecipeDB.STATION_NAMES.has(r.station), "станция %s" % r.station)
	for id in BuildDB.PIECES:
		for k in BuildDB.PIECES[id].cost:
			check(ItemDB.ITEMS.has(k), "ресурс %s постройки %s" % [k, id])
		check(ResourceLoader.exists("res://assets/textures/icons/build_%s.png" % id), "иконка постройки %s" % id)
	var required := ["foundation", "wall", "roof", "door", "window", "campfire", "crate", "bed", "workbench", "furnace", "fence", "tower", "bunker"]
	for r2 in required:
		check(BuildDB.PIECES.has(r2), "постройка %s" % r2)
	for id in ItemDB.ITEMS:
		check(ResourceLoader.exists("res://assets/textures/icons/%s.png" % id), "иконка %s" % id)
	for res in ["wood", "stone", "metal", "fabric", "rope", "electronics", "water_dirty"]:
		check(ItemDB.ITEMS.has(res), "ресурс %s" % res)
	check(QuestManager.QUESTS.size() == 12, "12 сюжетных заданий")
	check(ItemDB.get_item("stone").get("throwable", false), "камень — метательный обычный ресурс")
	for k in ["antenna", "radio_lamp", "coil", "map"]:
		check(ItemDB.is_key(k), "%s — сюжетный" % k)

func test_stats() -> void:
	section("Характеристики")
	DifficultyManager.restore_level(1)
	var s := SurvivalStats.new()
	s.setup_from_difficulty()
	s.hunger = 50.0
	s.tick(60.0, 18.0, false)
	check(is_equal_approx(s.hunger, 50.0 - float(DifficultyManager.p("hunger_rate"))), "голод за игровой час")
	s.hunger = 0.0
	s.thirst = 0.0
	var h0 := s.health
	s.tick(60.0, 18.0, false)
	check(s.health < h0, "голод и жажда отнимают здоровье")
	s = SurvivalStats.new()
	s.tick(300.0, -5.0, false)
	check(s.body_temp < 36.0, "холод снижает температуру")
	s.apply_food({"hunger": 200})
	check(s.hunger == 100.0, "ограничение 100")
