class_name UFOController
extends Node3D
## Летающая тарелка ТЦК: прилетает издалека, делает круг над базой, зависает,
## включает луч и крадёт ресурсы. Кабина — отдельная зона попадания (Area3D +
## CollisionShape3D). После половины урона — дым, красные огни, ускорение,
## отключения луча. После последнего попадания — искры, вращение, бегство.

signal left(defeated: bool)
signal phase_changed(phase: String)

enum S { APPROACH, CIRCLE, DESCEND, BEAM, ESCAPE, DEFEATED, GONE }

const HULL_R := 8.0
const HULL_Y := -0.1
const HULL_H := 1.3
const COCKPIT_C := Vector3(0, 1.0, 0)
const COCKPIT_R := 3.4
const HOVER_H := 9.0
const HULL_TOP := HULL_Y + HULL_H * 0.5
## Точка прицеливания — центр видимой части купола.
const AIM_LOCAL := Vector3(0, 1.8, 0)

## Попадание засчитывается только в видимый стеклянный купол над корпусом.
static func is_cockpit_local(lp: Vector3) -> bool:
	return lp.distance_to(COCKPIT_C) < COCKPIT_R + 0.15 and lp.y > HULL_TOP - 0.05

var state := S.APPROACH
var game
var base := Vector3.ZERO
var health: UFOHealth
var stealer: UFOResourceStealing
var final_raid := false
var beam_time_left := 140.0
var speed_mult := 1.0
var _t := 0.0
var _phase_t := 0.0
var _circle_a := 0.0
var _approach_from := Vector3.ZERO
var _drift_a := 0.0
var _beam_flicker := 0.0
var _beam_on := false
var _spin := 0.0
var _escape_dir := Vector3.FORWARD
var velocity := Vector3.ZERO
var _wobble := 0.0
var _last_pos := Vector3.ZERO

# Визуал
var tilt: Node3D
var ring: Node3D
var lamps: Array[MeshInstance3D] = []
var beam: MeshInstance3D
var beam_mat: ShaderMaterial
var engine_glow: MeshInstance3D
var smoke: CPUParticles3D
var sparks: CPUParticles3D
var cockpit_area: Area3D
var hull_area: Area3D
var hum: AudioStreamPlayer3D
var beam_snd: AudioStreamPlayer3D
var pigeon: PigeonModel
var _pigeon_on := false
var _lamp_red := false

func setup(g, base_pos: Vector3, saved := {}) -> void:
	game = g
	base = base_pos
	speed_mult = float(DifficultyManager.p("ufo_speed"))
	beam_time_left = float(DifficultyManager.p("ufo_beam_time"))
	health = UFOHealth.new()
	health.name = "UFOHealth"
	add_child(health)
	health.setup(int(saved.get("hits", 0)))
	health.hit.connect(_on_hit)
	health.destroyed.connect(_on_destroyed)
	stealer = UFOResourceStealing.new()
	stealer.name = "UFOResourceStealing"
	add_child(stealer)
	stealer.setup(g, self, saved.get("stealer", {}))
	_build()
	if saved.has("state"):
		# Восстановление налёта из сохранения: сразу зависаем над базой.
		final_raid = saved.get("final", false)
		beam_time_left = float(saved.get("beam_left", beam_time_left))
		global_position = base + Vector3(0, HOVER_H, 0)
		_set_state(S.BEAM)
		stealer.begin()
		if health.ratio() <= 0.5:
			_damaged_fx(true)
	else:
		var a := randf() * TAU
		_approach_from = base + Vector3(cos(a) * 190.0, 60.0, sin(a) * 190.0)
		global_position = _approach_from
		_set_state(S.APPROACH)

func _build() -> void:
	tilt = Node3D.new()
	add_child(tilt)
	var metal := Color(0.62, 0.66, 0.72)
	var hull := MK.add(tilt, MK.cyl_mesh(6.6, 8.0, 1.0, 24), metal, Vector3(0, 0, 0))
	hull.material_override = _metal_mat(metal)
	var rim := MK.add(tilt, MK.cyl_mesh(8.3, 8.3, 0.35, 24), metal.darkened(0.25), Vector3(0, -0.1, 0))
	rim.material_override = _metal_mat(metal.darkened(0.25))
	var belly := MK.add(tilt, MK.sphere_mesh(4.6, 16, 6), metal.darkened(0.15), Vector3(0, -0.5, 0))
	belly.scale = Vector3(1, 0.3, 1)
	belly.material_override = _metal_mat(metal.darkened(0.15))
	engine_glow = MK.add(tilt, MK.cyl_mesh(2.2, 1.6, 0.4, 16), Color(0.3, 1.0, 0.8), Vector3(0, -1.35, 0), Vector3.ZERO, true)
	# Кабина — большая стеклянная полусфера
	var dome := MK.add(tilt, MK.sphere_mesh(3.0, 16, 8), Color(0.45, 0.85, 1.0, 0.45), COCKPIT_C - Vector3(0, 0.4, 0))
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.45, 0.85, 1.0, 0.42)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.metallic = 0.3
	dm.roughness = 0.1
	dm.emission_enabled = true
	dm.emission = Color(0.2, 0.5, 0.7)
	dm.emission_energy_multiplier = 0.4
	dome.material_override = dm
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Пилот ТЦК внутри кабины (в фуражке)
	var pilot := Node3D.new()
	pilot.position = COCKPIT_C + Vector3(0, -0.2, 0)
	tilt.add_child(pilot)
	MK.box(pilot, Vector3(0.9, 0.9, 0.6), Color(0.38, 0.45, 0.32), Vector3(0, 0, 0))
	MK.sphere(pilot, 0.42, Color(0.6, 0.9, 0.5), Vector3(0, 0.8, 0), 8)
	MK.box(pilot, Vector3(1.0, 0.14, 1.0), Color(0.3, 0.38, 0.26), Vector3(0, 1.2, 0))
	MK.box(pilot, Vector3(0.6, 0.12, 0.1), Color(0.05, 0.05, 0.05), Vector3(0, 0.85, -0.38))
	# Антенна с мигающим шариком
	MK.cyl(tilt, 0.05, 0.05, 1.2, Color(0.7, 0.7, 0.7), COCKPIT_C + Vector3(0, 3.0, 0))
	lamps.append(MK.add(tilt, MK.sphere_mesh(0.22, 8, 4), Color(1, 0.2, 0.2), COCKPIT_C + Vector3(0, 3.7, 0), Vector3.ZERO, true, 3.0))
	# Вращающееся кольцо с лампами
	ring = Node3D.new()
	tilt.add_child(ring)
	var lamp_count := 10 if Settings.effects_enabled() else 6
	for i in lamp_count:
		var a := TAU * i / lamp_count
		var l := MK.add(ring, MK.sphere_mesh(0.3, 6, 4), Color(1.0, 0.85, 0.2), Vector3(cos(a) * 7.6, -0.3, sin(a) * 7.6), Vector3.ZERO, true)
		lamps.append(l)
		MK.box(ring, Vector3(0.8, 0.18, 0.5), metal.darkened(0.4), Vector3(cos(a) * 6.2, 0.55, sin(a) * 6.2), Vector3(0, -a, 0))
	# Надпись «ТЦК» на корпусе — со всех сторон и снизу
	for i in 4:
		var a2 := TAU * i / 4.0
		var lbl := Label3D.new()
		lbl.text = "ТЦК"
		lbl.font = UIStyle.title_font()
		lbl.font_size = 160
		lbl.outline_size = 24
		lbl.pixel_size = 0.012
		lbl.modulate = Color(0.95, 0.1, 0.1)
		lbl.outline_modulate = Color(1, 1, 1)
		lbl.position = Vector3(sin(a2) * 8.5, 0.1, cos(a2) * 8.5)
		lbl.rotation.y = a2
		lbl.double_sided = false
		tilt.add_child(lbl)
	var under := Label3D.new()
	under.text = "ТЦК"
	under.font = UIStyle.title_font()
	under.font_size = 256
	under.outline_size = 32
	under.pixel_size = 0.018
	under.modulate = Color(1, 0.15, 0.1)
	under.outline_modulate = Color.WHITE
	under.position = Vector3(0, -2.0, 0)
	under.rotation.x = PI * 0.5
	tilt.add_child(under)
	# Зоны попадания: кабина и корпус — разные CollisionShape3D
	cockpit_area = Area3D.new()
	cockpit_area.collision_layer = 8
	cockpit_area.collision_mask = 4
	cockpit_area.set_meta("ufo_cockpit", true)
	var ccs := CollisionShape3D.new()
	var csph := SphereShape3D.new()
	csph.radius = COCKPIT_R
	ccs.shape = csph
	ccs.position = COCKPIT_C
	cockpit_area.add_child(ccs)
	tilt.add_child(cockpit_area)
	cockpit_area.body_entered.connect(_on_stone_entered)
	hull_area = Area3D.new()
	hull_area.collision_layer = 8
	hull_area.collision_mask = 4
	hull_area.set_meta("ufo_hull", true)
	var hcs := CollisionShape3D.new()
	var hcyl := CylinderShape3D.new()
	hcyl.radius = HULL_R
	hcyl.height = HULL_H
	hcs.shape = hcyl
	hcs.position = Vector3(0, HULL_Y, 0)
	hull_area.add_child(hcs)
	tilt.add_child(hull_area)
	hull_area.body_entered.connect(_on_stone_entered)
	# Луч захвата (не наклоняется вместе с корпусом)
	beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 2.0
	bm.bottom_radius = 6.5
	bm.height = 1.0
	bm.radial_segments = 20
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/ufo_beam.gdshader")
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	add_child(beam)
	if Settings.effects_enabled():
		var light := OmniLight3D.new()
		light.light_color = Color(0.4, 1.0, 0.7)
		light.omni_range = 16.0
		light.light_energy = 1.5
		light.position.y = -3.0
		light.shadow_enabled = false
		add_child(light)
	# Дым и искры (ограниченное количество частиц)
	smoke = CPUParticles3D.new()
	smoke.amount = maxi(6, int(24 * Settings.particle_scale()))
	smoke.lifetime = 2.5
	smoke.direction = Vector3.UP
	smoke.spread = 25.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 4.0
	smoke.gravity = Vector3(0, 1.0, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.5
	smoke.mesh = MK.sphere_mesh(0.5, 6, 3)
	smoke.material_override = MK.mat(Color(0.25, 0.25, 0.25, 0.6), true)
	smoke.position = Vector3(3.0, 0.6, 1.0)
	smoke.emitting = false
	tilt.add_child(smoke)
	sparks = CPUParticles3D.new()
	sparks.amount = maxi(8, int(40 * Settings.particle_scale()))
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.3
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 12.0
	sparks.mesh = MK.box_mesh(Vector3(0.08, 0.08, 0.3))
	sparks.material_override = MK.mat(Color(1.0, 0.85, 0.3), true)
	sparks.position = COCKPIT_C
	sparks.emitting = false
	tilt.add_child(sparks)
	hum = AudioManager.make_loop_player_3d("ufo_hum", self, 2.0, 160.0)
	hum.play()
	beam_snd = AudioManager.make_loop_player_3d("beam", self, -2.0, 90.0)
	pigeon = PigeonModel.new()
	pigeon.visible = false
	pigeon.flapping = false
	pigeon.position = COCKPIT_C + Vector3(0.4, 3.05, 0)
	pigeon.scale = Vector3.ONE * 1.6
	tilt.add_child(pigeon)

func _metal_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.7 if Settings.quality() >= Settings.Quality.MEDIUM else 0.0
	m.roughness = 0.35
	return m

func _set_state(s: int) -> void:
	state = s
	_phase_t = 0.0
	var names := ["approach", "circle", "descend", "beam", "escape", "defeated", "gone"]
	phase_changed.emit(names[s])

func is_active_threat() -> bool:
	return state in [S.APPROACH, S.CIRCLE, S.DESCEND, S.BEAM]

func ground_y() -> float:
	return base.y

func _process(delta: float) -> void:
	if game == null or game.is_paused_gameplay():
		return
	_t += delta
	_phase_t += delta
	if delta > 0.0:
		velocity = velocity.lerp((global_position - _last_pos) / delta, 0.3)
	_last_pos = global_position
	ring.rotation.y += delta * (1.2 + (1.0 - health.ratio()) * 3.0)
	_animate_lamps()
	engine_glow.scale = Vector3.ONE * (1.0 + sin(_t * 8.0) * 0.08)
	var spd := 30.0 * speed_mult
	match state:
		S.APPROACH:
			var target := base + Vector3(22.0, 26.0, 0.0)
			global_position = global_position.move_toward(target, spd * delta)
			_face_motion(target, delta)
			if global_position.distance_to(target) < 1.0:
				_circle_a = 0.0
				_set_state(S.CIRCLE)
		S.CIRCLE:
			_circle_a += delta * TAU / (9.0 / speed_mult)
			global_position = base + Vector3(cos(_circle_a) * 22.0, 26.0 - _circle_a * 0.6, sin(_circle_a) * 22.0)
			tilt.rotation = Vector3(0, 0, -0.25)
			rotation.y = -_circle_a
			if _circle_a >= TAU:
				_set_state(S.DESCEND)
		S.DESCEND:
			var hover := base + Vector3(0, HOVER_H, 0)
			global_position = global_position.move_toward(hover, 8.0 * delta)
			_tilt_to_player(delta, 0.3)
			if global_position.distance_to(hover) < 0.3:
				_set_state(S.BEAM)
				stealer.begin()
				AudioManager.play_sfx("alert")
		S.BEAM:
			_tick_beam(delta)
		S.ESCAPE:
			_set_beam(false)
			global_position += (_escape_dir * 45.0 + Vector3.UP * 18.0) * delta * speed_mult
			_tilt_to_player(delta, 0.0)
			if _phase_t > 6.0:
				_finish(false)
		S.DEFEATED:
			_set_beam(false)
			_spin += delta * 9.0
			rotation.y = _spin
			tilt.rotation.z = sin(_t * 7.0) * 0.5
			var zig := Vector3(sin(_t * 5.0) * 10.0, 0, 0)
			global_position += (_escape_dir * 55.0 + Vector3.UP * (10.0 + _phase_t * 4.0) + zig) * delta
			if _phase_t > 5.0:
				_finish(true)

func _tick_beam(delta: float) -> void:
	var damaged := health.ratio() <= 0.5
	var hover := base + Vector3(0, HOVER_H, 0)
	# Покачивание после первых попаданий, после половины урона — быстрее и с дрейфом.
	var sway := (1.0 - health.ratio()) * 0.9 + 0.15
	# После половины урона тарелка двигается быстрее, но остаётся досягаемой.
	_drift_a += delta * (0.55 if damaged else 0.3) * speed_mult
	var drift_r := 4.0 if damaged else 1.2
	var target := hover + Vector3(cos(_drift_a) * drift_r, sin(_t * 1.7) * sway, sin(_drift_a) * drift_r)
	global_position = global_position.lerp(target, delta * 2.0)
	_tilt_to_player(delta, 0.5)
	# Ограниченное покачивание (не накапливается): сильнее после попаданий.
	_wobble = maxf(0.0, _wobble - delta * 0.6)
	tilt.rotation.z = sin(_t * 6.0) * sway * 0.08 + sin(_t * 15.0) * _wobble
	# Луч периодически отключается при повреждении
	var on := true
	if damaged:
		_beam_flicker -= delta
		if _beam_flicker <= 0.0:
			_beam_flicker = randf_range(1.5, 3.5)
		on = _beam_flicker > 1.0
	_set_beam(on)
	beam_time_left -= delta
	stealer.tick(delta, on, Vector3(global_position.x, base.y, global_position.z))
	if beam_time_left <= 0.0 or stealer.budget_exhausted():
		_start_escape()
	# Голубь иногда садится на НЛО
	if not _pigeon_on and _phase_t > 20.0 and randf() < delta * 0.02 * float(DifficultyManager.p("event_rate")):
		_pigeon_on = true
		pigeon.visible = true
		game.subtitle("Голубь сел на НЛО и смотрит на пилота ТЦК с осуждением.")
		AudioManager.play_sfx_3d("pigeon", global_position)

func _face_motion(target: Vector3, delta: float) -> void:
	var d := target - global_position
	if d.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), delta * 2.0)
	tilt.rotation = tilt.rotation.lerp(Vector3(-0.15, 0, 0), delta * 2.0)

## Наклон корпуса к игроку: кабина «выглядывает» — так в неё удобнее попасть.
func _tilt_to_player(delta: float, amount: float) -> void:
	var p: Vector3 = game.player.global_position
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.5:
		return
	var yaw := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, delta * 2.5)
	# Наклон «носом» к игроку (ось X корпуса): верх поворачивается к игроку.
	tilt.rotation.x = lerpf(tilt.rotation.x, -amount, delta * 2.0)
	if state != S.BEAM:
		tilt.rotation.z = lerpf(tilt.rotation.z, 0.0, delta * 2.0)

func _set_beam(on: bool) -> void:
	if on == _beam_on:
		if on:
			var h := maxf(1.0, global_position.y - base.y - 1.0)
			beam.scale = Vector3(1, h, 1)
			beam.global_position = Vector3(global_position.x, base.y + h * 0.5, global_position.z)
			beam.global_rotation = Vector3.ZERO
			beam_mat.set_shader_parameter("intensity", 0.8 + sin(_t * 12.0) * 0.2)
		return
	_beam_on = on
	beam.visible = on
	if on:
		beam_snd.play()
	else:
		beam_snd.stop()

func is_beam_on() -> bool:
	return _beam_on

func _animate_lamps() -> void:
	var damaged := health.ratio() <= 0.5 and state == S.BEAM
	for i in lamps.size():
		var on := int(_t * (8.0 if damaged else 3.0) + i) % 2 == 0
		var col := Color(1, 0.1, 0.1) if (damaged or i == 0) else Color(1.0, 0.85, 0.2)
		lamps[i].material_override = MK.mat(col if on else col.darkened(0.7), true, 3.0 if on else 0.0)

func _on_stone_entered(body: Node) -> void:
	if not (body is StoneProjectile):
		return
	var stone := body as StoneProjectile
	if stone.spent or state in [S.DEFEATED, S.ESCAPE, S.GONE]:
		return
	var lp := tilt.global_transform.affine_inverse() * stone.global_position
	if is_cockpit_local(lp):
		stone.spent = true
		stone.linear_velocity = -stone.linear_velocity * 0.3
		health.register_hit()
	else:
		var n := (stone.global_position - tilt.to_global(Vector3(0, HULL_Y, 0)))
		n = tilt.global_transform.basis.y if absf(lp.y - HULL_Y) > 0.3 else n
		stone.deflect(n)
		game.on_ufo_hull_hit()

func _on_hit(left_hits: int, max_hits: int) -> void:
	# Случайный нелепый звук при попадании в кабину
	if randf() < 0.35:
		AudioManager.play_sfx_3d(["silly_1", "silly_2", "silly_3", "silly_4"].pick_random(), global_position, 4.0)
	else:
		AudioManager.play_sfx_3d("cockpit_hit", global_position, 4.0)
	sparks.emitting = true
	get_tree().create_timer(0.3).timeout.connect(func(): if is_instance_valid(sparks): sparks.emitting = false)
	_wobble = minf(0.3, _wobble + 0.15)
	GameManager.vibrate(60)
	if left_hits <= max_hits / 2:
		_damaged_fx(true)
	game.on_ufo_hit(left_hits, max_hits)

func _damaged_fx(on: bool) -> void:
	if Settings.effects_enabled():
		smoke.emitting = on

func _on_destroyed() -> void:
	_set_state(S.DEFEATED)
	_set_beam(false)
	sparks.emitting = true
	smoke.emitting = true
	hum.pitch_scale = 1.6
	AudioManager.play_sfx("ufo_retreat")
	AudioManager.play_sfx("silly_3")
	_escape_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	stealer.drop_loot_on_defeat()

func _start_escape() -> void:
	if state != S.BEAM:
		return
	_set_state(S.ESCAPE)
	_escape_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	AudioManager.play_sfx("whoosh")

## Принудительное завершение (например, при выходе).
func _finish(defeated: bool) -> void:
	if state == S.GONE:
		return
	_set_state(S.GONE)
	if is_instance_valid(beam_snd):
		beam_snd.stop()
	left.emit(defeated)
	queue_free()

func save_data() -> Dictionary:
	return {
		"state": state,
		"hits": health.hits,
		"beam_left": beam_time_left,
		"base": [base.x, base.y, base.z],
		"final": final_raid,
		"stealer": stealer.save_data(),
	}

## Точка прицеливания для подсказок (центр кабины в мировых координатах).
func cockpit_global() -> Vector3:
	return tilt.to_global(AIM_LOCAL)
