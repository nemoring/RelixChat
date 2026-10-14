extends Control
## Финал: надпись-тизер, титры и короткая сцена с Интерполом после титров.

var art: Control
var label: Label
var credits: RichTextLabel
var dialogue: DialogueBox
var skip_btn: Button
var _phase := 0
var _credits_speed := 55.0
var _skip := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	art = InterpolArt.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.visible = false
	add_child(art)
	label = UIStyle.make_label("", 44, UIStyle.ACCENT, true)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate.a = 0.0
	add_child(label)
	credits = RichTextLabel.new()
	credits.bbcode_enabled = true
	credits.fit_content = true
	credits.scroll_active = false
	credits.anchor_left = 0.15
	credits.anchor_right = 0.85
	credits.text = CreditsText.TEXT + "\n\n[center][color=#888888]Спасибо, что сбежал вместе с Котакбасом.[/color][/center]"
	credits.visible = false
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(credits)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	skip_btn = UIStyle.make_button("Пропустить", Vector2(220, 70), 22)
	skip_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	skip_btn.position = Vector2(-240, 16)
	skip_btn.pressed.connect(func(): _skip = true)
	add_child(skip_btn)
	AudioManager.play_music("ending")
	AudioManager.stop_ambient()
	_run()

func _fade_text(text: String, hold: float) -> void:
	label.text = text
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 1.0)
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 0.0, 1.0)
	await tw.finished

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	await _fade_text("Котакбас вернётся в\n«Котакбас побег от ТЦК: Мобилизация»", 3.0)
	# Титры
	AudioManager.play_music("credits")
	credits.visible = true
	await get_tree().process_frame
	credits.position.y = size.y
	_phase = 1
	while credits.position.y + credits.size.y > -20.0 and not _skip:
		await get_tree().process_frame
	_skip = false
	credits.visible = false
	_phase = 2
	await _interpol()
	await _fade_text("КОНЕЦ?", 1.5)
	GameManager.in_game = false
	GameManager.state.chapter = "ending"
	GameManager.go_to_menu()

func _process(delta: float) -> void:
	if _phase == 1:
		credits.position.y -= _credits_speed * delta

func _interpol() -> void:
	skip_btn.visible = false
	art.visible = true
	AudioManager.play_music("tension")
	await dialogue.say("narrator", "normal", "Тем временем. Лион, Франция. Штаб-квартира Интерпола.")
	await dialogue.say("interpol", "suspicious", "Докладывайте.")
	await dialogue.say("interpol2", "normal", "Объект «Котакбас». Сбежал из квартиры через окно. Шесть сальто. Обогнал всех на ногах-пропеллерах.")
	await dialogue.say("interpol", "surprised", "Ноги-пропеллеры?")
	await dialogue.say("interpol2", "normal", "Так точно. Затем скрылся в лесу. Построил дом. Сбил летающую тарелку камнями. Починил радио.")
	await dialogue.say("interpol", "suspicious", "А это кто на всех фотографиях?")
	await dialogue.say("interpol2", "scared", "Голубь, шеф. Он везде. Мы думаем... он главный.")
	AudioManager.play_sfx("pigeon")
	await dialogue.say("interpol", "angry", "Объявить в международный розыск. Обоих. Особенно голубя.")
	dialogue.hide_box()

class InterpolArt extends Control:
	var _t := 0.0
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.18, 0.2, 0.26))
		draw_rect(Rect2(0, h * 0.72, w, h * 0.28), Color(0.25, 0.22, 0.2))
		# Доска с уликами
		draw_rect(Rect2(w * 0.3, h * 0.06, w * 0.4, h * 0.42), Color(0.55, 0.4, 0.25))
		draw_rect(Rect2(w * 0.3, h * 0.06, w * 0.4, h * 0.42), Color(0.1, 0.08, 0.06), false, 5.0)
		var pins := [Vector2(0.36, 0.14), Vector2(0.5, 0.12), Vector2(0.64, 0.16), Vector2(0.42, 0.32), Vector2(0.6, 0.34)]
		for i in pins.size():
			var p: Vector2 = pins[i] * Vector2(w, h)
			draw_rect(Rect2(p - Vector2(40, 30), Vector2(80, 60)), Color(0.95, 0.95, 0.9))
			draw_circle(p - Vector2(0, 26), 5, Color(0.9, 0.1, 0.1))
		for i in pins.size() - 1:
			draw_line(pins[i] * Vector2(w, h), pins[i + 1] * Vector2(w, h), Color(0.85, 0.1, 0.1), 3.0)
		# На фото — голубь
		var pc: Vector2 = pins[1] * Vector2(w, h) + Vector2(0, 6)
		draw_circle(pc, 14, Color(0.55, 0.58, 0.65))
		draw_circle(pc + Vector2(10, -8), 8, Color(0.45, 0.5, 0.6))
		draw_colored_polygon(PackedVector2Array([pc + Vector2(17, -9), pc + Vector2(26, -6), pc + Vector2(17, -4)]), Color(0.95, 0.75, 0.35))
		draw_string(UIStyle.title_font(), Vector2(w * 0.38, h * 0.47), "ДЕЛО №001: КОТАКБАС", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.1, 0.05, 0.02))
		# Лампа
		var sw := sin(_t * 1.5) * 0.04
		draw_line(Vector2(w * (0.5 + sw), 0), Vector2(w * (0.5 + sw * 2.0), h * 0.08), Color(0.1, 0.1, 0.1), 3.0)
		draw_circle(Vector2(w * (0.5 + sw * 2.0), h * 0.09), 14, Color(1, 0.9, 0.5))
