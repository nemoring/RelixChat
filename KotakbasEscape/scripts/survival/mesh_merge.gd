class_name MeshMerge
extends RefCounted
## Склейка нескольких примитивов в один ArrayMesh с цветами вершин:
## одно дерево = один меш = один draw call в MultiMesh.

static var _cache := {}

static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		var col: Color = p[2]
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var basis := xf.basis
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((basis * n[i]).normalized())
			cols.append(col)
		for i in ind.size():
			idx.append(base + ind[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am

static func vertex_color_material() -> StandardMaterial3D:
	if _cache.has("vcmat"):
		return _cache.vcmat
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	_cache.vcmat = m
	return m

static func _cyl(top: float, bottom: float, h: float, seg := 7) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func _sph(r: float, seg := 8, rings := 5) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _t(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)

## Меши ресурсов (кэшируются).
static func resource_mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var m: ArrayMesh
	match kind:
		"tree":
			m = merge([
				[_cyl(0.18, 0.28, 3.0), _t(Vector3(0, 1.5, 0)), Color(0.42, 0.28, 0.16)],
				[_sph(1.6), _t(Vector3(0, 3.6, 0), Vector3.ZERO, Vector3(1, 0.9, 1)), Color(0.24, 0.5, 0.2)],
				[_sph(1.1), _t(Vector3(0.6, 4.4, 0.3)), Color(0.28, 0.56, 0.22)],
			])
		"pine":
			m = merge([
				[_cyl(0.15, 0.25, 2.4), _t(Vector3(0, 1.2, 0)), Color(0.4, 0.27, 0.15)],
				[_cyl(0.0, 1.6, 2.6), _t(Vector3(0, 2.8, 0)), Color(0.13, 0.38, 0.2)],
				[_cyl(0.0, 1.2, 2.2), _t(Vector3(0, 4.0, 0)), Color(0.15, 0.44, 0.22)],
				[_cyl(0.0, 0.8, 1.6), _t(Vector3(0, 5.0, 0)), Color(0.17, 0.48, 0.24)],
			])
		"dead":
			m = merge([
				[_cyl(0.12, 0.25, 3.5), _t(Vector3(0, 1.75, 0)), Color(0.35, 0.3, 0.25)],
				[_cyl(0.05, 0.1, 1.6), _t(Vector3(0.5, 3.0, 0), Vector3(0, 0, -0.9)), Color(0.35, 0.3, 0.25)],
				[_cyl(0.05, 0.1, 1.2), _t(Vector3(-0.4, 2.4, 0.2), Vector3(0.3, 0, 0.9)), Color(0.35, 0.3, 0.25)],
			])
		"rock":
			m = merge([
				[_sph(1.0, 7, 4), _t(Vector3(0, 0.45, 0), Vector3(0.2, 0.5, 0), Vector3(1.3, 0.8, 1.0)), Color(0.5, 0.5, 0.52)],
				[_sph(0.6, 6, 4), _t(Vector3(0.7, 0.3, 0.3)), Color(0.45, 0.45, 0.47)],
			])
		"bush":
			var parts := [
				[_sph(0.75, 7, 4), _t(Vector3(0, 0.55, 0)), Color(0.22, 0.48, 0.2)],
				[_sph(0.55, 7, 4), _t(Vector3(0.5, 0.45, 0.2)), Color(0.25, 0.52, 0.22)],
			]
			for k in 6:
				var a := TAU * k / 6.0
				parts.append([_sph(0.09, 5, 3), _t(Vector3(cos(a) * 0.62, 0.65 + sin(k) * 0.15, sin(a) * 0.62)), Color(0.85, 0.12, 0.25)])
			m = merge(parts)
		"stone":
			m = merge([[_sph(0.25, 6, 3), _t(Vector3(0, 0.12, 0), Vector3(0.3, 0.7, 0), Vector3(1.2, 0.7, 1.0)), Color(0.58, 0.58, 0.6)]])
		"mushroom":
			m = merge([
				[_cyl(0.06, 0.08, 0.3), _t(Vector3(0, 0.15, 0)), Color(0.95, 0.92, 0.85)],
				[_sph(0.2, 7, 3), _t(Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1, 0.55, 1)), Color(0.8, 0.2, 0.15)],
			])
		"scrap":
			m = merge([
				[_box(Vector3(1.0, 0.4, 0.7)), _t(Vector3(0, 0.2, 0), Vector3(0.1, 0.4, 0.1)), Color(0.5, 0.35, 0.25)],
				[_cyl(0.3, 0.3, 0.2), _t(Vector3(0.4, 0.45, 0.1), Vector3(0.6, 0, 0.3)), Color(0.45, 0.45, 0.5)],
				[_box(Vector3(0.2, 0.9, 0.2)), _t(Vector3(-0.3, 0.4, -0.2), Vector3(0, 0, 0.5)), Color(0.55, 0.4, 0.3)],
			])
		"reeds":
			var rp := []
			for k in 7:
				rp.append([_cyl(0.02, 0.04, 1.6), _t(Vector3(sin(k * 2.1) * 0.4, 0.8, cos(k * 1.7) * 0.4), Vector3(sin(k) * 0.15, 0, cos(k) * 0.15)), Color(0.45, 0.5, 0.25)])
			m = merge(rp)
	_cache[kind] = m
	return m
