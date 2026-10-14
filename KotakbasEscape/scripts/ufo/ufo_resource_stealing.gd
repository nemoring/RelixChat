class_name UFOResourceStealing
extends Node
## Кража настоящих ресурсов: сначала из доступных ящиков под лучом (кроме тех,
## что у бункера), затем из инвентаря игрока, если он стоит в луче.
## Сюжетные предметы не крадутся. За налёт — ограниченная доля (по сложности).

const BEAM_RADIUS := 7.0
const CRATE_RADIUS := 16.0
const TICK := 3.0

var game
var ufo: Node3D
var budget := 0
var stolen_total := 0
var stolen := {} # id -> n
var _tick_t := TICK
var _started := false
var _fly_items: Array[Node3D] = []

func setup(g, u: Node3D, saved := {}) -> void:
	game = g
	ufo = u
	budget = int(saved.get("budget", 0))
	stolen_total = int(saved.get("stolen_total", 0))
	stolen = saved.get("stolen", {}).duplicate()
	_started = saved.has("budget")

## Расчёт бюджета кражи в начале зависания.
func begin() -> void:
	if _started:
		return
	_started = true
	var total := 0
	for c in game.buildings.crates():
		if not game.buildings.is_protected(c.pos):
			total += c.inv.total_stealable()
	total += game.inventory.total_stealable()
	budget = int(ceil(float(total) * float(DifficultyManager.p("ufo_steal_fraction"))))

func budget_exhausted() -> bool:
	return _started and stolen_total >= budget and budget > 0

func tick(delta: float, beam_on: bool, beam_ground: Vector3) -> void:
	_animate_items(delta)
	if not beam_on or not _started:
		return
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = TICK
	if stolen_total >= budget:
		return
	var per_tick := maxi(1, int(ceil(float(budget) / 22.0)))
	# 1) Ящики рядом с лучом
	var crates: Array = game.buildings.crates()
	crates.shuffle()
	for c in crates:
		if game.buildings.is_protected(c.pos):
			continue
		if Vector2(c.pos.x, c.pos.z).distance_to(Vector2(beam_ground.x, beam_ground.z)) > CRATE_RADIUS:
			continue
		var took := _steal_from(c.inv, per_tick, c.pos)
		if took > 0:
			return
	# 2) Инвентарь игрока, если он в луче
	var pp: Vector3 = game.player.global_position
	if Vector2(pp.x, pp.z).distance_to(Vector2(beam_ground.x, beam_ground.z)) < BEAM_RADIUS:
		var took2 := _steal_from(game.inventory, per_tick, pp)
		if took2 > 0:
			game.subtitle("Луч тянет вещи прямо из рук! Отойди из луча!")

func _steal_from(inv: Inventory, amount: int, from: Vector3) -> int:
	var slots := inv.stealable_slots()
	if slots.is_empty():
		return 0
	var pick: Array = slots.pick_random()
	var n := mini(amount, mini(int(pick[2]), budget - stolen_total))
	if n <= 0:
		return 0
	var res := inv.remove_from_slot(int(pick[0]), n)
	if res.is_empty():
		return 0
	stolen_total += int(res.n)
	stolen[res.id] = int(stolen.get(res.id, 0)) + int(res.n)
	_spawn_flying(res.id, from)
	AudioManager.play_sfx_3d("whoosh", from, -6.0)
	game.on_resource_stolen(res.id, int(res.n))
	return int(res.n)

## Визуально предмет поднимается по лучу и исчезает в тарелке.
func _spawn_flying(id: String, from: Vector3) -> void:
	if _fly_items.size() >= 6:
		var old: Node3D = _fly_items.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var n := Node3D.new()
	var spr := Sprite3D.new()
	spr.texture = ItemDB.icon(id)
	spr.pixel_size = 0.02
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.add_child(spr)
	game.add_child(n)
	n.global_position = from + Vector3(0, 1.0, 0)
	_fly_items.append(n)

func _animate_items(delta: float) -> void:
	var i := 0
	while i < _fly_items.size():
		var n := _fly_items[i]
		if not is_instance_valid(n):
			_fly_items.remove_at(i)
			continue
		var target := ufo.global_position + Vector3(0, -1.0, 0)
		n.global_position = n.global_position.move_toward(target, delta * 7.0)
		n.global_position.x = lerpf(n.global_position.x, target.x, delta * 2.0)
		n.global_position.z = lerpf(n.global_position.z, target.z, delta * 2.0)
		n.rotate_y(delta * 6.0)
		if n.global_position.distance_to(target) < 0.8:
			n.queue_free()
			_fly_items.remove_at(i)
		else:
			i += 1

## Награда при победе: иногда из тарелки выпадают редкие детали.
func drop_loot_on_defeat() -> void:
	var drop := {}
	if randf() < 0.6:
		drop["ufo_part"] = randi_range(1, 2)
	if randf() < 0.3:
		drop["metal"] = randi_range(1, 3)
	if not drop.is_empty():
		game.drop_items_dict(drop, game.player.global_position + game.player.forward() * 2.0)
		game.subtitle("Из тарелки что-то выпало! Подбери.")

func summary() -> String:
	var parts := []
	for k in stolen:
		parts.append("%s ×%d" % [ItemDB.item_name(k), int(stolen[k])])
	return ", ".join(parts)

func save_data() -> Dictionary:
	if not _started:
		return {}
	return {"budget": budget, "stolen_total": stolen_total, "stolen": stolen.duplicate()}
