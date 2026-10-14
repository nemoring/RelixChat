class_name TouchControls
extends Control
## Сенсорное управление выживанием с настоящим мультитачем:
## плавающий джойстик слева, обзор свайпами справа, круглые кнопки действий,
## панель быстрого доступа. Зеркальная раскладка, размеры из настроек.

signal button_pressed(id: String)
signal button_released(id: String)

var enabled := true
var move_vec := Vector2.ZERO
var look_delta := Vector2.ZERO
var buttons := {} # id -> {pos, r, label, visible, rect(Rect2 для прямоугольных), active}
var hotbar_items: Array = [] # [{id, n}] или null
var hotbar_selected := 0
var _owner := {} # индекс касания -> "joy" | "look" | id кнопки
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _joy_radius := 110.0
var _pressed := {}
var _icon_cache := {}

const GAME_BUTTONS := ["attack", "jump", "interact", "crouch", "throw", "use"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_define()
	resized.connect(_layout)
	Settings.changed.connect(_layout)
	_layout()

func _define() -> void:
	var defs := {
		"attack": "Удар", "jump": "Прыжок", "interact": "", "crouch": "Присесть",
		"throw": "Бросок", "use": "Съесть",
		"pause": "II", "inv": "Вещи", "craft": "Крафт", "build": "Стройка", "cam": "Вид", "map": "Карта",
		"rotate": "Поворот", "place": "Ставить", "cancel": "Отмена", "pieces": "Выбор",
	}
	for id in defs:
		buttons[id] = {"pos": Vector2.ZERO, "r": 50.0, "label": defs[id], "visible": true, "rect": Rect2()}
	for i in 6:
		buttons["hot%d" % i] = {"pos": Vector2.ZERO, "r": 0.0, "label": "", "visible": true, "rect": Rect2()}
	for id in ["throw", "use", "interact", "rotate", "place", "cancel", "pieces"]:
		buttons[id].visible = false

func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0:
		return
	var bs := float(Settings.get_value("button_size", 1.0))
	_joy_radius = 105.0 * float(Settings.get_value("joystick_size", 1.0))
	var mirror: bool = Settings.get_value("left_handed", false)
	var fx := func(x: float) -> float: return w - x if not mirror else x
	buttons.attack.pos = Vector2(fx.call(140 * bs), h - 150 * bs)
	buttons.attack.r = 72 * bs
	buttons.jump.pos = Vector2(fx.call(300 * bs), h - 92 * bs)
	buttons.jump.r = 52 * bs
	buttons.crouch.pos = Vector2(fx.call(300 * bs), h - 228 * bs)
	buttons.crouch.r = 44 * bs
	buttons.interact.pos = Vector2(fx.call(150 * bs), h - 330 * bs)
	buttons.interact.r = 60 * bs
	buttons.throw.pos = Vector2(fx.call(300 * bs), h - 370 * bs)
	buttons.throw.r = 62 * bs
	buttons.use.pos = Vector2(fx.call(430 * bs), h - 120 * bs)
	buttons.use.r = 48 * bs
	# Режим строительства
	buttons.place.pos = buttons.attack.pos
	buttons.place.r = 72 * bs
	buttons.rotate.pos = buttons.jump.pos
	buttons.rotate.r = 52 * bs
	buttons.cancel.pos = buttons.crouch.pos
	buttons.cancel.r = 46 * bs
	buttons.pieces.pos = buttons.interact.pos
	buttons.pieces.r = 52 * bs
	# Верхний ряд (меню)
	var top_ids := ["pause", "inv", "craft", "build", "cam", "map"]
	var tr_ := 36.0 * bs
	for i in top_ids.size():
		var x: float = fx.call(48 * bs + i * (tr_ * 2.0 + 12.0))
		buttons[top_ids[i]].pos = Vector2(x, 48 * bs)
		buttons[top_ids[i]].r = tr_
	# Панель быстрого доступа
	var cell := 78.0 * bs
	var total := cell * 6 + 8 * 5
	var x0 := w * 0.5 - total * 0.5
	for i in 6:
		buttons["hot%d" % i].rect = Rect2(x0 + i * (cell + 8), h - cell - 12, cell, cell)
	queue_redraw()

func set_visible_button(id: String, v: bool) -> void:
	if buttons.has(id) and buttons[id].visible != v:
		buttons[id].visible = v
		queue_redraw()

func set_label(id: String, text: String) -> void:
	if buttons.has(id) and buttons[id].label != text:
		buttons[id].label = text
		queue_redraw()

func set_build_mode(on: bool) -> void:
	for id in ["place", "rotate", "cancel", "pieces"]:
		buttons[id].visible = on
	for id in ["attack", "jump", "crouch"]:
		buttons[id].visible = not on
	queue_redraw()

func release_all() -> void:
	for idx in _owner.keys():
		var o: String = _owner[idx]
		if o != "joy" and o != "look":
			button_released.emit(o)
	_owner.clear()
	_pressed.clear()
	_joy_index = -1
	move_vec = Vector2.ZERO
	queue_redraw()

func _hit_button(p: Vector2) -> String:
	for id in buttons:
		var b: Dictionary = buttons[id]
		if not b.visible:
			continue
		if b.rect.size != Vector2.ZERO:
			if b.rect.has_point(p):
				return id
		elif p.distance_to(b.pos) <= b.r * 1.12:
			return id
	return ""

func _in_joy_zone(p: Vector2) -> bool:
	var mirror: bool = Settings.get_value("left_handed", false)
	var in_x := p.x < size.x * 0.42 if not mirror else p.x > size.x * 0.58
	return in_x and p.y > size.y * 0.3

func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var id := _hit_button(event.position)
			if id != "":
				_owner[event.index] = id
				_pressed[id] = true
				button_pressed.emit(id)
				get_viewport().set_input_as_handled()
			elif _in_joy_zone(event.position) and _joy_index == -1:
				_owner[event.index] = "joy"
				_joy_index = event.index
				_joy_center = event.position
				_joy_knob = event.position
			else:
				_owner[event.index] = "look"
			queue_redraw()
		else:
			var o: String = _owner.get(event.index, "")
			_owner.erase(event.index)
			if o == "joy":
				_joy_index = -1
				move_vec = Vector2.ZERO
			elif o != "" and o != "look":
				_pressed.erase(o)
				button_released.emit(o)
			queue_redraw()
	elif event is InputEventScreenDrag:
		var o2: String = _owner.get(event.index, "")
		if o2 == "joy":
			var d: Vector2 = event.position - _joy_center
			if d.length() > _joy_radius:
				# джойстик «едет» за пальцем
				_joy_center += d - d.normalized() * _joy_radius
				d = event.position - _joy_center
			_joy_knob = event.position
			var v := d / _joy_radius
			move_vec = v if v.length() > 0.15 else Vector2.ZERO
			queue_redraw()
		elif o2 == "look" or o2 == "throw":
			look_delta += event.relative

func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d

func is_held(id: String) -> bool:
	return _pressed.has(id)

func _icon(item_id: String) -> Texture2D:
	if not _icon_cache.has(item_id):
		_icon_cache[item_id] = ItemDB.icon(item_id)
	return _icon_cache[item_id]

func _draw() -> void:
	var font := UIStyle.bold_font()
	# Джойстик
	if _joy_index != -1:
		draw_circle(_joy_center, _joy_radius, Color(1, 1, 1, 0.12))
		draw_arc(_joy_center, _joy_radius, 0, TAU, 40, Color(1, 1, 1, 0.4), 3.0, true)
		var knob := _joy_center + (_joy_knob - _joy_center).limit_length(_joy_radius)
		draw_circle(knob, _joy_radius * 0.42, Color(1, 0.6, 0.15, 0.7))
	else:
		var mirror: bool = Settings.get_value("left_handed", false)
		var hint_c := Vector2(size.x - 190.0 if mirror else 190.0, size.y - 190.0)
		draw_circle(hint_c, _joy_radius, Color(1, 1, 1, 0.06))
		draw_arc(hint_c, _joy_radius, 0, TAU, 40, Color(1, 1, 1, 0.18), 2.0, true)
		draw_circle(hint_c, _joy_radius * 0.42, Color(1, 1, 1, 0.12))
	# Кнопки
	for id in buttons:
		var b: Dictionary = buttons[id]
		if not b.visible:
			continue
		var pressed := _pressed.has(id)
		if b.rect.size != Vector2.ZERO:
			_draw_hot_slot(id, b, pressed, font)
			continue
		var bg := Color(0.08, 0.08, 0.1, 0.55) if not pressed else Color(1, 0.55, 0.12, 0.75)
		if id == "attack" or id == "place":
			bg = Color(0.6, 0.15, 0.1, 0.55) if not pressed else Color(1, 0.35, 0.2, 0.8)
		if id == "throw":
			bg = Color(0.15, 0.3, 0.6, 0.6) if not pressed else Color(0.3, 0.6, 1.0, 0.8)
		if id == "interact":
			bg = Color(0.15, 0.45, 0.2, 0.65) if not pressed else Color(0.3, 0.8, 0.4, 0.85)
		draw_circle(b.pos, b.r, bg)
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0, true)
		var fs := int(clampf(b.r * 0.38, 15, 30))
		var text: String = b.label
		if id == "interact" and text.length() > 14:
			fs = int(fs * 0.8)
		var lines := text.split("\n")
		var line_h := fs * 1.05
		var y0: float = b.pos.y - (lines.size() - 1) * line_h * 0.5 + fs * 0.35
		for li in lines.size():
			var t: String = lines[li]
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if tw > b.r * 1.9 and id == "interact":
				# длинная подпись выносится под кнопку
				var tw2 := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
				var p2 := Vector2(b.pos.x - tw2 * 0.5, b.pos.y + b.r + 26)
				draw_rect(Rect2(p2 - Vector2(8, 22), Vector2(tw2 + 16, 30)), Color(0, 0, 0, 0.6))
				draw_string(font, p2, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
				draw_string(font, b.pos + Vector2(-9, 10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
				continue
			draw_string_outline(font, Vector2(b.pos.x - tw * 0.5, y0 + li * line_h), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(b.pos.x - tw * 0.5, y0 + li * line_h), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _draw_hot_slot(id: String, b: Dictionary, pressed: bool, font: Font) -> void:
	var i := int(id.substr(3))
	var r: Rect2 = b.rect
	var sel := i == hotbar_selected
	draw_rect(r, Color(0.06, 0.06, 0.08, 0.7) if not pressed else Color(0.3, 0.2, 0.1, 0.85))
	draw_rect(r, UIStyle.ACCENT if sel else Color(1, 1, 1, 0.3), false, 4.0 if sel else 2.0)
	if i < hotbar_items.size() and hotbar_items[i] != null:
		var it: Dictionary = hotbar_items[i]
		var tex := _icon(it.id)
		if tex:
			draw_texture_rect(tex, r.grow(-8), false)
		if int(it.n) > 1:
			var t := str(it.n)
			var fs := 20
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, r.end - Vector2(tw + 6, 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
			draw_string(font, r.end - Vector2(tw + 6, 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_string(font, r.position + Vector2(5, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5))
