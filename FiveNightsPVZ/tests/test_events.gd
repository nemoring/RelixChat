extends TestSuite
## Система случайных событий и HorrorDirector.


func test_all_random_events_run() -> void:
	var g := await start_game(4)
	for kind in HorrorDirector.RANDOM_EVENTS:
		var ok := g.director.random_event(kind)
		check(ok, "событие %s выполнено" % kind)
		await frames(1)
	check(not g.director.random_event("нет_такого"), "неизвестное событие отклоняется")
	await stop_game(g)


func test_all_ambient_events_run() -> void:
	var g := await start_game(4)
	for kind in HorrorDirector.AMBIENT:
		g.director._do_ambient(kind)
		await frames(1)
	check(not g.game_over, "фоновые события безопасны сами по себе")
	await stop_game(g)


func test_harm_is_not_tied_to_event_type() -> void:
	# Одинаковое событие иногда безвредно, иногда — нет: решает бросок.
	var g := await start_game(5)
	var harmful := 0
	var calm := 0
	for i in 60:
		var n_before: int = g.get_tree().get_processed_tweens().size()
		var log_before: int = g.director.event_log.size()
		g.director.rng.seed = i
		var r := g.director.rng.randf()
		if r < 0.4:
			harmful += 1
		else:
			calm += 1
	check(harmful > 0 and calm > 0, "есть и безвредные, и опасные исходы")
	await stop_game(g)


func test_director_phases_and_relief() -> void:
	var g := await start_game(3)
	var d := g.director
	d._enter(HorrorDirector.Phase.RELIEF)
	var any := false
	for i in 50:
		if d.request_escalation("courier", 1):
			any = true
	check(not any, "во время передышки эскалация запрещена")
	d._enter(HorrorDirector.Phase.THREAT)
	var allowed := 0
	for i in 200:
		if d.request_escalation("courier", 1):
			allowed += 1
	check(allowed > 0 and allowed < 200, "в фазе угрозы эскалация вероятностная (%d/200)" % allowed)
	await stop_game(g)


func test_phase_lengths_vary() -> void:
	var g := await start_game(2)
	var lens := {}
	for i in 10:
		g.director._enter(HorrorDirector.Phase.QUIET)
		lens[snappedf(g.director.phase_len, 0.1)] = true
	check(lens.size() > 5, "длительность тишины не фиксирована — угрозу не угадать")
	await stop_game(g)


func test_camping_detection() -> void:
	var g := await start_game(3)
	g.director.room_dwell = 900.0
	check(g.director.player_camping(), "долгое сидение на месте замечается")
	g.director.room_dwell = 0.0
	g.director.cam_history.clear()
	for i in 60:
		g.director.cam_history.append(1.0)
	check(g.director.player_camping(), "постоянный просмотр камер замечается")
	await stop_game(g)


func test_noise_reaches_entities() -> void:
	var g := await start_game(3)
	var w: FittingWoman = g.entities["woman"]
	w.state = "hunting"
	w.show_at("hall_center")
	w._timer = 30.0
	g.emit_noise(g.level.nav.pos_of("hall_e"), 0.8, "player")
	check(w.is_moving(), "слепая сущность идёт на шум")
	await stop_game(g)
