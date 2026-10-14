class_name PigeonModel
extends Node3D
## Голубь: главный тайный персонаж игры. Машет крыльями, крутит головой.

var flapping := true
var wing_l: Node3D
var wing_r: Node3D
var head: Node3D
var _t := 0.0

func _ready() -> void:
	var grey := Color(0.55, 0.58, 0.65)
	MK.sphere(self, 0.22, grey, Vector3.ZERO, 8).scale = Vector3(1.0, 0.9, 1.4)
	head = Node3D.new()
	head.position = Vector3(0, 0.2, -0.25)
	add_child(head)
	MK.sphere(head, 0.12, Color(0.35, 0.45, 0.5), Vector3.ZERO, 8)
	MK.cyl(head, 0.0, 0.035, 0.1, Color(0.9, 0.7, 0.3), Vector3(0, -0.02, -0.14), Vector3(-PI * 0.5, 0, 0), 5)
	MK.sphere(head, 0.03, Color(1, 0.5, 0.1), Vector3(-0.07, 0.04, -0.07), 5)
	MK.sphere(head, 0.03, Color(1, 0.5, 0.1), Vector3(0.07, 0.04, -0.07), 5)
	MK.box(self, Vector3(0.18, 0.04, 0.22), grey.darkened(0.3), Vector3(0, 0.02, 0.32))
	wing_l = Node3D.new()
	wing_l.position = Vector3(-0.15, 0.08, 0)
	add_child(wing_l)
	MK.box(wing_l, Vector3(0.36, 0.03, 0.26), grey.darkened(0.15), Vector3(-0.18, 0, 0))
	wing_r = Node3D.new()
	wing_r.position = Vector3(0.15, 0.08, 0)
	add_child(wing_r)
	MK.box(wing_r, Vector3(0.36, 0.03, 0.26), grey.darkened(0.15), Vector3(0.18, 0, 0))
	MK.cyl(self, 0.015, 0.015, 0.18, Color(0.9, 0.4, 0.4), Vector3(-0.06, -0.24, 0), Vector3.ZERO, 4)
	MK.cyl(self, 0.015, 0.015, 0.18, Color(0.9, 0.4, 0.4), Vector3(0.06, -0.24, 0), Vector3.ZERO, 4)

func _process(delta: float) -> void:
	_t += delta
	if flapping:
		var a := sin(_t * 22.0) * 0.9
		wing_l.rotation.z = a
		wing_r.rotation.z = -a
	else:
		wing_l.rotation.z = 0.1
		wing_r.rotation.z = -0.1
		head.position.z = -0.25 + sin(_t * 9.0) * 0.04 # кивает
	head.rotation.y = sin(_t * 1.7) * 0.6
