extends Node3D
## Главное меню: трёхмерный двор панельного дома, Котакбас у подъезда
## проигрывает случайные нелепые анимации. Крупные сенсорные кнопки.

var kot: KotakbasModel
var pigeon: PigeonModel
var cam: Camera3D
var _t := 0.0
var _next_anim := 2.0
var _pigeon_t := -1.0
var _ui: Control
var _continue_btn: Button

func _ready() -> void:
	_build_world()
	_build_ui()
	AudioManager.play_music("menu")
	AudioManager.play_ambient("city", -18.0)
	GameManager.back_requested.connect(_on_back)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.85, 0.75, 0.65)
	sm.ground_horizon_color = Color(0.5, 0.45, 0.4)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.8, 0.75, 0.7)
	e.fog_density = 0.012
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.shadow_enabled = Settings.shadows_enabled()
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# Двор: асфальт, газон, панельки, подъезд, лавочка, деревья.
	MK.box(self, Vector3(80, 0.2, 80), Color(0.33, 0.33, 0.35), Vector3(0, -0.1, 0))
	MK.box(self, Vector3(14, 0.22, 10), Color(0.3, 0.5, 0.25), Vector3(9, -0.08, 6))
	MK.panel_house(self, Vector3(0, 0, -10), Vector3(36, 24, 10), 1)
	MK.panel_house(self, Vector3(-26, 0, 6), Vector3(10, 24, 30), 2, 0.0)
	MK.panel_house(self, Vector3(28, 0, 2), Vector3(10, 18, 26), 3, 0.0)
	# Подъезд
	MK.box(self, Vector3(3.2, 3.0, 0.6), Color(0.55, 0.52, 0.5), Vector3(-2, 1.5, -4.8))
	MK.box(self, Vector3(1.4, 2.2, 0.1), Color(0.35, 0.22, 0.12), Vector3(-2, 1.1, -4.45))
	MK.box(self, Vector3(3.6, 0.15, 1.6), Color(0.5, 0.5, 0.5), Vector3(-2, 3.0, -4.3))
	MK.box(self, Vector3(0.7, 0.3, 0.05), Color(0.2, 0.3, 0.7), Vector3(-2, 2.45, -4.38))
	# Лавочка
	MK.box(self, Vector3(2.0, 0.08, 0.5), Color(0.55, 0.35, 0.18), Vector3(2.5, 0.5, -3.5))
	MK.box(self, Vector3(2.0, 0.5, 0.08), Color(0.55, 0.35, 0.18), Vector3(2.5, 0.8, -3.75))
	MK.box(self, Vector3(0.1, 0.5, 0.4), Color(0.2, 0.2, 0.2), Vector3(1.6, 0.25, -3.5))
	MK.box(self, Vector3(0.1, 0.5, 0.4), Color(0.2, 0.2, 0.2), Vector3(3.4, 0.25, -3.5))
	for p in [Vector3(8, 0, 4), Vector3(12, 0, 8), Vector3(-10, 0, 10), Vector3(14, 0, -2)]:
		MK.tree(self, p, randf_range(0.9, 1.3))
	# Машина «Жигули»
	var car := Node3D.new()
	car.position = Vector3(-8, 0, 2)
	car.rotation.y = 0.3
	add_child(car)
	MK.box(car, Vector3(1.7, 0.7, 4.0), Color(0.75, 0.2, 0.2), Vector3(0, 0.6, 0))
	MK.box(car, Vector3(1.5, 0.6, 2.0), Color(0.7, 0.2, 0.2), Vector3(0, 1.2, 0.2))
	for wp in [Vector3(-0.85, 0.3, 1.3), Vector3(0.85, 0.3, 1.3), Vector3(-0.85, 0.3, -1.3), Vector3(0.85, 0.3, -1.3)]:
		MK.cyl(car, 0.3, 0.3, 0.2, Color(0.1, 0.1, 0.1), wp, Vector3(0, 0, PI * 0.5))
	# Котакбас у подъезда
	kot = KotakbasModel.new()
	kot.position = Vector3(1.4, 0, -2.6)
	kot.rotation.y = PI + 0.4
	add_child(kot)
	kot.anim_finished.connect(func(_n): kot.play("idle"))
	pigeon = PigeonModel.new()
	pigeon.visible = false
	add_child(pigeon)
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.current = true

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.8))
	g.set_color(1, Color(0, 0, 0, 0.0))
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.anchor_bottom = 1.0
	grad.anchor_right = 0.55
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(grad)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)
	var title := UIStyle.make_label("Котакбас побег от ТЦК", 50, UIStyle.ACCENT, true)
	UIStyle.outline(title, 8)
	vb.add_child(title)
	var sub := UIStyle.make_label("Kotakbas Studio", 22, Color(0.85, 0.85, 0.85))
	vb.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	vb.add_child(spacer)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	_menu_button(grid, "Новая игра", _on_new_game)
	_continue_btn = _menu_button(grid, "Продолжить", _on_continue)
	_continue_btn.disabled = not SaveManager.has_any_save()
	_menu_button(grid, "Загрузить", func(): _ui.add_child(SaveLoadPanel.new()))
	_menu_button(grid, "Настройки", func(): _ui.add_child(SettingsPanel.new()))
	_menu_button(grid, "Авторы", _show_credits)
	_menu_button(grid, "Выход", func(): GameManager.quit_game())
	var ver := UIStyle.make_label("v%s · Android" % ProjectSettings.get_setting("application/config/version"), 16, Color(1, 1, 1, 0.5))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position -= Vector2(20, 10)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(ver)

func _menu_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := UIStyle.make_button(text, Vector2(270, 92), 30)
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call())
	parent.add_child(b)
	return b

func _on_new_game() -> void:
	SceneManager.change_scene(GameManager.SCENES.difficulty)

func _on_continue() -> void:
	if not GameManager.continue_game():
		GameManager.toast("Сохранение не найдено", UIStyle.BAD)

func _show_credits() -> void:
	var p := OverlayPanel.new()
	p.setup("Авторы")
	var sc := OverlayPanel.make_scroll()
	p.content.add_child(sc)
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = CreditsText.TEXT
	sc.add_child(l)
	_ui.add_child(p)

func _on_back() -> void:
	# Системная «Назад» в меню без открытых панелей — ничего не делаем (выход только кнопкой).
	pass

func _process(delta: float) -> void:
	_t += delta
	# Медленный облёт камеры
	var a := sin(_t * 0.12) * 0.35
	cam.position = Vector3(sin(a) * 7.0 + 2.0, 2.4 + sin(_t * 0.3) * 0.2, cos(a) * 7.0 + 3.0)
	cam.look_at(Vector3(-1.6, 1.4, -3.0))
	_next_anim -= delta
	if _next_anim <= 0.0 and kot.anim == "idle":
		_next_anim = randf_range(3.5, 6.5)
		_random_anim()
	if _pigeon_t >= 0.0:
		_pigeon_t += delta
		var k := _pigeon_t / 4.0
		pigeon.position = Vector3(lerpf(-20, 20, k), 6.0 + sin(k * PI) * 2.0, -1.0)
		pigeon.rotation.y = -PI * 0.5
		kot.look_target = pigeon.global_position
		if k >= 1.0:
			_pigeon_t = -1.0
			pigeon.visible = false

func _random_anim() -> void:
	var options := ["fall", "dance", "flip", "tpose", "pigeon", "sink"]
	match options.pick_random():
		"fall":
			kot.play("fall", 2.2)
			AudioManager.play_sfx("thud", -6.0)
		"dance":
			kot.play("dance", 3.0)
		"flip":
			kot.play("flip", 0.8)
			AudioManager.play_sfx("jump", -8.0)
		"tpose":
			kot.play("tpose")
			get_tree().create_timer(2.0).timeout.connect(func(): if kot.anim == "tpose": kot.play("idle"))
		"pigeon":
			pigeon.visible = true
			_pigeon_t = 0.0
			kot.play("look_up", 4.0)
			AudioManager.play_sfx("pigeon", -6.0)
		"sink":
			kot.play("sink", 3.0)
			AudioManager.play_sfx("whistle_down", -8.0)
