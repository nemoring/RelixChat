class_name KotakbasModel
extends Node3D
## Трёхмерный Котакбас из примитивов с процедурными нелепыми анимациями:
## ноги-пропеллер, сальто 720°, плоский подкат «как PNG», T-pose, танец,
## падение, провал под землю, процедурный ragdoll. Используется в меню, раннере и выживании.

signal anim_finished(name: String)

const SKIN := Color(0.96, 0.8, 0.65)
const HOODIE := Color(1.0, 0.5, 0.12)
const PANTS := Color(0.2, 0.25, 0.4)
const CAP := Color(0.16, 0.16, 0.2)
const SHOE := Color(0.95, 0.95, 0.95)

var body: Node3D        # точка вращения (центр масс) для сальто
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var flat_root: Node3D   # для «плоского» подката

var anim := "idle"
var anim_t := 0.0
var anim_len := 0.0
var run_speed := 1.0     # множитель скорости вращения ног
var leg_phase := 0.0
var flip_axis := Vector3.RIGHT
var flip_turns := 2.0
var look_target := Vector3.ZERO
var _rag_vel := Vector3.ZERO
var _rag_spin := Vector3.ZERO
var _rag_offset := Vector3.ZERO
var _base_y := 0.0

static var _mat_cache := {}

static func mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var key := str(color) + str(unshaded)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m

func _ready() -> void:
	_build()

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _build() -> void:
	flat_root = Node3D.new()
	add_child(flat_root)
	body = Node3D.new()
	body.position = Vector3(0, 0.95, 0)
	flat_root.add_child(body)
	# Туловище — оранжевая худи
	torso = Node3D.new()
	body.add_child(torso)
	var tb := BoxMesh.new()
	tb.size = Vector3(0.56, 0.62, 0.32)
	_part(torso, tb, HOODIE, Vector3(0, 0.32, 0))
	var pocket := BoxMesh.new()
	pocket.size = Vector3(0.36, 0.14, 0.02)
	_part(torso, pocket, HOODIE.darkened(0.2), Vector3(0, 0.15, -0.17))
	# Голова с шапкой и кошачьими ушами
	head = Node3D.new()
	head.position = Vector3(0, 0.66, 0)
	torso.add_child(head)
	var hs := SphereMesh.new()
	hs.radius = 0.24
	hs.height = 0.46
	hs.radial_segments = 12
	hs.rings = 6
	_part(head, hs, SKIN, Vector3(0, 0.2, 0))
	var cap := SphereMesh.new()
	cap.radius = 0.255
	cap.height = 0.3
	cap.is_hemisphere = true
	cap.radial_segments = 12
	cap.rings = 4
	_part(head, cap, CAP, Vector3(0, 0.25, 0))
	var ear := CylinderMesh.new()
	ear.top_radius = 0.0
	ear.bottom_radius = 0.09
	ear.height = 0.18
	ear.radial_segments = 4
	_part(head, ear, CAP, Vector3(-0.15, 0.48, 0), Vector3(0, 0, 0.35))
	_part(head, ear, CAP, Vector3(0.15, 0.48, 0), Vector3(0, 0, -0.35))
	var eye := SphereMesh.new()
	eye.radius = 0.06
	eye.height = 0.12
	eye.radial_segments = 8
	eye.rings = 4
	_part(head, eye, Color.WHITE, Vector3(-0.09, 0.22, -0.2))
	_part(head, eye, Color.WHITE, Vector3(0.09, 0.22, -0.2))
	var pupil := SphereMesh.new()
	pupil.radius = 0.03
	pupil.height = 0.06
	pupil.radial_segments = 6
	pupil.rings = 3
	_part(head, pupil, Color.BLACK, Vector3(-0.09, 0.22, -0.255))
	_part(head, pupil, Color.BLACK, Vector3(0.09, 0.22, -0.255))
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.12, 0.025, 0.02)
	_part(head, mouth, Color(0.4, 0.1, 0.1), Vector3(0, 0.1, -0.225))
	# Руки
	arm_l = _limb(torso, Vector3(-0.36, 0.58, 0), 0.075, 0.52, HOODIE, SKIN)
	arm_r = _limb(torso, Vector3(0.36, 0.58, 0), 0.075, 0.52, HOODIE, SKIN)
	# Ноги
	leg_l = _limb(body, Vector3(-0.14, 0.0, 0), 0.09, 0.82, PANTS, SHOE)
	leg_r = _limb(body, Vector3(0.14, 0.0, 0), 0.09, 0.82, PANTS, SHOE)

func _limb(parent: Node3D, pivot_pos: Vector3, radius: float, length: float, color: Color, tip: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 2
	_part(pivot, cm, color, Vector3(0, -length * 0.5, 0))
	var tipm := BoxMesh.new()
	tipm.size = Vector3(radius * 2.2, radius * 1.4, radius * 3.0)
	_part(pivot, tipm, tip, Vector3(0, -length + radius * 0.3, -radius * 0.6))
	return pivot

func play(name: String, length := 0.0) -> void:
	_reset_pose()
	anim = name
	anim_t = 0.0
	anim_len = length
	match name:
		"flip":
			flip_turns = 2.0 # 720°
			flip_axis = Vector3.RIGHT if randf() > 0.3 else Vector3.FORWARD # иногда боком
		"ragdoll":
			_rag_vel = Vector3(randf_range(-3, 3), 9.0, 6.0)
			_rag_spin = Vector3(randf_range(-14, 14), randf_range(-10, 10), randf_range(-14, 14))
			_rag_offset = Vector3.ZERO

func is_playing(name: String) -> bool:
	return anim == name

func _reset_pose() -> void:
	if body == null:
		return
	flat_root.scale = Vector3.ONE
	flat_root.rotation = Vector3.ZERO
	flat_root.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.position = Vector3(0, 0.95, 0)
	torso.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	arm_l.rotation = Vector3.ZERO
	arm_r.rotation = Vector3.ZERO
	leg_l.rotation = Vector3.ZERO
	leg_r.rotation = Vector3.ZERO

func _process(delta: float) -> void:
	if body == null:
		return
	anim_t += delta
	var t := anim_t
	match anim:
		"idle":
			torso.position.y = sin(t * 2.0) * 0.015
			arm_l.rotation.z = -0.08 + sin(t * 2.0) * 0.03
			arm_r.rotation.z = 0.08 - sin(t * 2.0) * 0.03
			head.rotation.y = sin(t * 0.7) * 0.2
		"walk":
			var s := sin(t * 8.0 * run_speed)
			leg_l.rotation.x = s * 0.6
			leg_r.rotation.x = -s * 0.6
			arm_l.rotation.x = -s * 0.5
			arm_r.rotation.x = s * 0.5
			body.position.y = 0.95 + absf(s) * 0.04
		"run", "boost":
			# Ноги вращаются как пропеллер, туловище почти неподвижно.
			leg_phase += delta * 22.0 * run_speed
			leg_l.rotation.x = leg_phase
			leg_r.rotation.x = leg_phase + PI
			arm_l.rotation.x = sin(leg_phase) * 0.9
			arm_r.rotation.x = -sin(leg_phase) * 0.9
			body.position.y = 0.95 + absf(sin(leg_phase)) * 0.05
			body.rotation.x = -1.25 if anim == "boost" else -0.08
		"tpose":
			leg_l.rotation = Vector3.ZERO
			leg_r.rotation = Vector3.ZERO
			arm_l.rotation.z = -PI * 0.5
			arm_r.rotation.z = PI * 0.5
			head.rotation.y = sin(t * 30.0) * 0.05 # лёгкий «глюк»
		"flip":
			var dur := anim_len if anim_len > 0.0 else 0.6
			var k := clampf(t / dur, 0.0, 1.0)
			var ang := -TAU * flip_turns * _ease(k)
			body.rotation = Vector3.ZERO
			body.rotate(flip_axis, ang)
			leg_phase += delta * 30.0
			leg_l.rotation.x = 1.2 + sin(leg_phase) * 0.4
			leg_r.rotation.x = 1.0 - sin(leg_phase) * 0.4
			arm_l.rotation.z = -2.2
			arm_r.rotation.z = 2.2
			if k >= 1.0:
				_finish()
		"slide":
			# Плоский, словно PNG, скользит по земле.
			flat_root.scale = Vector3(1.0, 1.0, 0.04)
			flat_root.rotation.x = -PI * 0.5
			flat_root.position.y = 0.06
			arm_l.rotation.z = -PI * 0.5
			arm_r.rotation.z = PI * 0.5
			flat_root.rotation.z = sin(t * 25.0) * 0.08
		"ragdoll":
			_rag_vel.y -= 25.0 * delta
			_rag_offset += _rag_vel * delta
			if _rag_offset.y < 0.0:
				_rag_offset.y = 0.0
				_rag_vel.y = absf(_rag_vel.y) * 0.4
				_rag_vel.x *= 0.6
				_rag_vel.z *= 0.6
				_rag_spin *= 0.7
			flat_root.position = _rag_offset
			body.rotation += _rag_spin * delta
			arm_l.rotation = Vector3(sin(t * 17.0) * 2.0, 0, -1.5 + sin(t * 13.0))
			arm_r.rotation = Vector3(cos(t * 15.0) * 2.0, 0, 1.5 + cos(t * 11.0))
			leg_l.rotation.x = sin(t * 19.0) * 1.5
			leg_r.rotation.x = cos(t * 21.0) * 1.5
			if anim_len > 0.0 and t >= anim_len:
				_finish()
		"dance":
			body.rotation.z = sin(t * 8.0) * 0.25
			body.position.y = 0.95 + absf(sin(t * 8.0)) * 0.12
			arm_l.rotation.z = -1.8 + sin(t * 16.0) * 0.8
			arm_r.rotation.z = 1.8 + cos(t * 16.0) * 0.8
			leg_l.rotation.z = -absf(sin(t * 8.0)) * 0.5
			leg_r.rotation.z = absf(cos(t * 8.0)) * 0.5
			head.rotation.z = sin(t * 8.0 + 1.0) * 0.35
			if anim_len > 0.0 and t >= anim_len:
				_finish()
		"fall":
			var k2 := clampf(t / 0.35, 0.0, 1.0)
			body.rotation.x = k2 * PI * 0.5
			body.position.y = 0.95 - k2 * 0.7
			arm_l.rotation.z = -2.6 * k2
			arm_r.rotation.z = 2.6 * k2
			leg_l.rotation.x = -0.4 * k2
			if t > 0.35:
				leg_l.rotation.x = -0.4 + sin(t * 20.0) * 0.3 # дрыгает ногой
			if anim_len > 0.0 and t >= anim_len:
				_finish()
		"sink":
			# Проваливается под землю и возвращается, будто текстура не прогрузилась.
			var half := (anim_len if anim_len > 0.0 else 3.0) * 0.5
			var depth := 0.0
			if t < half:
				depth = minf(t / 0.8, 1.0) * 2.2
			else:
				depth = maxf(0.0, 2.2 - (t - half) / 0.5 * 2.2)
			flat_root.position.y = -depth
			arm_l.rotation.z = -2.8
			arm_r.rotation.z = 2.8
			if anim_len > 0.0 and t >= anim_len:
				_finish()
		"look_up":
			head.rotation.x = 0.7
			if look_target != Vector3.ZERO:
				var dir := (look_target - global_position)
				head.rotation.y = clampf(atan2(-dir.x, -dir.z) - global_rotation.y, -1.2, 1.2)
			arm_r.rotation.z = 2.4
			if anim_len > 0.0 and t >= anim_len:
				_finish()
		"silly_pickup":
			body.rotation.y = t * 20.0
			arm_l.rotation.z = -2.8
			arm_r.rotation.z = 2.8
			if t >= 0.35:
				_finish()
		"attack":
			var k3 := clampf(t / 0.3, 0.0, 1.0)
			arm_r.rotation.x = -2.6 + k3 * 3.4
			torso.rotation.y = -0.4 + k3 * 0.8
			if t >= 0.3:
				_finish()
		"throw":
			var k4 := clampf(t / 0.35, 0.0, 1.0)
			arm_r.rotation.x = -2.8 + k4 * 3.6
			if t >= 0.35:
				_finish()
		"aim":
			arm_r.rotation.x = -2.8
			arm_l.rotation.x = -1.2
		"sit":
			leg_l.rotation.x = -PI * 0.5
			leg_r.rotation.x = -PI * 0.5
			body.position.y = 0.55
		"sleep":
			flat_root.rotation.z = PI * 0.5
			flat_root.position = Vector3(0.0, 0.25, 0.0)
		"stumble":
			# Спотыкается и улетает в кусты.
			var k5 := clampf(t / 0.9, 0.0, 1.0)
			body.rotation.x = -k5 * PI * 1.6
			body.position.y = 0.95 + sin(k5 * PI) * 1.2
			flat_root.position.z = -k5 * 3.5
			arm_l.rotation.z = -2.5
			arm_r.rotation.z = 2.5
			if t >= 0.9:
				_finish()

func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)

func _finish() -> void:
	var n := anim
	anim = "idle"
	_reset_pose()
	anim_finished.emit(n)
