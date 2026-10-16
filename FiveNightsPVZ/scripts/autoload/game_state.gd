extends Node
## Глобальное состояние: сохранения, настройки, достижения, статистика,
## параметры текущего запуска ночи. Автозагрузка "GameState".

signal settings_changed

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 1
const MAX_NIGHT := 6

const ACHIEVEMENTS := {
	"first_shift": {"title": "Первая смена", "desc": "Пережить первую ночь."},
	"all_five": {"title": "Пять ночей", "desc": "Пережить пятую ночь."},
	"night_six": {"title": "Сверхурочные", "desc": "Пережить шестую ночь."},
	"no_cams": {"title": "Вслепую", "desc": "Пережить ночь 2+ ни разу не включив камеры."},
	"perfect_shift": {"title": "Образцовый сотрудник", "desc": "Закончить ночь без нарушений."},
	"collector": {"title": "Архивариус", "desc": "Найти все пять документов."},
	"secret_end": {"title": "Возврат оформлен", "desc": "Получить секретную концовку."},
	"own_order": {"title": "Получено", "desc": "Принять собственный заказ."},
	"stare": {"title": "Не смотри", "desc": "Пережить встречу с Безликим вплотную."},
	"fake_detect": {"title": "Служебная проверка", "desc": "Распознать три поддельных сообщения."},
}

const ENDINGS := {
	"shift_over": "Смена окончена",
	"received": "Получено",
	"returned": "Возврат",
}

const DOCUMENT_COUNT := 5

## Пути можно переопределить (тесты пишут во временные файлы).
var save_path := SAVE_PATH
var settings_path := SETTINGS_PATH

## Сохраняемые данные.
var data := {}
## Настройки.
var settings := {}

## Параметры текущей ночи (не сохраняются).
var current_night := 1
var custom_difficulty := {}  # entity_id -> 0..20 для пользовательской ночи
var is_custom_night := false
var last_result := {}  # результат последней ночи для экрана итогов
var run_seed := 0

var _quality_runtime_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	load_game()
	_setup_audio_buses()
	apply_settings()


# ---------------------------------------------------------------- Сохранения

func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"player_name": "Денис Смирнов",
		"unlocked_night": 1,
		"night_in_progress": 0,
		"custom_unlocked": false,
		"achievements": {},
		"endings": {},
		"documents": [],
		"stats": {
			"nights_completed": 0,
			"deaths": 0,
			"deaths_by": {},
			"orders_issued": 0,
			"parcels_scanned": 0,
			"returns_processed": 0,
			"fakes_detected": 0,
			"play_time": 0.0,
			"best_violations": 99,
		},
	}


func default_settings() -> Dictionary:
	return {
		"quality": _default_quality(),
		"adaptive_quality": true,
		"brightness": 1.0,
		"flicker": true,
		"fov": 72.0,
		"mouse_sens": 0.25,
		"touch_sens": 0.35,
		"invert_y": false,
		"master_volume": 0.85,
		"sfx_volume": 1.0,
		"ambience_volume": 0.9,
		"subtitles": true,
		"touch_controls": "auto",  # auto | on | off
		"head_bob": true,
		"vsync": true,
		"fullscreen": false,
	}


func _default_quality() -> int:
	if OS.has_feature("mobile") or OS.has_feature("android"):
		return 0
	return 1


func load_game() -> void:
	data = default_data()
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Сохранение повреждено, используется новое.")
		return
	_merge_into(data, parsed)
	# JSON возвращает числа как float: приводим номера документов к int,
	# иначе has(int) не находит их и документы дублируются.
	var docs := []
	for d in data.get("documents", []):
		if not docs.has(int(d)):
			docs.append(int(d))
	data["documents"] = docs


func save_game() -> bool:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать сохранение: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func reset_progress() -> void:
	var name_keep: String = data.get("player_name", "Денис Смирнов")
	data = default_data()
	data["player_name"] = name_keep
	save_game()


func _merge_into(target: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		if target.has(k) and typeof(target[k]) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge_into(target[k], src[k])
		else:
			target[k] = src[k]


func load_settings() -> void:
	settings = default_settings()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for k in settings.keys():
		if cfg.has_section_key("settings", k):
			var v = cfg.get_value("settings", k)
			if typeof(v) == typeof(settings[k]) or (typeof(settings[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				settings[k] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(settings_path)


func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()
	apply_settings()


# ---------------------------------------------------------------- Прогресс

func start_night(n: int, custom := {}) -> void:
	current_night = clampi(n, 1, MAX_NIGHT)
	is_custom_night = not custom.is_empty()
	custom_difficulty = custom
	run_seed = randi()
	if not is_custom_night:
		data["night_in_progress"] = current_night
		save_game()


func complete_night(n: int, violations: int, used_cameras: bool) -> void:
	var stats: Dictionary = data["stats"]
	stats["nights_completed"] = int(stats["nights_completed"]) + 1
	stats["best_violations"] = mini(int(stats["best_violations"]), violations)
	data["night_in_progress"] = 0
	if not is_custom_night:
		data["unlocked_night"] = maxi(int(data["unlocked_night"]), mini(n + 1, MAX_NIGHT))
		if n >= 5:
			data["custom_unlocked"] = true
	if n == 1:
		unlock_achievement("first_shift")
	if n == 5:
		unlock_achievement("all_five")
	if n == 6:
		unlock_achievement("night_six")
	if violations == 0:
		unlock_achievement("perfect_shift")
	if n >= 2 and not used_cameras:
		unlock_achievement("no_cams")
	save_game()


func register_death(entity_id: String) -> void:
	var stats: Dictionary = data["stats"]
	stats["deaths"] = int(stats["deaths"]) + 1
	var by: Dictionary = stats["deaths_by"]
	by[entity_id] = int(by.get(entity_id, 0)) + 1
	save_game()


func add_stat(key: String, amount: float = 1.0) -> void:
	var stats: Dictionary = data["stats"]
	stats[key] = stats.get(key, 0) + amount


func unlock_achievement(id: String) -> bool:
	if not ACHIEVEMENTS.has(id):
		return false
	var ach: Dictionary = data["achievements"]
	if ach.has(id):
		return false
	ach[id] = Time.get_datetime_string_from_system()
	save_game()
	return true


func unlock_ending(id: String) -> void:
	var e: Dictionary = data["endings"]
	e[id] = int(e.get(id, 0)) + 1
	if id == "returned":
		unlock_achievement("secret_end")
	if id == "received":
		unlock_achievement("own_order")
	save_game()


func collect_document(idx: int) -> bool:
	var docs: Array = data["documents"]
	if docs.has(idx):
		return false
	docs.append(idx)
	if docs.size() >= DOCUMENT_COUNT:
		unlock_achievement("collector")
	save_game()
	return true


func has_all_documents() -> bool:
	return (data["documents"] as Array).size() >= DOCUMENT_COUNT


func is_night_unlocked(n: int) -> bool:
	return n <= int(data["unlocked_night"])


func player_name() -> String:
	return str(data.get("player_name", "Денис Смирнов"))


# ---------------------------------------------------------------- Настройки

const QUALITY_NAMES := ["Низкое", "Среднее", "Высокое"]


func quality() -> int:
	return int(settings.get("quality", 1))


func apply_settings() -> void:
	_apply_volume("Master", float(settings["master_volume"]))
	_apply_volume("SFX", float(settings["sfx_volume"]))
	_apply_volume("Ambience", float(settings["ambience_volume"]))
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
		var want_fs: bool = settings["fullscreen"]
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale()
	settings_changed.emit()


func render_scale() -> float:
	var base: float = [0.7, 0.85, 1.0][clampi(quality(), 0, 2)]
	return clampf(base * _quality_runtime_scale, 0.45, 1.0)


## Адаптивное качество: вызывается системой мониторинга FPS.
func adapt_quality(direction: int) -> void:
	if not settings.get("adaptive_quality", true):
		_quality_runtime_scale = 1.0
		return
	_quality_runtime_scale = clampf(_quality_runtime_scale + 0.1 * direction, 0.6, 1.0)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale()


func use_touch_controls() -> bool:
	var mode: String = settings.get("touch_controls", "auto")
	if mode == "on":
		return true
	if mode == "off":
		return false
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() and OS.has_feature("android")


func _apply_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func _setup_audio_buses() -> void:
	# Шины создаются кодом: SFX, Ambience, UI и реверберации помещений.
	if AudioServer.get_bus_index("SFX") >= 0:
		return
	var master := AudioServer.get_bus_index("Master")
	# Лимитер на мастере: никаких болезненных пиков при скримерах.
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.5
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(master, lim)
	for bus_name in ["SFX", "Ambience", "UI"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	# Реверберации: маленькое помещение, кафель, большой склад, коридор.
	var reverbs := {
		"RevSmall": [0.25, 0.6, 0.12],
		"RevTile": [0.45, 0.25, 0.22],
		"RevLarge": [0.75, 0.45, 0.2],
		"RevCorridor": [0.55, 0.35, 0.25],
	}
	for bus_name in reverbs.keys():
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "SFX")
		var rv := AudioEffectReverb.new()
		var p: Array = reverbs[bus_name]
		rv.room_size = p[0]
		rv.damping = p[1]
		rv.wet = p[2]
		rv.dry = 1.0
		rv.spread = 0.6
		AudioServer.add_bus_effect(i, rv)
	# Эффект «прислушивания»: фильтр на шине окружения управляется игроком.
	var amb := AudioServer.get_bus_index("Ambience")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(amb, lp)
	AudioServer.set_bus_effect_enabled(amb, 0, false)


func set_listening(on: bool) -> void:
	var amb := AudioServer.get_bus_index("Ambience")
	if amb < 0:
		return
	AudioServer.set_bus_effect_enabled(amb, 0, on)
	var fx := AudioServer.get_bus_effect(amb, 0) as AudioEffectLowPassFilter
	if fx:
		fx.cutoff_hz = 900.0 if on else 20000.0
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0:
		var base := linear_to_db(maxf(float(settings["sfx_volume"]), 0.0001))
		AudioServer.set_bus_volume_db(sfx, base + (4.0 if on else 0.0))


# ---------------------------------------------------------------- Управление

const KEYMAP := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_C, KEY_CTRL],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
	"listen": [KEY_Q],
	"drop": [KEY_G],
	"tasks": [KEY_TAB],
	"pause": [KEY_ESCAPE],
}


func _setup_input() -> void:
	for action in KEYMAP.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEYMAP[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("interact", mb)
	var rb := InputEventMouseButton.new()
	rb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("listen", rb)
	# Геймпад.
	var pad := {"interact": JOY_BUTTON_A, "flashlight": JOY_BUTTON_Y, "crouch": JOY_BUTTON_B, "listen": JOY_BUTTON_LEFT_SHOULDER, "sprint": JOY_BUTTON_LEFT_STICK, "drop": JOY_BUTTON_X, "pause": JOY_BUTTON_START, "tasks": JOY_BUTTON_BACK}
	for action in pad.keys():
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action]
		InputMap.action_add_event(action, jb)
	var axes := {"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0], "move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0]}
	for action in axes.keys():
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)
