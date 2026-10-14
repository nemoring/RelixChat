extends Node
## Компилирует все скрипты проекта (с автозагрузками) и сообщает об ошибках.
## Запуск: godot --headless --path . res://tests/compile_all.tscn

func _ready() -> void:
	var failed := 0
	var files := _collect("res://", [])
	for f in files:
		var s = load(f)
		if s == null or not (s is GDScript) or not s.can_instantiate():
			print("FAIL: ", f)
			failed += 1
	print("Скриптов проверено: %d, ошибок: %d" % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)

func _collect(dir: String, out: Array) -> Array:
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
