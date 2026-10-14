extends Control
## Заставка Kotakbas Studio (~6 секунд) + титульный экран игры.
## Касание: первое — пропускает заставку студии, второе — титульный экран.

const STUDIO := "Kotakbas Studio"
const STUDIO_TIME := 6.0
const TITLE_TIME := 3.6

var t := 0.0
var phase := 0 # 0 — студия, 1 — название игры, 2 — уход в меню
var glow: TextureRect
var letters_box: HBoxContainer
var letters: Array[Label] = []
var presents: Label
var glitch: ColorRect
var glitch_mat: ShaderMaterial
var black: ColorRect
var title_root: Control
var title_label: Label
var subtitle_label: Label
var _beep_done := false
var _glitch_done := false
var _phase_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Слабое освещение — радиальное свечение
	glow = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.2, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	glow.texture = gt
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.modulate.a = 0.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	# Буквы названия студии
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vb)
	letters_box = HBoxContainer.new()
	letters_box.add_theme_constant_override("separation", 0)
	letters_box.alignment = BoxContainer.ALIGNMENT_CENTER
	letters_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(letters_box)
	for ch in STUDIO:
		var l := UIStyle.make_label(ch if ch != " " else "  ", 84, Color(0.98, 0.93, 0.85), true)
		l.modulate.a = 0.0
		letters_box.add_child(l)
		letters.append(l)
	presents = UIStyle.make_label("Представляет", 34, UIStyle.ACCENT, false)
	presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	presents.modulate.a = 0.0
	vb.add_child(presents)
	# Glitch поверх всего
	glitch = ColorRect.new()
	glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glitch_mat = ShaderMaterial.new()
	glitch_mat.shader = load("res://shaders/glitch.gdshader")
	glitch.material = glitch_mat
	glitch.visible = false
	add_child(glitch)
	# Титульный экран
	title_root = CenterContainer.new()
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.visible = false
	add_child(title_root)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 18)
	title_root.add_child(tv)
	title_label = UIStyle.make_label("Котакбас побег от ТЦК", 76, UIStyle.ACCENT, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.outline(title_label, 10)
	tv.add_child(title_label)
	subtitle_label = UIStyle.make_label("«Игра, которую никто не просил»", 32, Color(0.9, 0.9, 0.9))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(subtitle_label)
	black = ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.modulate.a = 0.0
	add_child(black)
	letters_box.resized.connect(func(): letters_box.pivot_offset = letters_box.size * 0.5)
	AudioManager.play_sfx("whoosh", -8.0)

func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if pressed:
		accept_event()
		_skip()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_skip()

func _skip() -> void:
	if phase == 0:
		_start_title()
	elif phase == 1 and _phase_t > 0.3:
		_go_menu()

func _start_title() -> void:
	phase = 1
	_phase_t = 0.0
	glitch.visible = false
	glow.modulate.a = 0.25
	for l in letters:
		l.visible = false
	presents.visible = false
	black.modulate.a = 0.0
	title_root.visible = true
	title_root.modulate.a = 0.0
	AudioManager.play_music("menu", 2.0)

func _go_menu() -> void:
	if phase == 2:
		return
	phase = 2
	GameManager.intro_shown = true
	SceneManager.change_scene(GameManager.SCENES.menu)

func _process(delta: float) -> void:
	_phase_t += delta
	if phase == 0:
		t += delta
		_studio_timeline()
		if t >= STUDIO_TIME:
			_start_title()
	elif phase == 1:
		title_root.modulate.a = clampf(_phase_t / 0.6, 0.0, 1.0)
		var s := 1.0 + sin(_phase_t * 3.0) * 0.02
		title_label.pivot_offset = title_label.size * 0.5
		title_label.scale = Vector2(s, s)
		title_label.rotation = sin(_phase_t * 2.3) * 0.015
		if _phase_t >= TITLE_TIME:
			_go_menu()

func _studio_timeline() -> void:
	# 0–1 c: чёрный экран, проявляется слабый свет.
	glow.modulate.a = clampf(t / 1.0, 0.0, 1.0) * 0.6
	# 1–2 c: буквы проявляются поочерёдно.
	var n := letters.size()
	for i in n:
		var start := 1.0 + float(i) / n * 0.85
		letters[i].modulate.a = clampf((t - start) / 0.18, 0.0, 1.0)
	# 2–3 c: лёгкая дрожь и электронный звук.
	if t >= 2.0 and t < 3.0:
		letters_box.position = Vector2(randf_range(-3, 3), randf_range(-2, 2))
		if not _beep_done:
			_beep_done = true
			AudioManager.play_sfx("studio_beep")
	# 3–4 c: резкое увеличение и glitch.
	if t >= 3.0 and t < 4.0:
		var k := clampf((t - 3.0) / 0.25, 0.0, 1.0)
		var sc := lerpf(1.0, 1.35, 1.0 - pow(1.0 - k, 3.0))
		letters_box.scale = Vector2(sc, sc)
		glitch.visible = true
		glitch_mat.set_shader_parameter("intensity", 1.0 - (t - 3.0) * 0.7)
		letters_box.position = Vector2(randf_range(-10, 10), randf_range(-4, 4)) * (1.0 - (t - 3.0))
		if not _glitch_done:
			_glitch_done = true
			AudioManager.play_sfx("studio_glitch")
	elif t >= 4.0:
		glitch.visible = false
		letters_box.position = Vector2.ZERO
	# 4–5 c: «Представляет».
	presents.modulate.a = clampf((t - 4.0) / 0.5, 0.0, 1.0)
	# 5–6 c: плавное затемнение.
	black.modulate.a = clampf((t - 5.0) / 0.9, 0.0, 1.0)
