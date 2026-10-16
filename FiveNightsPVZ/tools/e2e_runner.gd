extends Node
## Сквозная проверка интерфейса настоящими кликами (нужен дисплей, например xvfb):
##   xvfb-run godot --path . --rendering-driver opengl3 res://tools/e2e.tscn
## Режим "touch" — те же шаги касаниями.

var fails := 0
var touch := false


func _ready() -> void:
	touch = OS.get_cmdline_user_args().has("touch")
	GameState.save_path = "user://e2e_save.json"
	GameState.settings_path = "user://e2e_settings.cfg"
	GameState.reset_progress()
	await _wait(0.5)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(2.0)
	await _press("Выбор ночи")
	_expect(_find("Ночь 1 — Первая смена") != null, "выбор ночи показывает ночи")
	await _press("Настройки")
	_expect(_find("Готово") != null, "настройки открываются")
	await _press("Готово")
	await _press("Дополнительно")
	_expect(_find_label("Достижения") != null, "дополнительно открывается")
	await _press("Новая игра")
	await _press("Подписать договор")
	await _wait(3.0)
	_expect(GameWorld.instance != null, "игра запустилась")
	if GameWorld.instance:
		var g := GameWorld.instance
		g.open_desk()
		await _wait(0.5)
		await _press("Почта")
		_expect(g.desk.tabs.current_tab == 3, "вкладка «Почта» переключается кликом")
		await _press("Пульт")
		var before: bool = g.level.lighting.switches["hall"]
		await _press("Зал:")
		_expect(g.level.lighting.switches["hall"] != before, "кнопка пульта переключает свет")
		await _press("Встать из-за стола")
		_expect(not g.player.seated, "кнопка «Встать» работает")
		g.hud.toggle_pause()
		await _wait(0.3)
		await _press("Продолжить")
		_expect(not g.hud.paused, "пауза снимается кнопкой")
		g.hud.toggle_pause()
		await _wait(0.3)
		await _press("В главное меню")
		await _wait(2.0)
		_expect(get_tree().current_scene and get_tree().current_scene.name == "MainMenu", "возврат в меню")
		await _press("Продолжить")
		await _wait(3.0)
		_expect(GameWorld.instance != null, "«Продолжить» запускает текущую ночь")
	print("E2E %s: ошибок %d" % ["touch" if touch else "mouse", fails])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.settings_path))
	get_tree().quit(1 if fails > 0 else 0)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _expect(c: bool, msg: String) -> void:
	print(("  ok   " if c else "  FAIL ") + msg)
	if not c:
		fails += 1


func _find(prefix: String) -> Button:
	for b in get_tree().root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix) and (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	for t in get_tree().root.find_children("*", "TabBar", true, false):
		pass
	return null


func _find_label(text: String) -> Label:
	for l in get_tree().root.find_children("*", "Label", true, false):
		if (l as Label).text == text and (l as Label).is_visible_in_tree():
			return l
	return null


func _press(prefix: String) -> void:
	var pos := Vector2(-1, -1)
	var b := _find(prefix)
	if b:
		pos = b.get_global_rect().get_center()
	else:
		# Вкладки TabContainer.
		for tc in get_tree().root.find_children("*", "TabContainer", true, false):
			var bar: TabBar = (tc as TabContainer).get_tab_bar()
			for i in bar.tab_count:
				if bar.get_tab_title(i).begins_with(prefix) and bar.is_visible_in_tree():
					pos = bar.get_global_transform() * bar.get_tab_rect(i).get_center()
	if pos.x < 0:
		_expect(false, "не найдена кнопка «%s»" % prefix)
		return
	if touch:
		for pressed in [true, false]:
			var t := InputEventScreenTouch.new()
			t.position = pos
			t.pressed = pressed
			Input.parse_input_event(t)
			await _wait(0.1)
	else:
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		Input.parse_input_event(mm)
		await _wait(0.05)
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.position = pos
			e.pressed = pressed
			Input.parse_input_event(e)
			await _wait(0.1)
	await _wait(0.3)
