class_name Interactable
extends StaticBody3D
## Базовый интерактивный объект. Наследники переопределяют prompt()/interact().
## Слой коллизии 8 — луч взаимодействия; solid=true добавляет слой мира.

signal used(by)

@export var solid := false
@export var prompt_text := "Осмотреть"
## Необязательный обработчик для простых объектов (телефон, метка обхода...).
var action: Callable
var enabled := true
var tag := ""


func _init() -> void:
	collision_mask = 0


func _ready() -> void:
	collision_layer = Build.LAYER_INTERACT | (Build.LAYER_WORLD if solid else 0)


func setup_shape(size: Vector3, offset := Vector3.ZERO) -> Interactable:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = offset
	add_child(cs)
	return self


func prompt(_player) -> String:
	return prompt_text if enabled else ""


func interact(player) -> void:
	if not enabled:
		return
	if action.is_valid():
		action.call(player)
	used.emit(player)
