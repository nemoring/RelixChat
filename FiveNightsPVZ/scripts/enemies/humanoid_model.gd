class_name HumanoidModel
extends Node3D
## Процедурная фигура человека с иерархией суставов для процедурной анимации.
## Это временная процедурная модель (не финальный ассет), но с суставами:
## походка, наклон головы, протянутые руки, «неправильные» пропорции.

var hips: Node3D
var spine: Node3D
var neck: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var face: MeshInstance3D
var parts: Array[MeshInstance3D] = []

var cfg := {
	"height": 1.0, "thin": 1.0, "arm_len": 1.0, "neck_len": 1.0,
	"jacket": Color(0.2, 0.22, 0.25), "pants": Color(0.12, 0.12, 0.14), "skin": Color(0.72, 0.6, 0.52),
	"hair": Color(0.08, 0.06, 0.05), "long_hair": false, "cap": false, "faceless": false,
	"dress": false, "vest": false, "tie": false, "stripe": false,
}
var _face_mat: ShaderMaterial


func build(options := {}) -> void:
	cfg.merge(options, true)
	var h: float = cfg["height"]
	var th: float = cfg["thin"]
	var jacket := Mats.color(cfg["jacket"], 0.85)
	var pants := Mats.color(cfg["pants"], 0.85)
	var skin := Mats.color(cfg["skin"], 0.6)
	hips = _joint(self, Vector3(0, 0.95 * h, 0))
	spine = _joint(hips, Vector3(0, 0.05, 0))
	parts.append(Build.capsule(spine, 0.19 * th, 0.62 * h, Vector3(0, 0.3 * h, 0), jacket))
	if cfg["dress"]:
		var d := Build.cyl(hips, 0.24 * th, 0.75 * h, Vector3(0, -0.3 * h, 0), Mats.color(cfg["jacket"], 0.9), Vector3.ZERO, 10)
		(d.mesh as CylinderMesh).top_radius = 0.17 * th
		(d.mesh as CylinderMesh).bottom_radius = 0.3 * th
		parts.append(d)
	neck = _joint(spine, Vector3(0, 0.6 * h, 0))
	parts.append(Build.cyl(neck, 0.05, 0.14 * cfg["neck_len"], Vector3(0, 0.07 * cfg["neck_len"], 0), skin))
	head = _joint(neck, Vector3(0, 0.14 * cfg["neck_len"], 0))
	parts.append(Build.sphere(head, 0.11, Vector3(0, 0.11, 0), skin, Vector3(0.9, 1.1, 0.95)))
	if cfg["faceless"]:
		var fm := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.17, 0.21)
		fm.mesh = q
		_face_mat = ShaderMaterial.new()
		_face_mat.shader = load("res://shaders/face_blur.gdshader")
		_face_mat.set_shader_parameter("skin", cfg["skin"])
		fm.material_override = _face_mat
		fm.position = Vector3(0, 0.11, -0.101)
		fm.rotation_degrees.y = 180
		head.add_child(fm)
		face = fm
	else:
		# Глаза: тёмные точки.
		for dx in [-0.035, 0.035]:
			Build.sphere(head, 0.012, Vector3(dx, 0.13, -0.095), Mats.color(Color(0.03, 0.03, 0.03), 0.2))
	parts.append(Build.sphere(head, 0.115, Vector3(0, 0.15, 0.015), Mats.color(cfg["hair"], 0.9), Vector3(0.95, 0.75, 1.0)))
	if cfg["long_hair"]:
		parts.append(Build.box(head, Vector3(0.24, 0.6, 0.08), Vector3(0, -0.1, 0.08), Mats.color(cfg["hair"], 0.95)))
		parts.append(Build.box(head, Vector3(0.05, 0.5, 0.18), Vector3(-0.11, -0.05, -0.0), Mats.color(cfg["hair"], 0.95)))
		parts.append(Build.box(head, Vector3(0.05, 0.5, 0.18), Vector3(0.11, -0.05, -0.0), Mats.color(cfg["hair"], 0.95)))
	if cfg["cap"]:
		parts.append(Build.cyl(head, 0.12, 0.07, Vector3(0, 0.2, 0), Mats.color(cfg["jacket"], 0.8)))
		parts.append(Build.box(head, Vector3(0.18, 0.015, 0.12), Vector3(0, 0.17, -0.13), Mats.color(cfg["jacket"], 0.8)))
	if cfg["vest"]:
		parts.append(Build.box(spine, Vector3(0.36 * th, 0.4 * h, 0.05), Vector3(0, 0.32 * h, -0.17 * th), Mats.color(Color(0.95, 0.55, 0.1), 0.7)))
	if cfg["stripe"]:
		parts.append(Build.box(spine, Vector3(0.4 * th, 0.04, 0.4 * th), Vector3(0, 0.2 * h, 0), Mats.emissive(Color(0.8, 0.85, 0.6), 0.3)))
	if cfg["tie"]:
		parts.append(Build.box(spine, Vector3(0.05, 0.3 * h, 0.02), Vector3(0, 0.42 * h, -0.19 * th), Mats.color(Color(0.3, 0.05, 0.08))))
		parts.append(Build.box(spine, Vector3(0.12, 0.08, 0.06), Vector3(0.1, 0.45 * h, -0.17 * th), Mats.color(Color(0.95, 0.95, 0.95))))
	var al: float = cfg["arm_len"]
	for side in [-1, 1]:
		var sh := _joint(spine, Vector3(0.22 * th * side, 0.55 * h, 0))
		parts.append(Build.capsule(sh, 0.055, 0.32 * al, Vector3(0, -0.16 * al, 0), jacket))
		var fo := _joint(sh, Vector3(0, -0.31 * al, 0))
		parts.append(Build.capsule(fo, 0.045, 0.3 * al, Vector3(0, -0.15 * al, 0), jacket))
		parts.append(Build.sphere(fo, 0.045, Vector3(0, -0.32 * al, 0), skin, Vector3(0.8, 1.3, 0.6)))
		if side < 0:
			arm_l = sh
			fore_l = fo
		else:
			arm_r = sh
			fore_r = fo
	for side in [-1, 1]:
		var lg := _joint(hips, Vector3(0.1 * side, 0, 0))
		parts.append(Build.capsule(lg, 0.075, 0.48 * h, Vector3(0, -0.24 * h, 0), pants))
		var sn := _joint(lg, Vector3(0, -0.47 * h, 0))
		parts.append(Build.capsule(sn, 0.06, 0.46 * h, Vector3(0, -0.23 * h, 0), pants))
		parts.append(Build.box(sn, Vector3(0.1, 0.07, 0.24), Vector3(0, -0.46 * h, -0.05), Mats.color(Color(0.05, 0.05, 0.05))))
		if side < 0:
			leg_l = lg
			shin_l = sn
		else:
			leg_r = lg
			shin_r = sn


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func set_face_intensity(v: float) -> void:
	if _face_mat:
		_face_mat.set_shader_parameter("intensity", v)


## Походка. phase — фаза шага (радианы), amount 0..1, stiff — «неправильность».
func walk(phase: float, amount: float, stiff := 0.0) -> void:
	var s := sin(phase) * 0.55 * amount
	leg_l.rotation.x = s
	leg_r.rotation.x = -s
	shin_l.rotation.x = maxf(0.0, -sin(phase + 0.6)) * 0.7 * amount
	shin_r.rotation.x = maxf(0.0, sin(phase + 0.6)) * 0.7 * amount
	arm_l.rotation.x = -s * (0.7 - stiff * 0.6)
	arm_r.rotation.x = s * (0.7 - stiff * 0.6)
	hips.position.y = 0.95 * cfg["height"] + absf(cos(phase)) * 0.03 * amount
	spine.rotation.z = sin(phase) * 0.04 * amount + stiff * 0.08 * sin(phase * 0.5)


func idle(t: float, uneasy := 0.0) -> void:
	spine.rotation.x = sin(t * 1.3) * 0.015
	head.rotation.y = sin(t * 0.4) * 0.05 * uneasy
	arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, 0.1)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, 0.1)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, 0.2)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, 0.2)
	shin_l.rotation.x = lerpf(shin_l.rotation.x, 0.0, 0.2)
	shin_r.rotation.x = lerpf(shin_r.rotation.x, 0.0, 0.2)


func reach(amount: float) -> void:
	arm_l.rotation.x = -1.4 * amount
	arm_r.rotation.x = -1.5 * amount
	fore_l.rotation.x = -0.2 * amount
	fore_r.rotation.x = -0.1 * amount


func head_tilt(roll: float, pitch := 0.0) -> void:
	head.rotation.z = roll
	head.rotation.x = pitch


func set_material_all(m: Material) -> void:
	for p in parts:
		p.material_override = m
