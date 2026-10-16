class_name Curtain
extends Interactable
## Шторка примерочной. Открывание — главный «триггер» Женщины из примерочной.

signal toggled(curtain, is_open)

var cabin_index := 0
var is_open := false
var _folds: Array[MeshInstance3D] = []
var _width := 1.6
var _cloth: Node3D


func build(width: float) -> void:
	_width = width
	collision_layer = Build.LAYER_INTERACT | Build.LAYER_WORLD
	Build.cyl(self, 0.012, width + 0.3, Vector3(0, 2.18, 0.0), Mats.metal(), Vector3(0, 0, 90), 6)
	_cloth = Node3D.new()
	add_child(_cloth)
	var mat := Mats.color(Color(0.28, 0.08, 0.1), 0.95)
	var n := 9
	for i in n:
		var f := Build.box(_cloth, Vector3(width / n + 0.02, 2.05, 0.03), Vector3(-width * 0.5 + (i + 0.5) * width / n, 1.12, 0.03 * ((i % 2) * 2 - 1)), mat)
		_folds.append(f)
	setup_shape(Vector3(width, 2.0, 0.12), Vector3(0, 1.1, 0))
	_apply()


func prompt(_p) -> String:
	if not enabled:
		return ""
	return "Задёрнуть шторку" if is_open else "Отдёрнуть шторку"


func interact(player) -> void:
	set_open(not is_open)
	used.emit(player)


func set_open(v: bool, silent := false) -> void:
	if v == is_open:
		return
	is_open = v
	_apply()
	if not silent:
		Sfx.play_3d("curtain", global_position + Vector3.UP * 1.8, -6.0, randf_range(0.9, 1.1))
	toggled.emit(self, v)


func _apply() -> void:
	var n := _folds.size()
	for i in n:
		var f := _folds[i]
		var closed_x := -_width * 0.5 + (i + 0.5) * _width / n
		var open_x := -_width * 0.5 - 0.1 + i * 0.035
		f.position.x = open_x if is_open else closed_x
		f.scale.x = 0.35 if is_open else 1.0
	# Открытая шторка не мешает проходу.
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).position.x = -_width * 0.42 if is_open else 0.0
			((c as CollisionShape3D).shape as BoxShape3D).size.x = 0.3 if is_open else _width
