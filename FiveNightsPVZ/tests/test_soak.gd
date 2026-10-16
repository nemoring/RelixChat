extends TestSuite
## Длительный прогон: ночь целиком на ускоренном времени. Игрок бездействует
## у стойки. Проверяем, что смена завершается (победой, увольнением или
## нападением) и директор успевает провести несколько фаз.


func _run_night(n: int) -> Dictionary:
	var g := await start_game(n)
	var phases := {}
	g.director.phase_changed.connect(func(p): phases[p] = true)
	Engine.time_scale = 16.0
	var t := 0.0
	while not g.game_over and t < g.night.duration / 16.0 + 20.0:
		await tree().process_frame
		t += g.get_process_delta_time() / 16.0
	Engine.time_scale = 1.0
	var res := {"over": g.game_over, "phases": phases.size(), "events": g.director.event_log.size(), "minute": g.night.minute(), "violations": g.night.violations, "death": g.death_cause, "log": g.director.event_log.slice(-8)}
	await stop_game(g)
	return res


func test_soak_night2() -> void:
	var r := await _run_night(2)
	check(r["over"], "ночь 2 завершилась (%s)" % str(r))
	check(r["phases"] >= 2, "директор сменил фазы")
	check(r["events"] >= 5, "директор генерировал события")
	print("     ночь 2: ", r)


func test_soak_night5() -> void:
	var r := await _run_night(5)
	check(r["over"], "ночь 5 завершилась (%s)" % str(r))
	print("     ночь 5: ", r)
