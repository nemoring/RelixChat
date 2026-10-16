extends Node
## Точка входа сквозной проверки: переносит раннер в корень, чтобы он
## пережил смену сцен (см. e2e_runner.gd).

func _ready() -> void:
	var r := Node.new()
	r.set_script(load("res://tools/e2e_runner.gd"))
	get_tree().root.add_child.call_deferred(r)
