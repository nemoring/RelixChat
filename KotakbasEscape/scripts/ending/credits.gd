extends Control
## Титры «Котакбас побег от ТЦК».
## Полный режим (после финала): «ПРОДОЛЖЕНИЕ СЛЕДУЕТ...» → тизер → титры (~90 с) →
## сцена в штабе Интерпола → «Мобилизация. Скоро. Возможно.» → экран «Игра пройдена!».
## Повторный просмотр: только титры → экран «Игра пройдена!».
## Удержание пальца ускоряет прокрутку, кнопка «Пропустить» пропускает текущую часть.

const DURATION := 90.0
const HOLD_MULT := 5.0

## [тип, текст]: t — крупный заголовок, h — заголовок раздела, n — имя, s — пробел, l — разделитель
const LINES := [
	["t", "KOTAKBAS STUDIO"], ["n", "представляет"], ["s", ""],
	["t", "Котакбас побег от ТЦК"], ["s", ""], ["l", ""],
	["h", "Разработка игры"], ["n", "Kotakbas Studio"],
	["h", "Идея и руководство проектом"], ["n", "Создатель Kotakbas Studio"],
	["h", "Игровой движок"], ["n", "Godot Engine 4.4.1"],
	["h", "Сценарий"], ["n", "Kotakbas Studio"],
	["h", "Геймдизайн"], ["n", "Kotakbas Studio"],
	["h", "2D и 3D графика"], ["n", "Kotakbas Studio"],
	["h", "Процедурная генерация ресурсов"], ["n", "Python"],
	["h", "Музыка и звуковые эффекты"], ["n", "Процедурный синтез"],
	["h", "Главный герой"], ["n", "Котакбас"],
	["h", "Специальный гость"], ["n", "Голубь"],
	["h", "Главный антагонист"], ["n", "Летающая тарелка ТЦК"],
	["h", "Отдел противовоздушной обороны"], ["n", "Котакбас и 20 камней"],
	["h", "Отдел тестирования"], ["n", "228 автоматических проверок"],
	["h", "Отдельная благодарность"], ["n", "Всем зайцам, пожертвовавшим сырое мясо"],
	["h", "Особая благодарность"], ["n", "Тульскому прянику"],
	["s", ""], ["l", ""],
	["t", "Спасибо за прохождение!"], ["s", ""],
	["n", "Котакбас обязательно вернётся..."], ["s", ""],
	["n", "© 2026 Kotakbas Studio"],
]

var phase := "start" # start, intro, scroll, epilogue, outro, end
var full := true
var roll: VBoxContainer
var caption: Label
var subcaption: Label
var skip_btn: Button
var end_panel: Control
var room: Control
var dialogue: DialogueBox
var holding := false
var _skip_flag := false
var _labels: Array[Label] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	full = GameManager.credits_full
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	room = InterpolRoom.new()
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room.visible = false
	add_child(room)
	roll = VBoxContainer.new()
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll.alignment = BoxContainer.ALIGNMENT_CENTER
	roll.visible = false
	add_child(roll)
	_build_roll()
	# Плавное появление/исчезновение текста у краёв экрана
	add_child(_edge_fade(true))
	add_child(_edge_fade(false))
	caption = _center_label(54)
	subcaption = _center_label(32)
	subcaption.offset_top = 110
	dialogue = DialogueBox.new()
	add_child(dialogue)
	skip_btn = UIStyle.make_button("Пропустить", Vector2(240, 80), 26)
	skip_btn.anchor_left = 1.0
	skip_btn.anchor_right = 1.0
	skip_btn.offset_left = -264
	skip_btn.offset_right = -24
	skip_btn.offset_top = 20
	skip_btn.offset_bottom = 100
	skip_btn.pressed.connect(skip)
	add_child(skip_btn)
	resized.connect(_layout)
	GameManager.back_requested.connect(skip)
	AudioManager.stop_ambient()
	_layout()
	_run()

func _ui_scale() -> float:
	return clampf(size.y / 720.0, 0.8, 1.6)

func _center_label(fs: int) -> Label:
	var l := UIStyle.make_label("", fs, Color.WHITE, true)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 40
	l.offset_right = -40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _edge_fade(top: bool) -> TextureRect:
	var tr := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 1))
	g.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	gt.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	gt.width = 8
	gt.height = 64
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_right = 1.0
	if top:
		tr.offset_bottom = 150
	else:
		tr.anchor_top = 1.0
		tr.anchor_bottom = 1.0
		tr.offset_top = -150
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _build_roll() -> void:
	for e in LINES:
		var kind: String = e[0]
		var l := Label.new()
		l.text = e[1]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color.WHITE)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_meta("kind", kind)
		match kind:
			"t":
				l.add_theme_font_override("font", UIStyle.title_font())
			"h":
				l.add_theme_font_override("font", UIStyle.title_font())
				l.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
			"l":
				l.text = "———"
				l.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		roll.add_child(l)
		_labels.append(l)

## Масштабирование под экран: ширина колонки и размер шрифтов зависят от
## размера экрана, перенос строк — чтобы ничего не обрезалось.
func _layout() -> void:
	var k := _ui_scale()
	var width := clampf(size.x - 80.0, 280.0, 1000.0)
	for l in _labels:
		var kind: String = l.get_meta("kind")
		var fs: int = {"t": 52, "h": 30, "n": 34, "s": 30, "l": 26}[kind]
		l.add_theme_font_size_override("font_size", int(fs * k))
		l.custom_minimum_size = Vector2(width, 0)
		if kind == "h":
			l.custom_minimum_size.y = 46 * k
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	roll.add_theme_constant_override("separation", int(10 * k))
	roll.custom_minimum_size.x = width
	roll.position.x = (size.x - width) * 0.5
	# Пересчитать высоту колонки по новой ширине (иначе контейнер не сжимается).
	roll.size = Vector2(width, 0)
	roll.reset_size()
	caption.add_theme_font_size_override("font_size", int(54 * k))
	subcaption.add_theme_font_size_override("font_size", int(30 * k))

func scroll_speed() -> float:
	var dist := size.y + roll.size.y
	return dist / DURATION * (HOLD_MULT if holding else 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		holding = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		holding = event.pressed

func skip() -> void:
	if phase in ["intro", "scroll", "epilogue", "outro"]:
		_skip_flag = true
		AudioManager.play_sfx("click")
		if dialogue.box.visible:
			dialogue._complete_text()
			dialogue._advance()

func _wait(t: float) -> void:
	var e := 0.0
	while e < t and not _skip_flag:
		await get_tree().process_frame
		e += get_process_delta_time()

func _show_text(l: Label, text: String, hold: float, fade := 0.8) -> void:
	l.text = text
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, fade)
	await tw.finished
	await _wait(hold)
	var tw2 := create_tween()
	tw2.tween_property(l, "modulate:a", 0.0, fade)
	await tw2.finished

func _run() -> void:
	if full:
		phase = "intro"
		AudioManager.stop_music(0.3)
		await get_tree().create_timer(0.8).timeout
		await _show_text(caption, "ПРОДОЛЖЕНИЕ СЛЕДУЕТ...", 2.2)
		caption.add_theme_color_override("font_color", UIStyle.ACCENT)
		await _show_text(caption, "Котакбас вернётся в\n«Котакбас побег от ТЦК: Мобилизация»", 3.0)
		caption.add_theme_color_override("font_color", Color.WHITE)
		_skip_flag = false
	await _scroll()
	if full:
		await _epilogue()
	_show_end()

func _scroll() -> void:
	phase = "scroll"
	AudioManager.play_music("finale", 1.5)
	roll.visible = true
	await get_tree().process_frame
	_layout()
	await get_tree().process_frame
	roll.position.y = size.y
	while roll.position.y + roll.size.y > 0.0 and not _skip_flag:
		await get_tree().process_frame
		roll.position.y -= scroll_speed() * get_process_delta_time()
	roll.visible = false
	_skip_flag = false
	holding = false

func _epilogue() -> void:
	phase = "epilogue"
	AudioManager.stop_music(1.5)
	await _show_text(caption, "Где-то в секретном штабе Интерпола...", 2.0)
	if not _skip_flag:
		room.visible = true
		room.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(room, "modulate:a", 1.0, 1.5)
		await tw.finished
		AudioManager.play_music("tension", 2.0)
	if not _skip_flag:
		await dialogue.say("interpol", "suspicious", "Он думает, что сбежал.")
	if not _skip_flag:
		await dialogue.say("interpol2", "normal", "А голубь?")
	if not _skip_flag:
		await dialogue.say("interpol", "smug", "Голубь уже в пути.")
	dialogue.hide_box()
	if not _skip_flag:
		AudioManager.play_sfx("pigeon", 3.0)
		await _wait(1.6)
	var tw2 := create_tween()
	tw2.tween_property(room, "modulate:a", 0.0, 1.2)
	await tw2.finished
	room.visible = false
	AudioManager.stop_music(1.0)
	phase = "outro"
	caption.add_theme_color_override("font_color", UIStyle.ACCENT)
	caption.text = "«Котакбас побег от ТЦК: Мобилизация»"
	subcaption.text = "«Скоро. Возможно.»"
	var tw3 := create_tween().set_parallel()
	tw3.tween_property(caption, "modulate:a", 1.0, 1.0)
	tw3.tween_property(subcaption, "modulate:a", 1.0, 1.0).set_delay(0.8)
	await tw3.finished
	await _wait(3.0)
	var tw4 := create_tween().set_parallel()
	tw4.tween_property(caption, "modulate:a", 0.0, 0.8)
	tw4.tween_property(subcaption, "modulate:a", 0.0, 0.8)
	await tw4.finished
	caption.add_theme_color_override("font_color", Color.WHITE)
	_skip_flag = false

func _show_end() -> void:
	phase = "end"
	skip_btn.visible = false
	AudioManager.play_music("finale", 1.0)
	end_panel = CenterContainer.new()
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(end_panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	end_panel.add_child(vb)
	var t := UIStyle.make_label("Игра пройдена!", int(60 * _ui_scale()), UIStyle.ACCENT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := UIStyle.make_label("Сложность: %s" % DifficultyManager.level_name(int(GameManager.state.get("difficulty", 1))), 24, UIStyle.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var bsize := Vector2(clampf(size.x - 80.0, 300.0, 560.0), 88)
	var menu := UIStyle.make_button("Вернуться в главное меню", bsize)
	menu.name = "MenuButton"
	menu.pressed.connect(func():
		AudioManager.play_sfx("click")
		GameManager.go_to_menu())
	vb.add_child(menu)
	var cont := UIStyle.make_button("Продолжить выживание", bsize)
	cont.name = "ContinueButton"
	cont.disabled = not can_continue()
	cont.pressed.connect(func():
		AudioManager.play_sfx("click")
		GameManager.continue_after_ending())
	vb.add_child(cont)
	var again := UIStyle.make_button("Посмотреть титры ещё раз", bsize)
	again.name = "AgainButton"
	again.pressed.connect(replay_credits)
	vb.add_child(again)

func can_continue() -> bool:
	return GameManager.state.get("chapter", "") == "survival" and not GameManager.state.get("survival", {}).is_empty()

func replay_credits() -> void:
	AudioManager.play_sfx("click")
	if is_instance_valid(end_panel):
		end_panel.queue_free()
	skip_btn.visible = true
	await _scroll()
	_show_end()

## Тёмная комната штаба Интерпола: стол, лампа, папка «КОТАКБАС».
class InterpolRoom extends Control:
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.03, 0.05))
		var flick := 0.9 + 0.1 * sin(_t * 13.0) * sin(_t * 3.1)
		var lamp := Vector2(w * 0.5, h * 0.12)
		# Конус света от лампы
		draw_colored_polygon(PackedVector2Array([lamp + Vector2(-30, 0), lamp + Vector2(30, 0), Vector2(w * 0.78, h * 0.72), Vector2(w * 0.22, h * 0.72)]), Color(1.0, 0.85, 0.5, 0.07 * flick))
		draw_line(Vector2(lamp.x, 0), lamp, Color(0.15, 0.15, 0.15), 4.0)
		draw_colored_polygon(PackedVector2Array([lamp + Vector2(-40, 20), lamp + Vector2(-14, -8), lamp + Vector2(14, -8), lamp + Vector2(40, 20)]), Color(0.2, 0.25, 0.2))
		draw_circle(lamp + Vector2(0, 22), 10, Color(1.0, 0.9, 0.6, flick))
		# Стол
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.12, h * 0.72), Vector2(w * 0.88, h * 0.72), Vector2(w * 0.98, h * 0.95), Vector2(w * 0.02, h * 0.95)]), Color(0.22, 0.14, 0.08))
		draw_rect(Rect2(w * 0.02, h * 0.95, w * 0.96, h * 0.05), Color(0.14, 0.09, 0.05))
		# Папка «КОТАКБАС»
		var fc := Vector2(w * 0.5, h * 0.8)
		var fw := minf(w * 0.3, 360.0)
		var fh := fw * 0.36
		draw_colored_polygon(PackedVector2Array([fc + Vector2(-fw * 0.5, -fh * 0.5), fc + Vector2(fw * 0.5, -fh * 0.5), fc + Vector2(fw * 0.56, fh * 0.5), fc + Vector2(-fw * 0.56, fh * 0.5)]), Color(0.78, 0.62, 0.36) * flick)
		draw_rect(Rect2(fc + Vector2(-fw * 0.42, -fh * 0.62), Vector2(fw * 0.3, fh * 0.15)), Color(0.72, 0.56, 0.32))
		var font := UIStyle.title_font()
		var fs := int(fw * 0.13)
		var text := "КОТАКБАС"
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, fc + Vector2(-tw * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.08, 0.06))
		var st := "СОВЕРШЕННО СЕКРЕТНО"
		var sfs := int(fs * 0.35)
		var stw := font.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_string(font, fc + Vector2(-stw * 0.5, -fh * 0.28), st, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(0.55, 0.08, 0.06, 0.8))
		# Силуэты агентов
		for side in [-1.0, 1.0]:
			var ax: float = w * 0.5 + side * w * 0.3
			draw_circle(Vector2(ax, h * 0.42), h * 0.06, Color(0.07, 0.07, 0.09))
			draw_colored_polygon(PackedVector2Array([Vector2(ax - h * 0.11, h * 0.72), Vector2(ax - h * 0.08, h * 0.5), Vector2(ax + h * 0.08, h * 0.5), Vector2(ax + h * 0.11, h * 0.72)]), Color(0.07, 0.07, 0.09))
			draw_rect(Rect2(Vector2(ax - h * 0.075, h * 0.345), Vector2(h * 0.15, h * 0.03)), Color(0.05, 0.05, 0.06))

## Отладка: сразу эпилог (для скриншотов).
func debug_epilogue() -> void:
	while phase != "scroll":
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	skip()
	while phase != "end":
		await get_tree().create_timer(1.4).timeout
		if dialogue.box.visible:
			dialogue.tap_advance()
			dialogue.tap_advance()
