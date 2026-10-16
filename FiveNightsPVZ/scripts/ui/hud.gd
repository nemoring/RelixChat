class_name HUD
extends Node
## Игровой интерфейс: только необходимое. Подсказка взаимодействия, время,
## короткий список заданий, заряд фонарика (когда важен), субтитры,
## пост-обработка, меню паузы, документы, экраны итогов.

var world
var post_layer: CanvasLayer
var layer: CanvasLayer
var post: ColorRect
var post_mat: ShaderMaterial
var crosshair: ColorRect
var _crosshair_shadow: ColorRect
var prompt: Label
var held: Label
var clock: Label
var tasks_box: VBoxContainer
var battery_bar: ProgressBar
var msg: Label
var sub: Label
var overlay: ColorRect
var intro: Label
var modal: Control
var paused := false
var _msg_t := 0.0
var _sub_t := 0.0
var _tasks_expanded := false
var _heart: AudioStreamPlayer
var _heart_t := 0.0
var _battery_show_t := 0.0


func setup(w) -> void:
	world = w
	process_mode = Node.PROCESS_MODE_ALWAYS
	post_layer = CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post = ColorRect.new()
	UIKit.full_rect(post)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	post.material = post_mat
	post_layer.add_child(post)
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	layer.add_child(root)
	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.8)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	_crosshair_shadow = ColorRect.new()
	_crosshair_shadow.color = Color(0, 0, 0, 0.6)
	_crosshair_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair_shadow)
	root.move_child(_crosshair_shadow, crosshair.get_index())
	prompt = _anchored_label(root, Control.PRESET_CENTER, Vector2(-300, 30), Vector2(600, 30), 20)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	held = _anchored_label(root, Control.PRESET_CENTER_BOTTOM, Vector2(-300, -150), Vector2(600, 26), 16, UIKit.DIM)
	held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock = _anchored_label(root, Control.PRESET_TOP_RIGHT, Vector2(-260, 14), Vector2(240, 30), 20, Color(0.8, 0.82, 0.8, 0.85))
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tasks_box = VBoxContainer.new()
	tasks_box.position = Vector2(16, 14)
	tasks_box.custom_minimum_size = Vector2(460, 0)
	tasks_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tasks_box)
	battery_bar = ProgressBar.new()
	battery_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	battery_bar.position = Vector2(18, -40)
	battery_bar.size = Vector2(160, 14)
	battery_bar.show_percentage = false
	battery_bar.modulate = Color(1, 1, 1, 0.7)
	battery_bar.visible = false
	battery_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(battery_bar)
	msg = _anchored_label(root, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -230), Vector2(800, 60), 19)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub = _anchored_label(root, Control.PRESET_CENTER_BOTTOM, Vector2(-450, -110), Vector2(900, 70), 19, Color(0.95, 0.92, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_shadow_color", Color.BLACK)
	sub.add_theme_constant_override("shadow_offset_x", 2)
	sub.add_theme_constant_override("shadow_offset_y", 2)
	overlay = UIKit.color_rect(Color(0, 0, 0, 1))
	root.add_child(overlay)
	intro = _anchored_label(root, Control.PRESET_CENTER, Vector2(-400, -60), Vector2(800, 120), 30)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal = Control.new()
	UIKit.full_rect(modal)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(modal)
	world.night.task_added.connect(func(_t): _refresh_tasks())
	world.night.task_changed.connect(func(_t): _refresh_tasks())
	world.player.flashlight_changed.connect(func(_on): _battery_show_t = 3.0)
	_heart = AudioStreamPlayer.new()
	_heart.stream = Sfx.get_stream("heartbeat")
	_heart.bus = "SFX"
	_heart.volume_db = -60.0
	add_child(_heart)
	_heart.play()


func _anchored_label(root: Control, preset: int, pos: Vector2, size: Vector2, font := 18, color := UIKit.TEXT) -> Label:
	var l := UIKit.label("", font, color)
	l.set_anchors_preset(preset)
	l.position = pos
	l.size = size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _process(delta: float) -> void:
	if paused:
		if Input.is_action_just_pressed("pause"):
			_unpause()
		return
	if _modal_close.is_valid() and Input.is_action_just_pressed("pause"):
		_modal_close.call()
		return
	var p: Player = world.player
	# Пост-обработка.
	post_mat.set_shader_parameter("brightness", float(GameState.settings["brightness"]))
	post_mat.set_shader_parameter("fear", world.director.fear)
	post_mat.set_shader_parameter("stare", world.stare_value)
	post_mat.set_shader_parameter("grain", [0.03, 0.045, 0.05][clampi(GameState.quality(), 0, 2)])
	# Сердцебиение при сильном страхе.
	var f: float = maxf(world.director.fear, world.stare_value)
	_heart.volume_db = lerpf(_heart.volume_db, -40.0 + f * 30.0 if f > 0.45 else -60.0, delta * 2.0)
	_heart.pitch_scale = 0.9 + f * 0.5
	# Подсказка.
	var show_ui: bool = not p.seated and not world.game_over
	prompt.text = _prompt_text(p) if show_ui else ""
	# Точка-прицел: всегда в центре экрана; при наведении на объект — крупнее и жёлтая.
	var center := crosshair.get_parent_control().size * 0.5
	var cs := Vector2(10, 10) if p.focus else Vector2(5, 5)
	crosshair.visible = show_ui and not p.is_hidden() or (show_ui and p.focus != null)
	crosshair.size = cs
	crosshair.position = (center - cs * 0.5).round()
	crosshair.color = Color(1.0, 0.85, 0.35, 0.95) if p.focus else Color(1, 1, 1, 0.85)
	_crosshair_shadow.visible = crosshair.visible
	_crosshair_shadow.size = cs + Vector2(2, 2)
	_crosshair_shadow.position = crosshair.position - Vector2(1, 1)
	held.text = ("В руках: %s   [G] положить на пол" % p.held_item.describe()) if p.held_item and show_ui else ""
	if p.hiding_in and show_ui:
		held.text = "Вы прячетесь %s. [E] — выйти" % p.hiding_in.spot_name
	if p.listening and show_ui:
		held.text = "Прислушиваетесь… " + _listen_hint(p)
	clock.text = "%s   Ночь %s" % [world.night.clock_text(), "★" if GameState.is_custom_night else str(world.night_index)]
	# Фонарик.
	_battery_show_t = maxf(0.0, _battery_show_t - delta)
	battery_bar.value = p.battery
	battery_bar.visible = show_ui and (p.flashlight_on or p.battery < 25.0 or _battery_show_t > 0.0)
	# Сообщения.
	if _msg_t > 0.0:
		_msg_t -= delta
		msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if _sub_t > 0.0:
		_sub_t -= delta
		sub.modulate.a = clampf(_sub_t, 0.0, 1.0)
	if Input.is_action_just_pressed("tasks"):
		toggle_tasks()


## Направление последнего значимого звука (кроме собственных шагов).
func _listen_hint(p: Player) -> String:
	var now := Time.get_ticks_msec()
	for i in range(Sfx.recent.size() - 1, -1, -1):
		var r: Array = Sfx.recent[i]
		if now - int(r[2]) > 5000:
			break
		var pos: Vector3 = r[1]
		var d := pos.distance_to(p.global_position)
		if d < 1.2 or d > 18.0:
			continue
		var to := pos - p.global_position
		var local := p.global_basis.inverse() * to
		var dir := "впереди"
		if absf(local.x) > absf(local.z):
			dir = "справа" if local.x > 0 else "слева"
		elif local.z > 0:
			dir = "сзади"
		var wall := "" if p.has_los(pos + Vector3.UP * 0.2) else ", за стеной"
		var dist := "рядом" if d < 4.0 else ("недалеко" if d < 9.0 else "далеко")
		return "%s — %s, %s%s" % [Sfx.AUDIBLE_NAMES[r[0]], dir, dist, wall]
	return "тишина"


func _prompt_text(p: Player) -> String:
	if p.focus_prompt == "":
		return ""
	var key := "[E]" if not GameState.use_touch_controls() else ""
	return ("%s %s" % [key, p.focus_prompt]).strip_edges()


func toggle_tasks() -> void:
	_tasks_expanded = not _tasks_expanded
	_refresh_tasks()


func _refresh_tasks() -> void:
	for c in tasks_box.get_children():
		c.queue_free()
	var act: Array = world.night.active_tasks()
	var shown := 0
	for t in act:
		if shown >= (8 if _tasks_expanded else 3):
			break
		var line := "• " + str(t["title"])
		if str(t.get("progress", "")) != "":
			line += "  [%s]" % t["progress"]
		if _tasks_expanded and t["deadline"] > 0:
			var left: float = t["deadline"] - world.night.minute()
			line += "  — до %s" % world.night.clock_text(left)
		var l := UIKit.label(line, 15, Color(0.85, 0.86, 0.8, 0.85))
		l.custom_minimum_size = Vector2(460, 0)
		tasks_box.add_child(l)
		shown += 1
	if act.size() > shown:
		tasks_box.add_child(UIKit.label("  …ещё %d (Tab)" % (act.size() - shown), 14, UIKit.DIM))


func message(text: String, duration := 3.0) -> void:
	msg.text = text
	_msg_t = duration
	msg.modulate.a = 1.0


func subtitle(text: String, duration := 4.0) -> void:
	sub.text = text
	_sub_t = duration
	sub.modulate.a = 1.0


func show_intro(n: int) -> void:
	var title: String = Story.NIGHT_TITLES[clampi(n, 1, 6)] if not GameState.is_custom_night else "Пользовательская ночь"
	intro.text = "НОЧЬ %d\n%s\n\n00:00" % [n, title]
	overlay.color.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(intro, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(overlay, "color:a", 0.0, 2.0)


# ------------------------------------------------------------------ Модальные окна

var _modal_close := Callable()


func _modal_open() -> PanelContainer:
	_close_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UIKit.color_rect(Color(0, 0, 0, 0.6))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(dim)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	modal.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return panel


func _close_modal() -> void:
	_modal_close = Callable()
	for c in modal.get_children():
		c.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _resume_capture() -> void:
	if not world.player.seated and not GameState.use_touch_controls() and not world.headless_test and not world.game_over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func has_modal() -> bool:
	return modal.get_child_count() > 0


func show_document(title: String, body: String) -> void:
	var panel := _modal_open()
	world.player.controls_locked = true
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	panel.add_child(v)
	v.add_child(UIKit.label(title, 22, UIKit.ACCENT))
	var text := RichTextLabel.new()
	text.text = body
	text.fit_content = true
	text.custom_minimum_size = Vector2(600, 120)
	text.add_theme_font_size_override("normal_font_size", 18)
	v.add_child(text)
	var close := func():
		_close_modal()
		if not world.game_over:
			world.player.controls_locked = false
		_resume_capture()
	v.add_child(UIKit.button("Закрыть  [Esc]", close))
	_modal_close = close


func toggle_pause() -> void:
	if paused:
		_unpause()
		return
	if has_modal():
		return
	paused = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := _modal_open()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(360, 0)
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UIKit.label("ПАУЗА", 26, UIKit.ACCENT))
	v.add_child(UIKit.button("Продолжить", _unpause))
	v.add_child(UIKit.button("Настройки", func():
		var s := SettingsPanel.new()
		_close_modal()
		modal.mouse_filter = Control.MOUSE_FILTER_STOP
		var c := CenterContainer.new()
		UIKit.full_rect(c)
		modal.add_child(c)
		c.add_child(s)
		s.closed.connect(func():
			_close_modal()
			paused = false
			toggle_pause())))
	v.add_child(UIKit.button("Начать ночь заново", func():
		get_tree().paused = false
		get_tree().reload_current_scene.call_deferred()))
	v.add_child(UIKit.button("В главное меню", func():
		get_tree().paused = false
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")))


func _unpause() -> void:
	paused = false
	get_tree().paused = false
	_close_modal()
	_resume_capture()


func open_terminal() -> void:
	var panel := _modal_open()
	world.player.controls_locked = true
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	panel.add_child(v)
	var t := UIKit.label("СТОЛ ЗАКАЗОВ № 7 · ТЕРМИНАЛ\n\n> ОТМЕНА ЗАКАЗА\n> ВВЕДИТЕ ДАТУ ОТКРЫТИЯ (ДДММГГ):", 18, Color(0.4, 1.0, 0.5))
	v.add_child(t)
	var le := LineEdit.new()
	le.max_length = 6
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	le.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	v.add_child(le)
	le.grab_focus()
	var submit := func():
		var code := le.text
		_close_modal()
		world.player.controls_locked = false
		_resume_capture()
		world.submit_terminal_code(code)
	le.text_submitted.connect(func(_s): submit.call())
	v.add_child(UIKit.button("Ввод", submit))
	var leave := func():
		_close_modal()
		world.player.controls_locked = false
		_resume_capture()
	v.add_child(UIKit.button("Отойти  [Esc]", leave))
	_modal_close = leave


# ------------------------------------------------------------------ Итоговые экраны

const DEATH_TITLES := {
	"faceless": "Он подошёл ближе",
	"woman": "Шторка",
	"courier": "Доставлено",
	"returner": "Возврат оформлен",
	"inspector": "Нарушение выявлено",
	"fired": "Вы уволены",
}


func show_game_over(entity_id: String, hint: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.color.a = 1.0
	var panel := _modal_open()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UIKit.label(DEATH_TITLES.get(entity_id, "Смена прервана"), 28, UIKit.DANGER))
	v.add_child(UIKit.label("%s · %s" % [NightData.ENTITY_TITLES.get(entity_id, "Руководство"), world.night.clock_text()], 16, UIKit.DIM))
	v.add_child(UIKit.label("Что запомнить:\n" + hint, 18))
	v.add_child(UIKit.button("Начать ночь заново", func():
		GameState.start_night(world.night_index, GameState.custom_difficulty if GameState.is_custom_night else {})
		get_tree().reload_current_scene.call_deferred()))
	v.add_child(UIKit.button("В главное меню", func(): get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")))


func show_night_complete(n: int, violations: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 2.0)
	await tw.finished
	var panel := _modal_open()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UIKit.label("06:00", 40, UIKit.ACCENT))
	v.add_child(UIKit.label("Смена окончена. Магнитный замок отключился сам.", 18))
	v.add_child(UIKit.label("Нарушений: %d   ·   Писем распознано: %d" % [violations, world.night.fakes_detected], 16, UIKit.DIM))
	if n < GameState.MAX_NIGHT and not GameState.is_custom_night:
		v.add_child(UIKit.button("Ночь %d" % (n + 1), func():
			GameState.start_night(n + 1)
			get_tree().reload_current_scene.call_deferred()))
	v.add_child(UIKit.button("В главное меню", func(): get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")))


const ENDING_TEXT := {
	"shift_over": ["СМЕНА ОКОНЧЕНА", "В 06:00 замок щёлкает. Вы выходите на улицу, в серый ноябрьский рассвет.\n\nНа следующий день вывеска «Посылка» снята. Окна заклеены. В домофоне никто не отвечает.\n\nЧерез неделю приходит уведомление: «Ваш заказ ожидает вас в пункте выдачи». Адрес — ул. Заводская, 7.\n\nОткрыта шестая ночь и пользовательская сложность."],
	"received": ["ПОЛУЧЕНО", "Вы расписываетесь. Ручка пишет сама — аккуратнее, чем вы когда-либо писали.\n\nКоробка тёплая. Внутри темно и очень тесно, и пахнет картоном.\n\nУтром новый ночной сотрудник сканирует посылку. Пищит сканер.\n«Получатель: —. Ячейка: Б-3»."],
	"returned": ["ВОЗВРАТ", "Терминал печатает: «ВОЗВРАТ ОФОРМЛЕН. ЗАКАЗ № П-118204 АННУЛИРОВАН».\n\nВ ячейке Б-3 что-то шевелится. Из коробки, которую вы так и не открывали, доносится кашель — живой, человеческий.\n\nАртём Ключников не помнит последних трёх недель. Он помнит только, что было очень темно, и что кто-то всё время просил принести другой размер.\n\nСтол заказов № 7 закрыт. Окончательно. Наверное."],
}


func show_ending(id: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 2.5)
	await tw.finished
	var panel := _modal_open()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(680, 0)
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var e: Array = ENDING_TEXT[id]
	v.add_child(UIKit.label("КОНЦОВКА: " + e[0], 30, UIKit.ACCENT))
	v.add_child(UIKit.label(e[1], 18))
	v.add_child(UIKit.button("В главное меню", func(): get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")))
