extends Node
## Загружает все скрипты проекта — выявляет ошибки компиляции.
## Запуск: godot --headless --path . res://tools/compile_all.tscn

func _ready() -> void:
	var failed := 0
	var files := _scan("res://scripts") + _scan("res://tests")
	for f in files:
		var s = load(f)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):
			print("FAIL ", f)
			failed += 1
	print("Скриптов: %d, ошибок: %d" % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _scan(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _scan(dir + "/" + sub)
	return out
