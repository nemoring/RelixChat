class_name OrderSystem
extends Node
## База заказов, коробки в ячейках, приёмка, выдача, возвраты.

signal order_issued(order)
signal parcel_scanned(box)
signal parcel_stored(box)
signal card_opened(order)

var world  # GameWorld
var rng := RandomNumberGenerator.new()
var orders: Array = []          # все записи базы
var active_cards: Array = []    # открытые карточки выдачи (клиенты ждут)
var pending_card: Dictionary = {}  # карточка, открытая на экране
var intake_boxes: Array = []
var _counter := 100000
var today := "12.11.2026"
var player_order: Dictionary = {}


func setup(w, night: int, seed_v: int) -> void:
	world = w
	rng.seed = seed_v
	today = Story.NIGHT_DATES[clampi(night, 1, 6)]
	_counter = 118300 + night * 997 + rng.randi_range(0, 400)
	_build_history(night)
	_fill_cells()
	w.level.scanner_spot.accept_fn = _scanner_accept
	w.level.counter_spot.accept_fn = _counter_accept
	for cell_id in w.level.cells.keys():
		var spot: DropSpot = w.level.cells[cell_id]
		spot.accept_fn = _cell_accept.bind(cell_id)
		spot.action = _cell_check.bind(cell_id)
		spot.prompt_text = "Сверить ячейку %s" % cell_id


func _next_no() -> String:
	_counter += rng.randi_range(3, 41)
	return "П-%06d" % _counter


func _date_days_ago(days: int) -> String:
	var t := Time.get_unix_time_from_datetime_string(_iso(today)) - days * 86400
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d.%02d.%04d" % [d.day, d.month, d.year]


static func _iso(ddmmyyyy: String) -> String:
	var p := ddmmyyyy.split(".")
	return "%s-%s-%sT00:00:00" % [p[2], p[1], p[0]]


static func days_between(a: String, b: String) -> int:
	var ta := Time.get_unix_time_from_datetime_string(_iso(a))
	var tb := Time.get_unix_time_from_datetime_string(_iso(b))
	return int(round((tb - ta) / 86400.0))


func _build_history(night: int) -> void:
	orders.clear()
	# Обычные выданные заказы за последний месяц — нужны для проверки возвратов.
	for i in 40:
		var days := rng.randi_range(0, 30)
		orders.append({
			"no": _next_no(), "recipient": Story.random_name(rng),
			"product": Story.PRODUCTS[rng.randi() % Story.PRODUCTS.size()],
			"cell": "", "status": "Выдан", "date": _date_days_ago(days), "kind": "normal",
		})
	# Пропавшие люди: их заказы до сих пор висят в базе.
	for m in Story.MISSING:
		orders.append({"no": m[1], "recipient": m[0], "product": m[3], "cell": "—", "status": "Ожидает получения" if m[0] != "Ключников А. Д." else "Выдан", "date": m[2], "kind": "missing"})
	# Заказ на имя игрока появляется со второй ночи и «едет» к пятой.
	if night >= 2:
		var st := "Оформлен" if night == 2 else ("В пути" if night < 5 else "В пути")
		player_order = {"no": "П-000007", "recipient": GameState.player_name(), "product": "—", "cell": "ТЕХ", "status": st, "date": today, "kind": "player"}
		orders.append(player_order)


## Расставляет коробки ожидающих заказов по ячейкам.
func _fill_cells() -> void:
	var ids: Array = world.level.cells.keys()
	ids.shuffle()
	for cell_id in ids:
		var count := rng.randi_range(1, 2)
		for k in count:
			var o := {
				"no": _next_no(), "recipient": Story.random_name(rng),
				"product": Story.PRODUCTS[rng.randi() % Story.PRODUCTS.size()],
				"cell": cell_id, "status": "Ожидает получения", "date": _date_days_ago(rng.randi_range(0, 5)), "kind": "normal",
			}
			orders.append(o)
			var box := make_box(o)
			world.level.cells[cell_id].stored.append(box)
			world.level.cells[cell_id].add_child(box)
			box.position = world.level.cells[cell_id].place_offset + Vector3(0.32 * k, 0, 0)
			box.rotation = Vector3.ZERO


func make_box(o: Dictionary) -> CarryBox:
	var b := CarryBox.new()
	var size := Vector3(rng.randf_range(0.28, 0.45), rng.randf_range(0.18, 0.34), rng.randf_range(0.22, 0.32))
	b.build(size, "parcel")
	b.order_no = o["no"]
	b.recipient = o["recipient"]
	b.cell = o["cell"]
	b.box_id = o["no"]
	b.refresh_label()
	o["box"] = b
	return b


func find(no: String) -> Dictionary:
	no = no.strip_edges().to_upper()
	for o in orders:
		if str(o["no"]).to_upper() == no:
			return o
	return {}


func search(query: String) -> Array:
	query = query.strip_edges().to_lower()
	var out := []
	for o in orders:
		if query == "" or str(o["no"]).to_lower().contains(query) or str(o["recipient"]).to_lower().contains(query):
			out.append(o)
	return out


# ------------------------------------------------------------------ Приёмка

func deliver_intake(count: int) -> Array:
	var spot: DropSpot = world.level.intake_spot
	var made := []
	for i in count:
		var o := {
			"no": _next_no(), "recipient": Story.random_name(rng),
			"product": Story.PRODUCTS[rng.randi() % Story.PRODUCTS.size()],
			"cell": "", "status": "Принят на ПВЗ", "date": today, "kind": "intake",
		}
		orders.append(o)
		var b := make_box(o)
		spot.add_child(b)
		spot.stored.append(b)
		b.position = Vector3(-0.45 + (i % 3) * 0.45, floori(i / 3.0) * 0.36, rng.randf_range(-0.2, 0.2))
		b.rotation.y = rng.randf_range(-0.3, 0.3)
		intake_boxes.append(b)
		made.append(b)
	Sfx.play_3d("shutter", Vector3(5.4, 1.2, 0.3), -4.0)
	return made


func _scanner_accept(box: CarryBox) -> String:
	Sfx.play_3d("beep", world.level.scanner_spot.global_position, -6.0)
	var o := find(box.order_no)
	if box.kind == "clothes":
		return "Это одежда для примерочной."
	if o.is_empty():
		return "Штрихкод не читается."
	if box.scanned or o["kind"] != "intake":
		world.hud_message("%s · ячейка %s · %s" % [o["no"], o["cell"] if o["cell"] != "" else "—", o["status"]])
		return ""
	# Назначаем свободную ячейку.
	var ids: Array = world.level.cells.keys()
	ids.sort_custom(func(a, b): return (world.level.cells[a] as DropSpot).stored.size() < (world.level.cells[b] as DropSpot).stored.size())
	var cell: String = ids[rng.randi() % mini(4, ids.size())]
	o["cell"] = cell
	o["status"] = "Ожидает размещения"
	box.cell = cell
	box.scanned = true
	box.refresh_label()
	world.hud_message("Отсканировано: %s → ячейка %s" % [o["no"], cell])
	GameState.add_stat("parcels_scanned")
	parcel_scanned.emit(box)
	return ""


func _cell_accept(box: CarryBox, cell_id: String) -> String:
	if box.kind == "clothes":
		return "Одежда хранится на вешалах."
	var src := find(box.order_no)
	if (not src.is_empty() and src["kind"] == "intake" and not box.scanned) or box.cell == "":
		return "Сначала отсканируйте посылку на стойке."
	if box.cell != cell_id:
		return "Ячейка не совпадает: эта посылка — в %s." % box.cell
	var o := find(box.order_no)
	if not o.is_empty() and o["status"] == "Ожидает размещения":
		o["status"] = "Ожидает получения"
		parcel_stored.emit(box)
	return ""


## Сверка ячейки (инвентаризация) — с пустыми руками.
func _cell_check(_player, cell_id: String) -> void:
	world.night.on_cell_checked(cell_id)


# ------------------------------------------------------------------ Выдача

func _counter_accept(box: CarryBox) -> String:
	if box.kind == "clothes":
		return "Это одежда для примерочной."
	for card in active_cards:
		if card["no"] == box.order_no:
			if not card.get("opened", false):
				return "Сначала откройте карточку заказа в компьютере."
			return ""
	if active_cards.is_empty():
		return "У стойки никого нет."
	return "Это не тот заказ."


func on_counter_item(box: CarryBox) -> void:
	for card in active_cards.duplicate():
		if card["no"] == box.order_no:
			active_cards.erase(card)
			var o := find(card["no"])
			if not o.is_empty():
				o["status"] = "Выдан"
				o["date"] = today
			GameState.add_stat("orders_issued")
			order_issued.emit(card)
			return


## Создаёт карточку выдачи для клиента. Возвращает {} если коробок нет.
func create_card(client_kind: String) -> Dictionary:
	var candidates := []
	for cell_id in world.level.cells.keys():
		for b in (world.level.cells[cell_id] as DropSpot).stored:
			if b is CarryBox and not _is_reserved((b as CarryBox).order_no):
				candidates.append(b)
	if candidates.is_empty():
		return {}
	var box: CarryBox = candidates[rng.randi() % candidates.size()]
	var o := find(box.order_no)
	var card := {"no": box.order_no, "recipient": o.get("recipient", "—"), "cell": box.cell, "product": o.get("product", "—"), "kind": client_kind, "opened": false}
	if client_kind == "faceless":
		card["recipient"] = "—"
		o["recipient"] = "—"
	active_cards.append(card)
	return card


func _is_reserved(no: String) -> bool:
	for c in active_cards:
		if c["no"] == no:
			return true
	return false


func open_card(card: Dictionary) -> void:
	card["opened"] = true
	pending_card = card
	card_opened.emit(card)


func cancel_card(no: String) -> void:
	for c in active_cards.duplicate():
		if c["no"] == no:
			active_cards.erase(c)


## Курьер «перекладывает» посылку: коробка исчезает из ячейки и появляется где-то ещё.
func misplace_random_box() -> CarryBox:
	var all := []
	for cell_id in world.level.cells.keys():
		for b in (world.level.cells[cell_id] as DropSpot).stored:
			all.append(b)
	if all.is_empty():
		return null
	var box: CarryBox = all[rng.randi() % all.size()]
	(box.get_parent() as DropSpot).take_out(box)
	var spots := [Vector3(13.4, 0, 11.3), Vector3(17.3, 0, 8.2), Vector3(1.0, 0, 6.4), Vector3(0.6, 0, 9.0), Vector3(16.8, 0, 6.0), Vector3(11.5, 0, 15.2)]
	box.reparent(world.level, false)
	box.position = spots[rng.randi() % spots.size()]
	box.rotation.y = rng.randf() * TAU
	var o := find(box.order_no)
	if not o.is_empty():
		o["note"] = "Последнее сканирование: %s, %s" % [Level.room_title(Level.room_at(box.position)), world.night.clock_text()]
	return box


# ------------------------------------------------------------------ Возвраты

## Генерирует заявку на возврат. valid_bias — вероятность корректной заявки.
func make_return_request(stage: int) -> Dictionary:
	var issued := []
	for o in orders:
		if o["status"] == "Выдан" and o["kind"] == "normal":
			issued.append(o)
	var r := {}
	var roll := rng.randf()
	if roll < 0.4 and not issued.is_empty():
		# Корректная заявка.
		var o: Dictionary = issued[rng.randi() % issued.size()]
		r = {"no": o["no"], "item": o["product"], "date": o["date"], "valid": days_between(o["date"], today) <= 14}
	elif roll < 0.6 and not issued.is_empty():
		# Товар не совпадает.
		var o2: Dictionary = issued[rng.randi() % issued.size()]
		var item: String = Story.RETURN_ITEMS_WRONG[rng.randi() % Story.RETURN_ITEMS_WRONG.size()] if stage >= 1 else Story.PRODUCTS[rng.randi() % Story.PRODUCTS.size()]
		if item == o2["product"]:
			item = Story.RETURN_ITEMS_HUMAN[0]
		r = {"no": o2["no"], "item": item, "date": o2["date"], "valid": false}
	elif roll < 0.8:
		# Заказа нет в базе.
		r = {"no": "П-%06d" % rng.randi_range(100000, 999999), "item": Story.RETURN_ITEMS_HUMAN[rng.randi() % Story.RETURN_ITEMS_HUMAN.size()], "date": _date_days_ago(rng.randi_range(1, 10)), "valid": false}
		if not find(r["no"]).is_empty():
			r["valid"] = false
	else:
		# Старый заказ (больше 14 дней) — или заказ пропавшего.
		var olds := []
		for o in orders:
			if o["status"] == "Выдан" and days_between(o["date"], today) > 14:
				olds.append(o)
		if olds.is_empty() or rng.randf() < 0.5:
			var m: Array = Story.MISSING[rng.randi() % Story.MISSING.size()]
			r = {"no": m[1], "item": m[3], "date": m[2], "valid": false}
		else:
			var o3: Dictionary = olds[rng.randi() % olds.size()]
			r = {"no": o3["no"], "item": o3["product"], "date": o3["date"], "valid": false}
	return r


## Проверка решения игрока по правилам.
func is_return_valid(r: Dictionary) -> bool:
	var o := find(r["no"])
	if o.is_empty():
		return false
	if o["status"] != "Выдан":
		return false
	if str(o["product"]) != str(r["item"]):
		return false
	return days_between(o["date"], today) <= 14


func add_future_order() -> Dictionary:
	var o := {"no": _next_no(), "recipient": Story.random_name(rng), "product": "—", "cell": "", "status": "Оформлен", "date": today, "kind": "future", "time": "%02d:%02d" % [rng.randi_range(6, 9), rng.randi_range(0, 59)]}
	o["note"] = "Время оформления: %s (ещё не наступило)" % o["time"]
	orders.append(o)
	return o


func add_player_card() -> Dictionary:
	var o := {"no": "П-%06d" % rng.randi_range(100, 999), "recipient": GameState.player_name(), "product": "—", "cell": "Б-%d" % rng.randi_range(1, 6), "status": "Ожидает получения", "date": today, "kind": "player_ghost"}
	orders.append(o)
	return o
