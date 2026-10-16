class_name CarryBox
extends Interactable
## Переносимая коробка / пакет с одеждой / товар возврата.

@export var box_id := ""
var kind := "parcel"  # parcel | clothes | return | special
var cell := ""         # ячейка хранения, напр. "Б-3"
var recipient := ""
var order_no := ""
var size_label := ""   # для одежды
var scanned := false
var dims := Vector3(0.4, 0.3, 0.3)
var home_parent: Node
var home_transform: Transform3D
var _label: Label3D
var mesh: MeshInstance3D
var held := false


func build(size: Vector3, k := "parcel") -> void:
	kind = k
	dims = size
	if kind == "clothes":
		mesh = Build.box(self, size, Vector3(0, size.y * 0.5, 0), Mats.color(Color(0.12, 0.13, 0.15), 0.3))
		Build.box(self, Vector3(size.x * 0.6, 0.08, 0.02), Vector3(0, size.y * 0.85, size.z * 0.51), Mats.color(Color(0.85, 0.85, 0.8)))
	else:
		mesh = Build.box(self, size, Vector3(0, size.y * 0.5, 0), Mats.cardboard(randf() * 100.0))
	setup_shape(size, Vector3(0, size.y * 0.5, 0))
	_label = Build.label(self, "", Vector3(0.0, size.y * 0.5 + 0.02, size.z * 0.5 + 0.004), 0.022, Color(0.05, 0.05, 0.05))
	refresh_label()


func refresh_label() -> void:
	if _label == null:
		return
	if kind == "clothes":
		_label.text = "РАЗМЕР %s" % size_label
	elif cell != "":
		_label.text = "%s\n%s" % [cell, order_no]
	else:
		_label.text = order_no


func prompt(player) -> String:
	if not enabled or held:
		return ""
	if player.held_item != null:
		return ""
	var what := "пакет с одеждой (%s)" % size_label if kind == "clothes" else "коробку %s" % order_no
	return "Взять " + what


func interact(player) -> void:
	if held or not enabled:
		return
	player.pick_up(self)
	Sfx.play_3d("rustle", global_position, -10.0, 1.3)
	used.emit(player)


func describe() -> String:
	if kind == "clothes":
		return "Одежда, размер %s" % size_label
	var s := "Заказ %s" % order_no
	if cell != "":
		s += " · ячейка %s" % cell
	return s
