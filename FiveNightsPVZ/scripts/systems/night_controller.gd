class_name NightController
extends Node
## Время смены, задания, нарушения, письма, сценарий ночи, условия победы/поражения.

signal task_added(task)
signal task_changed(task)
signal mail_received(mail)
signal violation_added(count, reason)
signal hour_changed(hour)

const GAME_MINUTES := 360.0
const MAX_VIOLATIONS := 3

var world
var night := 1
var duration := 600.0
var elapsed := 0.0
var running := false
var tasks: Array = []
var mails: Array = []
var violations := 0
var used_cameras := false
var fakes_detected := 0
var inventory_cells: Array = []
var tech_key_taken := false
var own_order_ready := false
var finale := false
var _script: Array = []
var _script_i := 0
var _task_id := 0
var _mail_id := 0
var _last_hour := -1
var _fake_pool: Array = []
var rng := RandomNumberGenerator.new()


func setup(w, n: int) -> void:
	world = w
	night = n
	duration = NightData.duration(n)
	_script = NightData.script_for(n).duplicate()
	rng.seed = GameState.run_seed + n
	_fake_pool = range(Story.FAKE_MAILS.size())
	_fake_pool.shuffle()
	_spawn_checkpoints()
	_spawn_document()
	_setup_static_interactions()


func start() -> void:
	running = true


# ------------------------------------------------------------------ Время

func minute() -> float:
	return elapsed / duration * GAME_MINUTES


func clock_text(offset_min := 0.0) -> String:
	var m := int(minute() + offset_min)
	return "%02d:%02d" % [clampi(m / 60, 0, 6), m % 60 if m < 360 else 0]


func hour() -> int:
	return int(minute() / 60.0)


func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	var m := minute()
	while _script_i < _script.size() and m >= float(_script[_script_i][0]):
		var beat: Array = _script[_script_i]
		_script_i += 1
		run_beat(beat[1], beat[2])
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)
		for l in world.level.clock_labels:
			(l as Label3D).text = clock_text()
	elif int(elapsed * 2.0) % 10 == 0:
		for l in world.level.clock_labels:
			(l as Label3D).text = clock_text()
	_check_deadlines(m)
	_check_fake_triggers()
	if m >= GAME_MINUTES:
		running = false
		world.end_night(true, "")


# ------------------------------------------------------------------ Сценарий

const TUTORIAL := {
	"intake": "Поступление: коробки на поддоне у рольставни (склад). Отнесите каждую к сканеру на стойке, затем — в указанную ячейку.",
	"client": "У стойки клиент. Сядьте за компьютер → «Заказы» → откройте карточку, найдите коробку в ячейке и положите на стойку.",
	"woman_request": "Голос из примерочной. Пакеты с размерами висят на вешалах в складе у восточной стены. Передайте через шторку.",
	"real_task": "Новое письмо с заданием обхода. Метки обхода — синие таблички на стенах.",
	"breaker": "Выбило автомат. Электрощиток — в подсобке, в конце служебного коридора.",
	"phone": "Звонит телефон на стене рабочего места. Он отключён много лет.",
	"faceless_outside": "Кто-то стоит за стеклянной дверью. Магнитный замок включён — он не войдёт. Не отключайте замок.",
}


func run_beat(kind: String, param) -> void:
	if night == 1 and not GameState.is_custom_night and TUTORIAL.has(kind):
		var hint: String = TUTORIAL[kind]
		get_tree().create_timer(2.5).timeout.connect(func(): world.hud_message(hint, 8.0))
	match kind:
		"mail_intro":
			var m := Story.intro_mail(night if not GameState.is_custom_night else 6, GameState.player_name())
			if not m.is_empty():
				add_mail(Story.REAL_SENDER, m["subject"], m["body"], false)
		"hint":
			world.hud_message(str(param), 6.0)
		"intake":
			var boxes: Array = world.orders.deliver_intake(int(param))
			var t := add_task("intake", "Приёмка: отсканировать и разложить посылки (%d)" % boxes.size(), 100.0, {"boxes": boxes, "left": boxes.size()})
			t["progress"] = "0/%d" % boxes.size()
			world.director.on_scripted("intake")
		"client":
			world.spawn_client(str(param))
		"woman_request":
			if world.entities.has("woman"):
				world.entities["woman"].request()
		"phone":
			world.ring_phone(int(param))
		"real_task":
			var rt: Dictionary = Story.REAL_TASK_MAILS[int(param) % Story.REAL_TASK_MAILS.size()]
			add_mail(Story.REAL_SENDER, rt["subject"], rt["body"], false, {"task": rt["task"], "checkpoint": rt["checkpoint"]})
		"breaker":
			world.trip_breaker(str(param))
		"faceless_outside":
			if world.entities.has("faceless"):
				world.entities["faceless"].appear_outside()
		"maglock_fail":
			world.maglock_fail()
		"courier_start":
			if world.entities.has("courier"):
				world.entities["courier"].activate()
		"returner":
			if world.entities.has("returner"):
				world.entities["returner"].arrive()
		"fake_mail":
			send_fake_mail()
		"inspector_cam":
			if world.entities.has("inspector"):
				world.entities["inspector"].appear_on_camera()
		"inventory":
			var ids: Array = world.level.cells.keys()
			ids.shuffle()
			inventory_cells = ids.slice(0, int(param))
			var t2 := add_task("inventory", "Инвентаризация: сверить ячейки %s" % ", ".join(PackedStringArray(inventory_cells)), 200.0, {"left": inventory_cells.duplicate()})
			t2["progress"] = "0/%d" % inventory_cells.size()
		"tech_key":
			world.enable_tech_key()
		"own_order":
			own_order_ready = true
			world.on_own_order_arrived()
		"finale":
			finale = true
			world.start_finale()


# ------------------------------------------------------------------ Задания

func add_task(kind: String, title: String, deadline_min: float, data := {}, fake := false) -> Dictionary:
	_task_id += 1
	var t := {"id": _task_id, "kind": kind, "title": title, "deadline": minute() + deadline_min if deadline_min > 0 else -1.0, "done": false, "failed": false, "data": data, "fake": fake, "progress": ""}
	tasks.append(t)
	task_added.emit(t)
	Sfx.play_ui("beep", -16.0, 0.8)
	return t


func complete_task(t: Dictionary) -> void:
	if t["done"] or t["failed"]:
		return
	t["done"] = true
	task_changed.emit(t)
	Sfx.play_ui("beep", -14.0, 1.3)


func fail_task(t: Dictionary, reason := "") -> void:
	if t["done"] or t["failed"]:
		return
	t["failed"] = true
	task_changed.emit(t)
	if not t["fake"]:
		add_violation(reason if reason != "" else "Не выполнено: " + t["title"])


func active_tasks() -> Array:
	return tasks.filter(func(t): return not t["done"] and not t["failed"])


func find_task(kind: String, pred := Callable()) -> Dictionary:
	for t in tasks:
		if t["kind"] == kind and not t["done"] and not t["failed"]:
			if not pred.is_valid() or pred.call(t):
				return t
	return {}


func _check_deadlines(m: float) -> void:
	for t in tasks:
		if t["done"] or t["failed"] or t["deadline"] < 0:
			continue
		if m >= t["deadline"]:
			if t["fake"]:
				t["failed"] = true
				task_changed.emit(t)
			else:
				world.on_task_expired(t)
				fail_task(t)


func add_violation(reason: String) -> void:
	violations += 1
	violation_added.emit(violations, reason)
	world.hud_message("НАРУШЕНИЕ: %s (%d/%d)" % [reason, violations, MAX_VIOLATIONS], 5.0)
	if night >= 2 and violations >= MAX_VIOLATIONS:
		world.fired()


func on_parcel_scanned(box: CarryBox) -> void:
	world.hud_message("Отнесите посылку в ячейку %s." % box.cell)


func on_parcel_stored(box: CarryBox) -> void:
	var t := find_task("intake", func(tt): return box in tt["data"]["boxes"])
	if t.is_empty():
		return
	t["data"]["left"] -= 1
	var total: int = (t["data"]["boxes"] as Array).size()
	t["progress"] = "%d/%d" % [total - int(t["data"]["left"]), total]
	task_changed.emit(t)
	if int(t["data"]["left"]) <= 0:
		complete_task(t)


func on_cell_checked(cell_id: String) -> void:
	var t := find_task("inventory")
	if t.is_empty():
		world.hud_message("Ячейка %s: %d поз." % [cell_id, (world.level.cells[cell_id] as DropSpot).stored.size()])
		return
	var left: Array = t["data"]["left"]
	if cell_id in left:
		left.erase(cell_id)
		Sfx.play_3d("beep", world.player.global_position, -10.0)
		world.hud_message("Ячейка %s сверена." % cell_id)
		t["progress"] = "%d/%d" % [inventory_cells.size() - left.size(), inventory_cells.size()]
		task_changed.emit(t)
		if left.is_empty():
			complete_task(t)
	else:
		world.hud_message("Ячейка %s не входит в список." % cell_id)


# ------------------------------------------------------------------ Почта

func add_mail(sender: String, subject: String, body: String, fake: bool, extra := {}) -> Dictionary:
	_mail_id += 1
	var shown_time := clock_text()
	if fake and rng.randf() < 0.5:
		shown_time = clock_text(rng.randf_range(40, 140))  # письмо «из будущего»
	var mail := {"id": _mail_id, "sender": sender, "subject": subject, "body": body, "time": shown_time, "fake": fake, "read": false, "reported": false}
	mail.merge(extra)
	if extra.has("task"):
		var t := add_task("fake" if fake else "patrol", extra["task"], 70.0, {"mail": _mail_id, "checkpoint": extra.get("checkpoint", ""), "action": extra.get("action", "")}, fake)
		mail["task_ref"] = t
	mails.append(mail)
	mail_received.emit(mail)
	world.hud_message("Новое письмо на компьютере.", 3.0)
	return mail


func send_fake_mail() -> void:
	if _fake_pool.is_empty():
		_fake_pool = range(Story.FAKE_MAILS.size())
		_fake_pool.shuffle()
	var f: Dictionary = Story.FAKE_MAILS[_fake_pool.pop_back()]
	var sender: String = Story.FAKE_SENDERS[rng.randi() % Story.FAKE_SENDERS.size()]
	add_mail(sender, f["subject"], f["body"], true, {"task": f["task"], "action": f["action"]})


func report_mail(mail: Dictionary) -> void:
	if mail["reported"]:
		return
	mail["reported"] = true
	if mail["fake"]:
		fakes_detected += 1
		GameState.add_stat("fakes_detected")
		world.hud_message("Письмо отмечено как поддельное. Спасибо.")
		if mail.has("task_ref"):
			var t: Dictionary = mail["task_ref"]
			t["failed"] = true
			task_changed.emit(t)
		if fakes_detected >= 3:
			if GameState.unlock_achievement("fake_detect"):
				world.hud_message("Достижение: Служебная проверка")
	else:
		add_violation("ложная жалоба на письмо руководства")


func _check_fake_triggers() -> void:
	var p: Player = world.player
	for t in tasks:
		if not t["fake"] or t["done"] or t["failed"]:
			continue
		var act: String = t["data"].get("action", "")
		var hit := false
		match act:
			"unlock_door":
				hit = not world.level.doors["front"].locked
			"warehouse_dark":
				hit = not world.level.lighting.switches["warehouse"]
			"hall_dark":
				hit = not world.level.lighting.switches["hall"]
			"tech_door":
				hit = p.global_position.distance_to(Vector3(13.6, 0, 1.5)) < 1.2
			"toilet_wait":
				hit = p.current_room == "toilet"
		if hit:
			t["done"] = true
			task_changed.emit(t)
			world.director.on_fake_followed(act)


# ------------------------------------------------------------------ Метки, документы

const CHECKPOINTS := {
	"cp_warehouse": [Vector3(0.12, 1.3, 5.6), Vector3(0, 90, 0)],
	"cp_corridor": [Vector3(13.88, 1.3, 11.6), Vector3(0, -90, 0)],
	"cp_utility": [Vector3(17.88, 1.3, 4.4), Vector3(0, -90, 0)],
	"cp_entrance": [Vector3(3.28, 1.3, 14.3), Vector3(0, -90, 0)],
	"cp_toilet": [Vector3(14.12, 1.3, 10.6), Vector3(0, 90, 0)],
}


func _spawn_checkpoints() -> void:
	for id in CHECKPOINTS.keys():
		var c := Interactable.new()
		c.position = CHECKPOINTS[id][0]
		c.rotation_degrees = CHECKPOINTS[id][1]
		world.level.add_child(c)
		Build.box(c, Vector3(0.1, 0.1, 0.02), Vector3.ZERO, Mats.color(Color(0.1, 0.4, 0.8)))
		Build.label(c, "МЕТКА", Vector3(0, 0.09, 0.012), 0.025, Color(0.1, 0.1, 0.1))
		c.setup_shape(Vector3(0.2, 0.2, 0.1))
		c.prompt_text = "Отметиться на метке"
		c.tag = id
		c.action = func(_p): _on_checkpoint(id)
		world.level.checkpoints[id] = c


func _on_checkpoint(id: String) -> void:
	Sfx.play_3d("beep", world.player.global_position, -8.0, 1.2)
	var t := find_task("patrol", func(tt): return tt["data"].get("checkpoint", "") == id)
	if t.is_empty():
		world.hud_message("Отметка принята. %s" % clock_text())
		return
	complete_task(t)
	world.hud_message("Обход отмечен.")


func _spawn_document() -> void:
	if GameState.is_custom_night or night > 5:
		return
	var place: Array = Story.DOCUMENT_PLACES[night - 1]
	var doc: Dictionary = Story.DOCUMENTS[place[1] - 1]
	var n := Note.new()
	n.title = doc["title"]
	n.body = doc["body"]
	n.doc_index = place[1]
	n.position = place[0]
	world.level.add_child(n)
	Build.box(n, Vector3(0.2, 0.01, 0.28), Vector3.ZERO, Mats.color(Color(0.88, 0.85, 0.75)), false, Vector3(0, 20, 0))
	n.setup_shape(Vector3(0.3, 0.12, 0.35))


func _setup_static_interactions() -> void:
	var lv: Level = world.level
	lv.breaker_panel.action = func(_p): world.reset_breakers()
	lv.maglock.action = func(_p): world.toggle_maglock()
	lv.desk_seat.action = func(_p): world.open_desk()
	lv.phone.action = func(_p): world.answer_phone()
	lv.printer.action = func(_p): world.take_receipt()
	lv.tech_terminal.action = func(_p): world.open_tech_terminal()
	lv.counter_spot.item_placed.connect(func(_s, box): world.on_counter_item(box))
	world.orders.parcel_scanned.connect(on_parcel_scanned)
	world.orders.parcel_stored.connect(on_parcel_stored)
