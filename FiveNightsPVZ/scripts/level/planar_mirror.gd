class_name PlanarMirror
extends Node3D
## Настоящее плоское зеркало через SubViewport (среднее/высокое качество).
## Камера зеркала видит слой «только для камер» — в отражении можно заметить
## то, чего нет в комнате.

var size := Vector2(0.7, 0.9)
var room := ""
var _vp: SubViewport
var _cam: Camera3D
var _quad: MeshInstance3D
var _active_allowed := true
var _tick := 0


func build(s: Vector2, room_id: String) -> void:
	size = s
	room = room_id
	Build.box(self, Vector3(s.x + 0.06, s.y + 0.06, 0.015), Vector3(0, 0, -0.012), Mats.color(Color(0.5, 0.5, 0.5), 0.4, 0.6))
	_vp = SubViewport.new()
	_vp.size = Vector2i(192, int(192 * s.y / s.x))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = Build.VIS_ALL | Build.VIS_CAM_ONLY | 16
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(_cam)
	_quad = Build.quad(self, s, Vector3.ZERO, null)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _vp.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.uv1_scale = Vector3(-1, 1, 1)
	m.uv1_offset = Vector3(1, 0, 0)
	m.albedo_color = Color(0.82, 0.86, 0.86)
	_quad.material_override = m


func set_enabled_quality(q: int) -> void:
	_active_allowed = q >= 1
	if not _active_allowed:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_quad.material_override = Mats.mirror()


func _process(_d: float) -> void:
	if not _active_allowed or _vp == null:
		return
	var eye_cam := get_viewport().get_camera_3d()
	if eye_cam == null:
		return
	var n := global_basis.z.normalized()
	var c := global_position
	var e := eye_cam.global_position
	var d := (e - c).dot(n)
	if d <= 0.05 or e.distance_to(c) > 5.0:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_tick += 1
	# Обновляем через кадр — экономия на мобильных.
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _tick % 2 == 0 else SubViewport.UPDATE_DISABLED
	var reflected := e - 2.0 * d * n
	var up := Vector3.UP
	var basis := Basis.looking_at(n, up)
	_cam.global_transform = Transform3D(basis, reflected)
	var right := basis.x
	var cam_up := basis.y
	var off := Vector2((c - reflected).dot(right), (c - reflected).dot(cam_up))
	_cam.set_frustum(size.y, off, d, 30.0)
