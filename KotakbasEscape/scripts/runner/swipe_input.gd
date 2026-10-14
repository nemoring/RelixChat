class_name SwipeInput
extends Node
## Распознавание свайпов на сенсорном экране. Свайп срабатывает сразу при
## превышении порога (не дожидаясь отпускания пальца) — отзывчивое управление.

signal swiped(dir: Vector2i)

var threshold_ratio := 0.045 # доля высоты экрана
var _start := {}
var _fired := {}
var blocked_rects: Array[Rect2] = [] # зоны кнопок (пауза), где свайпы не считаем

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			for r in blocked_rects:
				if r.has_point(event.position):
					return
			_start[event.index] = event.position
			_fired[event.index] = false
		else:
			_start.erase(event.index)
			_fired.erase(event.index)
	elif event is InputEventScreenDrag:
		if not _start.has(event.index) or _fired.get(event.index, true):
			return
		var d: Vector2 = event.position - _start[event.index]
		var th := get_viewport().get_visible_rect().size.y * threshold_ratio
		if d.length() >= th:
			_fired[event.index] = true
			if absf(d.x) > absf(d.y):
				swiped.emit(Vector2i(1 if d.x > 0 else -1, 0))
			else:
				swiped.emit(Vector2i(0, 1 if d.y > 0 else -1))
	elif event is InputEventKey and event.pressed and not event.echo:
		# Клавиатура — только для отладки на ПК.
		match event.keycode:
			KEY_LEFT, KEY_A: swiped.emit(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D: swiped.emit(Vector2i(1, 0))
			KEY_UP, KEY_W, KEY_SPACE: swiped.emit(Vector2i(0, -1))
			KEY_DOWN, KEY_S: swiped.emit(Vector2i(0, 1))
