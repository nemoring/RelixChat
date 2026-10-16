extends TestSuite
## Переходы между ночами, сценарий, нарушения, концовки.


func test_night_completion_unlocks_next() -> void:
	GameState.reset_progress()
	var g := await start_game(1)
	g.night.elapsed = g.night.duration - 0.05
	await seconds(0.3)
	check(g.game_over, "ночь завершилась в 06:00")
	eq(int(GameState.data["unlocked_night"]), 2, "открыта ночь 2")
	eq(int(GameState.data["night_in_progress"]), 0, "смена закрыта")
	check(GameState.data["achievements"].has("first_shift"), "достижение первой смены")
	await stop_game(g)


func test_night5_unlocks_six_and_custom() -> void:
	GameState.reset_progress()
	GameState.data["unlocked_night"] = 5
	var g := await start_game(5)
	g.night.elapsed = g.night.duration - 0.05
	await seconds(0.3)
	eq(int(GameState.data["unlocked_night"]), 6, "открыта шестая ночь")
	check(GameState.data["custom_unlocked"], "открыта пользовательская сложность")
	check(GameState.data["endings"].has("shift_over"), "концовка «Смена окончена»")
	await stop_game(g)


func test_script_beats_run_all_nights() -> void:
	# Прогоняем весь сценарий каждой ночи ускоренно: ни одно событие не падает.
	for n in range(1, 7):
		var g := await start_game(n)
		var script: Array = NightData.script_for(n)
		for beat in script:
			if beat[1] == "finale" or beat[1] == "own_order":
				continue
			g.night.run_beat(beat[1], beat[2])
			await frames(1)
		check(not g.game_over, "ночь %d: сценарий не убивает игрока сам по себе" % n)
		check(g.night.tasks.size() > 0, "ночь %d: есть задания" % n)
		check(g.night.mails.size() > 0, "ночь %d: есть письма" % n)
		await stop_game(g)


func test_durations_in_range() -> void:
	for n in range(1, 7):
		var d := NightData.duration(n)
		check(d >= 600.0 and d <= 900.0, "ночь %d длится 10–15 минут" % n)


func test_aggression_grows() -> void:
	for e in NightData.ENTITIES:
		check(NightData.aggression(5, e) >= NightData.aggression(1, e), "агрессия %s растёт" % e)
	eq(NightData.aggression(1, "courier"), 0, "в первую ночь курьер не нападает")


func test_custom_night_values() -> void:
	var g := await start_game(6, {"faceless": 0, "woman": 20, "courier": 3, "returner": 0, "inspector": 7})
	eq(g.entities["woman"].aggression, 20, "пользовательская агрессия")
	eq(g.entities["faceless"].aggression, 0, "отключённая сущность")
	await stop_game(g)
	GameState.is_custom_night = false


func test_secret_ending_requires_docs() -> void:
	GameState.reset_progress()
	var g := await start_game(5)
	g.submit_terminal_code(Story.CANCEL_CODE)
	check(not g.game_over, "без документов секретная концовка недоступна")
	g.hud._close_modal()
	for i in range(1, 6):
		GameState.collect_document(i)
	g.submit_terminal_code("000000")
	check(not g.game_over, "неверный код")
	g.submit_terminal_code(Story.CANCEL_CODE)
	check(g.game_over, "секретная концовка")
	check(GameState.data["endings"].has("returned"), "концовка «Возврат» сохранена")
	await stop_game(g)
	GameState.reset_progress()


func test_own_order_bad_ending() -> void:
	GameState.reset_progress()
	var g := await start_game(5)
	g.night.run_beat("own_order", null)
	var sign: Interactable = null
	for c in g.level.own_box.get_children():
		if c is Interactable:
			sign = c
	check(sign != null, "коробку с именем можно получить")
	sign.interact(g.player)
	check(g.game_over, "плохая концовка")
	check(GameState.data["endings"].has("received"), "концовка «Получено»")
	await stop_game(g)
	GameState.reset_progress()
