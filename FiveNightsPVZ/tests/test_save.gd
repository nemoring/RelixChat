extends TestSuite
## Сохранения: прогресс, настройки, достижения, концовки, статистика.


func test_save_roundtrip() -> void:
	GameState.reset_progress()
	GameState.data["unlocked_night"] = 4
	GameState.unlock_achievement("first_shift")
	GameState.unlock_ending("shift_over")
	GameState.collect_document(2)
	GameState.add_stat("orders_issued", 5)
	check(GameState.save_game(), "save_game вернул false")
	GameState.data = {}
	GameState.load_game()
	eq(int(GameState.data["unlocked_night"]), 4, "открытые ночи")
	check(GameState.data["achievements"].has("first_shift"), "достижение")
	check(GameState.data["endings"].has("shift_over"), "концовка")
	check((GameState.data["documents"] as Array).has(2.0) or (GameState.data["documents"] as Array).has(2), "документ")
	eq(int(GameState.data["stats"]["orders_issued"]), 5, "статистика")


func test_corrupted_save_falls_back() -> void:
	var f := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	f.store_string("{не json")
	f.close()
	GameState.load_game()
	eq(int(GameState.data["unlocked_night"]), 1, "повреждённое сохранение → новое")


func test_settings_roundtrip() -> void:
	GameState.set_setting("brightness", 1.4)
	GameState.set_setting("flicker", false)
	GameState.settings = {}
	GameState.load_settings()
	check(is_equal_approx(float(GameState.settings["brightness"]), 1.4), "яркость")
	eq(GameState.settings["flicker"], false, "мерцание")
	GameState.set_setting("flicker", true)
	GameState.set_setting("brightness", 1.0)


func test_documents_unlock_collector() -> void:
	GameState.reset_progress()
	for i in range(1, 6):
		GameState.collect_document(i)
	check(GameState.has_all_documents(), "все документы")
	check(GameState.data["achievements"].has("collector"), "достижение «Архивариус»")
	GameState.reset_progress()
