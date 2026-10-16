class_name Returner
extends Entity
## «Возврат». Требует вернуть деньги, каждый раз с другим товаром.
## Решение принимается в компьютере по регламенту. Ошибки и ожидание злят его;
## с каждым визитом он всё меньше похож на человека.

var state := "off"   # off | waiting | leaving | lunge
var request := {}
var task := {}
var visits := 0
var anger := 0
var _bell_t := 0.0
var _timer := 0.0
var _line_t := 0.0


func model_options() -> Dictionary:
	return {"jacket": Color(0.35, 0.3, 0.22), "pants": Color(0.2, 0.18, 0.15), "skin": Color(0.7, 0.6, 0.53), "height": 1.0, "thin": 1.05}


func _on_setup() -> void:
	step_sound = "step"
	step_volume = -10.0
	door_force_time = 1.5


func stage() -> int:
	return clampi(visits - 1 + anger, 0, 3)


func _apply_stage() -> void:
	var s := stage()
	var skin := Color(0.7, 0.6, 0.53).lerp(Color(0.5, 0.52, 0.5), s / 3.0)
	model.queue_free()
	model = HumanoidModel.new()
	add_child(model)
	model.build({"jacket": Color(0.35, 0.3, 0.22).darkened(s * 0.15), "pants": Color(0.2, 0.18, 0.15), "skin": skin, "height": 1.0 + s * 0.05, "thin": 1.05 - s * 0.1, "arm_len": 1.0 + s * 0.22, "neck_len": 1.0 + s * 0.5})
	model.head_tilt(s * 0.25, s * 0.1)
	stiff = s * 0.3


func arrive() -> void:
	if aggression <= 0 or state != "off":
		return
	visits += 1
	_apply_stage()
	state = "appear"
	active = true


func _process(delta: float) -> void:
	if state == "appear":
		var c: Vector3 = world.level.nav.pos_of("hall_counter") + Vector3.UP
		if not world.player.in_view(c) or world.player.global_position.distance_to(c) > 9.0:
			show_at("hall_counter", world.level.counter_spot.global_position)
			_begin_wait()
		return
	super._process(delta)


func _begin_wait() -> void:
	state = "waiting"
	request = world.orders.make_return_request(stage())
	request["valid"] = world.orders.is_return_valid(request)
	var deadline := maxf(25.0, 45.0 - aggression)
	task = world.night.add_task("return", "Возврат: проверить заявку в компьютере и принять решение", deadline, {"request": request})
	_bell_t = 0.0
	_say()
	world.director.note_event("returner")


func _say() -> void:
	var lines: Array = Story.RETURNER_LINES[stage()]
	world.subtitle("Клиент у стойки: «%s»" % lines[rng.randi() % lines.size()], 4.0)


func _tick(delta: float) -> void:
	match state:
		"waiting":
			face(world.player.global_position)
			model.head_tilt(stage() * 0.25 + sin(_t * 0.7) * 0.05 * stage(), stage() * 0.1)
			_bell_t -= delta
			if _bell_t <= 0.0:
				_bell_t = maxf(3.0, 12.0 - stage() * 3.0)
				Sfx.play_3d("bell", world.level.counter_spot.global_position + Vector3(0.8, 0, 0.2), -9.0 + stage() * 1.5, 1.0 - stage() * 0.05)
			_line_t -= delta
			if _line_t <= 0.0:
				_line_t = rng.randf_range(15.0, 25.0)
				_say()
		"leaving":
			if not seen_by_player():
				hide_entity()
				state = "off"
		"lunge":
			_timer -= delta
			var p: Player = world.player
			if dist_to_player() < 1.0 and not p.is_hidden():
				attack("Возврат: проверяйте заявку по регламенту (заказ в базе, статус «Выдан», не старше 14 дней, тот же товар) и не заставляйте его ждать. Мерцание ламп — признак его гнева.")
				return
			if not is_moving() or int(_timer * 2.0) % 3 == 0:
				go_to(world.level.nav.nearest(p.global_position), 2.6 + aggression * 0.03)
			if _timer <= 0.0:
				hide_entity()
				state = "off"
				world.director.on_encounter_end("returner")


## Решение игрока из компьютера.
func decide(accept: bool) -> void:
	if state != "waiting":
		return
	var correct: bool = accept == bool(request["valid"])
	GameState.add_stat("returns_processed")
	world.night.complete_task(task)
	if correct:
		world.subtitle("Клиент: «…Хорошо». [он уходит]" if accept else "Клиент: «Я вернусь». [он уходит]", 3.0)
		_leave()
	else:
		_anger_up()
		if state == "waiting":
			_leave()


func on_timeout() -> void:
	if state != "waiting":
		return
	_anger_up()
	if state == "waiting":
		task = world.night.add_task("return", "Возврат: клиент всё ещё ждёт!", 25.0, {"request": request})


func _anger_up() -> void:
	anger += 1
	world.level.lighting.flicker_zone("hall", 3.0)
	world.level.lighting.flicker_zone("workstation", 2.0)
	Sfx.play_3d("buzz", world.level.counter_spot.global_position + Vector3.UP, -10.0)
	if anger >= 3:
		_lunge()
	else:
		world.hud_message("Клиент недоволен. Лампы над стойкой мигают.", 3.0)
		_apply_stage()


func _lunge() -> void:
	state = "lunge"
	_timer = 22.0
	_apply_stage()
	model.reach(0.8)
	world.subtitle("«ВЕРНИТЕ»", 2.0)
	world.director.on_encounter_start("returner")
	Sfx.play_3d("thud", global_position + Vector3.UP, -6.0, 0.8)
	go_to(world.level.nav.nearest(world.player.global_position), 2.6)


func _leave() -> void:
	state = "leaving"
	go_to("vest", 1.1)
