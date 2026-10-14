class_name SettingsPanel
extends OverlayPanel
## Настройки: Графика, FPS, Управление, Звук, Дополнительно. Всё крупное, под палец.

var _tabs_box: HBoxContainer
var _page: VBoxContainer
var _current_tab := 0
const TABS := ["Графика", "Управление", "Звук", "Дополнительно"]

func _ready() -> void:
	setup("Настройки")
	_tabs_box = HBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", 8)
	content.add_child(_tabs_box)
	for i in TABS.size():
		var b := UIStyle.make_button(TABS[i], Vector2(200, 66), 24)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(i))
		_tabs_box.add_child(b)
	var sc := OverlayPanel.make_scroll()
	content.add_child(sc)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 10)
	sc.add_child(_page)
	_show_tab(0)

func _show_tab(i: int) -> void:
	AudioManager.play_sfx("click")
	_current_tab = i
	for k in _tabs_box.get_child_count():
		(_tabs_box.get_child(k) as Button).button_pressed = (k == i)
	for c in _page.get_children():
		c.queue_free()
	match i:
		0:
			_cycler("Качество графики", Settings.QUALITY_NAMES, int(Settings.get_value("graphics")), func(v): Settings.set_value("graphics", v))
			var fps_names := ["30", "60", "90", "120", "Без ограничения"]
			var fps_idx := Settings.FPS_OPTIONS.find(int(Settings.get_value("fps")))
			_cycler("Частота кадров", fps_names, maxi(0, fps_idx), func(v): Settings.set_value("fps", Settings.FPS_OPTIONS[v]))
			_note("Минимальная и низкая графика снижают разрешение 3D, отключают тени и сокращают дальность прорисовки. 90/120 FPS работают только на экранах с высокой частотой обновления.")
		1:
			_slider("Размер джойстика", "joystick_size", 0.7, 1.5)
			_slider("Размер кнопок", "button_size", 0.7, 1.5)
			_slider("Чувствительность камеры", "cam_sens", 0.3, 2.5)
			_toggle("Инверсия камеры по вертикали", "invert_y")
			_toggle("Зеркальное расположение (джойстик справа)", "left_handed")
			_toggle("Вибрация", "vibration")
		2:
			_slider("Общая громкость", "vol_master", 0.0, 1.0)
			_slider("Музыка", "vol_music", 0.0, 1.0)
			_slider("Эффекты", "vol_sfx", 0.0, 1.0)
			_slider("Окружение", "vol_ambient", 0.0, 1.0)
		3:
			var langs := ["ru", "en"]
			_cycler("Язык интерфейса", ["Русский", "English"], maxi(0, langs.find(str(Settings.get_value("language")))), func(v): Settings.set_value("language", langs[v]))
			_toggle("Субтитры", "subtitles")
			_toggle("Автосохранение", "autosave")
			_toggle("Показывать FPS", "show_fps")
			_note("Сюжетные диалоги доступны на русском языке. Сохранения хранятся только на устройстве, интернет не нужен.")

func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 76
	var l := UIStyle.make_label(label_text, 26)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	_page.add_child(row)
	return row

func _cycler(label_text: String, options: Array, index: int, on_change: Callable) -> void:
	var row := _row(label_text)
	var state := {"i": index}
	var left := UIStyle.make_button("<", Vector2(80, 70))
	var value := UIStyle.make_label(tr(options[index]), 26, UIStyle.ACCENT)
	value.custom_minimum_size.x = 250
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var right := UIStyle.make_button(">", Vector2(80, 70))
	var upd := func(dir: int):
		state.i = posmod(state.i + dir, options.size())
		value.text = tr(options[state.i])
		AudioManager.play_sfx("click")
		on_change.call(state.i)
	left.pressed.connect(upd.bind(-1))
	right.pressed.connect(upd.bind(1))
	row.add_child(left)
	row.add_child(value)
	row.add_child(right)

func _slider(label_text: String, key: String, mn: float, mx: float) -> void:
	var row := _row(label_text)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(380, 60)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := UIStyle.make_label("%d%%" % roundi(s.value * 100.0), 24, UIStyle.ACCENT)
	val.custom_minimum_size.x = 90
	s.value_changed.connect(func(v):
		val.text = "%d%%" % roundi(v * 100.0)
		Settings.data[key] = v
		Settings.apply_all()
		Settings.changed.emit())
	s.drag_ended.connect(func(_c): Settings.save_settings())
	row.add_child(s)
	row.add_child(val)

func _toggle(label_text: String, key: String) -> void:
	var row := _row(label_text)
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get_value(key))
	cb.custom_minimum_size = Vector2(120, 64)
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on):
		AudioManager.play_sfx("click")
		Settings.set_value(key, on))
	row.add_child(cb)

func _note(text: String) -> void:
	var l := UIStyle.make_label(text, 20, UIStyle.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(l)
