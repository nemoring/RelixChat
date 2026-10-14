class_name BuildingSystem
extends Node3D
## Строительство: призрак с проверкой места, привязка стен и крыши к фундаменту,
## поворот, подтверждение, отмена, разбор. Все постройки сериализуются.

signal built(id: String)
signal crate_opened(inv: Inventory, node: Node3D)

var game # SurvivalGame
var terrain: SurvivalTerrain
var buildings: Array = [] # [{id, pos, rot, node, body, data, inv}]
var placing := ""
var ghost: Node3D
var ghost_valid := false
var ghost_pos := Vector3.ZERO
var ghost_rot := 0.0
var demolish_mode := false
var _rot_extra := 0.0
var _demolish_target := -1

func setup(g, t: SurvivalTerrain) -> void:
	game = g
	terrain = t

# ------------------------------------------------------------------ Размещение

func start_placement(id: String) -> void:
	cancel()
	placing = id
	demolish_mode = false
	_rot_extra = 0.0
	ghost = BuildDB.build_visual(id, true)
	add_child(ghost)

func start_demolish() -> void:
	cancel()
	demolish_mode = true

func cancel() -> void:
	placing = ""
	demolish_mode = false
	_demolish_target = -1
	if is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	_highlight_demolish(-1)

func rotate_piece() -> void:
	_rot_extra += PI * 0.25 if BuildDB.PIECES.get(placing, {}).get("snap", "free") == "free" else PI * 0.5
	AudioManager.play_sfx("click")

func is_active() -> bool:
	return placing != "" or demolish_mode

func _process(_delta: float) -> void:
	if demolish_mode:
		var idx := _aimed_building()
		if idx != _demolish_target:
			_highlight_demolish(idx)
			_demolish_target = idx
		return
	if placing == "" or not is_instance_valid(ghost):
		return
	var aim: Vector3 = game.aim_point(7.0)
	_compute_snap(aim)
	ghost.global_position = ghost_pos
	ghost.rotation.y = ghost_rot
	var cost := BuildDB.cost_for(placing)
	var affordable: bool = game.inventory.has_all(cost)
	BuildDB.set_ghost_valid(ghost, ghost_valid and affordable)

func _compute_snap(aim: Vector3) -> void:
	var snap: String = BuildDB.PIECES[placing].snap
	ghost_valid = true
	match snap:
		"foundation":
			var gx := roundf(aim.x / BuildDB.GRID) * BuildDB.GRID
			var gz := roundf(aim.z / BuildDB.GRID) * BuildDB.GRID
			var y := terrain.height(gx, gz)
			for b in buildings:
				if b.id == "foundation" and Vector2(b.pos.x, b.pos.z).distance_to(Vector2(gx, gz)) < 3.2:
					y = b.pos.y
			ghost_pos = Vector3(gx, y, gz)
			ghost_rot = 0.0
			if _occupied("foundation", ghost_pos, 0.5):
				ghost_valid = false
			var spread := 0.0
			for corner in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5), Vector2(-1.5, 1.5), Vector2(1.5, 1.5)]:
				spread = maxf(spread, absf(terrain.height(gx + corner.x, gz + corner.y) - y))
			if spread > 1.6:
				ghost_valid = false
		"wall":
			var f := _nearest("foundation", aim, 3.5)
			if f.is_empty():
				ghost_pos = Vector3(aim.x, terrain.height(aim.x, aim.z), aim.z)
				ghost_rot = game.player_yaw() + _rot_extra
			else:
				var local: Vector3 = aim - f.pos
				var edges := [Vector3(0, 0, -1.5), Vector3(0, 0, 1.5), Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0)]
				var best: Vector3 = edges[0]
				var best_d := 999.0
				for e in edges:
					var d := Vector2(local.x - e.x, local.z - e.z).length()
					if d < best_d:
						best_d = d
						best = e
				ghost_pos = f.pos + best + Vector3(0, 0.4, 0)
				ghost_rot = 0.0 if absf(best.z) > 0.1 else PI * 0.5
				if _occupied_wall(ghost_pos):
					ghost_valid = false
		"roof":
			var f2 := _nearest("foundation", aim, 4.0)
			if f2.is_empty():
				ghost_valid = false
				ghost_pos = aim
			else:
				ghost_pos = f2.pos + Vector3(0, 3.4, 0)
				if _occupied("roof", ghost_pos, 0.5):
					ghost_valid = false
			ghost_rot = 0.0
		_:
			var px := snappedf(aim.x, 0.5)
			var pz := snappedf(aim.z, 0.5)
			var py := terrain.height(px, pz)
			var f3 := _nearest("foundation", Vector3(px, py, pz), 1.6)
			if not f3.is_empty():
				py = f3.pos.y + 0.4
			ghost_pos = Vector3(px, py, pz)
			ghost_rot = game.player_yaw() + PI + _rot_extra
			for b in buildings:
				if b.id != "foundation" and b.id != "roof" and b.pos.distance_to(ghost_pos) < 1.0:
					ghost_valid = false
	if terrain.height(ghost_pos.x, ghost_pos.z) < SurvivalTerrain.WATER_LEVEL - 0.2 and snap != "roof":
		ghost_valid = false
	if ghost_pos.distance_to(game.player.global_position) > 9.0:
		ghost_valid = false

func _nearest(id: String, p: Vector3, max_d: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for b in buildings:
		if b.id == id:
			var d: float = Vector2(b.pos.x, b.pos.z).distance_to(Vector2(p.x, p.z))
			if d < bd:
				bd = d
				best = b
	return best

func _occupied(id: String, p: Vector3, tol: float) -> bool:
	for b in buildings:
		if b.id == id and b.pos.distance_to(p) < tol:
			return true
	return false

func _occupied_wall(p: Vector3) -> bool:
	for b in buildings:
		if b.id in ["wall", "door", "window"] and b.pos.distance_to(p) < 0.5:
			return true
	return false

func confirm() -> bool:
	if demolish_mode:
		return _demolish()
	if placing == "" or not ghost_valid:
		GameManager.toast("Здесь строить нельзя", UIStyle.BAD, 1.2)
		AudioManager.play_sfx("xp_error", -6.0)
		return false
	var cost := BuildDB.cost_for(placing)
	if not game.inventory.remove_all(cost):
		GameManager.toast("Не хватает ресурсов", UIStyle.BAD, 1.2)
		AudioManager.play_sfx("xp_error", -6.0)
		return false
	var id := placing
	place(id, ghost_pos, ghost_rot, {})
	AudioManager.play_sfx("build")
	GameManager.vibrate(40)
	built.emit(id)
	if buildings.size() >= 10:
		GameManager.unlock_achievement("builder")
	return true

## Создание постройки (и при загрузке сохранения).
func place(id: String, pos: Vector3, rot: float, data: Dictionary) -> Dictionary:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 16
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = rot
	add_child(body)
	var vis := BuildDB.build_visual(id)
	body.add_child(vis)
	BuildDB.add_collision(id, body)
	var entry := {"id": id, "pos": pos, "rot": rot, "node": vis, "body": body, "data": data.duplicate(true), "inv": null}
	body.set_meta("building_index", buildings.size())
	var it := Interactable.new()
	it.position = Vector3(0, 1.0, 0)
	body.add_child(it)
	match id:
		"crate":
			var inv := Inventory.new(12)
			if data.has("items"):
				inv.from_array(data.items)
			entry.inv = inv
			it.label_func = func(): return "Открыть ящик" + (" (защищён бункером)" if is_protected(entry.pos) else "")
			it.action = func(): crate_opened.emit(inv, body)
		"bed":
			it.label = "Спать"
			it.action = func(): game.open_sleep_menu(entry)
		"campfire":
			it.label = "Костёр: готовить"
			it.action = func(): game.open_crafting("campfire")
			if Settings.effects_enabled():
				var p := AudioManager.make_loop_player_3d("fire", body, -10.0, 25.0)
				p.play()
		"workbench":
			it.label = "Верстак"
			it.action = func(): game.open_crafting("workbench")
		"furnace":
			it.label = "Печь: переплавка"
			it.action = func(): game.open_crafting("furnace")
		"door":
			var leaf := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.0, 2.2, 0.12)
			leaf.shape = bs
			leaf.position = Vector3(0, 1.1, 0)
			body.add_child(leaf)
			entry.data["open"] = data.get("open", false)
			var apply_door := func():
				var hinge: Node3D = vis.get_node("Hinge")
				hinge.rotation.y = -PI * 0.5 if entry.data.open else 0.0
				leaf.disabled = entry.data.open
			apply_door.call()
			it.label_func = func(): return "Закрыть дверь" if entry.data.open else "Открыть дверь"
			it.action = func():
				entry.data.open = not entry.data.open
				AudioManager.play_sfx("door", -4.0)
				apply_door.call()
		_:
			it.active = false
	buildings.append(entry)
	return entry

# ------------------------------------------------------------------ Разбор

func _aimed_building() -> int:
	var hit: Dictionary = game.camera_raycast(8.0, 16)
	if hit.is_empty():
		return -1
	var col: Object = hit.collider
	if col is StaticBody3D and col.has_meta("building_index"):
		for i in buildings.size():
			if buildings[i].body == col:
				return i
	return -1

func _highlight_demolish(idx: int) -> void:
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if is_instance_valid(b.node):
			b.node.scale = Vector3.ONE * (1.04 if i == idx else 1.0)

func _demolish() -> bool:
	var idx := _aimed_building()
	if idx < 0:
		GameManager.toast("Наведи прицел на постройку", UIStyle.BAD, 1.2)
		return false
	var b: Dictionary = buildings[idx]
	if b.inv != null and not b.inv.is_empty():
		GameManager.toast("Сначала освободи ящик", UIStyle.BAD, 1.2)
		return false
	var cost := BuildDB.cost_for(b.id)
	for k in cost:
		var back := int(ceil(cost[k] * 0.5))
		var left: int = game.inventory.add(k, back)
		if left > 0:
			game.drop_items(k, left, b.pos)
	b.body.queue_free()
	buildings.remove_at(idx)
	for i in buildings.size():
		buildings[i].body.set_meta("building_index", i)
	AudioManager.play_sfx("chop")
	GameManager.toast("Разобрано: %s" % BuildDB.PIECES[b.id].name, UIStyle.ACCENT, 1.2)
	_demolish_target = -1
	return true

# ------------------------------------------------------------------ Запросы

func count(id: String) -> int:
	var c := 0
	for b in buildings:
		if b.id == id:
			c += 1
	return c

func station_near(kind: String, p: Vector3, dist := 4.0) -> bool:
	for b in buildings:
		if b.id == kind and b.pos.distance_to(p) < dist:
			return true
	return false

func crates() -> Array:
	var out := []
	for b in buildings:
		if b.id == "crate":
			out.append(b)
	return out

func is_protected(p: Vector3) -> bool:
	for b in buildings:
		if b.id == "bunker" and Vector2(b.pos.x, b.pos.z).distance_to(Vector2(p.x, p.z)) < 4.0:
			return true
	return false

func is_under_roof(p: Vector3) -> bool:
	for b in buildings:
		if b.id == "roof" and absf(b.pos.x - p.x) < 1.7 and absf(b.pos.z - p.z) < 1.7 and b.pos.y > p.y and b.pos.y - p.y < 4.5:
			return true
		if b.id == "bunker" and b.pos.distance_to(p) < 2.6:
			return true
	return false

func near_fire(p: Vector3, dist := 5.0) -> bool:
	return station_near("campfire", p, dist)

## Центр базы: среднее положение важных построек (для налёта НЛО).
func base_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in buildings:
		if b.id in ["crate", "campfire", "bed", "workbench", "furnace", "foundation"]:
			sum += b.pos
			n += 1
	if n == 0:
		return Vector3.INF
	return sum / n

func nearest_bed(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for b in buildings:
		if b.id == "bed":
			var d: float = b.pos.distance_to(p)
			if d < bd:
				bd = d
				best = b
	return best

func save_data() -> Array:
	var out := []
	for b in buildings:
		var data: Dictionary = b.data.duplicate(true)
		if b.inv != null:
			data["items"] = b.inv.to_array()
		out.append({"id": b.id, "pos": [b.pos.x, b.pos.y, b.pos.z], "rot": b.rot, "data": data})
	return out

func load_data(arr: Array) -> void:
	for e in arr:
		var p: Array = e.pos
		place(str(e.id), Vector3(p[0], p[1], p[2]), float(e.rot), e.get("data", {}))
