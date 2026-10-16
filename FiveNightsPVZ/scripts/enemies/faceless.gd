class_name Faceless
extends Entity
## Клиент без лица. Почти беззвучен. Входит, только если магнитный замок
## отключён (или правила нарушаются на поздних ночах). Внутри:
## — долгий взгляд в лицо убивает (шкала «взгляда»),
## — если заказ не выдан вовремя, приближается, пока на него не смотрят.
## На камерах внутри помещения не виден — только рябь помех.

var state := "hidden"
var card := {}
var task := {}
var stare := 0.0
var _timer := 0.0
var _hop := 0.0
var _was_close := false


func model_options() -> Dictionary:
	return {"jacket": Color(0.16, 0.17, 0.2), "pants": Color(0.1, 0.1, 0.12), "skin": Color(0.6, 0.52, 0.47), "faceless": true, "height": 1.04, "thin": 0.95}


func _on_setup() -> void:
	step_sound = ""
	speed = 0.9
	can_open_doors = true


func appear_outside() -> void:
	if aggression <= 0 or state != "hidden":
		return
	global_position = world.level.spawn["faceless_outside"]
	point = "outside"
	visible = true
	active = true
	face(Vector3(1.6, 0, 14.0))
	set_vis_layers(Build.VIS_ALL)
	state = "outside"
	_timer = rng.randf_range(45.0, 90.0) * (1.0 + aggression * 0.05)
	world.director.note_event("faceless_outside")


## Нарушение правил: появляется у стойки, хотя дверь заперта.
func appear_inside() -> void:
	if state != "hidden":
		return
	state = "pending_inside"
	active = true


func _tick(delta: float) -> void:
	match state:
		"outside":
			_timer -= delta
			if not world.level.doors["front"].locked:
				_enter()
			elif _timer <= 0.0 and not seen_by_player():
				_vanish()
		"pending_inside":
			var p: Vector3 = world.level.nav.pos_of("hall_counter") + Vector3.UP
			if not world.player.in_view(p):
				show_at("hall_counter", world.player.global_position)
				set_vis_layers(Build.VIS_EYES_ONLY)
				_at_counter()
		"entering":
			pass
		"counter":
			face(world.player.global_position)
		"stalk":
			_stalk(delta)
		"leaving":
			if not seen_by_player():
				_vanish()
	if state in ["counter", "stalk", "entering"]:
		_update_stare(delta)


func _enter() -> void:
	state = "entering"
	set_vis_layers(Build.VIS_EYES_ONLY)
	var d: Door = world.level.doors["front"]
	d.set_open(true, false, 0.4)
	go_to("hall_counter", 0.9)


func on_arrived() -> void:
	if state == "entering":
		world.level.doors["front"].set_open(false, false, 0.3)
		_at_counter()


func _at_counter() -> void:
	state = "counter"
	face(world.level.counter_spot.global_position)
	card = world.orders.create_card("faceless")
	if card.is_empty():
		state = "leaving"
		return
	var deadline := maxf(25.0, 55.0 - aggression * 1.5)
	task = world.night.add_task("issue", "Выдать заказ клиенту без лица — откройте карточку", deadline, {"card": card})
	world.subtitle(Story.FACELESS_LINES[rng.randi() % Story.FACELESS_LINES.size()], 4.0)
	world.director.note_event("faceless_inside")


func on_card_opened() -> void:
	if not task.is_empty():
		task["title"] = "Выдать заказ %s · ячейка %s (не смотрите ему в лицо)" % [card["no"], card["cell"]]
		world.night.task_changed.emit(task)


func on_issued() -> void:
	world.night.complete_task(task)
	for b in world.level.counter_spot.stored.duplicate():
		if b is CarryBox and b.order_no == card["no"]:
			world.level.counter_spot.take_out(b)
			b.queue_free()
	if _was_close:
		GameState.unlock_achievement("stare")
	state = "leaving"
	card = {}
	world.subtitle("[он забирает коробку. Вы не слышали, как он ушёл]", 4.0)


func on_timeout() -> void:
	# Заказ не выдан: начинает приближаться. Карточка остаётся действительной.
	state = "stalk"
	world.orders.active_cards.append(card)
	_hop = 3.0
	world.director.note_event("faceless_stalk")


func _stalk(delta: float) -> void:
	var p: Player = world.player
	if dist_to_player() < 1.3:
		attack("Клиент без лица приближается, только когда вы на него не смотрите. Выдайте ему заказ — даже после срока, — но не смотрите в лицо.")
		return
	if dist_to_player() < 2.5:
		_was_close = true
	_hop -= delta
	if _hop > 0.0:
		return
	if seen_by_player():
		_hop = 0.5
		return
	_hop = maxf(2.0, rng.randf_range(4.0, 7.0) - aggression * 0.15)
	var nav: NavGraph = world.level.nav
	var path := nav.path(nav.nearest(global_position), nav.nearest(p.global_position), true)
	if path.size() >= 2:
		var next := path[1]
		# Проверяем, не закрыта ли дверь на пути — её он открывает бесшумно.
		var d := nav.door_between(path[0], next)
		if d and d.locked:
			return
		if d and not d.is_open:
			d.set_open(true, true)
		global_position = nav.pos_of(next)
		point = next
	else:
		# Та же точка — подходит вплотную шагами.
		var to: Vector3 = p.global_position - global_position
		to.y = 0
		global_position += to.normalized() * minf(to.length() - 0.8, 1.2)
	face(p.global_position)
	if rng.randf() < 0.3:
		Sfx.play_3d("cloth", global_position + Vector3.UP, -18.0, 0.7)


func _update_stare(delta: float) -> void:
	var p: Player = world.player
	var looking := visible and p.is_looking_at(head_pos(), 9.0) and dist_to_player() < 8.0
	if looking:
		var close := clampf(1.0 - dist_to_player() / 8.0, 0.0, 1.0)
		stare += delta * (0.12 + close * 0.35 + aggression * 0.01)
	else:
		stare = maxf(0.0, stare - delta * 0.35)
	world.stare_value = stare
	model.set_face_intensity(0.6 + stare)
	if stare >= 1.0:
		attack("Не смотрите Клиенту без лица в лицо дольше пары секунд. Отводите взгляд — шкала спадает.")


func _vanish() -> void:
	hide_entity()
	state = "hidden"
	stare = 0.0
	world.stare_value = 0.0
