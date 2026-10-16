class_name SettingsPanel
extends PanelContainer
## Настройки: графика, яркость, мерцание, звук, управление, субтитры.

signal closed


func _ready() -> void:
	theme = UIKit.theme()
	custom_minimum_size = Vector2(560, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(UIKit.label("НАСТРОЙКИ", 24, UIKit.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_option(box, "Качество графики", "quality", GameState.QUALITY_NAMES)
	_check(box, "Адаптивное качество (снижать разрешение при просадках)", "adaptive_quality")
	_slider(box, "Яркость", "brightness", 0.6, 1.8, 0.05)
	_check(box, "Мерцание ламп и фонарика", "flicker")
	_slider(box, "Поле зрения", "fov", 60.0, 95.0, 1.0)
	_slider(box, "Чувствительность мыши", "mouse_sens", 0.05, 1.0, 0.01)
	_slider(box, "Чувствительность сенсора", "touch_sens", 0.05, 1.0, 0.01)
	_check(box, "Инвертировать ось Y", "invert_y")
	_check(box, "Покачивание камеры при ходьбе", "head_bob")
	_slider(box, "Общая громкость", "master_volume", 0.0, 1.0, 0.01)
	_slider(box, "Эффекты", "sfx_volume", 0.0, 1.0, 0.01)
	_slider(box, "Окружение", "ambience_volume", 0.0, 1.0, 0.01)
	_check(box, "Субтитры и подписи звуков", "subtitles")
	_option(box, "Сенсорное управление", "touch_controls", ["auto", "on", "off"], ["Авто", "Вкл", "Выкл"])
	if not OS.has_feature("mobile"):
		_check(box, "Вертикальная синхронизация", "vsync")
		_check(box, "Полноэкранный режим", "fullscreen")
	root.add_child(UIKit.button("Готово", func():
		closed.emit()
		queue_free()))


func _row(box: Control, title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UIKit.label(title, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(240, 0)
	h.add_child(l)
	box.add_child(h)
	return h


func _slider(box: Control, title: String, key: String, mn: float, mx: float, step: float) -> void:
	var h := _row(box, title)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(GameState.settings[key])
	s.custom_minimum_size = Vector2(220, 32)
	var val := UIKit.label("%.2f" % s.value, 14, UIKit.DIM)
	val.custom_minimum_size = Vector2(50, 0)
	s.value_changed.connect(func(v):
		val.text = "%.2f" % v
		GameState.set_setting(key, v))
	h.add_child(s)
	h.add_child(val)


func _check(box: Control, title: String, key: String) -> void:
	var h := _row(box, title)
	var c := CheckButton.new()
	c.button_pressed = bool(GameState.settings[key])
	c.toggled.connect(func(v): GameState.set_setting(key, v))
	h.add_child(c)


func _option(box: Control, title: String, key: String, values: Array, labels: Array = []) -> void:
	var h := _row(box, title)
	var o := OptionButton.new()
	for i in values.size():
		o.add_item(str(labels[i] if labels.size() > i else values[i]), i)
	var cur = GameState.settings[key]
	var idx := values.find(cur) if typeof(cur) == TYPE_STRING else int(cur)
	o.select(maxi(idx, 0))
	o.item_selected.connect(func(i):
		var v = values[i] if typeof(cur) == TYPE_STRING else i
		GameState.set_setting(key, v))
	o.custom_minimum_size = Vector2(200, 36)
	h.add_child(o)
