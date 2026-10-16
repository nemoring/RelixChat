class_name Door
extends Interactable
## Распашная дверь. Блокирует ребро навигационного графа, глушит звук,
## может быть заперта. Сущности открывают двери с задержкой и шумом.

signal state_changed(door)

@export var door_id := ""
@export var width := 0.9
@export var height := 2.1
@export var open_angle := 95.0
var is_open := false
var locked := false
var lock_reason := "Заперто."
var nav_edge := []  # [waypoint_a, waypoint_b]
var _panel: MeshInstance3D
var _tween: Tween
var _busy := false
## Метка из стекла (входная дверь).
var glass := false


func build(mat: Material) -> void:
	solid = true
	# StaticBody вращается целиком: дверь сама является телом.
	collision_layer = Build.LAYER_INTERACT | Build.LAYER_WORLD
	var thick := 0.05
	if glass:
		_panel = Build.box(self, Vector3(width, height, 0.04), Vector3(width * 0.5, height * 0.5, 0), Mats.glass())
		Build.box(self, Vector3(width, 0.08, 0.06), Vector3(width * 0.5, 0.04, 0), Mats.metal(Color(0.25, 0.25, 0.27)))
		Build.box(self, Vector3(width, 0.08, 0.06), Vector3(width * 0.5, height - 0.04, 0), Mats.metal(Color(0.25, 0.25, 0.27)))
		Build.box(self, Vector3(0.06, height, 0.06), Vector3(0.03, height * 0.5, 0), Mats.metal(Color(0.25, 0.25, 0.27)))
		Build.box(self, Vector3(0.06, height, 0.06), Vector3(width - 0.03, height * 0.5, 0), Mats.metal(Color(0.25, 0.25, 0.27)))
		Build.box(self, Vector3(0.03, 0.35, 0.08), Vector3(width - 0.12, 1.05, 0), Mats.metal())
	else:
		_panel = Build.box(self, Vector3(width, height, thick), Vector3(width * 0.5, height * 0.5, 0), mat)
		Build.cyl(self, 0.025, 0.12, Vector3(width - 0.08, 1.0, 0.05), Mats.metal(), Vector3(90, 0, 0))
		Build.cyl(self, 0.025, 0.12, Vector3(width - 0.08, 1.0, -0.05), Mats.metal(), Vector3(90, 0, 0))
	setup_shape(Vector3(width, height, 0.08), Vector3(width * 0.5, height * 0.5, 0))


func prompt(_player) -> String:
	if not enabled:
		return ""
	if _busy:
		return ""
	if locked and not is_open:
		return "Заперто"
	return "Закрыть дверь" if is_open else "Открыть дверь"


func interact(player) -> void:
	if locked and not is_open:
		Sfx.play_3d("handle", global_position + global_basis.x * width * 0.8 + Vector3.UP, -6.0)
		if GameWorld.instance:
			GameWorld.instance.hud_message(lock_reason)
		return
	set_open(not is_open)
	if GameWorld.instance:
		GameWorld.instance.emit_noise(global_position, 0.45, "door")
	used.emit(player)


func set_open(v: bool, instant := false, speed := 1.0) -> void:
	if v == is_open:
		return
	is_open = v
	var target := -open_angle if v else 0.0
	if _tween:
		_tween.kill()
	if instant:
		rotation_degrees.y = _base_yaw + target
	else:
		_busy = true
		_tween = create_tween()
		_tween.tween_property(self, "rotation_degrees:y", _base_yaw + target, 0.55 / speed).set_trans(Tween.TRANS_SINE)
		_tween.tween_callback(func(): _busy = false)
		Sfx.play_3d("door_open" if v else "door_close", global_position + Vector3.UP * 1.2, -4.0, randf_range(0.9, 1.1))
	state_changed.emit(self)


var _base_yaw := 0.0


func capture_base() -> void:
	_base_yaw = rotation_degrees.y


func is_blocking() -> bool:
	return not is_open


## Сущность ломится в дверь: несколько ударов, затем открывает.
var _forcing := false


func entity_force(seconds: float) -> void:
	if is_open or _forcing:
		return
	_forcing = true
	_busy = true
	var t := 0.0
	while t < seconds:
		Sfx.play_3d("knock" if not glass else "glass_tap", global_position + Vector3.UP * 1.3, 0.0, randf_range(0.7, 0.9))
		if GameWorld.instance:
			GameWorld.instance.director.on_threat_signal(global_position, "door_bang")
		await get_tree().create_timer(1.3).timeout
		if not is_inside_tree():
			return
		t += 1.3
		if is_open:
			break
	_busy = false
	_forcing = false
	if not locked:
		set_open(true, false, 0.6)
