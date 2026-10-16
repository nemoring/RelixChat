class_name Build
extends RefCounted
## Небольшие помощники для процедурного построения геометрии.

const LAYER_WORLD := 1
const LAYER_INTERACT := 8
const LAYER_PLAYER := 2
const LAYER_ENTITY := 4

## Визуальные слои: 1 — всё, 2 — видно только на камерах, 3 — только глазами.
const VIS_ALL := 1
const VIS_CAM_ONLY := 2
const VIS_EYES_ONLY := 4


static func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide := false, rot_deg := Vector3.ZERO, cast_shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		add_box_collider(mi, size)
	return mi


static func add_box_collider(mi: Node3D, size: Vector3, layer := LAYER_WORLD) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	mi.add_child(sb)
	return sb


static func cyl(parent: Node, radius: float, height: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, sides := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func capsule(parent: Node, radius: float, height: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(height, radius * 2.0)
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, mat: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func quad(parent: Node, size: Vector2, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, size := 0.03, color := Color(0.1, 0.1, 0.1), rot_deg := Vector3.ZERO, width := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size / 32.0 * 1.0
	l.font_size = 32
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = rot_deg
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = width / l.pixel_size
	parent.add_child(l)
	return l


static func set_visual_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		set_visual_layers(c, layers)


static func set_shadows(node: Node, on: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		set_shadows(c, on)
