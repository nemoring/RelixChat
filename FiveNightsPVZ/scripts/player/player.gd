class_name Player
extends CharacterBody3D
## Игрок: ходьба, приседание, бег, фонарик с зарядом, взаимодействие,
## переноска коробок, укрытия, «прислушаться», работа за компьютером.

signal seated_changed(is_seated)
signal flashlight_changed(on)

const WALK := 2.2
const SPRINT := 3.7
const CROUCH := 1.1
const EYE := 1.62
const EYE_CROUCH := 1.0
const REACH := 2.3

var head: Node3D
var cam: Camera3D
var flashlight: SpotLight3D
var hold_point: Node3D
var body_model: Node3D

var controls_locked := false
var seated := false
var crouching := false
var listening := false
var hiding_in: HideSpot = null
var held_item: CarryBox = null
var flashlight_on := false
var battery := 100.0
var focus: Interactable = null
var focus_prompt := ""
var current_room := "workstation"
var noise_level := 0.0
var touch_move := Vector2.ZERO
var touch_sprint := false
var _touch_look := Vector2.ZERO
var _pitch := 0.0
var _step_acc := 0.0
var _bob_t := 0.0
var _seat_return: Transform3D
var _stand_cam_pos := Vector3.ZERO
var _fl_flicker := 0.0
var external_shake := 0.0


func _ready() -> void:
	collision_layer = Build.LAYER_PLAYER
	collision_mask = Build.LAYER_WORLD
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	cs.name = "Shape"
	add_child(cs)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	cam = Camera3D.new()
	cam.current = true
	cam.near = 0.04
	cam.far = 60.0
	cam.cull_mask = Build.VIS_ALL | Build.VIS_EYES_ONLY
	head.add_child(cam)
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.15, -0.12, 0.0)
	flashlight.spot_range = 14.0
	flashlight.spot_angle = 26.0
	flashlight.spot_angle_attenuation = 1.6
	flashlight.light_energy = 2.6
	flashlight.light_color = Color(1.0, 0.94, 0.82)
	flashlight.visible = false
	flashlight.shadow_bias = 0.05
	cam.add_child(flashlight)
	hold_point = Node3D.new()
	hold_point.position = Vector3(0.0, -0.38, -0.62)
	cam.add_child(hold_point)
	_build_body()
	apply_settings()
	GameState.settings_changed.connect(apply_settings)


## Простое тело — видно в зеркале и на камерах, но не из глаз игрока.
func _build_body() -> void:
	body_model = Node3D.new()
	add_child(body_model)
	var jacket := Mats.color(Color(0.15, 0.2, 0.17), 0.8)
	Build.capsule(body_model, 0.2, 0.75, Vector3(0, 1.2, 0), jacket)
	Build.sphere(body_model, 0.11, Vector3(0, 1.66, 0), Mats.color(Color(0.75, 0.6, 0.5), 0.6))
	Build.capsule(body_model, 0.08, 0.85, Vector3(-0.1, 0.43, 0), Mats.color(Color(0.1, 0.1, 0.12)))
	Build.capsule(body_model, 0.08, 0.85, Vector3(0.1, 0.43, 0), Mats.color(Color(0.1, 0.1, 0.12)))
	Build.box(body_model, Vector3(0.3, 0.2, 0.02), Vector3(0, 1.25, -0.2), Mats.color(Color(0.9, 0.5, 0.1)))  # бейдж-жилет
	Build.set_visual_layers(body_model, 16)


func apply_settings() -> void:
	cam.fov = float(GameState.settings.get("fov", 72.0))
	flashlight.shadow_enabled = GameState.quality() >= 1


# ------------------------------------------------------------------ Ввод

func _unhandled_input(event: InputEvent) -> void:
	if controls_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not seated:
		var sens: float = GameState.settings.get("mouse_sens", 0.25) * 0.01
		_rotate_view(-event.relative.x * sens, -event.relative.y * sens)
	if seated:
		return
	if event.is_action_pressed("interact"):
		try_interact()
	elif event.is_action_pressed("flashlight"):
		toggle_flashlight()
	elif event.is_action_pressed("drop"):
		drop_item()
	elif event.is_action_pressed("crouch"):
		if hiding_in == null:
			crouching = not crouching


func add_touch_look(delta: Vector2) -> void:
	_touch_look += delta


func _rotate_view(yaw: float, pitch: float) -> void:
	if GameState.settings.get("invert_y", false):
		pitch = -pitch
	rotate_y(yaw)
	_pitch = clampf(_pitch + pitch, deg_to_rad(-80), deg_to_rad(80))
	if hiding_in:
		_pitch = clampf(_pitch, deg_to_rad(-30), deg_to_rad(30))
	head.rotation.x = _pitch


# ------------------------------------------------------------------ Движение

func _physics_process(delta: float) -> void:
	if _touch_look != Vector2.ZERO:
		var ts: float = GameState.settings.get("touch_sens", 0.35) * 0.01
		if not controls_locked and not seated:
			_rotate_view(-_touch_look.x * ts, -_touch_look.y * ts)
		_touch_look = Vector2.ZERO
	_update_flashlight(delta)
	if controls_locked or seated or hiding_in:
		velocity = Vector3.ZERO
		noise_level = move_toward(noise_level, 0.0, delta * 2.0)
		_update_focus()
		return
	var want_listen := Input.is_action_pressed("listen") or _touch_listen
	if want_listen != listening:
		listening = want_listen
		GameState.set_listening(listening)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.05:
		input = touch_move
	var sprint := (Input.is_action_pressed("sprint") or touch_sprint) and not crouching and input.y < 0.0 and held_item == null
	var speed := CROUCH if crouching else (SPRINT if sprint else WALK)
	if listening:
		speed *= 0.35
	if held_item:
		speed *= 0.85
	var dir := (global_basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	var target_eye := EYE_CROUCH if crouching else EYE
	head.position.y = lerpf(head.position.y, target_eye, delta * 8.0)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	# Шум игрока для ИИ.
	var target_noise := 0.0
	if hspeed > 0.1:
		target_noise = 0.12 if crouching else (0.85 if sprint else 0.35)
	noise_level = move_toward(noise_level, target_noise, delta * 3.0)
	# Шаги и покачивание.
	if hspeed > 0.1:
		_step_acc += hspeed * delta
		var stride := 0.55 if crouching else (0.85 if sprint else 0.7)
		if _step_acc >= stride:
			_step_acc = 0.0
			_footstep(sprint)
		if GameState.settings.get("head_bob", true):
			_bob_t += delta * hspeed * 4.2
			cam.position.y = sin(_bob_t) * 0.025 * (hspeed / WALK)
			cam.position.x = cos(_bob_t * 0.5) * 0.015 * (hspeed / WALK)
	else:
		cam.position = cam.position.lerp(Vector3.ZERO, delta * 6.0)
	if external_shake > 0.0:
		external_shake = maxf(0.0, external_shake - delta)
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * external_shake * 0.03
	current_room = Level.room_at(global_position)
	_update_focus()


var _touch_listen := false


func set_touch_listen(v: bool) -> void:
	_touch_listen = v


func _footstep(sprint: bool) -> void:
	var sound := "step_soft" if crouching else "step"
	var pitch := 1.0
	match current_room:
		"warehouse", "tech":
			pitch = 0.9
		"corridor", "utility":
			pitch = 0.8
		"toilet", "hall", "workstation", "vestibule":
			pitch = 1.15
	var vol := -14.0 if crouching else (-4.0 if sprint else -9.0)
	Sfx.play_3d(sound, global_position + Vector3.UP * 0.05, vol, pitch * randf_range(0.92, 1.08), 18.0)
	if GameWorld.instance:
		GameWorld.instance.emit_noise(global_position, 0.1 if crouching else (0.8 if sprint else 0.3), "player")


# ------------------------------------------------------------------ Взаимодействие

func _update_focus() -> void:
	focus = null
	focus_prompt = ""
	if controls_locked or seated:
		return
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var to := from - cam.global_basis.z * REACH
	var exclude: Array[RID] = [get_rid()]
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to, Build.LAYER_INTERACT | Build.LAYER_WORLD, exclude)
		var r := space.intersect_ray(q)
		if r.is_empty():
			return
		var col: Object = r.collider
		if col is Interactable:
			var ia := col as Interactable
			if hiding_in and ia != hiding_in:
				exclude.append(ia.get_rid())
				continue
			var p := ia.prompt(self)
			if p != "":
				focus = ia
				focus_prompt = p
				return
			exclude.append(ia.get_rid())
		else:
			return
	if hiding_in:
		focus = hiding_in
		focus_prompt = hiding_in.prompt(self)


func try_interact() -> void:
	if controls_locked:
		return
	if hiding_in and focus == null:
		leave_hide()
		return
	if focus:
		focus.interact(self)


func pick_up(box: CarryBox) -> void:
	if held_item:
		return
	held_item = box
	box.held = true
	box.collision_layer = 0
	if box.get_parent() is DropSpot:
		(box.get_parent() as DropSpot).take_out(box)
	box.reparent(hold_point, false)
	box.position = Vector3(0, -box.dims.y * 0.5, 0)
	box.rotation = Vector3.ZERO
	if GameWorld.instance:
		GameWorld.instance.on_item_picked(box)


func release_item() -> CarryBox:
	var b := held_item
	if b == null:
		return null
	held_item = null
	b.held = false
	b.collision_layer = Build.LAYER_INTERACT
	return b


func drop_item() -> void:
	if held_item == null or hiding_in:
		return
	var b := release_item()
	var level := GameWorld.instance.level if GameWorld.instance else get_parent()
	b.reparent(level, true)
	var fwd := -global_basis.z
	var pos := global_position + fwd * 0.6
	# Не ставим коробку в стену.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, pos + Vector3.UP * 0.5, Build.LAYER_WORLD, [get_rid()])
	var r := space.intersect_ray(q)
	if not r.is_empty():
		pos = global_position + fwd * 0.2
	b.global_position = Vector3(pos.x, 0.0, pos.z)
	b.global_rotation = Vector3(0, global_rotation.y, 0)
	Sfx.play_3d("thud", b.global_position, -14.0, 1.6)
	if GameWorld.instance:
		GameWorld.instance.emit_noise(b.global_position, 0.4, "drop")


# ------------------------------------------------------------------ Фонарик

func toggle_flashlight() -> void:
	if battery <= 0.5 and not flashlight_on:
		Sfx.play_ui("click", -10.0, 0.7)
		if GameWorld.instance:
			GameWorld.instance.hud_message("Фонарик разряжен. Зарядка — у рабочего места.")
		return
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	Sfx.play_ui("click", -12.0, 1.4)
	flashlight_changed.emit(flashlight_on)


func _update_flashlight(delta: float) -> void:
	if flashlight_on:
		battery = maxf(0.0, battery - delta * 0.45)
		if battery <= 0.0:
			flashlight_on = false
			flashlight.visible = false
			flashlight_changed.emit(false)
		elif battery < 15.0 and GameState.settings.get("flicker", true):
			_fl_flicker -= delta
			if _fl_flicker <= 0.0:
				_fl_flicker = randf_range(0.05, 0.6)
				flashlight.light_energy = 2.6 * randf_range(0.2, 1.0)
		else:
			flashlight.light_energy = 2.6
	elif seated or current_room == "workstation":
		battery = minf(100.0, battery + delta * (2.0 if seated else 0.6))


# ------------------------------------------------------------------ Компьютер и укрытия

func sit(seat_pos: Vector3, look_target: Vector3) -> void:
	if seated:
		return
	if held_item:
		drop_item()
	seated = true
	crouching = false
	_seat_return = global_transform
	global_position = seat_pos
	look_at(Vector3(look_target.x, global_position.y, look_target.z), Vector3.UP)
	head.position.y = 1.22
	_pitch = deg_to_rad(-12)
	head.rotation.x = _pitch
	seated_changed.emit(true)


func stand() -> void:
	if not seated:
		return
	seated = false
	head.position.y = EYE
	_pitch = 0.0
	head.rotation.x = 0.0
	seated_changed.emit(false)


func enter_hide(spot: HideSpot) -> void:
	if held_item:
		drop_item()
	hiding_in = spot
	spot.occupied = true
	crouching = false
	var vp := spot.view_point.global_transform
	global_position = vp.origin - Vector3.UP * 1.0
	global_rotation = Vector3(0, vp.basis.get_euler().y, 0)
	head.position.y = 1.0
	$Shape.disabled = true
	_pitch = 0.0
	head.rotation.x = 0.0
	Sfx.play_3d("cloth", global_position + Vector3.UP, -8.0)
	if GameWorld.instance:
		GameWorld.instance.emit_noise(global_position, 0.25, "hide")


func leave_hide() -> void:
	if hiding_in == null:
		return
	var spot := hiding_in
	hiding_in = null
	spot.occupied = false
	global_position = spot.exit_point.global_position
	$Shape.disabled = false
	head.position.y = EYE
	Sfx.play_3d("cloth", global_position + Vector3.UP, -8.0)


func is_hidden() -> bool:
	return hiding_in != null


# ------------------------------------------------------------------ Восприятие

## Смотрит ли игрок на точку (в пределах угла и без преград).
func is_looking_at(point: Vector3, max_angle_deg := 30.0, check_los := true) -> bool:
	var to := point - cam.global_position
	if to.length() < 0.01:
		return true
	var ang := rad_to_deg((-cam.global_basis.z).angle_to(to.normalized()))
	if ang > max_angle_deg:
		return false
	if not check_los:
		return true
	return has_los(point)


func has_los(point: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, point, Build.LAYER_WORLD, [get_rid()])
	return space.intersect_ray(q).is_empty()


## Видна ли точка в кадре (поле зрения камеры) — для «движения на периферии».
func in_view(point: Vector3) -> bool:
	return cam.is_position_in_frustum(point) and has_los(point)


func eye_pos() -> Vector3:
	return cam.global_position


func view_yaw() -> float:
	return global_rotation.y
