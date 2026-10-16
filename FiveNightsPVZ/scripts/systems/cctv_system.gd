class_name CCTVSystem
extends Node
## Видеонаблюдение: 8 камер, одна SubViewport-камера рендерит реальную сцену
## с выбранной точки. Помехи, ночное видение, потеря сигнала, «устаревшее»
## изображение (застывший кадр с отстающими часами) и запись событий.

signal feed_changed(index)

var world
var viewport: SubViewport
var cam: Camera3D
var active := false
var current := 0
var night_vision := false
var material: ShaderMaterial
var stale := false            # показывается застывший кадр
var stale_texture: ImageTexture
var stale_clock := ""
var signal_lost := {}         # index -> seconds left
var recordings: Array = []    # [{cam, time, image}]
var rng := RandomNumberGenerator.new()
var _stale_t := 0.0
var _distort := 0.0
var _switch_noise := 0.0


func setup(w) -> void:
	world = w
	rng.seed = GameState.run_seed ^ 0xcc
	viewport = SubViewport.new()
	var res: Vector2i = [Vector2i(320, 180), Vector2i(480, 270), Vector2i(640, 360)][clampi(GameState.quality(), 0, 2)]
	viewport.size = res
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.positional_shadow_atlas_size = 1024
	add_child(viewport)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.far = 30.0
	cam.cull_mask = Build.VIS_ALL | Build.VIS_CAM_ONLY | 16
	viewport.add_child(cam)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/cctv.gdshader")
	# Экран в мире показывает то же изображение.
	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_texture = viewport.get_texture()
	screen_mat.emission_enabled = true
	screen_mat.emission_texture = viewport.get_texture()
	screen_mat.emission_energy_multiplier = 0.8
	screen_mat.albedo_color = Color(0.6, 0.7, 0.6)
	world.level.cctv_screen.material_override = screen_mat
	if world.night_index < 4 and not GameState.is_custom_night:
		signal_lost[7] = 99999.0  # техническая: «нет сигнала» до 4-й ночи


func texture() -> Texture2D:
	if stale and stale_texture:
		return stale_texture
	return viewport.get_texture()


func set_active(v: bool) -> void:
	active = v
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED
	if v:
		switch_to(current)
		Sfx.play_ui("static", -22.0)


func switch_to(i: int) -> void:
	current = clampi(i, 0, Level.CAMERAS.size() - 1)
	var m: Node3D = world.level.cam_mount_nodes[current]
	cam.global_transform = m.global_transform
	cam.position += -m.global_basis.z * 0.15
	stale = false
	_switch_noise = 0.35
	# Позднее изображение: камера может «зависнуть» на старом кадре.
	if world.night_index >= 3 and rng.randf() < 0.12 + world.night_index * 0.02:
		_schedule_stale()
	Sfx.play_ui("click", -16.0, 0.8)
	feed_changed.emit(current)


func _schedule_stale() -> void:
	_stale_t = 0.6


func _process(delta: float) -> void:
	for k in signal_lost.keys():
		signal_lost[k] -= delta
		if signal_lost[k] <= 0.0:
			signal_lost.erase(k)
	if not active:
		return
	if _stale_t > 0.0:
		_stale_t -= delta
		if _stale_t <= 0.0:
			var img := viewport.get_texture().get_image()
			if img:
				stale_texture = ImageTexture.create_from_image(img)
				stale = true
				stale_clock = world.night.clock_text(-rng.randf_range(20, 70))
	_switch_noise = maxf(0.0, _switch_noise - delta)
	_distort = move_toward(_distort, world.director.tension * 0.4 if world.night_index >= 2 else 0.0, delta * 0.5)
	material.set_shader_parameter("noise_amount", 0.08 + _switch_noise * 1.5 + (0.05 if night_vision else 0.0))
	material.set_shader_parameter("night_vision", 1.0 if night_vision else 0.0)
	material.set_shader_parameter("distortion", _distort + (0.6 if stale else 0.0) * 0.3)
	material.set_shader_parameter("signal_loss", 1.0 if signal_lost.has(current) else 0.0)
	material.set_shader_parameter("entity_static", entity_static(current))
	material.set_shader_parameter("brightness", 1.6 if night_vision else 1.1)


## Сущности, невидимые для камер, дают рябь, когда находятся в кадре.
func entity_static(i: int) -> float:
	var m: Node3D = world.level.cam_mount_nodes[i]
	var v := 0.0
	for e in world.entities.values():
		var ent := e as Entity
		if not ent.visible or ent.vis_layers != Build.VIS_EYES_ONLY:
			continue
		var to := ent.global_position + Vector3.UP - m.global_position
		if (-m.global_basis.z).angle_to(to.normalized()) < deg_to_rad(40.0) and to.length() < 14.0:
			v = maxf(v, 0.5 - to.length() * 0.02)
	return v


func clock_for_feed() -> String:
	return stale_clock if stale else world.night.clock_text()


func lose_signal(i: int, seconds: float) -> void:
	signal_lost[i] = seconds


func record() -> void:
	var img := viewport.get_texture().get_image()
	if img == null:
		return
	img.resize(160, 90)
	recordings.append({"cam": Level.CAMERAS[current]["title"], "time": clock_for_feed(), "image": ImageTexture.create_from_image(img)})
	if recordings.size() > 12:
		recordings.pop_front()
	Sfx.play_ui("beep", -14.0, 1.5)
