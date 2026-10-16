extends TestSuite
## Главное меню и сенсорный ввод.
## Настоящие клики мышью и касаниями проверяет tools/e2e.tscn (нужен дисплей):
## в headless-режиме движок не доставляет ввод в интерфейс.


func _find_button(root: Node, prefix: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix) and (b as Button).is_visible_in_tree():
			return b
	return null


func test_touch_reaches_gui() -> void:
	check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"), "касания должны доходить до кнопок интерфейса")


func test_menu_buttons_open_panels() -> void:
	var m: Node = load("res://scenes/main_menu.tscn").instantiate()
	tree().root.add_child(m)
	await frames(5)
	for name in ["Выбор ночи", "Настройки", "Дополнительно", "Новая игра"]:
		var b := _find_button(m, name)
		check(b != null, "кнопка «%s» есть" % name)
		if b == null:
			continue
		check(b.mouse_filter == Control.MOUSE_FILTER_STOP, "«%s» принимает нажатия" % name)
		b.pressed.emit()
		await frames(2)
		check(m.side.get_child_count() > 0, "«%s» открывает панель" % name)
		m._clear_side()
		await frames(2)
	m.queue_free()
	await frames(2)


func _touch(t: TouchControls, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	t._input(e)


func test_touch_multitouch_buttons() -> void:
	GameState.settings["touch_controls"] = "on"
	var g := await start_game(1)
	var t := g.touch
	check(t.visible, "сенсорное управление включено")
	await frames(2)
	# Палец 0 держит джойстик, палец 1 жмёт «Фонарик».
	_touch(t, 0, Vector2(150, 500), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(150, 420)
	t._input(drag)
	check(g.player.touch_move.y < -0.5, "джойстик двигает вперёд")
	var fb: Button = t._buttons["flash"]
	_touch(t, 1, fb.get_global_rect().get_center(), true)
	_touch(t, 1, fb.get_global_rect().get_center(), false)
	check(g.player.flashlight_on, "второй палец нажимает кнопку, пока первый держит джойстик")
	_touch(t, 0, Vector2(150, 420), false)
	check(g.player.touch_move == Vector2.ZERO, "джойстик отпущен")
	# «Слушать» — удержание.
	var lb: Button = t._buttons["listen"]
	_touch(t, 2, lb.get_global_rect().get_center(), true)
	check(g.player._touch_listen, "удержание «Слушать»")
	_touch(t, 2, lb.get_global_rect().get_center(), false)
	check(not g.player._touch_listen, "отпускание «Слушать»")
	# Эмулированная из касания мышь не вызывает «взаимодействие».
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.device = InputEvent.DEVICE_ID_EMULATION
	var d: Door = g.level.doors["wh_ws"]
	var was := d.is_open
	g.player.focus = d
	g.player._unhandled_input(mb)
	eq(d.is_open, was, "тап по экрану не открывает дверь")
	mb.device = 0
	g.player._unhandled_input(mb)
	check(d.is_open != was, "настоящий клик мышью взаимодействует")
	GameState.settings["touch_controls"] = "auto"
	await stop_game(g)


func test_inventory_cells_checkable() -> void:
	var g := await start_game(4)
	g.night.run_beat("inventory", 3)
	var t := g.night.find_task("inventory")
	check(not t.is_empty(), "задание инвентаризации")
	for id in g.night.inventory_cells.duplicate():
		var spot: DropSpot = g.level.cells[id]
		check(spot.prompt(g.player) != "", "у ячейки %s есть действие «Сверить»" % id)
		spot.interact(g.player)
	check(t["done"], "инвентаризация выполняется")
	await stop_game(g)


func test_documents_survive_reload() -> void:
	GameState.reset_progress()
	GameState.collect_document(1)
	GameState.collect_document(2)
	GameState.load_game()
	GameState.collect_document(1)
	eq((GameState.data["documents"] as Array).size(), 2, "документы не дублируются после загрузки")
	check(not GameState.has_all_documents(), "секретная концовка не открывается раньше времени")
	GameState.reset_progress()


func test_maglock_prompt_initial() -> void:
	var g := await start_game(1)
	eq(g.level.maglock.prompt_text, "Отключить магнитный замок", "подпись замка с самого начала")
	await stop_game(g)


func test_desk_does_not_rebuild_without_changes() -> void:
	var g := await start_game(2)
	g.open_desk()
	g.desk.tabs.current_tab = 5
	await frames(3)
	var before: Array = g.desk.panel_box.get_children()
	await seconds(1.2)
	var after: Array = g.desk.panel_box.get_children()
	check(before.size() > 0 and before[0] == after[0], "кнопки пульта не пересоздаются без причины")
	g.close_desk()
	await stop_game(g)
