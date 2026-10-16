extends Node
## Запуск всех тестов: godot --headless --path . res://tests/test_runner.tscn
## Код возврата 0 — все тесты пройдены.

const SUITES := [
	"res://tests/test_scenes.gd",
	"res://tests/test_menu.gd",
	"res://tests/test_save.gd",
	"res://tests/test_navigation.gd",
	"res://tests/test_cameras.gd",
	"res://tests/test_interactions.gd",
	"res://tests/test_nights.gd",
	"res://tests/test_win_lose.gd",
	"res://tests/test_events.gd",
	"res://tests/test_soak.gd",
]


func _ready() -> void:
	await get_tree().process_frame
	# Тесты не трогают настоящие сохранения.
	GameState.save_path = "user://test_save.json"
	GameState.settings_path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.load_game()
	GameState.load_settings()
	Engine.time_scale = 1.0
	var total := 0
	var failed := 0
	var only := OS.get_cmdline_user_args()
	for path in SUITES:
		if only.size() > 0 and not only.has(path.get_file().get_basename()):
			continue
		var suite: TestSuite = load(path).new()
		suite.runner = self
		var methods := []
		for m in suite.get_method_list():
			if str(m["name"]).begins_with("test_"):
				methods.append(m["name"])
		print("== ", path.get_file())
		for m in methods:
			total += 1
			suite._current = m
			var before: int = suite.failures.size()
			await suite.setup()
			await suite.call(m)
			await suite.teardown()
			Engine.time_scale = 1.0
			get_tree().paused = false
			if suite.failures.size() > before:
				failed += 1
				print("  FAIL ", m)
				for f in suite.failures.slice(before):
					print("     - ", f)
			else:
				print("  ok   ", m)
	print("\nИТОГО: %d тестов, провалено: %d" % [total, failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.settings_path))
	get_tree().quit(0 if failed == 0 else 1)
