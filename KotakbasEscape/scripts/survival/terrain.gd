class_name SurvivalTerrain
extends Node3D
## Открытый мир 512×512 м: детерминированный рельеф (лес, болото, река, деревня,
## завод, пещера, холмы, поляна), подгрузка участков (чанков) вокруг игрока,
## ресурсы через MultiMesh, упрощённые коллизии, вырубка и восстановление ресурсов.

const CHUNK := 32.0
const CELLS := 16
const STEP := CHUNK / CELLS
const HALF := 256.0
const WATER_LEVEL := -0.6
const SEED := 4242

# Регионы: центр, радиус, целевая высота выравнивания
const REGIONS := {
	"clearing": {"c": Vector2(0, 40), "r": 26.0, "h": 1.0, "name": "Поляна"},
	"village": {"c": Vector2(-130, -100), "r": 46.0, "h": 1.5, "name": "Заброшенная деревня"},
	"factory": {"c": Vector2(185, -60), "r": 46.0, "h": 1.2, "name": "Старый завод"},
	"swamp": {"c": Vector2(-140, 120), "r": 62.0, "h": -0.85, "name": "Болото"},
	"radio": {"c": Vector2(30, -200), "r": 24.0, "h": 21.0, "name": "Радиостанция на холме"},
	"cave": {"c": Vector2(150, -178), "r": 26.0, "h": 12.0, "name": "Пещера"},
}

const RES_INFO := {
	"tree": {"hp": 4, "drop": {"wood": 4}, "collide": 0.35},
	"pine": {"hp": 4, "drop": {"wood": 4}, "collide": 0.3},
	"dead": {"hp": 3, "drop": {"wood": 3}, "collide": 0.3},
	"rock": {"hp": 4, "drop": {"stone": 4}, "collide": 1.0},
	"bush": {"hp": 1, "drop": {"berries": 3}, "collide": 0.0},
	"stone": {"hp": 1, "drop": {"stone": 1}, "collide": 0.0},
	"mushroom": {"hp": 1, "drop": {"mushroom": 1}, "collide": 0.0},
	"scrap": {"hp": 2, "drop": {"scrap": 2}, "collide": 0.0},
	"reeds": {"hp": 1, "drop": {"fabric": 1}, "collide": 0.0},
}
const RESPAWN_MIN := {
	"tree": 4320.0, "pine": 4320.0, "dead": 4320.0, "rock": 2880.0,
	"bush": 1440.0, "stone": 600.0, "mushroom": 1440.0, "scrap": 2880.0, "reeds": 1440.0,
}

var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var noise3 := FastNoiseLite.new()
var chunks := {} # Vector2i -> Dictionary
var harvested := {} # "cx,cz,i" -> время восстановления (игровые минуты)
var radius := 2
var res_mult := 1.0
var time_source: Callable = func(): return 0.0
var _queue: Array[Vector2i] = []
var _center := Vector2i(9999, 9999)
var _terrain_mat: StandardMaterial3D
var _respawn_check := 0.0

func _ready() -> void:
	noise.seed = SEED
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	noise2.seed = SEED + 1
	noise2.frequency = 0.004
	noise3.seed = SEED + 2
	noise3.frequency = 0.03
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.roughness = 1.0
	radius = 1 if Settings.quality() == Settings.Quality.MINIMAL else (2 if Settings.quality() < Settings.Quality.HIGH else 3)
	res_mult = float(DifficultyManager.p("res_mult"))

# ------------------------------------------------------------------ Рельеф

static func smooth(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x) if e0 < e1 else 1.0 - smoothstep(e1, e0, x)

func river_x(z: float) -> float:
	return 110.0 + sin(z * 0.018) * 14.0

## «Сырая» высота в точке (используется для вершин сетки).
func raw_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 3.5 + noise2.get_noise_2d(x, z) * 5.0 + 1.5
	var hill_k := smooth(-95.0, -175.0, z)
	h += hill_k * (13.0 + noise3.get_noise_2d(x, z) * 7.0)
	var dr := absf(x - river_x(z))
	if dr < 18.0:
		h = lerpf(h, -2.6, smooth(18.0, 6.0, dr))
	for key in REGIONS:
		var r: Dictionary = REGIONS[key]
		var d := Vector2(x, z).distance_to(r.c)
		if d < r.r:
			var target: float = r.h
			if key == "swamp":
				target += noise3.get_noise_2d(x * 2.0, z * 2.0) * 0.9
			h = lerpf(h, target, smooth(r.r, r.r * 0.55, d))
	var edge := maxf(absf(x), absf(z))
	h += smooth(222.0, 252.0, edge) * 32.0
	return h

## Высота поверхности с билинейной интерполяцией по сетке (совпадает с мешем).
func height(x: float, z: float) -> float:
	var gx := floorf(x / STEP) * STEP
	var gz := floorf(z / STEP) * STEP
	var fx := (x - gx) / STEP
	var fz := (z - gz) / STEP
	var h00 := raw_height(gx, gz)
	var h10 := raw_height(gx + STEP, gz)
	var h01 := raw_height(gx, gz + STEP)
	var h11 := raw_height(gx + STEP, gz + STEP)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

func region_at(x: float, z: float) -> String:
	for key in REGIONS:
		var r: Dictionary = REGIONS[key]
		if Vector2(x, z).distance_to(r.c) < r.r * 0.9:
			return key
	if absf(x - river_x(z)) < 16.0:
		return "river"
	if z < -120.0:
		return "hills"
	return "forest"

func region_name(x: float, z: float) -> String:
	var r := region_at(x, z)
	if REGIONS.has(r):
		return REGIONS[r].name
	return {"river": "Река", "hills": "Холмы", "forest": "Лес"}.get(r, "Лес")

func is_water(x: float, z: float) -> bool:
	return height(x, z) < WATER_LEVEL - 0.1

func _vertex_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := noise3.get_noise_2d(x * 3.0, z * 3.0) * 0.06
	var c := Color(0.27 + n, 0.43 + n, 0.19)
	var reg := region_at(x, z)
	match reg:
		"clearing": c = Color(0.4 + n, 0.6 + n, 0.25)
		"swamp": c = Color(0.3 + n, 0.33 + n, 0.17)
		"village": c = Color(0.42 + n, 0.38 + n, 0.26)
		"factory": c = Color(0.38 + n, 0.37 + n, 0.34)
		"radio", "cave": c = Color(0.42 + n, 0.42 + n, 0.38)
	if h < WATER_LEVEL + 0.4:
		c = Color(0.55 + n, 0.5 + n, 0.36)
	if h < WATER_LEVEL - 0.6:
		c = Color(0.25, 0.24, 0.2)
	if slope > 0.55 or (reg == "hills" and h > 18.0):
		c = c.lerp(Color(0.5, 0.5, 0.5), clampf((slope - 0.4) * 2.0, 0.3, 0.8))
	return c

# ------------------------------------------------------------------ Чанки

func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))

func in_world(c: Vector2i) -> bool:
	var lim := int(HALF / CHUNK)
	return c.x >= -lim and c.x < lim and c.y >= -lim and c.y < lim

## Синхронная загрузка вокруг точки (при старте, чтобы игрок не провалился).
func load_around_now(p: Vector3) -> void:
	_center = chunk_of(p)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := _center + Vector2i(dx, dz)
			if in_world(c) and not chunks.has(c):
				_build_chunk(c)

func update_around(p: Vector3) -> void:
	var c := chunk_of(p)
	if c != _center:
		_center = c
		_queue.clear()
		var want := {}
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cc := c + Vector2i(dx, dz)
				if in_world(cc):
					want[cc] = true
					if not chunks.has(cc):
						_queue.append(cc)
		_queue.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
		for k in chunks.keys():
			if not want.has(k) and maxi(absi(k.x - c.x), absi(k.y - c.y)) > radius + 1:
				_unload_chunk(k)

func _process(delta: float) -> void:
	# Не больше одного чанка за кадр — без фризов.
	if _queue.size() > 0:
		var c: Vector2i = _queue.pop_front()
		if not chunks.has(c):
			_build_chunk(c)
	_respawn_check += delta
	if _respawn_check > 20.0:
		_respawn_check = 0.0
		_check_respawns()

func _unload_chunk(c: Vector2i) -> void:
	var ch: Dictionary = chunks[c]
	ch.node.queue_free()
	chunks.erase(c)

func _build_chunk(c: Vector2i) -> void:
	var node := Node3D.new()
	node.position = Vector3(c.x * CHUNK, 0, c.y * CHUNK)
	add_child(node)
	var ox := c.x * CHUNK
	var oz := c.y * CHUNK
	var n := CELLS + 1
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = raw_height(ox + i * STEP, oz + j * STEP)
	# Меш
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var h := hs[j * n + i]
			var hx := hs[j * n + mini(i + 1, n - 1)] - hs[j * n + maxi(i - 1, 0)]
			var hz := hs[mini(j + 1, n - 1) * n + i] - hs[maxi(j - 1, 0) * n + i]
			var slope := Vector2(hx, hz).length() / (STEP * 2.0)
			st.set_color(_vertex_color(ox + i * STEP, oz + j * STEP, h, slope))
			st.add_vertex(Vector3(i * STEP, h, j * STEP))
	for j in CELLS:
		for i in CELLS:
			var a := j * n + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	# Коллизия: HeightMapShape3D (высоты / 2 при равномерном масштабе 2 = шаг сетки)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	var scaled := PackedFloat32Array()
	scaled.resize(hs.size())
	for k in hs.size():
		scaled[k] = hs[k] / STEP
	hm.map_data = scaled
	cs.shape = hm
	cs.scale = Vector3(STEP, STEP, STEP)
	cs.position = Vector3(CHUNK * 0.5, 0, CHUNK * 0.5)
	body.add_child(cs)
	var ch := {"node": node, "body": body, "res": _gen_resources(c), "mm": {}, "shapes": {}}
	chunks[c] = ch
	_build_resource_visuals(c)

func _gen_resources(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, SEED))
	var out := []
	var ox := c.x * CHUNK
	var oz := c.y * CHUNK
	var tries := 46
	for k in tries:
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var roll := rng.randf()
		var roll2 := rng.randf()
		var reg := region_at(x, z)
		var h := height(x, z)
		if h < WATER_LEVEL + 0.15 and reg != "swamp":
			continue
		if maxf(absf(x), absf(z)) > 226.0:
			continue
		var kind := ""
		match reg:
			"forest":
				if roll < 0.36: kind = "tree" if roll2 < 0.6 else "pine"
				elif roll < 0.44: kind = "rock"
				elif roll < 0.44 + 0.06 * res_mult: kind = "bush"
				elif roll < 0.5 + 0.08 * res_mult: kind = "stone"
				elif roll < 0.58 + 0.04 * res_mult: kind = "mushroom"
			"clearing":
				if roll < 0.12 * res_mult + 0.1: kind = "stone"
				elif roll < 0.3: kind = "bush"
			"hills":
				if roll < 0.18: kind = "pine"
				elif roll < 0.32: kind = "rock"
				elif roll < 0.32 + 0.1 * res_mult: kind = "stone"
			"swamp":
				if roll < 0.12: kind = "dead"
				elif roll < 0.12 + 0.1 * res_mult: kind = "reeds"
				elif roll < 0.3 + 0.08 * res_mult: kind = "mushroom"
				elif roll < 0.4: kind = "stone"
			"river":
				if roll < 0.1 + 0.1 * res_mult: kind = "stone"
				elif roll < 0.25: kind = "reeds"
			"village":
				if Vector2(x, z).distance_to(REGIONS.village.c) > 28.0 and roll < 0.2: kind = "tree"
				elif roll < 0.12 * res_mult + 0.05: kind = "scrap"
				elif roll < 0.35: kind = "stone"
				elif roll < 0.4: kind = "bush"
			"factory":
				if roll < 0.18 * res_mult + 0.08: kind = "scrap"
				elif roll < 0.4: kind = "stone"
			"radio", "cave":
				if roll < 0.25: kind = "stone"
				elif roll < 0.3 and reg == "cave": kind = "rock"
		if kind == "":
			continue
		out.append({"kind": kind, "pos": Vector3(x, h, z), "rot": rng.randf() * TAU, "scale": rng.randf_range(0.8, 1.25), "hp": RES_INFO[kind].hp})
	return out

func _key(c: Vector2i, i: int) -> String:
	return "%d,%d,%d" % [c.x, c.y, i]

func _is_harvested(c: Vector2i, i: int) -> bool:
	var k := _key(c, i)
	if not harvested.has(k):
		return false
	if float(time_source.call()) >= float(harvested[k]):
		harvested.erase(k)
		return false
	return true

func _build_resource_visuals(c: Vector2i) -> void:
	var ch: Dictionary = chunks[c]
	for k in ch.mm:
		ch.mm[k].queue_free()
	ch.mm = {}
	for k in ch.shapes:
		ch.shapes[k].queue_free()
	ch.shapes = {}
	var by_kind := {}
	var res: Array = ch.res
	for i in res.size():
		if _is_harvested(c, i):
			continue
		var r: Dictionary = res[i]
		if not by_kind.has(r.kind):
			by_kind[r.kind] = []
		by_kind[r.kind].append(i)
		var cr: float = RES_INFO[r.kind].collide
		if cr > 0.0:
			var cs := CollisionShape3D.new()
			if r.kind == "rock":
				var sp := SphereShape3D.new()
				sp.radius = cr * r.scale
				cs.shape = sp
				cs.position = r.pos - ch.node.position + Vector3(0, 0.3, 0)
			else:
				var cy := CylinderShape3D.new()
				cy.radius = cr * r.scale
				cy.height = 4.0
				cs.shape = cy
				cs.position = r.pos - ch.node.position + Vector3(0, 2.0, 0)
			ch.body.add_child(cs)
			ch.shapes[i] = cs
	var vis_end := {"stone": 45.0, "mushroom": 40.0, "bush": 70.0, "reeds": 60.0, "scrap": 70.0}
	for kind in by_kind:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = MeshMerge.resource_mesh(kind)
		var ids: Array = by_kind[kind]
		mm.instance_count = ids.size()
		for j in ids.size():
			var r: Dictionary = res[ids[j]]
			var b := Basis(Vector3.UP, r.rot).scaled(Vector3.ONE * r.scale)
			mm.set_instance_transform(j, Transform3D(b, r.pos - ch.node.position))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = MeshMerge.vertex_color_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (kind in ["tree", "pine", "dead"] and Settings.shadows_enabled()) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end.has(kind):
			mmi.visibility_range_end = vis_end[kind] * (0.7 if Settings.quality() <= Settings.Quality.LOW else 1.0)
		ch.node.add_child(mmi)
		ch.mm[kind] = mmi

func _check_respawns() -> void:
	var now := float(time_source.call())
	var dirty := {}
	for k in harvested.keys():
		if now >= float(harvested[k]):
			harvested.erase(k)
			var p: PackedStringArray = k.split(",")
			dirty[Vector2i(int(p[0]), int(p[1]))] = true
	for c in dirty:
		if chunks.has(c):
			_build_resource_visuals(c)

# ------------------------------------------------------------------ Взаимодействие

## Ближайший ресурс перед игроком.
func find_resource(pos: Vector3, forward: Vector3, max_dist := 3.2) -> Dictionary:
	var best := {}
	var best_d := max_dist
	var c0 := chunk_of(pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := c0 + Vector2i(dx, dz)
			if not chunks.has(c):
				continue
			var res: Array = chunks[c].res
			for i in res.size():
				var r: Dictionary = res[i]
				var to: Vector3 = r.pos - pos
				to.y = 0.0
				var d := to.length()
				var reach := max_dist + (0.9 if r.kind in ["rock", "tree", "pine", "dead"] else 0.0)
				if d > reach or d > best_d + 0.9:
					continue
				if d > 0.6 and forward.dot(to.normalized()) < 0.35:
					continue
				if absf(r.pos.y - pos.y) > 3.0:
					continue
				if _is_harvested(c, i):
					continue
				var eff := d - (0.9 if r.kind in ["rock", "tree", "pine", "dead"] else 0.0)
				if eff < best_d:
					best_d = eff
					best = {"chunk": c, "index": i, "kind": r.kind, "pos": r.pos}
	return best

## Удар по ресурсу. Возвращает выпавшие предметы (пусто, если ресурс ещё цел).
func hit_resource(info: Dictionary, power := 1.0) -> Dictionary:
	if info.is_empty() or not chunks.has(info.chunk):
		return {}
	var ch: Dictionary = chunks[info.chunk]
	var r: Dictionary = ch.res[info.index]
	r.hp -= power
	if r.hp > 0:
		return {"partial": true}
	var drop: Dictionary = RES_INFO[r.kind].drop.duplicate()
	for k in drop:
		var mult := res_mult if r.kind in ["tree", "pine", "dead", "rock", "scrap"] else 1.0
		drop[k] = maxi(1, int(round(drop[k] * mult)))
	if r.kind == "rock" and randf() < 0.25:
		drop["scrap"] = 1
	if r.kind == "scrap" and randf() < 0.35:
		drop["electronics"] = 1
	if r.kind == "bush" and randf() < 0.3:
		drop["fabric"] = 1
	r.hp = RES_INFO[r.kind].hp
	harvested[_key(info.chunk, info.index)] = float(time_source.call()) + RESPAWN_MIN[r.kind]
	_build_resource_visuals(info.chunk)
	return drop

## Поиск ближайших подбираемых камней (для подсказок во время налёта).
func nearest_stone(pos: Vector3, max_dist := 40.0) -> Vector3:
	var best := Vector3.INF
	var best_d := max_dist
	var c0 := chunk_of(pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := c0 + Vector2i(dx, dz)
			if not chunks.has(c):
				continue
			var res: Array = chunks[c].res
			for i in res.size():
				if res[i].kind != "stone" or _is_harvested(c, i):
					continue
				var d: float = res[i].pos.distance_to(pos)
				if d < best_d:
					best_d = d
					best = res[i].pos
	return best

func save_data() -> Dictionary:
	return {"harvested": harvested.duplicate()}

func load_data(d: Dictionary) -> void:
	harvested = d.get("harvested", {}).duplicate()
