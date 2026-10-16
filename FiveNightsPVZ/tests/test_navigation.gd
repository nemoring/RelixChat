extends TestSuite
## Навигация противников: граф связен, двери блокируют, сущность доходит до цели.


func test_graph_connected() -> void:
	var g := await start_game(2)
	var nav := g.level.nav
	var names := nav.all_names()
	var open_tech: Door = g.level.doors["tech"]
	open_tech.locked = false
	g.level.doors["front"].locked = false
	for n in names:
		var p := nav.path("ws_desk", n, true)
		check(p.size() > 0, "нет пути ws_desk → " + n)
	open_tech.locked = true
	await stop_game(g)


func test_closed_doors_block() -> void:
	var g := await start_game(2)
	var nav := g.level.nav
	for d in g.level.doors.values():
		(d as Door).set_open(false, true)
	var p := nav.path("wh_mid", "cor_2", false)
	eq(p.size(), 0, "закрытые двери должны блокировать путь без открывания")
	p = nav.path("wh_mid", "cor_2", true)
	check(p.size() > 0, "открывающая двери сущность проходит")
	p = nav.path("cor_1", "tech", true)
	eq(p.size(), 0, "запертая техническая непроходима")
	await stop_game(g)


func test_waypoints_not_inside_walls() -> void:
	var g := await start_game(1)
	await frames(3)
	var space := g.get_world_3d().direct_space_state
	for n in g.level.nav.all_names():
		var pos := g.level.nav.pos_of(n) + Vector3.UP * 1.0
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.15
		q.shape = sh
		q.transform = Transform3D(Basis(), pos)
		q.collision_mask = Build.LAYER_WORLD
		var hits := space.intersect_shape(q, 4)
		var bad := []
		for h in hits:
			if not (h["collider"] is Door):
				bad.append(h["collider"])
		check(bad.is_empty(), "точка %s внутри стены/предмета" % n)
	await stop_game(g)


func test_edges_clear_of_walls() -> void:
	var g := await start_game(1)
	await frames(3)
	for d in g.level.doors.values():
		(d as Door).set_open(true, true)
	# Шторки, как и двери, сущность открывает перед проходом.
	for c in g.level.cabins:
		(c["curtain"] as Curtain).set_open(true, true)
	await frames(3)
	var space := g.get_world_3d().direct_space_state
	var nav := g.level.nav
	for id in nav.points.keys():
		for nb in nav.astar.get_point_connections(id):
			if nb < id:
				continue
			var a := nav.astar.get_point_position(id) + Vector3.UP
			var b := nav.astar.get_point_position(nb) + Vector3.UP
			var q := PhysicsRayQueryParameters3D.create(a, b, Build.LAYER_WORLD)
			var r := space.intersect_ray(q)
			check(r.is_empty() or r["collider"] is Door, "ребро %s—%s пересекает препятствие" % [nav.points[id]["name"], nav.points[nb]["name"]])
	await stop_game(g)


func test_avoid_rooms() -> void:
	var g := await start_game(2)
	var p := g.level.nav.path("cor_3", "wh_se", true, true, ["workstation"])
	check(p.size() > 0, "обходной путь есть")
	for n in p:
		check(g.level.nav.room_of(n) != "workstation", "путь не проходит через рабочее место")
	await stop_game(g)


func test_entity_walks_to_target() -> void:
	var g := await start_game(3)
	var c: Courier = g.entities["courier"]
	c.show_at("wh_shutter")
	c.state = "investigate"
	c._sense_t = 999.0
	c.go_to("cor_3", 3.0)
	Engine.time_scale = 4.0
	var t := 0.0
	var best := 999.0
	while t < 30.0 and best > 0.3:
		c._sense_t = 999.0
		await seconds(0.25)
		t += 0.25
		best = minf(best, c.global_position.distance_to(g.level.nav.pos_of("cor_3")))
	Engine.time_scale = 1.0
	check(best < 0.5, "курьер не дошёл до cor_3 (%s, state=%s, path=%s, i=%d, door=%s)" % [str(c.global_position), c.state, str(c._path), c._path_i, str(c._waiting_door)])
	await stop_game(g)
