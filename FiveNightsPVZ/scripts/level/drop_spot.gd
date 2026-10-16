class_name DropSpot
extends Interactable
## Место, куда можно положить коробку: ячейка стеллажа, стойка, сканер,
## примерочная. Логику приёма решает обработчик accept_fn(box) -> bool.

signal item_placed(spot, box)

@export var spot_id := ""
var accept_fn: Callable  # (box) -> String: "" если можно, иначе причина отказа
var place_offset := Vector3.ZERO
var keep_item := true
## false — предмет остаётся в руках (сканер).
var takes_item := true
var verb := "Положить"
var stored: Array = []


## Необязательно: когда действие без предмета доступно (например, сверка ячейки).
var action_available: Callable


func prompt(player) -> String:
	if not enabled:
		return ""
	if player.held_item == null:
		if not action.is_valid():
			return ""
		if action_available.is_valid() and not action_available.call():
			return ""
		return prompt_text
	return "%s: %s" % [verb, player.held_item.describe()]


func interact(player) -> void:
	if not enabled:
		return
	if player.held_item == null:
		if action.is_valid():
			action.call(player)
		return
	var box: CarryBox = player.held_item
	if accept_fn.is_valid():
		var why: String = accept_fn.call(box)
		if why != "":
			if GameWorld.instance:
				GameWorld.instance.hud_message(why)
			return
	if not takes_item:
		item_placed.emit(self, box)
		return
	player.release_item()
	if keep_item:
		box.reparent(self, false)
		box.position = place_offset + Vector3(0, 0, 0.02 * stored.size())
		box.rotation = Vector3.ZERO
		box.enabled = true
		stored.append(box)
	else:
		box.queue_free()
	Sfx.play_3d("rustle", global_position, -12.0, 1.4)
	item_placed.emit(self, box)


func take_out(box: CarryBox) -> void:
	stored.erase(box)
