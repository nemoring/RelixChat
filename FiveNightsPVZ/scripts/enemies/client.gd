class_name Client
extends Entity
## Обычный ночной клиент. Появляется в зале, хотя входная дверь заперта.

var card := {}
var kind := "normal"
var state := "idle"
var task := {}
var _wait := 0.0


func model_options() -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return {
		"jacket": Color.from_hsv(r.randf(), r.randf_range(0.1, 0.4), r.randf_range(0.15, 0.4)),
		"pants": Color.from_hsv(r.randf(), 0.1, r.randf_range(0.08, 0.2)),
		"skin": Color(0.72, 0.6, 0.52).darkened(r.randf_range(0, 0.25)),
		"height": r.randf_range(0.93, 1.06), "thin": r.randf_range(0.9, 1.15),
		"long_hair": r.randf() < 0.35,
	}


func begin(k: String) -> void:
	kind = k
	step_sound = "step_soft"
	step_volume = -14.0
	speed = 1.1
	card = world.orders.create_card("normal")
	if card.is_empty():
		queue_free()
		return
	if kind == "inside" or world.level.doors["front"].locked:
		# Появляется уже у стойки, когда никто не смотрит на зал.
		state = "appear"
	else:
		show_at("vest")
		go_to("hall_counter")
		state = "walk_in"


func _tick(delta: float) -> void:
	match state:
		"appear":
			pass
		"waiting":
			_wait += delta
			face(world.player.global_position)
			if kind == "inside":
				model.head_tilt(sin(_t * 0.3) * 0.15 + 0.2)
			if _wait > 25.0 and int(_wait) % 25 == 0 and _wait - delta < floorf(_wait):
				Sfx.play_3d("bell", world.level.counter_spot.global_position + Vector3(0.8, 0, 0.2), -10.0)
		"leaving":
			if not is_moving() and not seen_by_player():
				queue_free()


func _process(delta: float) -> void:
	if state == "appear":
		var cam_pos: Vector3 = world.level.nav.pos_of("hall_counter") + Vector3.UP
		if not world.player.in_view(cam_pos) or world.player.global_position.distance_to(cam_pos) > 9.0:
			show_at("hall_counter", world.player.global_position)
			_arrive()
		return
	super._process(delta)


func on_arrived() -> void:
	if state == "walk_in":
		_arrive()
	elif state == "leaving" and not seen_by_player():
		queue_free()


func _arrive() -> void:
	state = "waiting"
	active = true
	face(world.level.counter_spot.global_position)
	Sfx.play_3d("bell", world.level.counter_spot.global_position + Vector3(0.8, 0, 0.2), -8.0)
	task = world.night.add_task("issue", "Выдать заказ клиенту — откройте карточку на компьютере", 60.0, {"card": card})
	world.director.on_client_arrived(self)


func on_card_opened() -> void:
	if not task.is_empty():
		task["title"] = "Выдать заказ %s · ячейка %s" % [card["no"], card["cell"]]
		world.night.task_changed.emit(task)


func on_issued() -> void:
	world.night.complete_task(task)
	_take_box()
	world.subtitle("[клиент молча забирает коробку]" if kind == "inside" else "«Спасибо».", 3.0)
	_leave()


func _take_box() -> void:
	for b in world.level.counter_spot.stored.duplicate():
		if b is CarryBox and b.order_no == card["no"]:
			world.level.counter_spot.take_out(b)
			b.queue_free()


func leave_unserved() -> void:
	if kind == "inside":
		world.subtitle("[клиент долго смотрит на вас, потом уходит]", 3.0)
	_leave()


func _leave() -> void:
	state = "leaving"
	go_to("vest", 1.1)
