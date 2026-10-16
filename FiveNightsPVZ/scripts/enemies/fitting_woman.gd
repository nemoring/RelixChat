class_name FittingWoman
extends Entity
## Женщина из примерочной. Сначала — только голос и просьбы принести размер.
## Правило: если из-за шторки слышно ДЫХАНИЕ — шторку не открывать.
## Если тихо — кабинка пуста. Если её долго игнорировать (поздние ночи),
## она выходит и ищет по звуку: она слепа.

var state := "absent"   # absent | requesting | agitated | hunting | returning
var cabin := 0
var want_size := ""
var task := {}
var patience := 2
var _timer := 0.0
var _breath: AudioStreamPlayer3D
var _voice_t := 0.0
var _target_noise := Vector3.ZERO
var _has_target := false
var _sizes := ["42", "44", "46", "48", "50", "52"]


func model_options() -> Dictionary:
	return {"jacket": Color(0.32, 0.12, 0.14), "skin": Color(0.62, 0.58, 0.55), "hair": Color(0.03, 0.03, 0.03), "long_hair": true, "dress": true, "height": 1.12, "thin": 0.78, "arm_len": 1.25, "neck_len": 1.4}


func _on_setup() -> void:
	step_sound = "step_soft"
	step_volume = -16.0
	stiff = 0.6
	for c in world.level.cabins:
		(c["curtain"] as Curtain).toggled.connect(_on_curtain)
		var spot: DropSpot = c["spot"]
		spot.accept_fn = _accept_item.bind(world.level.cabins.find(c))
		spot.item_placed.connect(_on_item_given)


func cabin_pos() -> Vector3:
	return world.level.cabins[cabin]["inside"]


func request() -> void:
	if aggression <= 0 or state in ["hunting", "returning", "agitated"]:
		return
	cabin = rng.randi_range(0, 1)
	want_size = _sizes[rng.randi() % _sizes.size()]
	state = "requesting"
	patience = 2
	active = true
	var line: String = Story.WOMAN_LINES[mini(rng.randi() % Story.WOMAN_LINES.size(), 1 + aggression / 4)]
	line = line.replace("%s", want_size)
	_say(line)
	var deadline := maxf(30.0, 60.0 - aggression * 1.5)
	if not task.is_empty() and not task["done"] and not task["failed"]:
		task["failed"] = true
		world.night.task_changed.emit(task)
	task = world.night.add_task("woman", "Примерочная %d: принести размер %s (вешала на складе)" % [cabin + 1, want_size], deadline, {})
	_enable_spot(true)


func _say(line: String) -> void:
	Sfx.play_3d("whisper", cabin_pos() + Vector3.UP * 1.5, -12.0, 1.15, 14.0)
	world.subtitle("Голос из примерочной %d: %s" % [cabin + 1, line], 5.0)


func _enable_spot(on: bool) -> void:
	for i in world.level.cabins.size():
		(world.level.cabins[i]["spot"] as DropSpot).enabled = on and i == cabin


func _accept_item(box: CarryBox, idx: int) -> String:
	if box.kind != "clothes":
		return "Это не одежда."
	if idx != cabin:
		return "[за этой шторкой тихо]"
	if (world.level.cabins[idx]["curtain"] as Curtain).is_open:
		return "Задёрните шторку."
	return ""


func _on_item_given(_spot, box: CarryBox) -> void:
	if box.size_label == want_size:
		world.subtitle("Голос: %s" % Story.WOMAN_THANKS[rng.randi() % Story.WOMAN_THANKS.size()], 3.0)
		world.night.complete_task(task)
		_calm()
	else:
		patience -= 1
		world.subtitle("Голос: %s" % Story.WOMAN_WRONG[rng.randi() % Story.WOMAN_WRONG.size()], 3.0)
		Sfx.play_3d("knock", cabin_pos() + Vector3.UP, -10.0, 0.8)
		if patience <= 0:
			_agitate()


func _calm() -> void:
	state = "absent"
	_enable_spot(false)
	_stop_breath()


func on_timeout() -> void:
	if state != "requesting":
		return
	if world.night_index == 1 and not GameState.is_custom_night:
		# Обучающая ночь: голос просто замолкает.
		world.subtitle("[голос в примерочной затих]", 3.0)
		_calm()
		return
	_agitate()


func _agitate() -> void:
	state = "agitated"
	_enable_spot(true)
	_timer = rng.randf_range(35.0, 60.0) - aggression
	_start_breath(cabin_pos() + Vector3.UP * 1.4)
	world.director.note_event("woman_agitated")


func _start_breath(pos: Vector3) -> void:
	_stop_breath()
	_breath = Sfx.make_loop("breath", world.level, pos, -10.0, "SFX", 9.0)


func _stop_breath() -> void:
	if is_instance_valid(_breath):
		_breath.queue_free()
	_breath = null


func _on_curtain(curtain: Curtain, opened: bool) -> void:
	if not opened:
		return
	if curtain.cabin_index != cabin:
		if state != "absent" and rng.randf() < 0.3:
			world.subtitle("[пусто. Голос продолжает звучать из соседней кабинки]", 3.0)
		return
	match state:
		"agitated":
			_lunge_from_cabin()
		"requesting":
			world.subtitle("[в примерочной никого нет. На крючке висит платье]", 4.0)
			_say("…не открывайте. Я ещё не готова.")
		_:
			pass


func _lunge_from_cabin() -> void:
	show_at("cab_a" if cabin == 0 else "cab_b", world.player.global_position)
	set_vis_layers(Build.VIS_ALL)
	attack("Если из примерочной слышно дыхание — не открывайте шторку. Принесите нужный размер: это её успокоит.")


func _tick(delta: float) -> void:
	match state:
		"requesting":
			_voice_t -= delta
			if _voice_t <= 0.0:
				_voice_t = rng.randf_range(18.0, 32.0)
				if rng.randf() < 0.5:
					_say(("%s-й…" % want_size) if rng.randf() < 0.5 else "Вы там? Я жду.")
		"agitated":
			_timer -= delta
			if _timer <= 0.0:
				if aggression >= 7 and world.director.request_escalation("woman", 2):
					_emerge()
				else:
					_timer = rng.randf_range(20.0, 35.0)
		"hunting":
			_hunt(delta)
		"returning":
			if not is_moving():
				hide_entity()
				_stop_breath()
				(world.level.cabins[cabin]["curtain"] as Curtain).set_open(false)
				active = true
				state = "requesting" if not task.get("done", true) and not task.get("failed", true) else "absent"
				if state == "requesting":
					_agitate()


func _emerge() -> void:
	state = "hunting"
	var cab := world.level.cabins[cabin] as Dictionary
	(cab["curtain"] as Curtain).set_open(true)
	show_at("cab_a" if cabin == 0 else "cab_b")
	set_vis_layers(Build.VIS_ALL)
	_stop_breath()
	_breath = Sfx.make_loop("breath", self, Vector3(0, 1.6, 0), -8.0, "SFX", 8.0)
	_timer = rng.randf_range(45.0, 70.0) + aggression
	speed = 1.0
	go_to("cab_a_front" if cabin == 0 else "cab_b_front")
	world.subtitle("[шторка отдёрнулась сама]", 3.0)
	world.director.note_event("woman_hunt")


func on_noise(pos: Vector3, loudness: float) -> void:
	if state != "hunting":
		return
	var hear_r := 3.0 + loudness * 12.0
	if pos.distance_to(global_position) <= hear_r:
		_target_noise = pos
		_has_target = true
		var nav: NavGraph = world.level.nav
		go_to(nav.nearest(pos), 1.2 + loudness * 1.2 + aggression * 0.04)


func _hunt(delta: float) -> void:
	_timer -= delta
	var p: Player = world.player
	var d := dist_to_player()
	if d < 1.1 and not p.is_hidden() and (p.noise_level > 0.15 or d < 0.7):
		attack("Женщина из примерочной слепа и идёт на звук. Присядьте, не двигайтесь или спрячьтесь, пока она не вернётся в кабинку.")
		return
	if _has_target and not is_moving():
		_has_target = false
		# Добралась до источника звука: медленно «прислушивается».
		var to := _target_noise - global_position
		to.y = 0
		if to.length() > 0.4:
			global_position += to.normalized() * minf(to.length(), delta * 0.6)
	if not is_moving() and not _has_target and rng.randf() < delta * 0.25:
		var pts: PackedStringArray = world.level.nav.neighbors(world.level.nav.nearest(global_position))
		if pts.size() > 0:
			go_to(pts[rng.randi() % pts.size()], 0.8)
	if _timer <= 0.0:
		state = "returning"
		go_to("cab_a" if cabin == 0 else "cab_b", 1.0)


func is_breathing() -> bool:
	return state == "agitated"
