extends Node3D
## Глава 2. «БЕГИ, КОТАКБАС!» — трёхмерный раннер с конечной целью по очкам.
## Мир движется навстречу игроку (игрок у z=0), сегменты и препятствия переиспользуются.

const LANE_X := [-2.4, 0.0, 2.4]
const SPAWN_Z := -110.0
const BASE_SPEED := 12.0
const GRAVITY := 38.0
const JUMP_V := 12.5
const SLIDE_TIME := 0.75
const LANE_SPEED := 16.0
const BUFFER_TIME := 0.25

enum State { INTRO, RUN, FINALE, CAUGHT, DONE }

var state := State.INTRO
var rng := RandomNumberGenerator.new()
var gen: RunnerGenerator

# Мир
var world: Node3D
var segments: Array[Node3D] = []
var seg_pool := {}
var rows: Array = [] # [{z, nodes:[...], hit, counted}]
var obs_pool := {}
var pickups: Array[Node3D] = []
var pick_pool: Array[Node3D] = []
var powerups: Array[Node3D] = []
var env: Environment
var sun: DirectionalLight3D

# Игрок
var player: Node3D
var model: KotakbasModel
var bike_node: Node3D
var companion: PigeonModel
var lane := 1
var py := 0.0
var vy := 0.0
var grounded := true
var slide_t := 0.0
var slide_on_land := false
var buffer: Array = [] # [{dir: Vector2i, t: float}]
var t_boost := 0.0
var t_magnet := 0.0
var t_pigeon := 0.0
var t_nokia := 0.0
var t_invuln := 0.0
var t_tpose := 0.0
var has_helmet := false
var has_bike := false
var helmet_node: Node3D

# Прогресс
var score := 0.0
var target := 5000
var lives := 3
var max_lives := 3
var combo := 0
var combo_timer := 0.0
var checkpoint := 0.0
var theme_idx := 0
var row_dist := 0.0
var speed := 0.0
var speed_mult := 1.0
var density := 0.5
var hits_taken := 0
var _intro_t := 0.0
var _finale_t := 0.0
var _bush: Node3D
var _stumbled := false
var _elapsed := 0.0

# Камера
var cam: Camera3D
var cam_roll := 0.0
var shake := 0.0

# Интерфейс
var hud: CanvasLayer
var score_label: Label
var target_label: Label
var progress: ProgressBar
var lives_label: Label
var power_label: Label
var combo_label: Label
var center_label: Label
var loc_label: Label
var hint_label: Label
var caught_panel: Control
var swipe: SwipeInput
var _pause: PauseMenu
var _pause_btn: Button

func _ready() -> void:
	rng.randomize()
	target = int(DifficultyManager.p("runner_target"))
	speed_mult = float(DifficultyManager.p("runner_speed_mult"))
	max_lives = int(DifficultyManager.p("runner_lives"))
	lives = max_lives
	var sus: int = int(GameManager.flag("suspicion", 0))
	density = minf(0.95, float(DifficultyManager.p("runner_density")) + minf(0.15, sus * 0.03))
	gen = RunnerGenerator.new(0, density)
	var saved: Dictionary = GameManager.state.get("runner", {})
	checkpoint = float(saved.get("checkpoint", 0.0))
	score = checkpoint
	theme_idx = _theme_for(score)
	_build_env()
	_build_player()
	_build_hud()
	_fill_segments()
	swipe = SwipeInput.new()
	add_child(swipe)
	swipe.swiped.connect(_on_swipe)
	GameManager.back_requested.connect(_open_pause)
	GameManager.app_paused.connect(_open_pause)
	AudioManager.play_music("runner")
	AudioManager.play_ambient("city", -14.0)
	# Последствия решений из новеллы
	has_bike = GameManager.flag("has_bicycle", false)
	bike_node.visible = has_bike
	if GameManager.flag("runner_head_start", false):
		_set_helmet(true)
	_start_intro()

func _theme_for(s: float) -> int:
	return clampi(int(s / (float(target) / 8.0)), 0, 7)

# ------------------------------------------------------------------ Построение

func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.5, 0.85)
	sm.sky_horizon_color = Color(0.8, 0.8, 0.85)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_density = 0.016
	env.fog_light_color = RunnerBuild.THEMES[theme_idx].fog
	env.fog_sky_affect = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = Settings.shadows_enabled()
	sun.directional_shadow_max_distance = 30.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	world = Node3D.new()
	add_child(world)
	cam = Camera3D.new()
	cam.fov = 68
	cam.far = 180.0
	add_child(cam)
	cam.current = true

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	model = KotakbasModel.new()
	model.rotation.y = 0.0
	player.add_child(model)
	model.anim_finished.connect(_on_anim_finished)
	bike_node = RunnerBuild.build_bicycle()
	player.add_child(bike_node)
	helmet_node = Node3D.new()
	var hm := MK.add(helmet_node, MK.sphere_mesh(0.3, 10, 6), Color(0.95, 0.75, 0.1))
	hm.scale = Vector3(1, 0.7, 1)
	helmet_node.position = Vector3(0, 0.88, 0)
	helmet_node.visible = false
	model.head.add_child(helmet_node)
	companion = PigeonModel.new()
	companion.visible = GameManager.flag("pigeon_friend", false)
	add_child(companion)

func _fill_segments() -> void:
	var z := 30.0
	while z > SPAWN_Z - 60.0:
		var s := _get_segment(theme_idx)
		s.position.z = z
		segments.append(s)
		z -= RunnerBuild.SEG_LEN

func _get_segment(theme: int) -> Node3D:
	var pool: Array = seg_pool.get(theme, [])
	var s: Node3D
	if pool.size() > 0:
		s = pool.pop_back()
		s.visible = true
	else:
		s = RunnerBuild.build_segment(theme, rng)
		world.add_child(s)
	return s

func _recycle_segment(s: Node3D) -> void:
	var th: int = s.get_meta("theme")
	s.visible = false
	if not seg_pool.has(th):
		seg_pool[th] = []
	seg_pool[th].append(s)
	# Освобождаем пулы давно пройденных локаций (экономия памяти).
	for k in seg_pool.keys():
		if int(k) < theme_idx - 1:
			for old in seg_pool[k]:
				old.queue_free()
			seg_pool.erase(k)

func _get_obstacle(kind: int) -> Node3D:
	var pool: Array = obs_pool.get(kind, [])
	var n: Node3D
	if pool.size() > 0 and rng.randf() < 0.85:
		n = pool.pop_at(rng.randi() % pool.size())
		n.visible = true
	else:
		n = RunnerBuild.build_obstacle(kind, rng)
		world.add_child(n)
	n.rotation = Vector3.ZERO
	n.set_meta("smashed", false)
	return n

func _release_obstacle(n: Node3D) -> void:
	n.visible = false
	var k: int = n.get_meta("kind")
	if not obs_pool.has(k):
		obs_pool[k] = []
	if obs_pool[k].size() < 12:
		obs_pool[k].append(n)
	else:
		n.queue_free()

func _get_pickup() -> Node3D:
	var p: Node3D
	if pick_pool.size() > 0:
		p = pick_pool.pop_back()
		p.visible = true
	else:
		p = RunnerBuild.build_pryanik()
		world.add_child(p)
	return p

func _release_pickup(p: Node3D) -> void:
	p.visible = false
	pick_pool.append(p)

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 14)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	score_label = UIStyle.make_label("0", 54, Color.WHITE, true)
	UIStyle.outline(score_label, 8)
	tl.add_child(score_label)
	target_label = UIStyle.make_label("", 22, Color(1, 1, 1, 0.9))
	UIStyle.outline(target_label, 5)
	tl.add_child(target_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(320, 18)
	progress.show_percentage = false
	tl.add_child(progress)
	lives_label = UIStyle.make_label("", 34, UIStyle.BAD)
	UIStyle.outline(lives_label, 6)
	tl.add_child(lives_label)
	power_label = UIStyle.make_label("", 22, UIStyle.ACCENT)
	UIStyle.outline(power_label, 5)
	tl.add_child(power_label)
	combo_label = UIStyle.make_label("", 28, Color(1, 0.9, 0.3), true)
	UIStyle.outline(combo_label, 6)
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	combo_label.position.y = 90
	combo_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(combo_label)
	loc_label = UIStyle.make_label("", 34, Color.WHITE, true)
	UIStyle.outline(loc_label, 8)
	loc_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	loc_label.position.y = 24
	loc_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	loc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(loc_label)
	center_label = UIStyle.make_label("", 64, UIStyle.ACCENT, true)
	UIStyle.outline(center_label, 12)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(center_label)
	hint_label = UIStyle.make_label("Свайп ← → — смена полосы · ↑ — прыжок · ↓ — подкат", 26, Color.WHITE)
	UIStyle.outline(hint_label, 6)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position.y -= 70
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_label)
	_pause_btn = UIStyle.make_button("II", Vector2(96, 96), 36)
	_pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.position = Vector2(-120, 18)
	_pause_btn.pressed.connect(_open_pause)
	root.add_child(_pause_btn)

func _show_center(text: String, time := 1.6, color: Color = UIStyle.ACCENT) -> void:
	center_label.text = text
	center_label.add_theme_color_override("font_color", color)
	center_label.modulate.a = 1.0
	center_label.pivot_offset = center_label.size * 0.5
	center_label.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(center_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(time)
	tw.tween_property(center_label, "modulate:a", 0.0, 0.4)

func _show_location() -> void:
	loc_label.text = RunnerBuild.THEMES[theme_idx].name
	loc_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(loc_label, "modulate:a", 0.0, 0.8)

func _update_hud() -> void:
	score_label.text = str(int(score))
	target_label.text = "Цель: %d · %s" % [target, RunnerBuild.THEMES[theme_idx].name]
	progress.value = clampf(score / float(target), 0.0, 1.0) * 100.0
	var hearts := ""
	for i in max_lives:
		hearts += "♥" if i < lives else "♡"
	if has_bike:
		hearts += "  +велик"
	if has_helmet:
		hearts += "  +шлем"
	lives_label.text = hearts
	var p := []
	if t_boost > 0: p.append("Кроссовки %d" % ceili(t_boost))
	if t_magnet > 0: p.append("Магнит %d" % ceili(t_magnet))
	if t_pigeon > 0: p.append("Голубь %d" % ceili(t_pigeon))
	if t_nokia > 0: p.append("Nokia %d" % ceili(t_nokia))
	power_label.text = "  ".join(p)
	combo_label.text = ("Комбо x%.1f" % _combo_mult()) if combo >= 5 else ""

# ------------------------------------------------------------------ Ввод

func _on_swipe(dir: Vector2i) -> void:
	if state != State.RUN and state != State.FINALE:
		return
	buffer.append({"dir": dir, "t": BUFFER_TIME})
	if buffer.size() > 3:
		buffer.pop_front()

func _process_buffer(delta: float) -> void:
	var i := 0
	while i < buffer.size():
		var b: Dictionary = buffer[i]
		b.t -= delta
		var done := false
		var d: Vector2i = b.dir
		if d.x != 0:
			var nl := clampi(lane + d.x, 0, 2)
			if nl != lane:
				lane = nl
				cam_roll = -d.x * 0.07
				AudioManager.play_sfx("swipe", -8.0)
				if grounded and slide_t <= 0.0 and rng.randf() < 0.3:
					t_tpose = 0.3 # иногда перемещается в T-pose
					model.play("tpose")
			done = true
		elif d.y < 0:
			if grounded:
				_jump()
				done = true
		elif d.y > 0:
			if grounded:
				_slide()
			else:
				vy = -26.0 # быстрое приземление
				slide_on_land = true
			done = true
		if done or b.t <= 0.0:
			buffer.remove_at(i)
		else:
			i += 1

func _jump() -> void:
	grounded = false
	vy = JUMP_V
	slide_t = 0.0
	AudioManager.play_sfx("jump", -4.0)
	model.play("flip", 2.0 * JUMP_V / GRAVITY)

func _slide() -> void:
	slide_t = SLIDE_TIME
	AudioManager.play_sfx("slide", -4.0)
	model.play("slide")

# ------------------------------------------------------------------ Цикл

func _start_intro() -> void:
	state = State.INTRO
	py = 14.0
	vy = 0.0
	grounded = false
	model.play("flip", 1.4)
	model.flip_turns = 3.0
	_show_location()
	_update_hud()

func _process(delta: float) -> void:
	_elapsed += delta
	match state:
		State.INTRO:
			_intro_t += delta
			if not grounded:
				vy -= GRAVITY * 0.5 * delta
				py += vy * delta
			if py <= 0.0 and not grounded:
				py = 0.0
				grounded = true
				AudioManager.play_sfx("thud")
				shake = 0.5
				GameManager.vibrate(80)
				model.play("run")
				_show_center("БЕГИ, КОТАКБАС!", 1.2)
				if GameManager.flag("start_nokia", false):
					_activate("nokia", 8.0)
			if grounded:
				speed = lerpf(speed, _target_speed(), delta * 2.0)
				_move_world(delta)
				if _intro_t > 2.6:
					state = State.RUN
		State.RUN, State.FINALE:
			_tick_run(delta)
		State.CAUGHT:
			speed = lerpf(speed, 0.0, delta * 3.0)
			_move_world(delta)
		State.DONE:
			speed = lerpf(speed, 0.0, delta * 2.5)
			_move_world(delta)
	_update_player_visual(delta)
	_update_camera(delta)
	if Engine.get_process_frames() % 6 == 0:
		_update_hud()
	if hint_label.visible and _elapsed > 9.0:
		hint_label.visible = false

func _target_speed() -> float:
	var prog := clampf(score / float(target), 0.0, 1.0)
	var s := BASE_SPEED * speed_mult * (1.0 + 0.25 * prog)
	if t_boost > 0.0:
		s *= 1.45
	return s

func _combo_mult() -> float:
	return 1.0 + minf(combo, 40) / 20.0

func _tick_run(delta: float) -> void:
	speed = lerpf(speed, _target_speed(), delta * 3.0)
	_process_buffer(delta)
	# вертикаль
	if not grounded:
		vy -= GRAVITY * delta
		py += vy * delta
		if py <= 0.0:
			py = 0.0
			vy = 0.0
			grounded = true
			if slide_on_land:
				slide_on_land = false
				_slide()
			elif model.anim != "ragdoll":
				model.play("boost" if t_boost > 0.0 else "run")
	if slide_t > 0.0:
		slide_t -= delta
		if slide_t <= 0.0 and grounded and model.anim == "slide":
			model.play("boost" if t_boost > 0.0 else "run")
	if t_tpose > 0.0:
		t_tpose -= delta
		if t_tpose <= 0.0 and model.anim == "tpose":
			model.play("run")
	# таймеры бонусов
	t_magnet = maxf(0.0, t_magnet - delta)
	t_pigeon = maxf(0.0, t_pigeon - delta)
	t_nokia = maxf(0.0, t_nokia - delta)
	t_invuln = maxf(0.0, t_invuln - delta)
	if t_boost > 0.0:
		t_boost -= delta
		if t_boost <= 0.0 and grounded and model.anim == "boost":
			model.play("run")
	combo_timer -= delta
	if combo_timer <= 0.0 and combo > 0:
		combo = maxi(0, combo - 1)
		combo_timer = 0.5
	# очки за дистанцию
	var d := speed * delta
	if state == State.RUN:
		score += d * 1.0 * (1.0 + (_combo_mult() - 1.0) * 0.5)
	_move_world(delta)
	if state == State.RUN:
		row_dist += d
		var gap := maxf(13.0, speed * 0.85) * lerpf(1.45, 0.95, density)
		if row_dist >= gap:
			row_dist = 0.0
			_spawn_row(gap)
	_check_collisions()
	_check_pickups(delta)
	# смена локации и чекпоинты
	var th := _theme_for(score)
	if th != theme_idx and state == State.RUN:
		theme_idx = th
		checkpoint = float(theme_idx) * float(target) / 8.0
		_show_location()
		GameManager.toast("Чекпоинт: %d очков" % int(checkpoint), UIStyle.GOOD, 1.5)
	if state == State.RUN and score >= target:
		_start_finale()
	if state == State.FINALE:
		_tick_finale(delta)

func _move_world(delta: float) -> void:
	var d := speed * delta
	for s in segments:
		s.position.z += d
	if segments.size() > 0 and segments[0].position.z - RunnerBuild.SEG_LEN > 12.0:
		var old: Node3D = segments.pop_front()
		_recycle_segment(old)
		var last: Node3D = segments[segments.size() - 1]
		var th := 7 if state == State.FINALE else theme_idx
		var s2 := _get_segment(th)
		s2.position.z = last.position.z - RunnerBuild.SEG_LEN
		segments.append(s2)
		# плавная смена цвета тумана по локации
		var tw := create_tween()
		tw.tween_property(env, "fog_light_color", RunnerBuild.THEMES[th].fog, 2.0)
	var i := 0
	while i < rows.size():
		var r: Dictionary = rows[i]
		r.z += d
		for n in r.nodes:
			n.position.z += d
			if n.get_meta("smashed", false):
				n.position.y += delta * 8.0
				n.rotation.x += delta * 9.0
		if r.z > 2.0 and not r.counted:
			r.counted = true
			if not r.hit and state == State.RUN:
				combo += 1
				combo_timer = 2.0
				score += 5.0 * _combo_mult() * speed_mult
		if r.z > 14.0:
			for n in r.nodes:
				_release_obstacle(n)
			rows.remove_at(i)
		else:
			i += 1
	var k := 0
	while k < pickups.size():
		var p := pickups[k]
		p.position.z += d
		p.rotation.y += delta * 4.0
		if p.position.z > 8.0:
			pickups.remove_at(k)
			_release_pickup(p)
		else:
			k += 1
	k = 0
	while k < powerups.size():
		var pu := powerups[k]
		pu.position.z += d
		pu.rotation.y += delta * 2.0
		pu.position.y = 1.2 + sin(_elapsed * 3.0) * 0.15
		if pu.position.z > 8.0:
			powerups.remove_at(k)
			pu.queue_free()
		else:
			k += 1
	# анимации препятствий (машут руками, вращаются)
	for r in rows:
		for n in r.nodes:
			for c in n.get_children():
				if c.has_meta("wave"):
					c.rotation.z = 2.6 + sin(_elapsed * 10.0) * 0.4
				elif c.has_meta("spin"):
					c.rotation.y += delta * 2.0
					c.position.y = 1.9 + sin(_elapsed * 2.0) * 0.15

func _spawn_row(gap: float) -> void:
	var prev_safe := gen.safe_lane
	var cells := gen.next_row()
	var row := {"z": SPAWN_Z, "nodes": [], "hit": false, "counted": false, "cells": cells}
	for l in 3:
		if cells[l] == RunnerGenerator.NONE:
			continue
		var n := _get_obstacle(cells[l])
		n.position = Vector3(LANE_X[l], 0, SPAWN_Z)
		n.set_meta("lane", l)
		row.nodes.append(n)
	rows.append(row)
	# Пряники ведут по безопасной полосе от прошлого ряда к текущему.
	var count := 5
	for j in count:
		var z := SPAWN_Z + gap * (0.2 + 0.6 * float(j) / float(count))
		var l2 := gen.safe_lane if j >= count / 2 else prev_safe
		var p := _get_pickup()
		p.position = Vector3(LANE_X[l2], 1.0, z)
		pickups.append(p)
	# Бонусы
	var chance := float(DifficultyManager.p("runner_bonus_chance"))
	if rng.randf() < chance * 0.45:
		var kinds := RunnerBuild.POWERUPS.duplicate()
		if GameManager.flag("pigeon_follows", false) or GameManager.flag("pigeon_friend", false):
			kinds.append("pigeon")
		var kind: String = kinds.pick_random()
		var pu := RunnerBuild.build_powerup(kind)
		world.add_child(pu)
		pu.position = Vector3(LANE_X[rng.randi() % 3], 1.2, SPAWN_Z + gap * 0.5)
		powerups.append(pu)

func _player_x() -> float:
	return player.position.x

func _is_invulnerable() -> bool:
	return t_nokia > 0.0 or t_boost > 0.0 or t_invuln > 0.0 or state == State.FINALE

func _check_collisions() -> void:
	var px := _player_x()
	for r in rows:
		if absf(r.z) > 4.5:
			continue
		for n in r.nodes:
			if n.get_meta("smashed", false):
				continue
			var half_len: float = float(n.get_meta("len")) * 0.5
			if absf(n.position.z) > half_len + 0.4:
				continue
			if absf(px - n.position.x) > 1.3:
				continue
			var kind: int = n.get_meta("kind")
			var hit := false
			match kind:
				RunnerGenerator.BLOCK:
					hit = true
				RunnerGenerator.LOW:
					hit = py < (0.08 if n.get_meta("pit") else 0.85)
				RunnerGenerator.HIGH:
					hit = slide_t <= 0.0
			if not hit:
				continue
			if t_boost > 0.0 or t_nokia > 0.0:
				# Ускорение/Nokia — препятствие отлетает
				n.set_meta("smashed", true)
				AudioManager.play_sfx("boing", -4.0)
				score += 15.0 * speed_mult
				continue
			if _is_invulnerable():
				continue
			r.hit = true
			n.set_meta("smashed", true)
			_on_hit()
			return

func _on_hit() -> void:
	combo = 0
	shake = 1.0
	GameManager.vibrate(160)
	_slowmo(0.35, 0.3)
	t_invuln = 1.6
	hits_taken += 1
	if has_bike:
		has_bike = false
		bike_node.visible = false
		AudioManager.play_sfx("crash")
		GameManager.toast("Велосипед принял удар на себя!", UIStyle.ACCENT, 1.5)
	elif has_helmet:
		_set_helmet(false)
		AudioManager.play_sfx("helmet_break")
		GameManager.toast("Шлем спас!", UIStyle.ACCENT, 1.5)
	else:
		lives -= 1
		AudioManager.play_sfx("crash")
	model.play("ragdoll", 0.9)
	slide_t = 0.0
	if lives <= 0:
		_caught()

func _on_anim_finished(n: String) -> void:
	if state == State.DONE:
		return
	if n == "ragdoll" or n == "flip" or n == "silly_pickup":
		if grounded and slide_t <= 0.0:
			model.play("boost" if t_boost > 0.0 else "run")
		elif not grounded:
			model.play("flip", 0.5)

func _check_pickups(delta: float) -> void:
	var ppos := Vector3(_player_x(), py + 0.9, 0)
	var k := 0
	while k < pickups.size():
		var p := pickups[k]
		var collected := false
		var d := p.position - ppos
		if t_magnet > 0.0 and d.length() < 9.0 and p.position.z > -9.0:
			p.position = p.position.move_toward(ppos, delta * 30.0)
			d = p.position - ppos
		if absf(d.x) < 0.9 and absf(d.z) < 0.9 and absf(d.y) < 1.3:
			collected = true
		elif t_pigeon > 0.0 and absf(p.position.z) < 1.0:
			collected = true # голубь собирает со всех полос
		if collected:
			pickups.remove_at(k)
			_release_pickup(p)
			combo += 1
			combo_timer = 2.0
			score += 10.0 * speed_mult * _combo_mult()
			AudioManager.play_sfx("coin", -8.0, 1.0 + minf(combo, 20) * 0.02, 0.0)
		else:
			k += 1
	k = 0
	while k < powerups.size():
		var pu := powerups[k]
		var d2 := pu.position - ppos
		if absf(d2.x) < 1.0 and absf(d2.z) < 1.0 and absf(d2.y) < 1.5:
			powerups.remove_at(k)
			var kind: String = pu.get_meta("power")
			pu.queue_free()
			_activate(kind)
		else:
			k += 1

func _activate(kind: String, dur := -1.0) -> void:
	AudioManager.play_sfx("nokia" if kind == "nokia" else "powerup")
	GameManager.toast(RunnerBuild.POWERUP_NAMES.get(kind, kind), UIStyle.ACCENT, 1.3)
	if grounded and slide_t <= 0.0:
		model.play("silly_pickup") # короткая нелепая анимация
	match kind:
		"sneakers":
			t_boost = 5.0 if dur < 0 else dur
			if grounded:
				model.play("boost")
		"helmet":
			_set_helmet(true)
		"pigeon":
			t_pigeon = 10.0 if dur < 0 else dur
			companion.visible = true
		"magnet":
			t_magnet = 10.0 if dur < 0 else dur
		"nokia":
			t_nokia = 7.0 if dur < 0 else dur

func _set_helmet(on: bool) -> void:
	has_helmet = on
	helmet_node.visible = on

func _slowmo(scale_v: float, duration: float) -> void:
	Engine.time_scale = scale_v
	get_tree().create_timer(duration, true, false, true).timeout.connect(func():
		if state != State.DONE:
			Engine.time_scale = 1.0)

# ------------------------------------------------------------------ Визуал

func _update_player_visual(delta: float) -> void:
	var tx: float = LANE_X[lane]
	player.position.x = move_toward(player.position.x, tx, LANE_SPEED * delta)
	player.position.y = py
	model.run_speed = speed / 12.0
	bike_node.visible = has_bike and state != State.DONE
	model.position.y = 0.35 if (has_bike and model.anim in ["run", "boost"]) else 0.0
	# мигание после удара
	model.visible = not (t_invuln > 0.0 and int(_elapsed * 14.0) % 2 == 0) or state != State.RUN
	if t_nokia > 0.0:
		model.flat_root.rotation.y = sin(_elapsed * 30.0) * 0.1
	if companion.visible:
		var target_pos := player.position + Vector3(1.2, 2.4 + sin(_elapsed * 3.0) * 0.3, -0.8)
		if t_pigeon > 0.0:
			target_pos = Vector3(sin(_elapsed * 6.0) * 2.6, 1.6, -1.5)
		companion.position = companion.position.lerp(target_pos, delta * 6.0)
		companion.rotation.y = 0.0

func _update_camera(delta: float) -> void:
	var px := player.position.x
	var desired := Vector3(px * 0.65, 3.4 + py * 0.25, 6.2)
	if state == State.INTRO and not grounded:
		desired = Vector3(3.5, 3.0 + py * 0.5, 7.0)
	cam.position = cam.position.lerp(desired, minf(1.0, delta * 6.0))
	var look := Vector3(px * 0.8, 1.0 + py * 0.3, -8.0)
	cam.look_at(look)
	cam_roll = lerpf(cam_roll, 0.0, delta * 5.0)
	cam.rotation.z += cam_roll
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.5)
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25
	var fov_target := 68.0 + (12.0 if t_boost > 0.0 else 0.0) + speed * 0.12
	cam.fov = lerpf(cam.fov, fov_target, delta * 3.0)

# ------------------------------------------------------------------ Финал и поражение

func _start_finale() -> void:
	state = State.FINALE
	_finale_t = 0.0
	AudioManager.play_sfx("fanfare")
	_show_center("ПОБЕГ ПОЧТИ ЗАВЕРШЁН", 2.2, UIStyle.GOOD)
	GameManager.unlock_achievement("runner_done")
	if hits_taken == 0:
		GameManager.unlock_achievement("no_hit")

func _tick_finale(delta: float) -> void:
	_finale_t += delta
	if _finale_t > 3.0 and _bush == null:
		_bush = Node3D.new()
		world.add_child(_bush)
		for l in 3:
			var b := RunnerBuild.build_bush()
			b.position.x = LANE_X[l]
			_bush.add_child(b)
		_bush.position = Vector3(0, 0, -70.0)
	if _bush:
		_bush.position.z += speed * delta
		if _bush.position.z > -2.5 and not _stumbled:
			_stumbled = true
			state = State.DONE
			model.play("stumble")
			AudioManager.play_sfx("fall")
			_slowmo(0.4, 0.8)
			_show_center("", 0.1)
			get_tree().create_timer(1.6, true, false, true).timeout.connect(_finish_runner)

func _finish_runner() -> void:
	Engine.time_scale = 1.0
	AudioManager.play_sfx("thud")
	shake = 1.2
	GameManager.state.runner = {"done": true, "checkpoint": 0.0}
	GameManager.state.survival = {}
	GameManager.start_chapter("survival")

func _caught() -> void:
	state = State.CAUGHT
	AudioManager.play_sfx("alert")
	_show_center("ТЦК ПОЙМАЛО КОТАКБАСА!", 99.0, UIStyle.BAD)
	center_label.offset_bottom = -200
	GameManager.state.runner = {"checkpoint": checkpoint}
	await get_tree().create_timer(1.2, true, false, true).timeout
	Engine.time_scale = 1.0
	caught_panel = PanelContainer.new()
	caught_panel.anchor_left = 0.5
	caught_panel.anchor_right = 0.5
	caught_panel.anchor_top = 0.5
	caught_panel.anchor_bottom = 0.5
	caught_panel.offset_left = -300
	caught_panel.offset_right = 300
	caught_panel.offset_top = 40
	caught_panel.grow_vertical = Control.GROW_DIRECTION_END
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	caught_panel.add_child(vb)
	var info := UIStyle.make_label("Котакбас вырвался в последний момент... Попробуем ещё раз с чекпоинта: %d очков" % int(checkpoint), 22)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 560
	vb.add_child(info)
	var retry := UIStyle.make_button("Попробовать снова", Vector2(560, 88))
	retry.pressed.connect(func():
		AudioManager.play_sfx("click")
		GameManager.state.chapter = "runner"
		SceneManager.change_scene(GameManager.SCENES.runner))
	vb.add_child(retry)
	var menu := UIStyle.make_button("В главное меню", Vector2(560, 80))
	menu.pressed.connect(func():
		GameManager.autosave()
		GameManager.go_to_menu())
	vb.add_child(menu)
	hud.get_child(0).add_child(caught_panel)
	GameManager.autosave()

# ------------------------------------------------------------------ Сохранение / пауза

func save_state() -> Dictionary:
	return {"checkpoint": checkpoint}

func _open_pause() -> void:
	if is_instance_valid(_pause) or state == State.DONE or SceneManager.is_busy():
		return
	_pause = PauseMenu.new()
	if GameManager.debug_enabled:
		_pause.extra_buttons = [
			["[Отладка] +1000 очков", func(): score += 1000.0],
			["[Отладка] Завершить раннер", func():
				score = target
				_pause.close()],
		]
	hud.add_child(_pause)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
