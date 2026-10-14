extends Node
## Интеграционный тест: на каждой сложности НЛО прогоняется камнями в кабину,
## требуемое число попаданий = 10/13/17/20, попадания по корпусу не засчитываются.
## Запуск: godot --headless --path . res://tests/ufo_combat_test.tscn

var failed := 0

func _ready() -> void:
	Engine.max_fps = 0
	for level in 4:
		await _run_level(level)
	print("UFO COMBAT: %s" % ("OK" if failed == 0 else "FAILED (%d)" % failed))
	get_tree().quit(1 if failed > 0 else 0)

func _run_level(level: int) -> void:
	DifficultyManager.restore_level(level)
	GameManager.reset_state(level)
	GameManager.state.chapter = "survival"
	var game: Node = load("res://scenes/survival/survival.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout # интро главы
	await game.debug_ufo_scene()
	var ufo: UFOController = game.ufo_manager.ufo
	var expected: int = DifficultyManager.p("ufo_hits")
	var state := {"defeated": false, "end_time": 0.0}
	game.ufo_manager.raid_ended.connect(func(d, _s, _t):
		state.defeated = d
		state.end_time = game.time_min)
	var throws := 0
	var outcomes := {}
	var hull_test_done := false
	while is_instance_valid(ufo) and ufo.health.hits < expected and throws < expected * 4:
		# Проверка: бросок в корпус снизу не засчитывается
		if not hull_test_done:
			hull_test_done = true
			var hits_before := ufo.health.hits
			var below := ufo.global_position - Vector3(0, 8, 0)
			StoneProjectile.launch(game, below, Vector3(0, 30, 0), game)
			await get_tree().create_timer(1.2).timeout
			if ufo.health.hits != hits_before:
				print("  FAIL: попадание в корпус засчитано (уровень %d)" % level)
				failed += 1
		_keep_distance(game, ufo)
		_aim(game, ufo)
		game._start_aim()
		await get_tree().physics_frame
		var shot: Dictionary = game._compute_throw()
		outcomes[shot.outcome] = int(outcomes.get(shot.outcome, 0)) + 1
		game._release_throw()
		throws += 1
		await get_tree().create_timer(0.45).timeout
	await get_tree().create_timer(1.0).timeout
	var hits: int = ufo.health.hits if is_instance_valid(ufo) else expected
	print("Уровень %d (%s): нужно %d, попаданий %d, бросков %d, прогноз %s" % [level, DifficultyManager.level_name(level), expected, hits, throws, outcomes])
	if hits < expected:
		print("  FAIL: не удалось прогнать НЛО")
		failed += 1
	# ждём улёта
	var t := 0.0
	while is_instance_valid(game.ufo_manager.ufo) and t < 10.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	if not state.defeated:
		print("  FAIL: нет сигнала победы")
		failed += 1
	var next: float = game.ufo_manager.next_raid - state.end_time
	if next < 1.5 * 1440.0 - 1.0 or next > 2.0 * 1440.0 + 1.0:
		print("  FAIL: следующий налёт через %.0f мин (ожидалось 2160–2880)" % next)
		failed += 1
	game.queue_free()
	await get_tree().process_frame

## Игрок держит дистанцию ~16 м от тарелки (как и подсказывает интерфейс).
func _keep_distance(game, ufo: UFOController) -> void:
	var p: Vector3 = game.player.global_position
	var flat := Vector3(p.x - ufo.global_position.x, 0, p.z - ufo.global_position.z)
	if flat.length() < 14.0 or flat.length() > 20.0:
		var np := ufo.global_position + flat.normalized() * 16.0
		game.player.global_position = Vector3(np.x, game.terrain.height(np.x, np.z) + 0.2, np.z)

func _aim(game, ufo: UFOController) -> void:
	var cam: Camera3D = game.player.active_camera()
	var to := ufo.cockpit_global() - cam.global_position
	game.player.yaw = atan2(-to.x, -to.z)
	game.player.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	game.player.look(Vector2.ZERO)
