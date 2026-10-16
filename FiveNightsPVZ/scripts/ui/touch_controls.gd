class_name TouchControls
extends CanvasLayer
## Сенсорное управление для Android: левый виртуальный джойстик, обзор
## свайпом по правой половине, кнопки действий.
##
## Кнопки обрабатываются по событиям касания напрямую (любым пальцем),
## а не через эмуляцию мыши: эмуляция работает только для первого пальца,
## и кнопка не нажималась бы, пока другой палец держит джойстик.

var world
var root: Control
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _look_idx := -1
var _look_last := Vector2.ZERO
var _knob: Control
var _base: Control
var _buttons := {}
var _actions := {}
var _held := {}  # индекс пальца -> id кнопки
const STICK_R := 90.0


func setup(w) -> void:
	world = w
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_base = _circle(STICK_R * 2.0, Color(1, 1, 1, 0.08))
	_knob = _circle(70.0, Color(1, 1, 1, 0.2))
	_base.visible = false
	_knob.visible = false
	_btn("interact", "Действие", Vector2(-170, -200), Vector2(150, 90), func(): world.player.try_interact())
	_btn("flash", "Фонарик", Vector2(-170, -310), Vector2(150, 70), func(): world.player.toggle_flashlight())
	_btn("crouch", "Присесть", Vector2(-340, -130), Vector2(150, 70), func():
		if world.player.hiding_in == null:
			world.player.crouching = not world.player.crouching)
	_btn("drop", "Положить", Vector2(-340, -220), Vector2(150, 70), func(): world.player.drop_item())
	_btn("sprint", "Бег", Vector2(-340, -310), Vector2(150, 70), func(): world.player.touch_sprint = not world.player.touch_sprint)
	_btn("pause", "II", Vector2(-90, 20), Vector2(70, 60), func():
		if world.game_over:
			return
		if world.desk.visible:
			world.close_desk()
		else:
			world.hud.toggle_pause(), Control.PRESET_TOP_RIGHT)
	_btn("tasks", "Задания", Vector2(-260, 20), Vector2(150, 60), func(): world.hud.toggle_tasks(), Control.PRESET_TOP_RIGHT)
	_btn("listen", "Слушать", Vector2(-170, -110), Vector2(150, 70), func(): pass)
	visible = GameState.use_touch_controls()
	GameState.settings_changed.connect(func(): visible = GameState.use_touch_controls())


func _circle(d: float, c: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(d * 0.5))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p


func _btn(id: String, text: String, pos: Vector2, size: Vector2, cb: Callable, preset := Control.PRESET_BOTTOM_RIGHT) -> Button:
	var b := Button.new()
	b.text = text
	b.set_anchors_preset(preset)
	b.position = pos
	b.size = size
	b.modulate = Color(1, 1, 1, 0.55)
	b.focus_mode = Control.FOCUS_NONE
	# Нажатия обрабатываются в _input по касаниям, не мышью.
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(b)
	_buttons[id] = b
	_actions[id] = cb
	return b


func _process(_d: float) -> void:
	if not visible:
		return
	var seated: bool = world.player.seated
	var modal: bool = world.hud.has_modal() or world.hud.paused
	for id in _buttons.keys():
		var show: bool = not world.game_over and not modal
		if id != "pause":
			show = show and not seated
		(_buttons[id] as Button).visible = show
	_buttons["sprint"].modulate = Color(0.6, 1, 0.7, 0.8) if world.player.touch_sprint else Color(1, 1, 1, 0.55)
	if (world.game_over or seated or modal) and (_stick_idx >= 0 or _look_idx >= 0):
		_release_all()


func _release_all() -> void:
	_stick_idx = -1
	_look_idx = -1
	world.player.touch_move = Vector2.ZERO
	world.player.set_touch_listen(false)
	_held.clear()
	_base.visible = false
	_knob.visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var id := _button_at(event.position)
			if id != "":
				_held[event.index] = id
				(_buttons[id] as Button).modulate.a = 0.95
				if id == "listen":
					world.player.set_touch_listen(true)
				else:
					Sfx.play_ui("click", -16.0)
					(_actions[id] as Callable).call()
				get_viewport().set_input_as_handled()
				return
			if world.player.seated or world.game_over or world.hud.has_modal() or world.hud.paused:
				return
			var half := root.get_viewport_rect().size.x * 0.5
			if event.position.x < half and _stick_idx < 0:
				_stick_idx = event.index
				_stick_origin = event.position
				_base.visible = true
				_knob.visible = true
				_base.position = _stick_origin - _base.size * 0.5
				_knob.position = _stick_origin - _knob.size * 0.5
				get_viewport().set_input_as_handled()
			elif event.position.x >= half and _look_idx < 0:
				_look_idx = event.index
				_look_last = event.position
				get_viewport().set_input_as_handled()
		else:
			if _held.has(event.index):
				var id: String = _held[event.index]
				_held.erase(event.index)
				(_buttons[id] as Button).modulate.a = 0.55
				if id == "listen":
					world.player.set_touch_listen(false)
				get_viewport().set_input_as_handled()
			elif event.index == _stick_idx:
				_stick_idx = -1
				world.player.touch_move = Vector2.ZERO
				_base.visible = false
				_knob.visible = false
			elif event.index == _look_idx:
				_look_idx = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_idx:
			var d: Vector2 = (event.position - _stick_origin).limit_length(STICK_R)
			_knob.position = _stick_origin + d - _knob.size * 0.5
			world.player.touch_move = d / STICK_R
			get_viewport().set_input_as_handled()
		elif event.index == _look_idx:
			world.player.add_touch_look((event.position - _look_last) * 2.0)
			_look_last = event.position
			get_viewport().set_input_as_handled()


func _button_at(pos: Vector2) -> String:
	for id in _buttons.keys():
		var b := _buttons[id] as Button
		if b.visible and b.get_global_rect().has_point(pos):
			return id
	return ""
