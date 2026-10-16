class_name HideSpot
extends Interactable
## Укрытие: шкафчик, кабинка туалета, под столом. Игрок перемещается в точку
## укрытия с ограниченным обзором. Безликого укрытие не останавливает.

@export var spot_name := "укрытие"
var view_point: Node3D
var exit_point: Node3D
var occupied := false


func prompt(player) -> String:
	if not enabled:
		return ""
	return "Выйти" if player.hiding_in == self else "Спрятаться: " + spot_name


func interact(player) -> void:
	if player.hiding_in == self:
		player.leave_hide()
	else:
		player.enter_hide(self)
	used.emit(player)
