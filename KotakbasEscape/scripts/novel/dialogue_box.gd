class_name DialogueBox
extends Control
## Собственная система диалогов: печать по буквам, анимированные портреты с эмоциями,
## журнал (история сообщений), пропуск прочитанного, автопродолжение, варианты
## ответов с таймером и подсказками. Используется в новелле и в выживании.

signal advanced
signal choice_made(index: int)

const CHARS_PER_SEC := 45.0

var portrait: Portrait
var name_label: Label
var text_label: RichTextLabel
var box: PanelContainer
var choices_box: VBoxContainer
var timer_bar: ProgressBar
var next_marker: Label
var auto_btn: Button
var skip_btn: Button
var log_btn: Button
var history: Array = [] # [{speaker, text}]

var auto_mode := false
var skip_mode := false
var _typing := false
var _visible_chars := 0.0
var _waiting := false
var _auto_wait := 0.0
var _line_id := ""
var _choosing := false
var _choice_time := 0.0
var _choice_total := 0.0
var _choice_default := 0
var _choice_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait = Portrait.new()
	portrait.anchor_left = 0.0
	portrait.anchor_right = 0.0
	portrait.anchor_top = 1.0
	portrait.anchor_bottom = 1.0
	portrait.offset_left = 10
	portrait.offset_right = 330
	portrait.offset_top = -560
	portrait.offset_bottom = -170
	add_child(portrait)
	box = PanelContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = -240
	box.offset_bottom = -12
	box.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.06, 0.06, 0.08, 0.93), 22, Color(1, 0.55, 0.12, 0.7)))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_box_input)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	name_label = UIStyle.make_label("", 30, UIStyle.ACCENT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	log_btn = _small_btn("Журнал", top)
	log_btn.pressed.connect(show_history)
	auto_btn = _small_btn("Авто", top)
	auto_btn.toggle_mode = true
	auto_btn.toggled.connect(func(on): auto_mode = on)
	skip_btn = _small_btn("Пропуск", top)
	skip_btn.toggle_mode = true
	skip_btn.toggled.connect(func(on): skip_mode = on)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = false
	text_label.scroll_active = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size.y = 120
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_size_override("normal_font_size", 30)
	vb.add_child(text_label)
	next_marker = UIStyle.make_label("»»", 26, UIStyle.ACCENT)
	next_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_marker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	vb.add_child(next_marker)
	# Варианты ответа
	choices_box = VBoxContainer.new()
	choices_box.anchor_left = 0.3
	choices_box.anchor_right = 0.97
	choices_box.anchor_top = 0.0
	choices_box.anchor_bottom = 1.0
	choices_box.offset_bottom = -250
	choices_box.offset_top = 16
	choices_box.alignment = BoxContainer.ALIGNMENT_END
	choices_box.add_theme_constant_override("separation", 8)
	choices_box.visible = false
	add_child(choices_box)
	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size.y = 14
	timer_bar.visible = false
	hide_box()

func _small_btn(text: String, parent: Control) -> Button:
	var b := UIStyle.make_button(text, Vector2(150, 58), 22)
	parent.add_child(b)
	return b

func hide_box() -> void:
	box.visible = false
	portrait.visible = false
	choices_box.visible = false

func is_busy() -> bool:
	return box.visible or choices_box.visible

## Показать реплику. Ждать завершения: await dialogue.say(...)
func say(speaker: String, emotion: String, text: String, line_id := "") -> void:
	var info: Dictionary = Portrait.SPEAKERS.get(speaker, Portrait.SPEAKERS.narrator)
	box.visible = true
	portrait.visible = speaker != "narrator"
	portrait.set_character(speaker, emotion)
	name_label.text = info.name
	name_label.add_theme_color_override("font_color", info.color)
	if speaker == "narrator":
		text_label.text = "[i]" + text + "[/i]"
	else:
		text_label.text = text
	history.append({"speaker": info.name, "text": text})
	if history.size() > 200:
		history.pop_front()
	_line_id = line_id
	var already_read := line_id != "" and SaveManager.is_line_read(line_id)
	_visible_chars = 0.0
	text_label.visible_characters = 0
	_typing = true
	_waiting = true
	_auto_wait = 0.0
	portrait.talking = true
	next_marker.visible = false
	if skip_mode and already_read:
		_complete_text()
		await get_tree().create_timer(0.06).timeout
		_advance()
	elif skip_mode and not already_read:
		skip_mode = false
		skip_btn.button_pressed = false
	if _waiting:
		await advanced
	if line_id != "":
		SaveManager.mark_line_read(line_id)

func _process(delta: float) -> void:
	if _typing:
		_visible_chars += delta * CHARS_PER_SEC
		var total := text_label.get_total_character_count()
		text_label.visible_characters = int(_visible_chars)
		if int(_visible_chars) % 3 == 0 and int(_visible_chars) != int(_visible_chars - delta * CHARS_PER_SEC):
			AudioManager.play_sfx("blip", -20.0, 1.0, 0.15)
		if _visible_chars >= total:
			_complete_text()
	elif _waiting and auto_mode and box.visible and not _choosing:
		_auto_wait += delta
		if _auto_wait > 1.2 + text_label.get_total_character_count() * 0.03:
			_advance()
	if _choosing and _choice_total > 0.0:
		_choice_time -= delta
		timer_bar.value = _choice_time / _choice_total * 100.0
		if _choice_time <= 0.0:
			_pick(_choice_default, true)
	if next_marker.visible:
		next_marker.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)

func _complete_text() -> void:
	_typing = false
	text_label.visible_characters = -1
	portrait.talking = false
	next_marker.visible = true

func _advance() -> void:
	if not _waiting:
		return
	_waiting = false
	next_marker.visible = false
	advanced.emit()

func _on_box_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not tap:
		return
	accept_event()
	tap_advance()

func tap_advance() -> void:
	if _choosing:
		return
	if _typing:
		_complete_text()
	else:
		AudioManager.play_sfx("click", -12.0)
		_advance()

## Варианты ответа: options = [{text, enabled, hint}]. timer > 0 — выбор на время,
## по истечении выбирается default_index. Возвращает индекс.
func choose(options: Array, timer := 0.0, default_index := 0) -> int:
	_choosing = true
	choices_box.visible = true
	for c in choices_box.get_children():
		c.queue_free()
	_choice_buttons.clear()
	if timer > 0.0:
		timer_bar = ProgressBar.new()
		timer_bar.show_percentage = false
		timer_bar.custom_minimum_size.y = 16
		timer_bar.value = 100
		var fill := StyleBoxFlat.new()
		fill.bg_color = UIStyle.BAD
		fill.set_corner_radius_all(8)
		timer_bar.add_theme_stylebox_override("fill", fill)
		choices_box.add_child(timer_bar)
	for i in options.size():
		var o: Dictionary = options[i]
		var txt: String = o.text
		if o.get("hint", "") != "":
			txt += "\n[" + str(o.hint) + "]"
		var b := UIStyle.make_button(txt, Vector2(0, 76), 25)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not o.get("enabled", true)
		if b.disabled:
			b.text = "(недоступно) " + b.text
		b.pressed.connect(_pick.bind(i, false))
		choices_box.add_child(b)
		_choice_buttons.append(b)
	_choice_total = timer
	_choice_time = timer
	_choice_default = default_index
	AudioManager.play_sfx("choice", -6.0)
	var idx: int = await choice_made
	return idx

func _pick(i: int, timed_out: bool) -> void:
	if not _choosing:
		return
	_choosing = false
	choices_box.visible = false
	if timed_out:
		GameManager.toast("Время вышло!", UIStyle.BAD, 1.5)
	AudioManager.play_sfx("click")
	history.append({"speaker": "›", "text": _choice_buttons[i].text if i < _choice_buttons.size() else ""})
	choice_made.emit(i)

func show_history() -> void:
	AudioManager.play_sfx("click")
	var p := OverlayPanel.new()
	p.setup("Журнал")
	var sc := OverlayPanel.make_scroll()
	p.content.add_child(sc)
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := ""
	for h in history:
		t += "[color=#ff8c1f]%s[/color] %s\n\n" % [h.speaker, h.text]
	l.text = t
	sc.add_child(l)
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
