class_name TouchControls
extends CanvasLayer
## Сенсорное управление для Android: левый виртуальный джойстик, обзор
## свайпом по правой половине, кнопки действий.

var world
var root: Control
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _look_idx := -1
var _look_last := Vector2.ZERO
var _knob: Control
var _base: Control
var _buttons := {}
const STICK_R := 90.0


func setup(w) -> void:
	world = w
	layer = 3
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
	_btn("crouch", "Присесть", Vector2(-340, -130), Vector2(150, 70), func(): world.player.crouching = not world.player.crouching)
	_btn("drop", "Положить", Vector2(-340, -220), Vector2(150, 70), func(): world.player.drop_item())
	_btn("sprint", "Бег", Vector2(-340, -310), Vector2(150, 70), func(): world.player.touch_sprint = not world.player.touch_sprint)
	_btn("pause", "II", Vector2(-90, 20), Vector2(70, 60), func():
		if world.desk.visible:
			world.close_desk()
		else:
			world.hud.toggle_pause(), Control.PRESET_TOP_RIGHT)
	_btn("tasks", "Задания", Vector2(-260, 20), Vector2(150, 60), func():
		var ev := InputEventAction.new()
		ev.action = "tasks"
		ev.pressed = true
		Input.parse_input_event(ev), Control.PRESET_TOP_RIGHT)
	var listen := _btn("listen", "Слушать", Vector2(-170, -110), Vector2(150, 70), func(): pass)
	listen.button_down.connect(func(): world.player.set_touch_listen(true))
	listen.button_up.connect(func(): world.player.set_touch_listen(false))
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
	b.pressed.connect(cb)
	root.add_child(b)
	_buttons[id] = b
	return b


func _process(_d: float) -> void:
	if not visible:
		return
	var seated: bool = world.player.seated
	for id in _buttons.keys():
		if id != "pause":
			(_buttons[id] as Button).visible = not seated and not world.game_over
	_buttons["sprint"].modulate = Color(0.6, 1, 0.7, 0.8) if world.player.touch_sprint else Color(1, 1, 1, 0.55)


func _input(event: InputEvent) -> void:
	if not visible or world.player.seated or world.game_over or world.hud.has_modal():
		return
	var half := root.get_viewport_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_button(event.position):
				return
			if event.position.x < half and _stick_idx < 0:
				_stick_idx = event.index
				_stick_origin = event.position
				_base.visible = true
				_knob.visible = true
				_base.position = _stick_origin - _base.size * 0.5
				_knob.position = _stick_origin - _knob.size * 0.5
			elif event.position.x >= half and _look_idx < 0:
				_look_idx = event.index
				_look_last = event.position
		else:
			if event.index == _stick_idx:
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
		elif event.index == _look_idx:
			world.player.add_touch_look((event.position - _look_last) * 2.0)
			_look_last = event.position


func _over_button(pos: Vector2) -> bool:
	for b in _buttons.values():
		if (b as Button).visible and (b as Button).get_global_rect().has_point(pos):
			return true
	return false
