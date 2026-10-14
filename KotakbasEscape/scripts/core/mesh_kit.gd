class_name MK
extends RefCounted
## Набор помощников для построения лёгкой low-poly геометрии из примитивов.
## Меши и материалы кэшируются и переиспользуются (меньше draw calls и памяти).

static var _mesh_cache := {}

static func mat(color: Color, unshaded := false, emission := 0.0) -> StandardMaterial3D:
	var key := "m%s_%s_%s" % [color, unshaded, emission]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mesh_cache[key] = m
	return m

static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _mesh_cache.has(key):
		var b := BoxMesh.new()
		b.size = size
		_mesh_cache[key] = b
	return _mesh_cache[key]

static func cyl_mesh(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var key := "c%s_%s_%s_%s" % [top, bottom, h, seg]
	if not _mesh_cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_mesh_cache[key] = c
	return _mesh_cache[key]

static func sphere_mesh(r: float, seg := 10, rings := 6) -> SphereMesh:
	var key := "s%s_%s_%s" % [r, seg, rings]
	if not _mesh_cache.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = seg
		s.rings = rings
		_mesh_cache[key] = s
	return _mesh_cache[key]

static func add(parent: Node, mesh: Mesh, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, unshaded := false, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, unshaded, emission)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not Settings.shadows_enabled() else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func box(parent: Node, size: Vector3, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	return add(parent, box_mesh(size), color, pos, rot)

static func cyl(parent: Node, top: float, bottom: float, h: float, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, seg := 8) -> MeshInstance3D:
	return add(parent, cyl_mesh(top, bottom, h, seg), color, pos, rot)

static func sphere(parent: Node, r: float, color: Color, pos := Vector3.ZERO, seg := 10) -> MeshInstance3D:
	return add(parent, sphere_mesh(r, seg, maxi(4, seg / 2)), color, pos)

## Статичная коллизия-коробка (упрощённые коллизии).
static func static_box(parent: Node, size: Vector3, pos: Vector3, rot := Vector3.ZERO, layer := 1) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation = rot
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	return sb

## Текстура окон панельного дома, сгенерированная в коде (без внешних файлов).
static func panel_house_texture(seed_v: int) -> ImageTexture:
	var key := "panel%d" % seed_v
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var wall := Color(0.72, 0.7, 0.66).darkened(rng.randf() * 0.15)
	img.fill(wall)
	for fy in 8:
		for fx in 4:
			var lit := rng.randf() < 0.25
			var c := Color(1.0, 0.85, 0.45) if lit else Color(0.25, 0.32, 0.4)
			var x0 := fx * 16 + 3
			var y0 := fy * 16 + 4
			for y in range(y0, y0 + 9):
				for x in range(x0, x0 + 10):
					img.set_pixel(x, y, c)
			for x in range(fx * 16, fx * 16 + 16):
				img.set_pixel(x, fy * 16, wall.darkened(0.25))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mesh_cache[key] = tex
	return tex

static func textured_mat(tex: Texture2D, uv_scale := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = uv_scale
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

## Панельный дом: коробка с текстурой окон, крыша, подъезд.
static func panel_house(parent: Node, pos: Vector3, size: Vector3, seed_v: int, rot_y := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = box_mesh(size)
	mi.material_override = textured_mat(panel_house_texture(seed_v % 4), Vector3(size.x / 12.0 * 3.0, size.y / 24.0 * 2.0, 1))
	mi.position.y = size.y * 0.5
	n.add_child(mi)
	box(n, Vector3(size.x + 0.4, 0.4, size.z + 0.4), Color(0.4, 0.38, 0.36), Vector3(0, size.y + 0.2, 0))
	return n

## Простое дерево (ствол + крона).
static func tree(parent: Node, pos: Vector3, scale_v := 1.0, pine := false) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * scale_v
	parent.add_child(n)
	cyl(n, 0.15, 0.22, 2.0, Color(0.42, 0.28, 0.16), Vector3(0, 1.0, 0), Vector3.ZERO, 6)
	if pine:
		cyl(n, 0.0, 1.3, 2.4, Color(0.13, 0.42, 0.2), Vector3(0, 2.6, 0), Vector3.ZERO, 7)
		cyl(n, 0.0, 1.0, 2.0, Color(0.15, 0.48, 0.22), Vector3(0, 3.6, 0), Vector3.ZERO, 7)
	else:
		sphere(n, 1.3, Color(0.25, 0.55, 0.22), Vector3(0, 2.8, 0), 8)
	return n
