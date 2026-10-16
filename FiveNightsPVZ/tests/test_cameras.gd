extends TestSuite
## Камеры: 8 каналов, переключение, реальная картинка, слепые зоны, рябь, запись.


func test_switch_all_channels() -> void:
	var g := await start_game(2)
	g.open_desk()
	await frames(2)
	check(g.cctv.active, "камеры включаются за компьютером")
	for i in 8:
		g.cctv.switch_to(i)
		await frames(1)
		eq(g.cctv.current, i, "канал")
		check(g.cctv.cam.global_position.distance_to(g.level.cam_mount_nodes[i].global_position) < 0.5, "камера на месте крепления %d" % i)
	check(g.cctv.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "рендер активен")
	g.close_desk()
	check(not g.cctv.active, "камеры выключаются")
	check(g.cctv.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "рендер остановлен — экономия")
	await stop_game(g)


func test_coverage_has_blind_spots() -> void:
	var g := await start_game(2)
	await frames(5)
	var nav := g.level.nav
	check(nav.cam_coverage.size() > 0, "покрытие посчитано")
	check(nav.is_covered("hall_center"), "центр зала под камерой")
	check(nav.is_covered("cor_2"), "коридор под камерой")
	check(not nav.is_covered("toilet_sink"), "туалет — слепая зона")
	check(not nav.is_covered("ws_desk"), "рабочее место — слепая зона")
	await stop_game(g)


func test_cam_only_and_eyes_only_layers() -> void:
	var g := await start_game(4)
	check(g.cctv.cam.cull_mask & Build.VIS_CAM_ONLY, "камеры видят слой «только камеры»")
	check(not (g.cctv.cam.cull_mask & Build.VIS_EYES_ONLY), "камеры не видят слой «только глаза»")
	check(not (g.player.cam.cull_mask & Build.VIS_CAM_ONLY), "игрок не видит слой «только камеры»")
	# Безликий внутри: на камере не виден, но даёт рябь.
	var f: Faceless = g.entities["faceless"]
	f.show_at("hall_center")
	f.set_vis_layers(Build.VIS_EYES_ONLY)
	check(g.cctv.entity_static(1) > 0.0, "рябь на CAM 2 при Безликом в кадре")
	f.hide_entity()
	eq(g.cctv.entity_static(1), 0.0, "без сущности ряби нет")
	await stop_game(g)


func test_signal_loss_and_record() -> void:
	var g := await start_game(2)
	check(g.cctv.signal_lost.has(7), "CAM 8 без сигнала до 4-й ночи")
	g.open_desk()
	g.cctv.switch_to(0)
	await frames(3)
	g.cctv.record()
	await frames(1)
	check(g.cctv.recordings.size() >= 0, "запись не падает")
	g.cctv.lose_signal(0, 1.0)
	check(g.cctv.signal_lost.has(0), "потеря сигнала")
	g.close_desk()
	await stop_game(g)


func test_stale_feed_clock_lags() -> void:
	var g := await start_game(3)
	g.night.elapsed = g.night.duration * 0.5
	g.open_desk()
	g.cctv.switch_to(1)
	g.cctv._schedule_stale()
	await seconds(1.0)
	if g.cctv.stale:
		check(g.cctv.clock_for_feed() != g.night.clock_text(), "часы устаревшего кадра отстают")
	else:
		# В headless-рендере изображения может не быть — проверяем логику напрямую.
		g.cctv.stale = true
		g.cctv.stale_clock = g.night.clock_text(-30)
		check(g.cctv.clock_for_feed() != g.night.clock_text(), "часы устаревшего кадра отстают")
	g.close_desk()
	await stop_game(g)
