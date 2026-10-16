extends TestSuite
## Достижимость: игрок, стоящий перед объектом и смотрящий на него,
## должен получить именно этот объект в прицел (настоящий луч от камеры).


func aim(g: GameWorld, stand: Vector3, target: Vector3) -> void:
	var p := g.player
	p.global_position = stand
	var eye := stand + Vector3.UP * p.head.position.y
	var to := target - eye
	p.rotation = Vector3(0, atan2(-to.x, -to.z), 0)
	p._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	p.head.rotation.x = p._pitch
	await frames(3)
	p._update_focus()


func expect_focus(g: GameWorld, stand: Vector3, target_node: Node3D, what: String, aim_at = null) -> void:
	var t: Vector3 = aim_at if aim_at != null else target_node.global_position
	await aim(g, stand, t)
	check(g.player.focus == target_node, "%s: в прицеле %s (подсказка «%s»)" % [what, str(g.player.focus.name if g.player.focus else "ничего"), g.player.focus_prompt])


func hold(g: GameWorld, box: CarryBox) -> void:
	if g.player.held_item:
		var old := g.player.release_item()
		old.queue_free()
	g.player.pick_up(box)


func test_checkpoints_reachable() -> void:
	var g := await start_game(1)
	var stands := {
		"cp_warehouse": Vector3(1.1, 0, 6.1), "cp_corridor": Vector3(13.0, 0, 11.0),
		"cp_utility": Vector3(16.5, 0, 4.7), "cp_entrance": Vector3(1.9, 0, 14.4), "cp_toilet": Vector3(15.3, 0, 10.4),
	}
	for id in stands.keys():
		await expect_focus(g, stands[id], g.level.checkpoints[id], "метка " + id)
	await stop_game(g)


func test_fixed_objects_reachable() -> void:
	var g := await start_game(1)
	var lv := g.level
	await expect_focus(g, Vector3(16.8, 0, 5.6), lv.breaker_panel, "щиток")
	await expect_focus(g, Vector3(1.0, 0, 15.0), lv.maglock, "магнитный замок")
	await expect_focus(g, Vector3(10.4, 0, 9.0), lv.desk_seat, "компьютер", lv.pc_screen.global_position)
	await expect_focus(g, Vector3(14.5, 0, 9.0), lv.mirrors[0].get_parent().get_node_or_null("x") if false else lv.doors["toilet"], "дверь туалета", lv.doors["toilet"].global_position + Vector3(0, 1.2, 0.5))
	lv.phone.enabled = true
	await expect_focus(g, Vector3(11.1, 0, 7.6), lv.phone, "телефон")
	for hs in lv.hide_spots:
		var h := hs as HideSpot
		await expect_focus(g, h.exit_point.global_position, h, "укрытие " + h.spot_name)
	await stop_game(g)


func test_boxes_in_cells_can_be_taken() -> void:
	var g := await start_game(1)
	for id in g.level.cells.keys():
		var spot: DropSpot = g.level.cells[id]
		if spot.stored.is_empty():
			continue
		var box: CarryBox = spot.stored[0]
		var front := spot.global_basis.z
		var stand := box.global_position + front * 1.0
		stand.y = 0
		await expect_focus(g, stand, box, "коробка в ячейке " + id, box.global_position + Vector3.UP * box.dims.y * 0.5)
	await stop_game(g)


func test_full_issue_by_aiming() -> void:
	var g := await start_game(1)
	var p := g.player
	g.spawn_client("inside")
	p.rotation.y = 0
	await frames(5)
	var c: Client = g.clients[0]
	g.orders.open_card(c.card)
	var box: CarryBox = g.orders.find(c.card["no"])["box"]
	var spot: DropSpot = box.get_parent()
	var stand := box.global_position + spot.global_basis.z * 1.0
	stand.y = 0
	await aim(g, stand, box.global_position + Vector3.UP * box.dims.y * 0.5)
	check(p.focus == box, "целимся в нужную коробку")
	p.try_interact()
	check(p.held_item == box, "коробка взята")
	await aim(g, Vector3(8.2, 0, 9.3), g.level.counter_spot.global_position + Vector3.UP * 0.1)
	check(p.focus == g.level.counter_spot, "в прицеле стойка выдачи (%s)" % p.focus_prompt)
	p.try_interact()
	check(p.held_item == null, "коробка положена на стойку")
	check(c.task["done"], "заказ выдан")
	await stop_game(g)


func test_scan_and_store_by_aiming() -> void:
	var g := await start_game(1)
	var p := g.player
	var boxes: Array = g.orders.deliver_intake(2)
	g.night.add_task("intake", "т", 90.0, {"boxes": boxes, "left": 2})
	var box: CarryBox = boxes[0]
	await aim(g, Vector3(5.4, 0, 2.3), box.global_position + Vector3.UP * 0.1)
	check(p.focus is CarryBox, "на поддоне в прицеле коробка (%s)" % p.focus_prompt)
	p.try_interact()
	check(p.held_item != null, "коробка с поддона взята")
	await aim(g, Vector3(9.4, 0, 9.2), g.level.scanner_spot.global_position + Vector3.UP * 0.1)
	check(p.focus == g.level.scanner_spot, "в прицеле сканер (%s)" % p.focus_prompt)
	p.try_interact()
	var held: CarryBox = p.held_item
	check(held != null and held.scanned, "отсканировано")
	if held:
		var cell: DropSpot = g.level.cells[held.cell]
		var stand := cell.global_position + cell.global_basis.z * 1.0
		stand.y = 0
		await aim(g, stand, cell.global_position + Vector3.UP * 0.2)
		check(p.focus == cell, "в прицеле ячейка %s (%s)" % [held.cell, p.focus_prompt])
		p.try_interact()
		check(p.held_item == null, "посылка размещена")
	await stop_game(g)


func test_clothes_to_fitting_by_aiming() -> void:
	var g := await start_game(2)
	var p := g.player
	var w: FittingWoman = g.entities["woman"]
	w.request()
	var item: CarryBox = null
	for ch in g.level.clothes_rail.get_children():
		if ch is CarryBox and ch.size_label == w.want_size:
			item = ch
	await aim(g, Vector3(10.7, 0, item.global_position.z), item.global_position + Vector3.UP * 0.4)
	check(p.focus == item, "в прицеле пакет %s (%s)" % [w.want_size, p.focus_prompt])
	p.try_interact()
	check(p.held_item == item, "одежда взята")
	var cab: Dictionary = g.level.cabins[w.cabin]
	var spot: DropSpot = cab["spot"]
	var front: Vector3 = cab["inside"]
	await aim(g, Vector3(front.x, 0, 11.3), Vector3(front.x, 1.2, 10.0))
	check(p.focus == spot, "в прицеле «Передать за шторку» (%s)" % p.focus_prompt)
	p.try_interact()
	check(w.task["done"], "размер передан")
	await stop_game(g)


func test_inventory_by_aiming() -> void:
	var g := await start_game(4)
	var p := g.player
	g.night.run_beat("inventory", 2)
	for id in g.night.inventory_cells.duplicate():
		var cell: DropSpot = g.level.cells[id]
		var stand := cell.global_position + cell.global_basis.z * 1.0
		stand.y = 0
		# Целимся в пустой край ячейки, а не в коробку.
		await aim(g, stand, cell.global_position + cell.global_basis.x * 0.45 + Vector3.UP * 0.15)
		check(p.focus == cell, "можно сверить ячейку %s (%s)" % [id, p.focus_prompt])
		p.try_interact()
	check(g.night.find_task("inventory").is_empty(), "инвентаризация выполнена")
	await stop_game(g)


func test_fitting_from_many_angles() -> void:
	var g := await start_game(2)
	var p := g.player
	var w: FittingWoman = g.entities["woman"]
	w.request()
	var cab: Dictionary = g.level.cabins[w.cabin]
	var spot: DropSpot = cab["spot"]
	var cx: float = cab["inside"].x
	var bad := []
	for dz in [0.6, 1.0, 1.6]:
		for dx in [-0.5, 0.0, 0.5]:
			for y in [0.9, 1.3]:
				var item := CarryBox.new()
				item.size_label = "42" if w.want_size != "42" else "44"
				item.build(Vector3(0.08, 0.9, 0.45), "clothes")
				g.level.add_child(item)
				hold(g, item)
				await aim(g, Vector3(cx + dx, 0, 10.35 + dz), Vector3(cx + dx * 0.3, y, 10.0))
				if p.focus != spot:
					bad.append("(%.1f, %.1f, h%.1f)→%s" % [dx, dz, y, p.focus_prompt])
	check(bad.is_empty(), "место передачи видно с разных позиций: " + ", ".join(PackedStringArray(bad)))
	# Нельзя пройти сквозь закрытую шторку внутрь кабинки.
	var cur: Curtain = cab["curtain"]
	check(cur.collision_layer & Build.LAYER_WORLD, "закрытая шторка твёрдая")
	await stop_game(g)


func test_counter_and_scanner_from_many_angles() -> void:
	var g := await start_game(1)
	var p := g.player
	var boxes: Array = g.orders.deliver_intake(1)
	hold(g, boxes[0])
	var bad := []
	for stand in [Vector3(8.2, 0, 9.2), Vector3(7.6, 0, 9.4), Vector3(8.9, 0, 9.3), Vector3(8.2, 0, 8.6)]:
		await aim(g, stand, g.level.counter_spot.global_position + Vector3.UP * 0.05)
		if p.focus != g.level.counter_spot:
			bad.append("стойка с %s → «%s»" % [str(stand), p.focus_prompt])
	for stand in [Vector3(9.4, 0, 9.2), Vector3(9.9, 0, 9.0), Vector3(9.0, 0, 9.3)]:
		await aim(g, stand, g.level.scanner_spot.global_position + Vector3.UP * 0.1)
		if p.focus != g.level.scanner_spot:
			bad.append("сканер с %s → «%s»" % [str(stand), p.focus_prompt])
	check(bad.is_empty(), ", ".join(PackedStringArray(bad)))
	await stop_game(g)


## Для каждого интерактивного объекта ищем свободную точку на полу рядом,
## откуда прицел попадает именно в него.
func test_every_interactable_reachable() -> void:
	for n in [1, 5]:
		var g := await start_game(n)
		if n == 5:
			g.night.run_beat("tech_key", null)
			g.level.doors["tech"].locked = false
			g.level.doors["tech"].set_open(true, true)
		for d in g.level.doors.values():
			if d.door_id != "front" and d.door_id != "tech":
				(d as Door).set_open(true, true)
		g.level.phone.enabled = true
		g.level.printer.enabled = true
		await frames(3)
		var space := g.get_world_3d().direct_space_state
		var all := g.level.find_children("*", "Interactable", true, false)
		var unreachable := []
		for node in all:
			var ia := node as Interactable
			if ia is Door or ia is CarryBox or ia is DropSpot:
				continue
			if not ia.is_visible_in_tree():
				continue
			var target := ia.global_position
			for c in ia.get_children():
				if c is CollisionShape3D:
					target = (c as CollisionShape3D).global_position
			var ok := false
			for r in [0.8, 1.2, 1.6]:
				for k in 12:
					var a := k * TAU / 12.0
					var stand := Vector3(target.x + cos(a) * r, 0, target.z + sin(a) * r)
					var q := PhysicsShapeQueryParameters3D.new()
					var sh := CapsuleShape3D.new()
					sh.radius = 0.28
					sh.height = 1.6
					q.shape = sh
					q.transform = Transform3D(Basis(), stand + Vector3.UP * 0.9)
					q.collision_mask = Build.LAYER_WORLD
					if not space.intersect_shape(q, 1).is_empty():
						continue
					if Level.room_at(stand) == "street" and Level.room_at(target) != "street":
						continue
					await aim(g, stand, target)
					if g.player.focus == ia or (g.player.focus != null and ia.is_ancestor_of(g.player.focus)):
						ok = true
						break
				if ok:
					break
			if not ok:
				unreachable.append("%s «%s» %s" % [ia.name, ia.prompt(g.player), str(target.snapped(Vector3.ONE * 0.01))])
		check(unreachable.is_empty(), "ночь %d, недостижимы: %s" % [n, "; ".join(PackedStringArray(unreachable))])
		await stop_game(g)
