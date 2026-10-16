class_name Courier
extends Entity
## Курьер. Приходит со склада через рольставню, перекладывает коробки,
## оставляет посылки. Идёт на свет и шум, использует слепые зоны камер,
## преследует по служебному коридору. Закрытая дверь задерживает его.

var state := "off"   # off | patrol | work | investigate | chase | search | leave
var _timer := 0.0
var _sense_t := 0.0
var _last_seen := Vector3.ZERO
var _lost_t := 0.0
var _saw_hide_t := 99.0
var _visits := 0
var _box: MeshInstance3D

const PATROL_POINTS := ["wh_shutter", "wh_nw", "wh_ne", "wh_w", "wh_mid", "wh_e", "wh_sw", "wh_s", "wh_se", "wh_door_ws", "wh_door_cor", "cor_1", "cor_2", "cor_3", "cor_4"]
const DEEP_POINTS := ["ws_center", "ws_desk", "util", "toilet", "hall_center", "hall_counter"]


func model_options() -> Dictionary:
	return {"jacket": Color(0.12, 0.16, 0.22), "pants": Color(0.08, 0.09, 0.1), "skin": Color(0.55, 0.47, 0.42), "cap": true, "stripe": true, "height": 1.08, "thin": 1.2, "arm_len": 1.05}


func _on_setup() -> void:
	step_sound = "step_heavy"
	step_volume = -3.0
	step_stride = 0.85
	door_force_time = 2.6
	_box = Build.box(model.spine, Vector3(0.45, 0.32, 0.35), Vector3(0, 0.25, -0.35), Mats.cardboard(7.0))


func activate() -> void:
	if aggression <= 0 or state != "off":
		return
	_visits += 1
	show_at("wh_shutter")
	Sfx.play_3d("shutter", Vector3(5.4, 1.2, 0.3), -2.0)
	state = "patrol"
	_timer = rng.randf_range(90.0, 150.0) + aggression * 6.0
	_box.visible = true
	_next_patrol()
	world.director.note_event("courier_in")


func _speed_walk() -> float:
	return 1.15 + aggression * 0.02


func _speed_chase() -> float:
	return 2.9 + aggression * 0.04


func _next_patrol() -> void:
	var nav: NavGraph = world.level.nav
	var options: Array = PATROL_POINTS.duplicate()
	if aggression >= 9 and world.director.request_escalation("courier", 1):
		options += DEEP_POINTS
	# Если игрок смотрит в камеры — выбирает точки вне обзора текущей камеры.
	if world.cctv.active:
		var cam_i: int = world.cctv.current
		options = options.filter(func(n): return not (cam_i in nav.cam_coverage.get(n, [])))
	# При долгом сидении игрока на одном месте директор направляет его ближе.
	if world.director.player_camping() and world.director.request_escalation("courier", 2):
		# На ранних ночах — только стучит в дверь рабочего места (предупреждение).
		var target := nav.nearest(world.player.global_position) if aggression >= 8 else "wh_door_ws"
		go_to(target, _speed_walk())
		return
	if options.is_empty():
		options = PATROL_POINTS.duplicate()
	# Обычный обход не идёт через рабочее место и зал.
	var avoid := ["workstation", "hall", "vestibule"] if aggression < 9 else []
	if not go_to(options[rng.randi() % options.size()], _speed_walk(), avoid):
		go_to("wh_mid", _speed_walk())


func _tick(delta: float) -> void:
	if state == "off":
		return
	_saw_hide_t += delta
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = 0.2
		_sense()
	var p: Player = world.player
	match state:
		"patrol":
			_timer -= delta
			if not is_moving():
				if rng.randf() < 0.35 and current_room() == "warehouse":
					_work()
				else:
					_next_patrol()
			if _timer <= 0.0:
				_leave()
		"work":
			_timer -= delta
			if _timer <= 0.0:
				state = "patrol"
				_timer = rng.randf_range(40.0, 80.0)
				_next_patrol()
		"investigate":
			if not is_moving():
				state = "patrol"
				_next_patrol()
		"chase":
			if dist_to_player() < 1.0 and not p.is_hidden():
				attack("Курьер видит далеко, если вы на свету или с фонарём. В темноте двигайтесь медленно. Закрытая дверь задерживает его на пару секунд.")
				return
			if p.is_hidden():
				if _saw_hide_t < 1.5 and dist_to_player() < 2.5:
					attack("Курьер видел, как вы прячетесь. Прячьтесь, только когда он потерял вас из виду.")
					return
			_lost_t += delta
			if not is_moving() or _lost_t < 0.1:
				go_to(world.level.nav.nearest(_last_seen), _speed_chase())
			if _lost_t > 6.0:
				state = "search"
				_timer = rng.randf_range(8.0, 14.0)
		"search":
			_timer -= delta
			if not is_moving():
				var nb: PackedStringArray = world.level.nav.neighbors(point)
				if nb.size() > 0:
					go_to(nb[rng.randi() % nb.size()], _speed_walk())
			if _timer <= 0.0:
				state = "patrol"
				world.director.on_encounter_end("courier")
				_next_patrol()
		"leave":
			if not is_moving():
				hide_entity()
				state = "off"
				Sfx.play_3d("shutter", Vector3(5.4, 1.2, 0.3), -4.0, 0.9)
				world.director.schedule_return("courier", rng.randf_range(60.0, 140.0) - aggression * 3.0)


func _work() -> void:
	state = "work"
	_timer = rng.randf_range(4.0, 9.0)
	stop()
	Sfx.play_3d("rustle", global_position + Vector3.UP, -4.0)
	if rng.randf() < 0.5:
		Sfx.play_3d("creak", global_position + Vector3.UP * 1.5, -6.0)
	if world.director.request_escalation("courier_misplace", 0) and rng.randf() < 0.5:
		world.orders.misplace_random_box()
	elif rng.randf() < 0.3:
		var boxes: Array = world.orders.deliver_intake(1)
		var t: Dictionary = world.night.add_task("intake", "Приёмка: посылка от курьера (1)", 90.0, {"boxes": boxes, "left": 1})
		t["progress"] = "0/1"


func _sense() -> void:
	var p: Player = world.player
	if p.is_hidden():
		return
	var lit: bool = p.flashlight_on or world.level.lighting.is_zone_lit(Level.room_zone(p.current_room))
	var rng_sight := 12.0 if lit else (2.5 if p.crouching else 4.0)
	if sees_player(rng_sight, 130.0):
		_last_seen = p.global_position
		_lost_t = 0.0
		_saw_hide_t = 0.0
		if state != "chase":
			state = "chase"
			Sfx.play_3d("thud", global_position + Vector3.UP, -8.0, 0.7)
			world.director.on_encounter_start("courier")
			go_to(world.level.nav.nearest(_last_seen), _speed_chase())
		elif not is_moving() or world.level.nav.nearest(_last_seen) != (_path[_path.size() - 1] if _path.size() > 0 else ""):
			go_to(world.level.nav.nearest(_last_seen), _speed_chase())
		# Последние метры — напрямую.
		if dist_to_player() < 2.2:
			var to := p.global_position - global_position
			to.y = 0
			global_position += to.normalized() * _speed_chase() * 0.2
			face(p.global_position)


func on_noise(pos: Vector3, loudness: float) -> void:
	if state in ["off", "chase", "leave"]:
		return
	if pos.distance_to(global_position) <= loudness * 14.0:
		state = "investigate"
		go_to(world.level.nav.nearest(pos), _speed_walk() * 1.4)


func _leave() -> void:
	state = "leave"
	go_to("wh_shutter", _speed_walk())


func on_blocked(_door: Door) -> void:
	if state == "chase":
		state = "search"
		_timer = 6.0
