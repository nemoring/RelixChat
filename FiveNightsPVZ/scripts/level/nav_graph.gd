class_name NavGraph
extends RefCounted
## Граф путевых точек для ИИ. Дешёвый на мобильных, детерминированный,
## тестируемый. Закрытые двери помечают рёбра; сущности, умеющие открывать
## двери, проходят их с задержкой.

var astar := AStar3D.new()
var names := {}        # name -> id
var points := {}       # id -> {name, pos, room}
var door_edges := {}   # "a|b" -> Door
var cam_coverage := {} # name -> Array[cam_index]
var _next := 0


func add_point(point_name: String, pos: Vector3, room: String) -> int:
	var id := _next
	_next += 1
	astar.add_point(id, pos)
	names[point_name] = id
	points[id] = {"name": point_name, "pos": pos, "room": room}
	return id


func connect_points(a: String, b: String, door: Door = null) -> void:
	var ia: int = names[a]
	var ib: int = names[b]
	astar.connect_points(ia, ib, true)
	if door:
		door_edges[_key(ia, ib)] = door
		door.nav_edge = [a, b]


func _key(ia: int, ib: int) -> String:
	return "%d|%d" % [mini(ia, ib), maxi(ia, ib)]


func pos_of(point_name: String) -> Vector3:
	return astar.get_point_position(names[point_name])


func room_of(point_name: String) -> String:
	return points[names[point_name]]["room"]


func nearest(pos: Vector3) -> String:
	var id := astar.get_closest_point(pos)
	return points[id]["name"]


func door_between(a: String, b: String) -> Door:
	return door_edges.get(_key(names[a], names[b]))


## Путь как массив имён точек. can_open_doors=false — закрытые двери непроходимы.
func path(from_name: String, to_name: String, can_open_doors := true, avoid_locked := true) -> PackedStringArray:
	var disabled := []
	for k in door_edges.keys():
		var d: Door = door_edges[k]
		var blocked := (not can_open_doors and d.is_blocking()) or (avoid_locked and d.locked and not d.is_open)
		if blocked:
			var parts: PackedStringArray = k.split("|")
			var ia := int(parts[0])
			var ib := int(parts[1])
			if astar.are_points_connected(ia, ib):
				astar.disconnect_points(ia, ib)
				disabled.append([ia, ib])
	var ids := astar.get_id_path(names[from_name], names[to_name])
	for e in disabled:
		astar.connect_points(e[0], e[1], true)
	var out := PackedStringArray()
	for id in ids:
		out.append(points[id]["name"])
	return out


func neighbors(point_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in astar.get_point_connections(names[point_name]):
		out.append(points[id]["name"])
	return out


func points_in_room(room: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in points.keys():
		if points[id]["room"] == room:
			out.append(points[id]["name"])
	return out


func all_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n in names.keys():
		out.append(n)
	return out


func is_covered(point_name: String) -> bool:
	return not (cam_coverage.get(point_name, []) as Array).is_empty()
