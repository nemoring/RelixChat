extends Node
## Сохранения с атомарной записью: данные пишутся во временный файл,
## старый файл переименовывается в .bak, затем временный становится основным.
## При повреждении основного файла загружается резервная копия.

signal saved(slot: String)
signal loaded(slot: String)

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const SLOTS := ["auto", "1", "2", "3"]
const PROFILE_PATH := "user://profile.json"

var profile := {
	"achievements": [],
	"read_lines": {},
	"completed": false,
}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_profile()

func slot_path(slot: String) -> String:
	return "%s/slot_%s.json" % [SAVE_DIR, slot]

func write_json_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось открыть %s: %s" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "", false))
	f.flush()
	f.close()
	# Проверяем, что записанный файл читается.
	var check := _read_json(tmp)
	if check.is_empty():
		push_error("Проверка временного сохранения не прошла")
		return false
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	return err == OK

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func save_slot(slot: String, state: Dictionary) -> bool:
	var data := state.duplicate(true)
	data["version"] = SAVE_VERSION
	data["timestamp"] = Time.get_unix_time_from_system()
	data["datetime"] = Time.get_datetime_string_from_system(false, true)
	var ok := write_json_atomic(slot_path(slot), data)
	if ok:
		saved.emit(slot)
	return ok

func load_slot(slot: String) -> Dictionary:
	var path := slot_path(slot)
	var data := _read_json(path)
	if not _valid(data):
		data = _read_json(path + ".bak")
		if not _valid(data):
			return {}
		push_warning("Основное сохранение повреждено, загружена резервная копия: " + slot)
	loaded.emit(slot)
	return data

func _valid(data: Dictionary) -> bool:
	return not data.is_empty() and data.has("chapter") and data.has("difficulty") and int(data.get("version", 0)) <= SAVE_VERSION

func has_slot(slot: String) -> bool:
	return _valid(_read_json(slot_path(slot))) or _valid(_read_json(slot_path(slot) + ".bak"))

func delete_slot(slot: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = slot_path(slot) + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func slot_meta(slot: String) -> Dictionary:
	var d := load_slot(slot)
	if d.is_empty():
		return {}
	return {
		"slot": slot,
		"chapter": d.get("chapter", ""),
		"difficulty": int(d.get("difficulty", 1)),
		"datetime": d.get("datetime", ""),
		"timestamp": float(d.get("timestamp", 0)),
		"playtime": float(d.get("playtime", 0)),
	}

func latest_slot() -> String:
	var best := ""
	var best_t := -1.0
	for s in SLOTS:
		var m := slot_meta(s)
		if not m.is_empty() and m.timestamp > best_t:
			best_t = m.timestamp
			best = s
	return best

func has_any_save() -> bool:
	return latest_slot() != ""

# --- Профиль (достижения и прочитанные реплики, общие для всех прохождений) ---

func _load_profile() -> void:
	var d := _read_json(PROFILE_PATH)
	if d.is_empty():
		d = _read_json(PROFILE_PATH + ".bak")
	for k in d.keys():
		profile[k] = d[k]

func save_profile() -> void:
	write_json_atomic(PROFILE_PATH, profile)

func mark_line_read(line_id: String) -> void:
	profile.read_lines[line_id] = true

func is_line_read(line_id: String) -> bool:
	return profile.read_lines.has(line_id)
