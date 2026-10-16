class_name TestSuite
extends RefCounted
## Базовый класс набора тестов. Методы test_* выполняются по очереди (могут быть async).

var runner  # TestRunner
var failures: Array[String] = []
var _current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [_current, msg])


func eq(a, b, msg: String) -> void:
	if a != b:
		failures.append("%s: %s (ожидалось %s, получено %s)" % [_current, msg, str(b), str(a)])


func tree() -> SceneTree:
	return runner.get_tree()


func frames(n: int) -> void:
	for i in n:
		await runner.get_tree().process_frame


func seconds(t: float) -> void:
	await runner.get_tree().create_timer(t, true).timeout


## Запускает игровую сцену указанной ночи и ждёт инициализации.
func start_game(night: int, custom := {}) -> GameWorld:
	GameState.start_night(night, custom)
	var g: GameWorld = load("res://scenes/game.tscn").instantiate()
	g.headless_test = true
	runner.get_tree().root.add_child(g)
	await frames(5)
	await seconds(0.2)
	return g


func stop_game(g: GameWorld) -> void:
	if is_instance_valid(g):
		runner.get_tree().paused = false
		g.queue_free()
		await frames(3)


func setup() -> void:
	pass


func teardown() -> void:
	pass
