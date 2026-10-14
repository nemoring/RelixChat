class_name Creature
extends Node3D
## Животные и враждебные существа. Кинематическое движение по высоте рельефа
## (дёшево для мобильных), конечный автомат: бродит / убегает / преследует / атакует.

signal died(creature: Creature)

const TYPES := {
	"rabbit": {"name": "Заяц", "hp": 12, "speed": 3.0, "run": 7.5, "dmg": 0, "hostile": false, "drop": {"meat_raw": 1}},
	"boar": {"name": "Кабан", "hp": 60, "speed": 2.2, "run": 6.0, "dmg": 12, "hostile": "territorial", "drop": {"meat_raw": 3}},
	"wolf": {"name": "Волк", "hp": 40, "speed": 3.0, "run": 6.6, "dmg": 9, "hostile": true, "drop": {"meat_raw": 2}},
	"goose": {"name": "Злой гусь", "hp": 22, "speed": 2.0, "run": 5.2, "dmg": 5, "hostile": true, "drop": {"meat_raw": 1, "fabric": 1}},
}

var kind := "rabbit"
var hp := 10.0
var state := "wander"
var target_dir := Vector3.FORWARD
var _state_t := 0.0
var _attack_cd := 0.0
var _hurt_t := 0.0
var _anim_t := 0.0
var terrain: SurvivalTerrain
var player: Node3D
var game
var body: Node3D
var legs: Array[Node3D] = []
var head_node: Node3D
var dead := false

func setup(k: String, t: SurvivalTerrain, p: Node3D, g) -> void:
	kind = k
	terrain = t
	player = p
	game = g
	hp = float(TYPES[k].hp) * float(DifficultyManager.p("enemy_hp_mult"))
	_build()

func _build() -> void:
	body = Node3D.new()
	add_child(body)
	match kind:
		"rabbit":
			MK.sphere(body, 0.22, Color(0.6, 0.55, 0.5), Vector3(0, 0.25, 0), 7).scale = Vector3(1, 0.9, 1.3)
			head_node = Node3D.new()
			head_node.position = Vector3(0, 0.42, -0.25)
			body.add_child(head_node)
			MK.sphere(head_node, 0.13, Color(0.62, 0.57, 0.52), Vector3.ZERO, 7)
			MK.box(head_node, Vector3(0.05, 0.28, 0.08), Color(0.62, 0.57, 0.52), Vector3(-0.06, 0.2, 0.03))
			MK.box(head_node, Vector3(0.05, 0.28, 0.08), Color(0.62, 0.57, 0.52), Vector3(0.06, 0.2, 0.03))
			MK.sphere(body, 0.07, Color.WHITE, Vector3(0, 0.3, 0.28), 5)
		"boar":
			MK.box(body, Vector3(0.7, 0.6, 1.3), Color(0.35, 0.25, 0.18), Vector3(0, 0.65, 0))
			head_node = Node3D.new()
			head_node.position = Vector3(0, 0.65, -0.75)
			body.add_child(head_node)
			MK.box(head_node, Vector3(0.5, 0.45, 0.5), Color(0.32, 0.22, 0.16))
			MK.box(head_node, Vector3(0.25, 0.2, 0.15), Color(0.8, 0.55, 0.5), Vector3(0, -0.05, -0.3))
			MK.box(head_node, Vector3(0.04, 0.15, 0.04), Color(0.95, 0.95, 0.9), Vector3(-0.15, -0.1, -0.3), Vector3(0.4, 0, 0))
			MK.box(head_node, Vector3(0.04, 0.15, 0.04), Color(0.95, 0.95, 0.9), Vector3(0.15, -0.1, -0.3), Vector3(0.4, 0, 0))
			for p in [Vector3(-0.25, 0.35, -0.45), Vector3(0.25, 0.35, -0.45), Vector3(-0.25, 0.35, 0.45), Vector3(0.25, 0.35, 0.45)]:
				var leg := Node3D.new()
				leg.position = p
				body.add_child(leg)
				MK.box(leg, Vector3(0.14, 0.4, 0.14), Color(0.25, 0.18, 0.12), Vector3(0, -0.18, 0))
				legs.append(leg)
		"wolf":
			MK.box(body, Vector3(0.45, 0.45, 1.1), Color(0.4, 0.4, 0.45), Vector3(0, 0.75, 0))
			head_node = Node3D.new()
			head_node.position = Vector3(0, 0.95, -0.65)
			body.add_child(head_node)
			MK.box(head_node, Vector3(0.35, 0.32, 0.35), Color(0.42, 0.42, 0.47))
			MK.box(head_node, Vector3(0.18, 0.15, 0.25), Color(0.38, 0.38, 0.42), Vector3(0, -0.05, -0.25))
			MK.cyl(head_node, 0.0, 0.07, 0.15, Color(0.35, 0.35, 0.4), Vector3(-0.1, 0.22, 0.05), Vector3.ZERO, 4)
			MK.cyl(head_node, 0.0, 0.07, 0.15, Color(0.35, 0.35, 0.4), Vector3(0.1, 0.22, 0.05), Vector3.ZERO, 4)
			MK.add(head_node, MK.sphere_mesh(0.03, 4, 2), Color(1.0, 0.9, 0.2), Vector3(-0.09, 0.05, -0.18), Vector3.ZERO, true, 2.0)
			MK.add(head_node, MK.sphere_mesh(0.03, 4, 2), Color(1.0, 0.9, 0.2), Vector3(0.09, 0.05, -0.18), Vector3.ZERO, true, 2.0)
			MK.box(body, Vector3(0.1, 0.1, 0.5), Color(0.4, 0.4, 0.45), Vector3(0, 0.85, 0.7), Vector3(-0.5, 0, 0))
			for p in [Vector3(-0.15, 0.55, -0.4), Vector3(0.15, 0.55, -0.4), Vector3(-0.15, 0.55, 0.4), Vector3(0.15, 0.55, 0.4)]:
				var leg2 := Node3D.new()
				leg2.position = p
				body.add_child(leg2)
				MK.box(leg2, Vector3(0.1, 0.55, 0.1), Color(0.35, 0.35, 0.4), Vector3(0, -0.27, 0))
				legs.append(leg2)
		"goose":
			MK.sphere(body, 0.3, Color(0.95, 0.95, 0.95), Vector3(0, 0.45, 0), 8).scale = Vector3(0.9, 0.8, 1.3)
			head_node = Node3D.new()
			head_node.position = Vector3(0, 0.75, -0.3)
			body.add_child(head_node)
			MK.box(head_node, Vector3(0.08, 0.45, 0.08), Color(0.95, 0.95, 0.95), Vector3(0, 0.1, 0))
			MK.sphere(head_node, 0.1, Color(0.95, 0.95, 0.95), Vector3(0, 0.35, -0.03), 6)
			MK.box(head_node, Vector3(0.07, 0.05, 0.16), Color(1.0, 0.55, 0.1), Vector3(0, 0.33, -0.15))
			MK.sphere(head_node, 0.02, Color.BLACK, Vector3(-0.05, 0.38, -0.08), 4)
			MK.sphere(head_node, 0.02, Color.BLACK, Vector3(0.05, 0.38, -0.08), 4)
			for p in [Vector3(-0.1, 0.22, 0), Vector3(0.1, 0.22, 0)]:
				var leg3 := Node3D.new()
				leg3.position = p
				body.add_child(leg3)
				MK.box(leg3, Vector3(0.04, 0.22, 0.04), Color(1.0, 0.55, 0.1), Vector3(0, -0.11, 0))
				legs.append(leg3)

func _hostile() -> bool:
	var h = TYPES[kind].hostile
	if typeof(h) == TYPE_BOOL:
		return h
	return _hurt_t > 0.0 # территориальный — только если его задели или подошли слишком близко

func take_damage(amount: float, from: Vector3) -> void:
	if dead:
		return
	hp -= amount
	_hurt_t = 12.0
	AudioManager.play_sfx_3d("hit", global_position, -4.0)
	if kind == "goose":
		AudioManager.play_sfx_3d("honk", global_position)
	body.scale = Vector3(1.2, 0.8, 1.2)
	var away := (global_position - from)
	away.y = 0
	global_position += away.normalized() * 0.6
	if hp <= 0.0:
		_die()
	elif kind == "rabbit":
		state = "flee"
	else:
		state = "chase"

func _die() -> void:
	dead = true
	state = "dead"
	var tw := create_tween()
	tw.tween_property(body, "rotation:z", PI * 0.5, 0.3)
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		game.drop_items_dict(TYPES[kind].drop, global_position)
		died.emit(self)
		queue_free())

func _process(delta: float) -> void:
	if dead or game == null or game.is_paused_gameplay():
		return
	_state_t -= delta
	_attack_cd -= delta
	_hurt_t = maxf(0.0, _hurt_t - delta)
	body.scale = body.scale.lerp(Vector3.ONE, delta * 8.0)
	var info: Dictionary = TYPES[kind]
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	var aggro := float(DifficultyManager.p("enemy_aggro"))
	var spd := float(info.speed)
	match state:
		"wander":
			if _state_t <= 0.0:
				_state_t = randf_range(2.0, 5.0)
				var a := randf() * TAU
				target_dir = Vector3(cos(a), 0, sin(a)) if randf() < 0.75 else Vector3.ZERO
			if kind == "rabbit" and dist < 7.0:
				state = "flee"
			elif kind == "boar" and dist < 3.5:
				_hurt_t = 6.0
				state = "chase"
			elif _hostile() and dist < aggro:
				state = "chase"
				if kind == "wolf":
					AudioManager.play_sfx_3d("howl", global_position, -6.0)
				elif kind == "goose":
					AudioManager.play_sfx_3d("honk", global_position)
		"flee":
			target_dir = -to_p.normalized()
			spd = float(info.run)
			if dist > 22.0:
				state = "wander"
		"chase":
			target_dir = to_p.normalized()
			spd = float(info.run)
			if dist < 1.6:
				target_dir = Vector3.ZERO
				if _attack_cd <= 0.0 and int(info.dmg) > 0:
					_attack_cd = 1.3
					game.damage_player(float(info.dmg) * float(DifficultyManager.p("enemy_dmg_mult")), "%s атакует!" % info.name)
					body.position.z = -0.3
			if dist > aggro * 2.2 or (not _hostile() and kind == "boar"):
				state = "wander"
	body.position.z = lerpf(body.position.z, 0.0, delta * 6.0)
	if target_dir.length() > 0.01:
		var step := target_dir * spd * delta
		var np := global_position + step
		if terrain.height(np.x, np.z) > SurvivalTerrain.WATER_LEVEL - 0.3:
			global_position = np
		else:
			target_dir = -target_dir
		rotation.y = lerp_angle(rotation.y, atan2(-target_dir.x, -target_dir.z), delta * 8.0)
		_anim_t += delta * spd * 3.0
		for i in legs.size():
			legs[i].rotation.x = sin(_anim_t + i * PI) * 0.6
		if kind == "rabbit":
			body.position.y = absf(sin(_anim_t)) * 0.2
	global_position.y = terrain.height(global_position.x, global_position.z)
