class_name CraftingSystem
extends Node
## Очередь изготовления: ресурсы списываются при постановке в очередь,
## предмет появляется по истечении времени. Требования к станции проверяются.

signal queue_changed
signal crafted(item_id: String, n: int)

const MAX_QUEUE := 5

var game
var queue: Array = [] # [{recipe, left, total}]
var _pending_output: Array = [] # не влезло в инвентарь

func setup(g) -> void:
	game = g

func station_available(station: String) -> bool:
	if station == "hand":
		return true
	return game.buildings.station_near(station, game.player.global_position, 4.5)

func can_craft(recipe_id: String) -> bool:
	var r: Dictionary = RecipeDB.RECIPES[recipe_id]
	return station_available(r.station) and game.inventory.has_all(RecipeDB.cost_for(recipe_id)) and queue.size() < MAX_QUEUE

func enqueue(recipe_id: String) -> bool:
	if queue.size() >= MAX_QUEUE:
		GameManager.toast("Очередь заполнена", UIStyle.BAD, 1.2)
		return false
	var r: Dictionary = RecipeDB.RECIPES[recipe_id]
	if not station_available(r.station):
		GameManager.toast("Нужна станция: %s" % RecipeDB.STATION_NAMES[r.station], UIStyle.BAD, 1.4)
		return false
	if not game.inventory.remove_all(RecipeDB.cost_for(recipe_id)):
		GameManager.toast("Не хватает ресурсов", UIStyle.BAD, 1.2)
		return false
	var t := RecipeDB.time_for(recipe_id)
	queue.append({"recipe": recipe_id, "left": t, "total": t})
	AudioManager.play_sfx("click")
	queue_changed.emit()
	return true

func cancel(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var e: Dictionary = queue[index]
	var cost := RecipeDB.cost_for(e.recipe)
	for k in cost:
		var left: int = game.inventory.add(k, int(cost[k]))
		if left > 0:
			game.drop_items(k, left, game.player.global_position)
	queue.remove_at(index)
	queue_changed.emit()

func _process(delta: float) -> void:
	if not _pending_output.is_empty() and Engine.get_process_frames() % 60 == 0:
		var p: Dictionary = _pending_output[0]
		var left: int = game.inventory.add(p.id, p.n)
		if left == 0:
			_pending_output.pop_front()
		else:
			p.n = left
	if queue.is_empty() or get_tree().paused:
		return
	var e: Dictionary = queue[0]
	e.left -= delta
	if e.left <= 0.0:
		queue.pop_front()
		var r: Dictionary = RecipeDB.RECIPES[e.recipe]
		var left2: int = game.inventory.add(r.result, int(r.n))
		if left2 > 0:
			_pending_output.append({"id": r.result, "n": left2})
			GameManager.toast("Инвентарь полон — предмет подождёт", UIStyle.BAD, 1.5)
		AudioManager.play_sfx("craft_done")
		GameManager.toast("Готово: %s ×%d" % [ItemDB.item_name(r.result), int(r.n)], UIStyle.GOOD, 1.3)
		crafted.emit(r.result, int(r.n))
		if r.station == "workbench" and randf() < 0.12:
			game.events.chair_fall()
		queue_changed.emit()

func save_data() -> Dictionary:
	return {"queue": queue.duplicate(true), "pending": _pending_output.duplicate(true)}

func load_data(d: Dictionary) -> void:
	queue = d.get("queue", []).duplicate(true)
	_pending_output = d.get("pending", []).duplicate(true)
	queue_changed.emit()
