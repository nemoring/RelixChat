class_name SurvivalPlayer
extends CharacterBody3D
## Игрок выживания: вид от первого лица с переключением на третье,
## ходьба/бег/присед/прыжок, плавание вброд, выносливость, удары.

const WALK := 4.4
const RUN := 7.2
const CROUCH := 2.3
const JUMP_V := 5.4
const GRAVITY := 15.0

var head: Node3D
var cam_fp: Camera3D
var arm: SpringArm3D
var cam_tp: Camera3D
var model: KotakbasModel
var collider: CollisionShape3D
var third_person := false
var crouching := false
var yaw := 0.0
var pitch := 0.0
var input_move := Vector2.ZERO
var running := false
var in_water := false
var frozen := false
var stats: SurvivalStats
var _step_t := 0.0
var _capsule: CapsuleShape3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.4
	collider = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.38
	_capsule.height = 1.8
	collider.shape = _capsule
	collider.position.y = 0.9
	add_child(collider)
	model = KotakbasModel.new()
	model.rotation.y = PI
	add_child(model)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	cam_fp = Camera3D.new()
	cam_fp.fov = 72
	cam_fp.near = 0.08
	cam_fp.far = Settings.view_distance() + 40.0
	head.add_child(cam_fp)
	arm = SpringArm3D.new()
	arm.spring_length = 4.2
	arm.collision_mask = 1
	arm.position = Vector3(0.6, 0.15, 0)
	var sp := SphereShape3D.new()
	sp.radius = 0.25
	arm.shape = sp
	head.add_child(arm)
	cam_tp = Camera3D.new()
	cam_tp.fov = 70
	cam_tp.far = cam_fp.far
	arm.add_child(cam_tp)
	set_third_person(false)

func set_third_person(on: bool) -> void:
	third_person = on
	model.visible = on
	if on:
		cam_tp.current = true
	else:
		cam_fp.current = true

func active_camera() -> Camera3D:
	return cam_tp if third_person else cam_fp

func look(delta_px: Vector2) -> void:
	var sens := 0.0042 * float(Settings.get_value("cam_sens", 1.0))
	var inv := -1.0 if Settings.get_value("invert_y", false) else 1.0
	yaw -= delta_px.x * sens
	pitch = clampf(pitch - delta_px.y * sens * inv, -1.45, 1.35)
	rotation.y = yaw
	head.rotation.x = pitch

func forward() -> Vector3:
	return -global_transform.basis.z

func set_crouch(on: bool) -> void:
	crouching = on
	_capsule.height = 1.2 if on else 1.8
	collider.position.y = 0.6 if on else 0.9
	head.position.y = 1.05 if on else 1.62

func try_jump() -> bool:
	if frozen:
		return false
	if is_on_floor() and stats.stamina >= 8.0:
		velocity.y = JUMP_V
		stats.stamina -= 8.0
		if crouching:
			set_crouch(false)
		model.play("flip", 0.6) # да, Котакбас прыгает только сальто
		AudioManager.play_sfx("jump", -12.0)
		return true
	return false

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if not frozen:
		var basis := global_transform.basis
		dir = (basis.x * input_move.x + basis.z * input_move.y)
		dir.y = 0.0
		if dir.length() > 1.0:
			dir = dir.normalized()
	running = input_move.length() > 0.88 and stats.stamina > 3.0 and not crouching
	var spd := CROUCH if crouching else (RUN if running else WALK)
	in_water = global_position.y < SurvivalTerrain.WATER_LEVEL - 0.35
	if in_water:
		spd *= 0.55
	var target_v := dir * spd
	var accel := 12.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, target_v.x, accel * spd * delta)
	velocity.z = move_toward(velocity.z, target_v.z, accel * spd * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if in_water and global_position.y < SurvivalTerrain.WATER_LEVEL - 1.25:
		velocity.y = maxf(velocity.y, 1.5) # не тонем — Котакбас плавает как топор, но держится
	move_and_slide()
	# Выносливость
	if running and dir.length() > 0.1:
		stats.stamina = maxf(0.0, stats.stamina - 11.0 * delta)
	else:
		stats.stamina = minf(100.0, stats.stamina + 9.0 * delta)
	# Анимации модели (видны в третьем лице)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if model.anim in ["idle", "walk", "run"]:
		var want := "idle"
		if moving:
			want = "run" if running else "walk"
		if model.anim != want:
			model.play(want)
		model.run_speed = 0.6 if want == "run" else 1.0
	if moving and is_on_floor():
		_step_t -= delta * (1.6 if running else 1.0)
		if _step_t <= 0.0:
			_step_t = 0.42
			AudioManager.play_sfx("splash" if in_water else "step", -18.0 if not in_water else -14.0, 1.0, 0.15)
	# Наклон камеры при беге — лёгкое покачивание
	if not third_person:
		cam_fp.position.y = sin(Time.get_ticks_msec() * 0.012) * 0.03 if moving else 0.0
