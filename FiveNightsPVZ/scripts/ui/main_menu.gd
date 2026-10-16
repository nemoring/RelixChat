extends Node3D
## Главное меню: пустой ночной ПВЗ с работающим монитором на фоне.

var level: Level
var cam: Camera3D
var ui: Control
var menu_box: VBoxContainer
var side: Control
var _t := 0.0
var _warm := 0.0
var _status: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.35, 0.45)
	e.ambient_light_energy = 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.04, 0.05, 0.07)
	e.fog_density = 0.04
	we.environment = e
	add_child(we)
	level = Level.new()
	add_child(level)
	level.build(1979)
	level.apply_quality(GameState.quality())
	# Пустой ночной зал: горит только рабочее место, зал — в полутьме.
	level.lighting.set_switch("hall", false)
	level.lighting.set_switch("warehouse", false)
	level.lighting.set_switch("corridor", false)
	for l in level.clock_labels:
		l.text = "03:17"
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.cull_mask = Build.VIS_ALL | Build.VIS_EYES_ONLY
	add_child(cam)
	cam.position = Vector3(4.2, 1.55, 14.6)
	cam.look_at(Vector3(10.0, 1.1, 9.4), Vector3.UP)
	cam.current = true
	_build_ui()


func _process(delta: float) -> void:
	_t += delta
	cam.position = Vector3(4.2 + sin(_t * 0.07) * 0.25, 1.55 + sin(_t * 0.11) * 0.04, 14.6 + cos(_t * 0.05) * 0.2)
	cam.look_at(Vector3(10.0, 1.1, 9.4), Vector3.UP)
	if _warm < 1.0:
		_warm = Sfx.warmup_step()
		_status.text = "Подготовка звука… %d%%" % int(_warm * 100.0) if _warm < 1.0 else ""


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	UIKit.full_rect(ui)
	ui.theme = UIKit.theme()
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.size = Vector2(460, 0)
	shade.custom_minimum_size = Vector2(460, 0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	menu_box = VBoxContainer.new()
	menu_box.position = Vector2(48, 60)
	menu_box.custom_minimum_size = Vector2(360, 0)
	menu_box.add_theme_constant_override("separation", 10)
	ui.add_child(menu_box)
	side = CenterContainer.new()
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.offset_left = 460
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(side)
	_status = UIKit.label("", 14, UIKit.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(48, -40)
	ui.add_child(_status)
	_main()


func _clear_side() -> void:
	for c in side.get_children():
		c.queue_free()


func _main() -> void:
	for c in menu_box.get_children():
		c.queue_free()
	menu_box.add_child(UIKit.label("FIVE NIGHTS\nAT ПВЗ", 44, Color(0.85, 0.88, 0.85)))
	menu_box.add_child(UIKit.label("ул. Заводская, 7 · ночная смена 00:00–06:00", 15, UIKit.DIM))
	menu_box.add_child(Control.new())
	menu_box.add_child(UIKit.button("Новая игра", _new_game))
	var cont_night := _continue_night()
	var cb := UIKit.button("Продолжить (ночь %d)" % cont_night if cont_night > 0 else "Продолжить", func(): _start(cont_night))
	cb.disabled = cont_night <= 0
	menu_box.add_child(cb)
	menu_box.add_child(UIKit.button("Выбор ночи", _night_select))
	menu_box.add_child(UIKit.button("Настройки", _settings))
	menu_box.add_child(UIKit.button("Дополнительно", _extras))
	if not OS.has_feature("web"):
		menu_box.add_child(UIKit.button("Выход", func(): get_tree().quit()))


func _continue_night() -> int:
	var inprog := int(GameState.data.get("night_in_progress", 0))
	if inprog > 0:
		return inprog
	var u := int(GameState.data.get("unlocked_night", 1))
	return u if u > 1 else 0


func _start(n: int, custom := {}) -> void:
	if n <= 0:
		return
	GameState.start_night(n, custom)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _new_game() -> void:
	_clear_side()
	var p := PanelContainer.new()
	side.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(480, 0)
	p.add_child(v)
	v.add_child(UIKit.label("Анкета ночного сотрудника", 22, UIKit.ACCENT))
	v.add_child(UIKit.label("Зарплата — 15 000 ₽ за смену. Предыдущий сотрудник уволился. Так сказали.", 15, UIKit.DIM))
	v.add_child(UIKit.label("Фамилия и имя:", 16))
	var le := LineEdit.new()
	le.text = GameState.player_name()
	le.max_length = 32
	v.add_child(le)
	if int(GameState.data.get("unlocked_night", 1)) > 1:
		v.add_child(UIKit.label("Внимание: открытые ночи сохранятся, текущая смена начнётся с первой ночи.", 14, UIKit.DANGER))
	v.add_child(UIKit.button("Подписать договор", func():
		var n := le.text.strip_edges()
		GameState.data["player_name"] = n if n != "" else "Денис Смирнов"
		GameState.save_game()
		_start(1)))


func _night_select() -> void:
	_clear_side()
	var p := PanelContainer.new()
	side.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(480, 0)
	p.add_child(v)
	v.add_child(UIKit.label("Выбор ночи", 22, UIKit.ACCENT))
	for n in range(1, GameState.MAX_NIGHT + 1):
		var nn: int = n
		var b := UIKit.button("Ночь %d — %s" % [n, Story.NIGHT_TITLES[n]], func(): _start(nn))
		b.disabled = not GameState.is_night_unlocked(n)
		if b.disabled:
			b.text = "Ночь %d — ███████" % n
		v.add_child(b)


func _settings() -> void:
	_clear_side()
	var s := SettingsPanel.new()
	side.add_child(s)
	s.closed.connect(_clear_side)


func _extras() -> void:
	_clear_side()
	var p := PanelContainer.new()
	side.add_child(p)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(620, 520)
	p.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UIKit.label("Достижения", 22, UIKit.ACCENT))
	var ach: Dictionary = GameState.data["achievements"]
	for id in GameState.ACHIEVEMENTS.keys():
		var a: Dictionary = GameState.ACHIEVEMENTS[id]
		var got := ach.has(id)
		v.add_child(UIKit.label(("✓ " if got else "· ") + a["title"] + " — " + a["desc"], 15, UIKit.TEXT if got else UIKit.DIM))
	v.add_child(UIKit.label("Концовки", 22, UIKit.ACCENT))
	var ends: Dictionary = GameState.data["endings"]
	for id in GameState.ENDINGS.keys():
		var got := ends.has(id)
		v.add_child(UIKit.label(("✓ " + GameState.ENDINGS[id]) if got else "· ???", 15, UIKit.TEXT if got else UIKit.DIM))
	v.add_child(UIKit.label("Статистика", 22, UIKit.ACCENT))
	var st: Dictionary = GameState.data["stats"]
	v.add_child(UIKit.label("Смен отработано: %d\nСмертей: %d\nВыдано заказов: %d\nОтсканировано посылок: %d\nВозвратов обработано: %d\nПоддельных писем распознано: %d" % [st["nights_completed"], st["deaths"], st["orders_issued"], st["parcels_scanned"], st["returns_processed"], st["fakes_detected"]], 15))
	v.add_child(UIKit.label("Архив документов (%d/%d)" % [(GameState.data["documents"] as Array).size(), GameState.DOCUMENT_COUNT], 22, UIKit.ACCENT))
	for i in range(1, GameState.DOCUMENT_COUNT + 1):
		var idx: int = i
		if (GameState.data["documents"] as Array).has(i) or (GameState.data["documents"] as Array).has(float(i)):
			var d: Dictionary = Story.DOCUMENTS[i - 1]
			v.add_child(UIKit.button(d["title"], func(): _show_doc(idx), 36))
		else:
			v.add_child(UIKit.label("· не найден", 15, UIKit.DIM))
	if GameState.data.get("custom_unlocked", false):
		v.add_child(UIKit.button("Пользовательская ночь", _custom_night))
	v.add_child(UIKit.button("Сбросить прогресс", func():
		GameState.reset_progress()
		_main()
		_clear_side()))


func _show_doc(i: int) -> void:
	_clear_side()
	var p := PanelContainer.new()
	side.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	p.add_child(v)
	var d: Dictionary = Story.DOCUMENTS[i - 1]
	v.add_child(UIKit.label(d["title"], 20, UIKit.ACCENT))
	v.add_child(UIKit.label(d["body"], 16))
	v.add_child(UIKit.button("Назад", _extras))


func _custom_night() -> void:
	_clear_side()
	var p := PanelContainer.new()
	side.add_child(p)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	p.add_child(v)
	v.add_child(UIKit.label("Пользовательская ночь", 22, UIKit.ACCENT))
	var values := {}
	for id in NightData.ENTITIES:
		values[id] = NightData.AGGRESSION[6][id]
		var h := HBoxContainer.new()
		var l := UIKit.label(NightData.ENTITY_TITLES[id], 16)
		l.custom_minimum_size = Vector2(240, 0)
		h.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 20
		s.step = 1
		s.value = values[id]
		s.custom_minimum_size = Vector2(180, 30)
		var val := UIKit.label(str(int(s.value)), 16)
		var eid: String = id
		s.value_changed.connect(func(x):
			values[eid] = int(x)
			val.text = str(int(x)))
		h.add_child(s)
		h.add_child(val)
		v.add_child(h)
	v.add_child(UIKit.button("Начать", func(): _start(6, values)))
