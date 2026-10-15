extends Node
## Тест финала: отбитый финальный налёт закрывает задание → автоматическая кат-сцена →
## титры (прокрутка, ускорение, масштаб) → эпилог Интерпола → «Игра пройдена!» →
## продолжение выживания без повторного финала, в т.ч. после загрузки сохранения.
## Запуск: godot --headless --path . res://tests/ending_test.tscn

var failed := 0

func check(cond: bool, what: String) -> void:
	printerr(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		failed += 1

func _ready() -> void:
	await get_tree().process_frame
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	DifficultyManager.set_level_for_new_game(0)
	GameManager.reset_state(0)
	GameManager.in_game = true
	GameManager.start_chapter("survival", false)
	var g = await _wait_scene("Survival", 30.0)
	await get_tree().create_timer(4.5).timeout
	# Сюжет дошёл до финального налёта (радио восстановлено)
	var fi := -1
	for i in QuestManager.QUESTS.size():
		if QuestManager.QUESTS[i].id == "final_event":
			fi = i
	g.quests.index = fi
	g.pois.set_generator_fixed()
	g.pois.set_radio_fixed()
	g.ufo_manager.start_raid(true, {"state": 3, "hits": 0, "final": true})
	await get_tree().create_timer(0.5).timeout
	var ufo: UFOController = g.ufo_manager.ufo
	check(ufo != null and ufo.final_raid, "финальный налёт идёт")
	var starts := {"n": 0}
	for k in ufo.health.max_hits:
		ufo.health.register_hit()
	# Ждём титры, прокликивая диалоги кат-сцены
	var t := 0.0
	var saw_ending := false
	while t < 60.0:
		var cs := get_tree().current_scene
		if cs and cs.name == "Credits":
			break
		if is_instance_valid(g) and cs == g:
			if g._ending and not saw_ending:
				saw_ending = true
				check(g.player.frozen and not g.controls.visible, "управление заблокировано в кат-сцене")
			if g.dialogue.box.visible:
				g.dialogue.tap_advance()
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	check(saw_ending, "финальная кат-сцена запустилась автоматически после задания")
	var cr = get_tree().current_scene
	check(cr != null and cr.name == "Credits", "открылась сцена титров credits.tscn")
	if cr == null or cr.name != "Credits":
		return _finish()
	check(GameManager.flag("game_completed", false), "флаг прохождения игры сохранён")
	check(SaveManager.profile.completed, "прохождение записано в профиль")
	var saved := SaveManager.load_slot("auto")
	check(saved.get("flags", {}).get("game_completed", false) and saved.get("chapter") == "survival", "автосохранение: пройдено, глава — выживание")
	# Интро титров
	t = 0.0
	while cr.phase != "scroll" and t < 20.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	check(cr.phase == "scroll", "после «ПРОДОЛЖЕНИЕ СЛЕДУЕТ...» начались титры")
	await get_tree().create_timer(0.5).timeout
	var y0: float = cr.roll.position.y
	await get_tree().create_timer(1.0).timeout
	var y1: float = cr.roll.position.y
	check(y1 < y0, "текст прокручивается снизу вверх (%.0f → %.0f)" % [y0, y1])
	var dur: float = (cr.size.y + cr.roll.size.y) / cr.scroll_speed()
	check(dur > 80.0 and dur < 100.0, "длительность титров ≈ 90 с (%.0f с)" % dur)
	var normal: float = cr.scroll_speed()
	cr.holding = true
	check(cr.scroll_speed() > normal * 3.0, "удержание пальца ускоряет прокрутку")
	await get_tree().create_timer(3.0).timeout
	cr.holding = false
	var vp: Vector2 = cr.size
	var clipped := 0
	var texts := []
	for l in cr._labels:
		texts.append(l.text)
		if l.size.x > vp.x or l.get_line_count() > l.get_visible_line_count() and l.get_visible_line_count() > 0:
			clipped += 1
	check(clipped == 0, "нет обрезанных надписей при %dx%d" % [vp.x, vp.y])
	check(cr.roll.position.x >= 0.0 and cr.roll.position.x + cr.roll.size.x <= vp.x + 1.0, "колонка титров в пределах экрана")
	for must in ["KOTAKBAS STUDIO", "Котакбас и 20 камней", "Тульскому прянику", "© 2026 Kotakbas Studio", "Godot Engine 4.4.1"]:
		check(must in texts, "в титрах есть «%s»" % must)
	# Пропуск титров → эпилог Интерпола
	cr.skip()
	t = 0.0
	while cr.phase != "epilogue" and t < 5.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	check(cr.phase == "epilogue", "кнопка «Пропустить» переходит к сцене после титров")
	var lines := []
	t = 0.0
	while cr.phase != "end" and t < 40.0:
		if cr.dialogue.box.visible:
			var txt: String = cr.dialogue.text_label.text
			if not (txt in lines):
				lines.append(txt)
			cr.dialogue.tap_advance()
		await get_tree().create_timer(0.15).timeout
		t += 0.15
	check("Он думает, что сбежал." in lines and "А голубь?" in lines and "Голубь уже в пути." in lines, "диалог агентов Интерпола")
	check(cr.phase == "end", "экран «Игра пройдена!»")
	if cr.phase != "end":
		return _finish()
	var cont: Button = cr.end_panel.find_child("ContinueButton", true, false)
	check(cr.end_panel.find_child("MenuButton", true, false) != null and cr.end_panel.find_child("AgainButton", true, false) != null, "кнопки меню и повтора титров")
	check(cont != null and not cont.disabled, "можно продолжить выживание")
	# Повтор титров
	cr.replay_credits()
	await get_tree().create_timer(0.5).timeout
	check(cr.phase == "scroll", "титры можно посмотреть ещё раз")
	cr.skip()
	await get_tree().create_timer(0.5).timeout
	check(cr.phase == "end", "после повтора — снова экран прохождения")
	# Продолжить выживание
	cont = cr.end_panel.find_child("ContinueButton", true, false)
	cont.pressed.emit()
	var g2 = await _wait_scene("Survival", 30.0)
	await get_tree().create_timer(5.0).timeout
	check(get_tree().current_scene == g2 and not g2._ending, "выживание продолжается, финал не повторяется")
	check(g2.story_completed() and g2.quests.index >= QuestManager.QUESTS.size(), "все задания выполнены")
	check(not g2.player.frozen, "управление вернулось")
	# Загрузка завершённого сохранения не запускает титры снова
	GameManager.save_game("3")
	GameManager.load_game("3")
	var g3 = await _wait_scene("Survival", 30.0)
	await get_tree().create_timer(5.0).timeout
	check(get_tree().current_scene == g3 and not g3._ending, "после загрузки завершённого сохранения титры не запускаются")
	SaveManager.delete_slot("3")
	_finish()

func _finish() -> void:
	printerr("ENDING: %s" % ("OK" if failed == 0 else "FAILED (%d)" % failed))
	get_tree().quit(1 if failed > 0 else 0)

func _wait_scene(name: String, timeout: float):
	var t := 0.0
	while t < timeout:
		var cs := get_tree().current_scene
		if cs and cs.name == name and not SceneManager.is_busy():
			return cs
		await get_tree().process_frame
		t += get_process_delta_time()
	check(false, "сцена %s не загрузилась" % name)
	return null
