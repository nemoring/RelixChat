extends Node
## Глобальное состояние прохождения: сложность, глава, сюжетные флаги, перенос
## предметов между главами, достижения, жизненный цикл Android-приложения.

signal chapter_changed(chapter: String)
signal achievement_unlocked(id: String)
signal app_paused
signal app_resumed
signal back_requested

const SCENES := {
	"intro": "res://scenes/intro/studio_intro.tscn",
	"menu": "res://scenes/menu/main_menu.tscn",
	"difficulty": "res://scenes/difficulty/difficulty_select.tscn",
	"novel": "res://scenes/novel/novel.tscn",
	"runner": "res://scenes/runner/runner.tscn",
	"survival": "res://scenes/survival/survival.tscn",
	"credits": "res://scenes/ending/credits.tscn",
}

const CHAPTER_TITLES := {
	"novel": "Глава 1. Обычное утро Котакбаса",
	"runner": "Глава 2. БЕГИ, КОТАКБАС!",
	"survival": "Глава 3. Лес Котакбаса",
}

const ACHIEVEMENTS := {
	"pvo": ["ПВО на минималках", "Прогнать НЛО ТЦК камнями"],
	"pigeon_friend": ["Голубиная дипломатия", "Подружиться с голубем"],
	"runner_done": ["Беги, Котакбас, беги", "Завершить раннер"],
	"no_hit": ["Ни царапины", "Пройти раннер без столкновений"],
	"first_night": ["Первая ночь", "Пережить первую ночь в лесу"],
	"builder": ["Прораб", "Построить 10 объектов"],
	"xp": ["Ностальгия", "Найти компьютер с Windows XP в лесу"],
	"robbed": ["Налоговая проверка", "Позволить НЛО украсть ресурсы"],
	"radio": ["Алло, это лес?", "Восстановить радиосвязь"],
	"finish": ["Это только начало", "Пройти игру"],
	"window": ["Классика жанра", "Выпрыгнуть в окно"],
	"chair": ["Стул победил", "Упасть со стула"],
}

## Отладочные функции доступны только в отладочной сборке, в релизе выключены.
var debug_enabled: bool = OS.is_debug_build()
var intro_shown := false
var in_game := false
var current_slot := "1"
var state: Dictionary = {}
var _playtime_accum := 0.0

var _overlay: CanvasLayer
var _fps_label: Label
var _toast_box: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	# Тема применяется глобально (в т.ч. к Control внутри CanvasLayer).
	var theme := UIStyle.build_theme()
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.fallback_font = UIStyle.body_font()
	ThemeDB.fallback_font_size = 26
	get_tree().root.theme = theme
	_build_overlay()
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()
	reset_state(DifficultyManager.Level.NORMAL)

func _process(delta: float) -> void:
	if in_game and not get_tree().paused:
		state["playtime"] = float(state.get("playtime", 0.0)) + delta
	if _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

# ---------------------------------------------------------------- Состояние

func reset_state(difficulty: int) -> void:
	state = {
		"difficulty": difficulty,
		"chapter": "novel",
		"flags": {},
		"carry_items": {},
		"novel": {},
		"runner": {},
		"survival": {},
		"achievements": [],
		"playtime": 0.0,
	}

func new_game(difficulty: int) -> void:
	DifficultyManager.set_level_for_new_game(difficulty)
	reset_state(difficulty)
	current_slot = "1"
	start_chapter("novel")

func start_chapter(chapter: String, autosave := true) -> void:
	state["chapter"] = chapter
	in_game = chapter in ["novel", "runner", "survival"]
	chapter_changed.emit(chapter)
	if autosave and in_game:
		SaveManager.save_slot("auto", state)
	SceneManager.change_scene(SCENES[chapter], CHAPTER_TITLES.get(chapter, ""))

func flag(name: String, default = false):
	return state.flags.get(name, default)

func set_flag(name: String, value) -> void:
	state.flags[name] = value

## Предметы, перенесённые из новеллы в выживание (еда, рюкзак...).
func add_carry_item(id: String, count: int) -> void:
	state.carry_items[id] = int(state.carry_items.get(id, 0)) + count

# ---------------------------------------------------------------- Сохранения

func capture_scene_state() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("save_state"):
		var chapter: String = state.chapter
		state[chapter] = scene.save_state()

func save_game(slot: String) -> bool:
	if not in_game:
		return false
	capture_scene_state()
	current_slot = slot
	return SaveManager.save_slot(slot, state)

func autosave() -> void:
	if in_game and Settings.get_value("autosave", true):
		save_game("auto")

func load_game(slot: String) -> bool:
	var data := SaveManager.load_slot(slot)
	if data.is_empty():
		return false
	reset_state(int(data.get("difficulty", 1)))
	for k in data.keys():
		state[k] = data[k]
	DifficultyManager.restore_level(int(state.difficulty))
	current_slot = slot if slot != "auto" else current_slot
	start_chapter(str(state.chapter), false)
	return true

func continue_game() -> bool:
	var slot := SaveManager.latest_slot()
	if slot == "":
		return false
	return load_game(slot)

## Титры. full=true — после финальной кат-сцены (с эпилогом и экраном «Игра пройдена!»),
## false — повторный просмотр только титров.
var credits_full := true

func show_credits(full: bool) -> void:
	credits_full = full
	in_game = false
	SceneManager.change_scene(SCENES.credits)

## Продолжить выживание после прохождения сюжета.
func continue_after_ending() -> void:
	DifficultyManager.restore_level(int(state.get("difficulty", 1)))
	start_chapter("survival", false)

func go_to_menu() -> void:
	in_game = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	DifficultyManager.unlock()
	SceneManager.change_scene(SCENES.menu)

# ---------------------------------------------------------------- Достижения

func unlock_achievement(id: String) -> void:
	if not ACHIEVEMENTS.has(id):
		return
	if not (id in state.achievements):
		state.achievements.append(id)
	if id in SaveManager.profile.achievements:
		return
	SaveManager.profile.achievements.append(id)
	SaveManager.save_profile()
	achievement_unlocked.emit(id)
	toast("Достижение: %s" % ACHIEVEMENTS[id][0], Color(1.0, 0.8, 0.2))
	AudioManager.play_sfx("achievement")

# ---------------------------------------------------------------- Оверлей

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 120
	add_child(_overlay)
	_fps_label = Label.new()
	_fps_label.position = Vector2(10, 4)
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fps_label)
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position.y = 70
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_overlay.add_child(_toast_box)

func toast(text: String, color: Color = Color.WHITE, duration := 3.0) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.08, 0.08, 0.1, 0.88), 14, color))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	_toast_box.add_child(panel)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
		_toast_box.remove_child(_toast_box.get_child(0))
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)

func _on_settings_changed() -> void:
	_fps_label.visible = Settings.get_value("show_fps", false)

# ---------------------------------------------------------------- Android

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Сворачивание приложения: сохраняем безопасное состояние.
			if in_game:
				autosave()
				SaveManager.save_profile()
			app_paused.emit()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			app_resumed.emit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back_requested.emit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if in_game:
				autosave()
			SaveManager.save_profile()
			get_tree().quit()

func vibrate(ms: int) -> void:
	if Settings.get_value("vibration", true):
		Input.vibrate_handheld(ms)

func quit_game() -> void:
	if in_game:
		autosave()
	SaveManager.save_profile()
	get_tree().quit()
