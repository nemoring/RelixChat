extends TestSuite
## Взаимодействия: коробки, сканер, ячейки, выдача, двери, замок, щиток,
## шторки, укрытия, фонарик, компьютер.


func test_pickup_scan_store() -> void:
	var g := await start_game(1)
	var p := g.player
	var boxes: Array = g.orders.deliver_intake(1)
	var box: CarryBox = boxes[0]
	box.interact(p)
	check(p.held_item == box, "коробка в руках")
	# В ячейку без сканирования нельзя.
	var any_cell: DropSpot = g.level.cells.values()[0]
	any_cell.interact(p)
	check(p.held_item == box, "без сканирования ячейка не принимает")
	g.level.scanner_spot.interact(p)
	check(box.scanned and box.cell != "", "посылка отсканирована и получила ячейку")
	check(p.held_item == box, "после сканирования коробка остаётся в руках")
	var wrong := ""
	for id in g.level.cells.keys():
		if id != box.cell:
			wrong = id
			break
	g.level.cells[wrong].interact(p)
	check(p.held_item == box, "чужая ячейка отклоняет")
	var t: Dictionary = g.night.add_task("intake", "тест", 50.0, {"boxes": [box], "left": 1})
	g.level.cells[box.cell].interact(p)
	check(p.held_item == null, "правильная ячейка принимает")
	check(t["done"], "задание приёмки выполнено")
	await stop_game(g)


func test_issue_order_to_client() -> void:
	var g := await start_game(1)
	var p := g.player
	g.spawn_client("inside")
	var c: Client = g.clients[0]
	# Клиент появляется, когда на стойку не смотрят.
	p.rotation.y = 0
	await frames(5)
	eq(c.state, "waiting", "клиент у стойки")
	var t: Dictionary = c.task
	check(not t.is_empty(), "задание выдачи")
	var card: Dictionary = c.card
	var box: CarryBox = g.orders.find(card["no"])["box"]
	box.interact(p)
	g.level.counter_spot.interact(p)
	check(p.held_item == box, "без открытой карточки выдать нельзя")
	g.orders.open_card(card)
	g.level.counter_spot.interact(p)
	check(p.held_item == null, "коробка выдана")
	check(t["done"], "задание выдачи выполнено")
	eq(c.state, "leaving", "клиент уходит")
	eq(g.orders.find(card["no"])["status"], "Выдан", "статус в базе")
	await stop_game(g)


func test_doors_and_lock() -> void:
	var g := await start_game(1)
	var d: Door = g.level.doors["wh_ws"]
	var was := d.is_open
	d.interact(g.player)
	check(d.is_open != was, "дверь открывается/закрывается")
	var tech: Door = g.level.doors["tech"]
	tech.interact(g.player)
	check(not tech.is_open, "запертая дверь не открывается")
	check(g.level.doors["front"].locked, "замок включён")
	g.toggle_maglock()
	check(not g.level.doors["front"].locked, "замок отключается")
	g.toggle_maglock()
	check(g.level.doors["front"].locked, "замок включается")
	await stop_game(g)


func test_breaker_trip_and_reset() -> void:
	var g := await start_game(1)
	var lt := g.level.lighting
	check(lt.is_zone_powered("warehouse"), "склад запитан")
	g.trip_breaker("A2")
	check(not lt.is_zone_powered("warehouse"), "автомат выбит — света нет")
	check(not g.night.find_task("breaker").is_empty(), "появилось задание")
	g.reset_breakers()
	check(lt.is_zone_powered("warehouse"), "питание восстановлено")
	check(g.night.find_task("breaker").is_empty(), "задание закрыто")
	lt.set_switch("hall", false)
	check(not lt.is_zone_lit("hall"), "выключатель гасит зал")
	lt.set_switch("hall", true)
	await stop_game(g)


func test_curtain_hide_flashlight() -> void:
	var g := await start_game(1)
	var p := g.player
	var cur: Curtain = g.level.cabins[0]["curtain"]
	cur.interact(p)
	check(cur.is_open, "шторка открылась")
	cur.interact(p)
	check(not cur.is_open, "шторка закрылась")
	var hs: HideSpot = g.level.hide_spots[0]
	hs.interact(p)
	check(p.is_hidden(), "игрок спрятался")
	hs.interact(p)
	check(not p.is_hidden(), "игрок вышел")
	p.toggle_flashlight()
	check(p.flashlight_on, "фонарик включён")
	var b := p.battery
	await seconds(1.0)
	check(p.battery < b, "заряд расходуется")
	p.toggle_flashlight()
	await stop_game(g)


func test_desk_sit_and_mail_report() -> void:
	var g := await start_game(4)
	g.open_desk()
	check(g.player.seated, "игрок сел")
	check(g.desk.visible, "интерфейс компьютера открыт")
	g.night.send_fake_mail()
	var fake: Dictionary = g.night.mails[g.night.mails.size() - 1]
	check(fake["fake"], "письмо поддельное")
	var before: int = g.night.violations
	g.night.report_mail(fake)
	eq(g.night.violations, before, "жалоба на поддельное — без нарушения")
	eq(g.night.fakes_detected, 1, "распознано")
	var real := g.night.add_mail(Story.REAL_SENDER, "т", "т", false)
	g.night.report_mail(real)
	eq(g.night.violations, before + 1, "ложная жалоба на настоящее — нарушение")
	g.close_desk()
	check(not g.player.seated, "игрок встал")
	await stop_game(g)


func test_woman_size_delivery() -> void:
	var g := await start_game(2)
	var w: FittingWoman = g.entities["woman"]
	w.request()
	eq(w.state, "requesting", "просьба")
	var spot: DropSpot = g.level.cabins[w.cabin]["spot"]
	check(spot.enabled, "место передачи активно")
	var size := w.want_size
	var item: CarryBox = null
	for c in g.level.clothes_rail.get_children():
		if c is CarryBox and c.size_label == size:
			item = c
	check(item != null, "нужный размер на вешале")
	item.interact(g.player)
	spot.interact(g.player)
	eq(w.state, "absent", "успокоилась")
	check(w.task["done"], "задание выполнено")
	await stop_game(g)


func test_return_decision_rules() -> void:
	var g := await start_game(3)
	var os := g.orders
	var valid := {}
	for o in os.orders:
		if o["status"] == "Выдан" and o["kind"] == "normal" and OrderSystem.days_between(o["date"], os.today) <= 14:
			valid = o
			break
	check(not valid.is_empty(), "есть выданный свежий заказ")
	check(os.is_return_valid({"no": valid["no"], "item": valid["product"], "date": valid["date"]}), "корректный возврат")
	check(not os.is_return_valid({"no": valid["no"], "item": "Зубной протез", "date": valid["date"]}), "чужой товар — отказ")
	check(not os.is_return_valid({"no": "П-000000", "item": "x", "date": os.today}), "нет в базе — отказ")
	var r: Returner = g.entities["returner"]
	r.arrive()
	await frames(3)
	g.player.rotation.y = 0
	await frames(3)
	eq(r.state, "waiting", "Возврат у стойки")
	r.decide(r.request["valid"])
	eq(r.anger, 0, "верное решение не злит")
	eq(r.state, "leaving", "уходит")
	await stop_game(g)
