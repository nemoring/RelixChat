class_name StoneProjectile
extends RigidBody3D
## Брошенный камень — настоящий физический объект (RigidBody3D, непрерывная
## проверка столкновений). Баллистика решается так, чтобы камень летел в точку прицела.

const SPEED := 30.0
const MAX_ACTIVE := 6
const LIFETIME := 6.0
const GRAVITY := 9.8

static var active: Array = []

var spent := false
var _life := LIFETIME
var _bounced := false
var game

func _init() -> void:
	mass = 0.6
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	collision_layer = 4
	collision_mask = 1
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.5
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.16
	cs.shape = sp
	add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshMerge.resource_mesh("stone")
	mi.material_override = MeshMerge.vertex_color_material()
	mi.position.y = -0.1
	mi.scale = Vector3.ONE * 0.7
	add_child(mi)
	body_entered.connect(_on_body_entered)

static func launch(parent: Node, from: Vector3, velocity: Vector3, g) -> StoneProjectile:
	# Ограничение количества активных снарядов: самый старый удаляется.
	active = active.filter(func(s): return is_instance_valid(s))
	while active.size() >= MAX_ACTIVE:
		var old = active.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var s := StoneProjectile.new()
	s.game = g
	parent.add_child(s)
	s.global_position = from
	s.linear_velocity = velocity
	s.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
	active.append(s)
	return s

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Попадание по животным (они не физические тела — проверяем расстояние).
	if not spent and game != null and linear_velocity.length() > 5.0:
		var c = game.creatures.target_in_front(global_position, linear_velocity.normalized(), 0.9)
		if c != null:
			c.take_damage(15.0, global_position - linear_velocity.normalized())
			spent = true

func _on_body_entered(b: Node) -> void:
	if spent:
		return
	if linear_velocity.length() > 6.0:
		AudioManager.play_sfx_3d("thud", global_position, -12.0)
	spent = true # после первого удара о землю камень больше не опасен

## Отскок от корпуса НЛО (корпус не засчитывается).
func deflect(normal: Vector3) -> void:
	if _bounced:
		return
	_bounced = true
	spent = true
	linear_velocity = linear_velocity.bounce(normal.normalized()) * 0.45
	AudioManager.play_sfx_3d("metal_hit", global_position, 0.0)

## Решение баллистики: скорость для попадания в target из from при скорости v.
## Возвращает [низкая дуга, высокая дуга] (может быть пусто, если цель вне досягаемости).
static func solve(from: Vector3, target: Vector3, v := SPEED, g := GRAVITY) -> Array:
	var d := target - from
	var flat := Vector3(d.x, 0, d.z)
	var x := flat.length()
	var y := d.y
	var dir := flat.normalized() if x > 0.001 else Vector3.FORWARD
	var v2 := v * v
	var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	if disc < 0.0:
		return []
	var root := sqrt(disc)
	var out := []
	for sgn in [-1.0, 1.0]:
		var ang := atan2(v2 + sgn * root, g * x)
		out.append(dir * cos(ang) * v + Vector3.UP * sin(ang) * v)
	return out

## Моделирование траектории до цели: "cockpit", "hull" или "miss".
## ufo_xf — глобальная трансформация наклонного корпуса НЛО.
static func predict(from: Vector3, vel: Vector3, ufo_xf: Transform3D, cockpit_c: Vector3, cockpit_r: float, hull_r: float, hull_y: float, hull_h: float, ground_y: float, g := GRAVITY) -> String:
	var p := from
	var v := vel
	var dt := 1.0 / 120.0
	var inv := ufo_xf.affine_inverse()
	for i in 600:
		v.y -= g * dt
		p += v * dt
		var lp := inv * p
		if UFOController.is_cockpit_local(lp):
			return "cockpit"
		if absf(lp.y - hull_y) < hull_h * 0.5 and Vector2(lp.x, lp.z).length() < hull_r:
			return "hull"
		if p.y < ground_y - 0.5:
			return "miss"
	return "miss"
