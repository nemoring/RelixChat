class_name Entity
extends Node3D
## Базовая сущность: модель, движение по графу путевых точек, двери, шаги,
## проверки видимости. Конкретное поведение — в наследниках (_tick).

signal arrived

var world
var id := ""
var aggression := 0
var model: HumanoidModel
var point := ""             # ближайшая/текущая путевая точка
var active := false
var speed := 1.4
var step_sound := "step"
var step_volume := -10.0
var step_stride := 0.75
var stiff := 0.0
var can_open_doors := true
var door_force_time := 0.0  # 0 — открывает сразу
var rng := RandomNumberGenerator.new()
var _path := PackedStringArray()
var _path_i := 0
var _walk_phase := 0.0
var _step_acc := 0.0
var _t := 0.0
var _waiting_door: Door = null
var _moving := false
var vis_layers := Build.VIS_ALL


func setup(w, entity_id: String, aggr: int) -> void:
	world = w
	id = entity_id
	aggression = aggr
	rng.seed = GameState.run_seed + hash(entity_id)
	model = HumanoidModel.new()
	add_child(model)
	model.build(model_options())
	hide_entity()
	_on_setup()


func model_options() -> Dictionary:
	return {}


func _on_setup() -> void:
	pass


func hide_entity() -> void:
	visible = false
	active = false
	_moving = false
	_path = PackedStringArray()


func show_at(point_name: String, look_at_pos = null) -> void:
	point = point_name
	global_position = world.level.nav.pos_of(point_name)
	visible = true
	active = true
	if look_at_pos != null:
		face(look_at_pos)


func face(pos: Vector3) -> void:
	var p := Vector3(pos.x, global_position.y, pos.z)
	if p.distance_to(global_position) > 0.01:
		look_at(p, Vector3.UP)


func set_vis_layers(layers: int) -> void:
	vis_layers = layers
	Build.set_visual_layers(model, layers)


# ------------------------------------------------------------------ Движение

func go_to(target_point: String, spd := -1.0) -> bool:
	if spd > 0:
		speed = spd
	var nav: NavGraph = world.level.nav
	point = nav.nearest(global_position)
	_path = nav.path(point, target_point, can_open_doors)
	_path_i = 0
	_moving = _path.size() > 0
	return _moving


func stop() -> void:
	_moving = false
	_path = PackedStringArray()


func is_moving() -> bool:
	return _moving


func _process(delta: float) -> void:
	if world == null or world.game_over:
		return
	_t += delta
	if active:
		_tick(delta)
		_move(delta)
	if visible and model:
		if _moving and _waiting_door == null:
			_walk_phase += delta * speed * 4.0
			model.walk(_walk_phase, clampf(speed / 1.4, 0.4, 1.4), stiff)
		else:
			model.idle(_t, stiff)


func _tick(_delta: float) -> void:
	pass


func _move(delta: float) -> void:
	if not _moving or _path_i >= _path.size():
		return
	if _waiting_door:
		if _waiting_door.is_open:
			_waiting_door = null
		else:
			return
	var nav: NavGraph = world.level.nav
	var target_name := _path[_path_i]
	# Дверь между текущей и следующей точкой.
	if _path_i > 0:
		var d := nav.door_between(_path[_path_i - 1], target_name)
		if d and not d.is_open:
			if d.locked:
				_moving = false
				on_blocked(d)
				return
			if door_force_time > 0.0:
				_waiting_door = d
				d.entity_force(door_force_time)
				return
			d.set_open(true, false, 0.8)
	var target := nav.pos_of(target_name)
	var to := target - global_position
	to.y = 0
	var dist := to.length()
	if dist < 0.08:
		point = target_name
		_path_i += 1
		if _path_i >= _path.size():
			_moving = false
			arrived.emit()
			on_arrived()
		return
	var stepv := minf(dist, speed * delta)
	global_position += to / dist * stepv
	var look := global_position + to / dist
	var desired := Transform3D().looking_at(to / dist, Vector3.UP).basis
	global_basis = global_basis.slerp(desired, clampf(delta * 6.0, 0.0, 1.0)).orthonormalized()
	_step_acc += stepv
	if _step_acc >= step_stride and step_sound != "":
		_step_acc = 0.0
		Sfx.play_3d(step_sound, global_position + Vector3.UP * 0.05, step_volume, rng.randf_range(0.85, 1.05), 20.0)
	look = look


func on_arrived() -> void:
	pass


func on_blocked(_door: Door) -> void:
	pass


# ------------------------------------------------------------------ Восприятие

func head_pos() -> Vector3:
	if model and model.head:
		return model.head.global_position + Vector3.UP * 0.1
	return global_position + Vector3.UP * 1.6


func dist_to_player() -> float:
	return global_position.distance_to(world.player.global_position)


## Видит ли игрок сущность глазами.
func seen_by_player(max_angle := 40.0) -> bool:
	if not visible:
		return false
	var p: Player = world.player
	if vis_layers == Build.VIS_CAM_ONLY:
		return false
	return p.cam.is_position_in_frustum(head_pos()) and p.has_los(head_pos()) or (p.cam.is_position_in_frustum(global_position + Vector3.UP) and p.has_los(global_position + Vector3.UP))


## Видит ли сущность игрока (луч от головы к глазам игрока).
func sees_player(max_range: float, fov_deg := 120.0) -> bool:
	var p: Player = world.player
	var eye: Vector3 = p.eye_pos()
	var from := head_pos()
	var to := eye - from
	if to.length() > max_range:
		return false
	var fwd := -global_basis.z
	if rad_to_deg(fwd.angle_to(Vector3(to.x, 0, to.z).normalized())) > fov_deg * 0.5:
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, eye, Build.LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


func attack(hint: String) -> void:
	world.kill_player(id, hint)


func current_room() -> String:
	return Level.room_at(global_position)
