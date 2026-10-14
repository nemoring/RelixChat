class_name Interactable
extends Node3D
## Универсальная точка взаимодействия (предмет, NPC, ящик, постройка).
## Игрок видит подпись на контекстной кнопке и вызывает action.

var label := ""
var action: Callable
var radius := 2.6
var active := true
var label_func: Callable # динамическая подпись (необязательно)

func _ready() -> void:
	add_to_group("interactable")

func get_text() -> String:
	if not active:
		return ""
	if label_func.is_valid():
		return str(label_func.call())
	return label

func interact() -> void:
	if active and action.is_valid():
		action.call()
