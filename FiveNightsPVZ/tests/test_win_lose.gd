extends TestSuite
## Условия победы и поражения; у каждой опасности есть предупреждение и контрмера.


func _await_over(g: GameWorld, limit := 8.0) -> void:
	var t := 0.0
	while not g.game_over and t < limit:
		await seconds(0.1)
		t += 0.1


func test_fired_after_three_violations() -> void:
	var g := await start_game(2)
	for i in 3:
		g.night.add_violation("тест")
	check(g.game_over, "три нарушения — увольнение")
	await stop_game(g)


func test_night1_no_firing() -> void:
	var g := await start_game(1)
	for i in 3:
		g.night.add_violation("тест")
	check(not g.game_over, "в обучающей ночи не увольняют")
	await stop_game(g)


func test_woman_curtain_rule() -> void:
	var g := await start_game(3)
	var w: FittingWoman = g.entities["woman"]
	w.request()
	var cur: Curtain = g.level.cabins[w.cabin]["curtain"]
	cur.set_open(true)
	check(not g.game_over, "без дыхания открыть шторку безопасно")
	cur.set_open(false)
	w.on_timeout()
	check(w.is_breathing(), "после просрочки — дыхание (предупреждение)")
	cur.set_open(true)
	await frames(2)
	check(g.game_over, "открыть шторку при дыхании — смерть")
	await stop_game(g)


func test_faceless_stare_kills_and_look_away_saves() -> void:
	var g := await start_game(3)
	var f: Faceless = g.entities["faceless"]
	var p := g.player
	f.show_at("hall_counter")
	f.state = "counter"
	f.set_vis_layers(Build.VIS_EYES_ONLY)
	p.global_position = Vector3(9.0, 0, 8.6)
	await frames(2)
	# Смотрим в лицо.
	p.look_at(Vector3(f.head_pos().x, p.global_position.y, f.head_pos().z), Vector3.UP)
	p.head.look_at(f.head_pos(), Vector3.UP)
	await seconds(1.0)
	check(f.stare > 0.0, "шкала взгляда растёт")
	# Отвели взгляд — шкала спадает.
	p.rotation.y += PI
	var s := f.stare
	await seconds(1.0)
	check(f.stare < s, "шкала спадает, если отвернуться")
	check(not g.game_over, "короткий взгляд безопасен")
	p.rotation.y -= PI
	Engine.time_scale = 3.0
	await _await_over(g, 12.0)
	check(g.game_over, "долгий взгляд в лицо убивает")
	await stop_game(g)


func test_inspector_dont_turn_around() -> void:
	var g := await start_game(4)
	var i: Inspector = g.entities["inspector"]
	i.behind_event()
	eq(i.state, "behind", "дыхание за спиной")
	Engine.time_scale = 4.0
	await seconds(10.0)
	check(not g.game_over, "не оборачиваясь — выживаем")
	check(i.state != "behind", "проверяющий ушёл")
	Engine.time_scale = 1.0
	i.state = "off"
	i.behind_event()
	g.player.rotation.y += PI
	await frames(3)
	check(g.game_over, "обернулся — смерть")
	await stop_game(g)


func test_courier_sees_lit_player() -> void:
	var g := await start_game(3)
	var c: Courier = g.entities["courier"]
	var p := g.player
	p.global_position = Vector3(10.4, 0, 3.95)
	c.activate()
	c.global_position = g.level.nav.pos_of("wh_w")
	c.face(p.global_position)
	c.stop()
	g.level.lighting.set_switch("warehouse", true)
	c._sense()
	eq(c.state, "chase", "на свету курьер замечает издалека")
	await stop_game(g)
	g = await start_game(3)
	c = g.entities["courier"]
	p = g.player
	p.global_position = Vector3(10.4, 0, 3.95)
	p.crouching = true
	c.activate()
	c.global_position = g.level.nav.pos_of("wh_w")
	c.face(p.global_position)
	c.stop()
	g.level.lighting.set_switch("warehouse", false)
	await frames(2)
	c._sense()
	check(c.state != "chase", "в темноте, присев, далеко — не замечает")
	await stop_game(g)


func test_jumpscare_per_entity() -> void:
	for id in ["faceless", "woman", "courier", "returner", "inspector"]:
		var g := await start_game(4)
		var e: Entity = g.entities[id]
		e.show_at("hall_center")
		Engine.time_scale = 3.0
		g.kill_player(id, "тест")
		await _await_over(g, 1.0)
		var t := 0.0
		while g.jumpscare.active and t < 6.0:
			await seconds(0.1)
			t += 0.1
		Engine.time_scale = 1.0
		check(g.game_over, "%s: нападение завершает ночь" % id)
		check(not g.jumpscare.active, "%s: анимация нападения завершилась" % id)
		await stop_game(g)
