class_name CreatureSpawner
extends Node3D
## Поддерживает ограниченное число активных существ вокруг игрока (оптимизация).
## Днём — зайцы и кабаны, ночью — волки, в деревне — злые гуси.

var game
var terrain: SurvivalTerrain
var player: Node3D
var creatures: Array[Creature] = []
var max_active := 5
var _t := 2.0

func setup(g, t: SurvivalTerrain, p: Node3D) -> void:
	game = g
	terrain = t
	player = p
	max_active = [3, 4, 6, 8][Settings.quality()]

func _process(delta: float) -> void:
	if game.is_paused_gameplay():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 2.0
	# Удаляем дальних
	for c in creatures.duplicate():
		if not is_instance_valid(c):
			creatures.erase(c)
		elif c.global_position.distance_to(player.global_position) > 80.0:
			creatures.erase(c)
			c.queue_free()
	if creatures.size() >= max_active:
		return
	var a := randf() * TAU
	var r := randf_range(32.0, 50.0)
	var p: Vector3 = player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
	if absf(p.x) > 220 or absf(p.z) > 220:
		return
	var h := terrain.height(p.x, p.z)
	if h < SurvivalTerrain.WATER_LEVEL + 0.2:
		return
	var reg := terrain.region_at(p.x, p.z)
	if reg in ["clearing", "radio"] and not game.is_night():
		return
	var kind := "rabbit"
	var roll := randf() * float(DifficultyManager.p("event_rate"))
	if game.is_night():
		kind = "wolf" if roll > 0.35 else "rabbit"
	elif reg == "village":
		kind = "goose" if roll > 0.3 else "rabbit"
	elif roll > 0.75:
		kind = "boar"
	spawn(kind, Vector3(p.x, h, p.z))

func spawn(kind: String, pos: Vector3) -> Creature:
	var c := Creature.new()
	add_child(c)
	c.global_position = pos
	c.setup(kind, terrain, player, game)
	c.died.connect(func(cr): creatures.erase(cr))
	creatures.append(c)
	return c

## Ближайшее существо перед игроком (для удара).
func target_in_front(pos: Vector3, fwd: Vector3, reach: float) -> Creature:
	var best: Creature = null
	var bd := reach
	for c in creatures:
		if not is_instance_valid(c) or c.dead:
			continue
		var to := c.global_position - pos
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 0.8 or fwd.dot(to.normalized()) > 0.45):
			bd = d
			best = c
	return best

func clear_all() -> void:
	for c in creatures:
		if is_instance_valid(c):
			c.queue_free()
	creatures.clear()
