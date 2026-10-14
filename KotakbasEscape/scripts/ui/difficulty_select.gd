extends Control
## Выбор сложности — один раз в начале прохождения.

var _selected := 1
var _cards: Array[Button] = []
var _desc: Label
var _start: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	var title := UIStyle.make_label("Выбери сложность", 44, UIStyle.ACCENT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := UIStyle.make_button("Назад", Vector2(180, 72))
	back.pressed.connect(_back)
	header.add_child(back)
	var warn := UIStyle.make_label("Сложность выбирается один раз и влияет на все главы: новеллу, раннер, выживание и НЛО ТЦК.", 22, UIStyle.MUTED)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 150
	vb.add_child(row)
	for i in 4:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = DifficultyManager.p_for(i, "name")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(200, 140)
		b.add_theme_font_override("font", UIStyle.title_font())
		b.add_theme_font_size_override("font_size", 30)
		var col: Color = DifficultyManager.p_for(i, "color")
		b.add_theme_stylebox_override("normal", UIStyle.button_style(Color(0.12, 0.12, 0.15), col.darkened(0.3)))
		b.add_theme_stylebox_override("pressed", UIStyle.button_style(col.darkened(0.55), col, 16))
		b.add_theme_stylebox_override("hover", UIStyle.button_style(Color(0.16, 0.15, 0.15), col))
		b.add_theme_stylebox_override("hover_pressed", UIStyle.button_style(col.darkened(0.55), col, 16))
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.pressed.connect(_select.bind(i))
		row.add_child(b)
		_cards.append(b)
	var desc_panel := PanelContainer.new()
	desc_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(desc_panel)
	_desc = UIStyle.make_label("", 26)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_panel.add_child(_desc)
	_start = UIStyle.make_button("Начать побег", Vector2(420, 96), 34)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.pressed.connect(_begin)
	vb.add_child(_start)
	_select(1)
	GameManager.back_requested.connect(_back)

func _select(i: int) -> void:
	_selected = i
	AudioManager.play_sfx("click")
	for k in _cards.size():
		_cards[k].button_pressed = (k == i)
	_desc.text = DifficultyManager.p_for(i, "desc")
	_desc.add_theme_color_override("font_color", UIStyle.TEXT)

func _begin() -> void:
	AudioManager.play_sfx("fanfare")
	GameManager.new_game(_selected)

func _back() -> void:
	if not SceneManager.is_busy():
		SceneManager.change_scene(GameManager.SCENES.menu)
