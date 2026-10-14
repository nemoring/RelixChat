class_name NovelArt
extends Control
## Двухмерные фоны локаций новеллы, нарисованные в коде (плоская иллюстрация),
## с анимированными деталями, и кат-сцена прыжка из окна.

var location := "bedroom"
var flags: Dictionary = {}
var cut_t := 0.0 # прогресс кат-сцены 0..1
var _t := 0.0
const INK := Color(0.1, 0.08, 0.07)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func P(x: float, y: float) -> Vector2:
	return Vector2(x * size.x, y * size.y)

func R(x0: float, y0: float, x1: float, y1: float) -> Rect2:
	return Rect2(P(x0, y0), P(x1, y1) - P(x0, y0))

func box(x0: float, y0: float, x1: float, y1: float, col: Color, outline := true, w := 4.0) -> void:
	var r := R(x0, y0, x1, y1)
	draw_rect(r, col)
	if outline:
		draw_rect(r, INK, false, w)

func poly(pts: Array, col: Color, outline := true) -> void:
	var pv := PackedVector2Array()
	for p in pts:
		pv.append(P(p.x, p.y))
	draw_colored_polygon(pv, col)
	if outline:
		pv.append(pv[0])
		draw_polyline(pv, INK, 4.0, true)

func circ(x: float, y: float, r: float, col: Color, outline := true) -> void:
	var c := P(x, y)
	var rr := r * size.y
	draw_circle(c, rr, col)
	if outline:
		draw_arc(c, rr, 0, TAU, 28, INK, 3.0, true)

func line(x0: float, y0: float, x1: float, y1: float, col: Color = INK, w := 4.0) -> void:
	draw_line(P(x0, y0), P(x1, y1), col, w, true)

func text(x: float, y: float, s: String, sz: int, col: Color) -> void:
	draw_string(UIStyle.title_font(), P(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _draw() -> void:
	match location:
		"bedroom": _bedroom()
		"kitchen": _kitchen()
		"corridor": _corridor()
		"balcony": _balcony()
		"entrance": _entrance()
		"yard": _yard()
		"jump": _jump()
		"black": draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	# Лёгкая виньетка
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.0))

func _wall(col: Color, floor_col: Color, floor_y := 0.74) -> void:
	box(0, 0, 1, floor_y, col, false)
	box(0, floor_y, 1, 1, floor_col, false)
	line(0, floor_y, 1, floor_y, INK, 5)
	for i in 10:
		line(i * 0.11, floor_y, i * 0.11 - 0.06, 1.0, floor_col.darkened(0.15), 3)

func _window(x0: float, y0: float, x1: float, y1: float, night := false) -> void:
	box(x0 - 0.01, y0 - 0.015, x1 + 0.01, y1 + 0.015, Color(0.95, 0.95, 0.92))
	var sky := Color(0.55, 0.75, 0.95) if not night else Color(0.1, 0.12, 0.25)
	box(x0, y0, x1, y1, sky, false)
	# облака
	var cx := x0 + fmod(_t * 0.01, x1 - x0)
	circ(cx, y0 + (y1 - y0) * 0.3, 0.025, Color(1, 1, 1, 0.9), false)
	circ(cx + 0.02, y0 + (y1 - y0) * 0.3, 0.03, Color(1, 1, 1, 0.9), false)
	# дома за окном
	box(x0 + 0.01, y0 + (y1 - y0) * 0.55, x0 + (x1 - x0) * 0.45, y1, Color(0.6, 0.6, 0.65), false)
	box(x0 + (x1 - x0) * 0.55, y0 + (y1 - y0) * 0.45, x1 - 0.01, y1, Color(0.55, 0.55, 0.6), false)
	line((x0 + x1) * 0.5, y0, (x0 + x1) * 0.5, y1, Color(0.95, 0.95, 0.92), 6)
	line(x0, (y0 + y1) * 0.5, x1, (y0 + y1) * 0.5, Color(0.95, 0.95, 0.92), 6)
	draw_rect(R(x0, y0, x1, y1), INK, false, 4)

func _bedroom() -> void:
	_wall(Color(0.62, 0.72, 0.82), Color(0.55, 0.38, 0.25))
	# узор обоев
	for i in 12:
		for j in 6:
			circ(0.04 + i * 0.085, 0.06 + j * 0.12, 0.006, Color(1, 1, 1, 0.25), false)
	_window(0.54, 0.14, 0.72, 0.5)
	# шторы
	var sway := sin(_t * 1.3) * 0.006
	poly([Vector2(0.51, 0.1), Vector2(0.56 + sway, 0.1), Vector2(0.55 + sway, 0.56), Vector2(0.5, 0.56)], Color(0.85, 0.35, 0.3))
	poly([Vector2(0.7 - sway, 0.1), Vector2(0.75, 0.1), Vector2(0.76, 0.56), Vector2(0.71 - sway, 0.56)], Color(0.85, 0.35, 0.3))
	line(0.49, 0.1, 0.77, 0.1, INK, 6)
	# часы 06:47
	box(0.3, 0.12, 0.42, 0.22, Color(0.15, 0.15, 0.18))
	text(0.31, 0.2, "06:47", int(size.y * 0.06), Color(1, 0.25, 0.2) if int(_t * 2.0) % 2 == 0 else Color(0.6, 0.1, 0.1))
	# постер
	box(0.08, 0.1, 0.22, 0.32, Color(0.2, 0.2, 0.25))
	text(0.095, 0.24, "КОТ", int(size.y * 0.07), Color(1, 0.6, 0.2))
	# кровать
	box(0.04, 0.56, 0.42, 0.82, Color(0.5, 0.33, 0.2))
	box(0.04, 0.46, 0.08, 0.82, Color(0.45, 0.3, 0.18))
	box(0.08, 0.53, 0.42, 0.66, Color(0.35, 0.5, 0.85))
	poly([Vector2(0.09, 0.5), Vector2(0.18, 0.49), Vector2(0.19, 0.57), Vector2(0.09, 0.58)], Color(0.96, 0.96, 0.96))
	for k in 4:
		line(0.14 + k * 0.07, 0.53, 0.18 + k * 0.07, 0.66, Color(0.25, 0.4, 0.75), 3)
	# тумбочка с телефоном
	box(0.44, 0.58, 0.51, 0.8, Color(0.6, 0.42, 0.28))
	if not flags.get("has_phone", false):
		box(0.455, 0.545, 0.495, 0.58, Color(0.1, 0.1, 0.12))
		if int(_t * 3.0) % 3 == 0:
			box(0.46, 0.55, 0.49, 0.575, Color(0.4, 0.8, 1.0), false)
	# стол и стул
	box(0.6, 0.55, 0.8, 0.59, Color(0.6, 0.4, 0.25))
	line(0.62, 0.59, 0.62, 0.8, INK, 6)
	line(0.78, 0.59, 0.78, 0.8, INK, 6)
	box(0.68, 0.5, 0.71, 0.55, Color(0.3, 0.3, 0.35))
	var tilt := 0.02 if flags.get("fell_chair", false) else 0.0
	poly([Vector2(0.66, 0.66 + tilt), Vector2(0.74, 0.66 - tilt), Vector2(0.74, 0.69 - tilt), Vector2(0.66, 0.69 + tilt)], Color(0.5, 0.3, 0.2))
	line(0.73, 0.66, 0.74, 0.5, INK, 6)
	line(0.67, 0.69, 0.665, 0.82, INK, 5)
	line(0.73, 0.69, 0.735, 0.82, INK, 5)
	# шкаф
	box(0.82, 0.1, 0.97, 0.8, Color(0.55, 0.37, 0.22))
	line(0.895, 0.12, 0.895, 0.78, INK, 4)
	circ(0.88, 0.45, 0.008, Color(0.9, 0.8, 0.3))
	circ(0.91, 0.45, 0.008, Color(0.9, 0.8, 0.3))
	if not flags.get("has_backpack", false):
		box(0.85, 0.06, 0.93, 0.1, Color(0.2, 0.5, 0.3))
	# ковёр
	poly([Vector2(0.15, 0.86), Vector2(0.7, 0.86), Vector2(0.75, 0.97), Vector2(0.1, 0.97)], Color(0.7, 0.2, 0.25))

func _kitchen() -> void:
	_wall(Color(0.95, 0.88, 0.6), Color(0.75, 0.75, 0.72))
	for i in 20:
		line(i * 0.05, 0.35, i * 0.05, 0.74, Color(1, 1, 1, 0.35), 2)
	line(0, 0.35, 1, 0.35, Color(0.8, 0.7, 0.4), 4)
	_window(0.46, 0.1, 0.62, 0.38)
	# холодильник
	box(0.04, 0.12, 0.2, 0.8, Color(0.94, 0.94, 0.96))
	line(0.04, 0.34, 0.2, 0.34, INK, 4)
	box(0.17, 0.18, 0.18, 0.28, Color(0.6, 0.6, 0.6))
	box(0.17, 0.4, 0.18, 0.55, Color(0.6, 0.6, 0.6))
	box(0.07, 0.2, 0.12, 0.26, Color(1, 0.4, 0.5))
	# плита и чайник
	box(0.24, 0.52, 0.38, 0.8, Color(0.9, 0.9, 0.9))
	circ(0.28, 0.53, 0.015, INK)
	circ(0.34, 0.53, 0.015, INK)
	poly([Vector2(0.29, 0.52), Vector2(0.3, 0.44), Vector2(0.35, 0.44), Vector2(0.36, 0.52)], Color(0.85, 0.2, 0.2))
	if int(_t) % 4 < 2:
		circ(0.37, 0.42 - fmod(_t, 1.0) * 0.05, 0.01, Color(1, 1, 1, 0.6), false)
	# стол
	box(0.44, 0.6, 0.68, 0.64, Color(0.6, 0.45, 0.3))
	line(0.46, 0.64, 0.46, 0.84, INK, 6)
	line(0.66, 0.64, 0.66, 0.84, INK, 6)
	if not flags.get("took_pryaniki", false):
		for k in 3:
			poly([Vector2(0.5 + k * 0.045, 0.6), Vector2(0.51 + k * 0.045, 0.57), Vector2(0.54 + k * 0.045, 0.57), Vector2(0.545 + k * 0.045, 0.6)], Color(0.65, 0.38, 0.15))
	# телевизор на полке
	box(0.7, 0.36, 0.9, 0.39, Color(0.5, 0.35, 0.22))
	box(0.72, 0.18, 0.88, 0.36, Color(0.18, 0.16, 0.15))
	if flags.get("tv_on", false):
		box(0.735, 0.2, 0.865, 0.34, Color(0.4 + 0.1 * sin(_t * 9.0), 0.5, 0.65), false)
		text(0.745, 0.29, "НОВОСТИ", int(size.y * 0.025), Color.WHITE)
	else:
		box(0.735, 0.2, 0.865, 0.34, Color(0.08, 0.1, 0.1), false)
	# ящик стола
	box(0.8, 0.52, 0.97, 0.8, Color(0.62, 0.45, 0.3))
	line(0.8, 0.62, 0.97, 0.62, INK, 4)
	box(0.87, 0.565, 0.9, 0.58, Color(0.9, 0.8, 0.4))
	box(0.87, 0.68, 0.9, 0.695, Color(0.9, 0.8, 0.4))

func _corridor() -> void:
	_wall(Color(0.7, 0.62, 0.5), Color(0.45, 0.32, 0.22))
	for i in 25:
		line(i * 0.04, 0, i * 0.04, 0.74, Color(0, 0, 0, 0.05), 6)
	# дверь
	box(0.4, 0.1, 0.6, 0.8, Color(0.45, 0.25, 0.15), true, 6)
	box(0.43, 0.15, 0.57, 0.42, Color(0.5, 0.3, 0.2))
	box(0.43, 0.47, 0.57, 0.76, Color(0.5, 0.3, 0.2))
	circ(0.565, 0.47, 0.012, Color(0.9, 0.8, 0.3))
	circ(0.5, 0.22, 0.012, Color(0.2, 0.2, 0.2))
	if flags.get("knocking", false):
		var sh := sin(_t * 40.0) * 0.003
		draw_rect(R(0.4 + sh, 0.1, 0.6 + sh, 0.8), Color(1, 1, 1, 0.08))
	# вешалка
	line(0.26, 0.18, 0.38, 0.18, INK, 6)
	poly([Vector2(0.28, 0.2), Vector2(0.33, 0.2), Vector2(0.35, 0.5), Vector2(0.26, 0.5)], Color(0.3, 0.35, 0.45))
	# полка со справкой
	box(0.08, 0.42, 0.24, 0.45, Color(0.5, 0.35, 0.2))
	if not flags.get("has_spravka", false):
		poly([Vector2(0.12, 0.42), Vector2(0.14, 0.33), Vector2(0.2, 0.34), Vector2(0.19, 0.42)], Color(0.97, 0.97, 0.92))
		line(0.145, 0.36, 0.185, 0.365, Color(0.3, 0.3, 0.6), 2)
		line(0.143, 0.38, 0.183, 0.385, Color(0.3, 0.3, 0.6), 2)
	box(0.09, 0.45, 0.23, 0.8, Color(0.55, 0.38, 0.24))
	# зеркало
	poly([Vector2(0.74, 0.14), Vector2(0.88, 0.14), Vector2(0.88, 0.6), Vector2(0.74, 0.6)], Color(0.7, 0.85, 0.9))
	line(0.76, 0.2, 0.8, 0.16, Color(1, 1, 1, 0.8), 4)
	line(0.77, 0.26, 0.84, 0.18, Color(1, 1, 1, 0.6), 3)
	# обувь
	poly([Vector2(0.64, 0.8), Vector2(0.7, 0.8), Vector2(0.71, 0.84), Vector2(0.63, 0.84)], Color(0.95, 0.95, 0.95))
	poly([Vector2(0.72, 0.8), Vector2(0.78, 0.8), Vector2(0.79, 0.84), Vector2(0.71, 0.84)], Color(0.95, 0.95, 0.95))

func _balcony() -> void:
	# небо и вид
	box(0, 0, 1, 1, Color(0.55, 0.75, 0.95), false)
	for k in 3:
		var cx := fmod(0.1 + k * 0.35 + _t * 0.008, 1.2) - 0.1
		circ(cx, 0.1 + k * 0.05, 0.04, Color(1, 1, 1, 0.9), false)
		circ(cx + 0.04, 0.1 + k * 0.05, 0.05, Color(1, 1, 1, 0.9), false)
	# дальний лес
	for i in 30:
		var x := i * 0.035
		poly([Vector2(x, 0.48), Vector2(x + 0.02, 0.36 - fmod(i * 0.37, 0.05)), Vector2(x + 0.04, 0.48)], Color(0.2, 0.42, 0.25), false)
	# промзона с трубой
	box(0.6, 0.38, 0.75, 0.5, Color(0.5, 0.5, 0.55), false)
	box(0.66, 0.22, 0.68, 0.4, Color(0.6, 0.4, 0.35), false)
	circ(0.67 + sin(_t) * 0.01, 0.19 - fmod(_t * 0.05, 0.06), 0.02, Color(0.8, 0.8, 0.8, 0.7), false)
	# город
	for i in 9:
		box(i * 0.115, 0.45 + fmod(i * 0.23, 0.1), i * 0.115 + 0.1, 0.62, Color(0.62, 0.6, 0.62).darkened(fmod(i * 0.13, 0.2)), false)
	# пол балкона и перила
	box(0, 0.62, 1, 1, Color(0.6, 0.58, 0.55), false)
	box(0, 0.55, 1, 0.58, Color(0.3, 0.3, 0.32))
	for i in 21:
		line(i * 0.05, 0.58, i * 0.05, 0.78, Color(0.3, 0.3, 0.32), 5)
	box(0, 0.78, 1, 0.8, Color(0.3, 0.3, 0.32))
	# окно балкона (рама слева)
	var open_k := 1.0 if flags.get("balcony_open", false) else 0.0
	box(0.02, 0.08, 0.26, 0.55, Color(0.95, 0.95, 0.93))
	if open_k > 0.0:
		box(0.04, 0.1, 0.24, 0.53, Color(0.55, 0.75, 0.95), false)
		poly([Vector2(0.24, 0.1), Vector2(0.34, 0.06), Vector2(0.34, 0.58), Vector2(0.24, 0.53)], Color(0.8, 0.9, 1.0, 0.6))
	else:
		box(0.04, 0.1, 0.24, 0.53, Color(0.75, 0.88, 1.0, 0.7), false)
		line(0.14, 0.1, 0.14, 0.53, Color(0.95, 0.95, 0.93), 6)
	# бельё
	line(0.32, 0.12, 0.98, 0.14, INK, 2)
	var sw := sin(_t * 2.0) * 0.01
	poly([Vector2(0.36, 0.12), Vector2(0.44, 0.122), Vector2(0.45 + sw, 0.26), Vector2(0.35 + sw, 0.26)], Color(1, 0.6, 0.2))
	poly([Vector2(0.5, 0.123), Vector2(0.56, 0.124), Vector2(0.565 + sw, 0.32), Vector2(0.495 + sw, 0.32)], Color(0.3, 0.4, 0.8))
	box(0.6, 0.125, 0.68, 0.2, Color(0.95, 0.95, 0.95))
	# хлам
	box(0.84, 0.64, 0.98, 0.78, Color(0.7, 0.55, 0.35))
	box(0.86, 0.58, 0.95, 0.64, Color(0.65, 0.5, 0.3))
	# голубь на перилах
	if not flags.get("pigeon_left", false):
		_pigeon(0.74, 0.5, 1.0)

func _pigeon(x: float, y: float, s: float, flap := false) -> void:
	var bob := sin(_t * 6.0) * 0.004
	var grey := Color(0.6, 0.63, 0.7)
	poly([Vector2(x - 0.045 * s, y + bob), Vector2(x + 0.03 * s, y - 0.03 * s + bob), Vector2(x + 0.05 * s, y + 0.02 * s + bob), Vector2(x - 0.01 * s, y + 0.045 * s + bob)], grey)
	circ(x + 0.035 * s, y - 0.045 * s + bob, 0.025 * s, Color(0.45, 0.5, 0.6))
	poly([Vector2(x + 0.055 * s, y - 0.05 * s + bob), Vector2(x + 0.075 * s, y - 0.043 * s + bob), Vector2(x + 0.055 * s, y - 0.038 * s + bob)], Color(0.95, 0.75, 0.35), false)
	circ(x + 0.04 * s, y - 0.05 * s + bob, 0.006 * s, Color(1.0, 0.5, 0.1), false)
	if flap:
		var a := sin(_t * 25.0) * 0.04 * s
		poly([Vector2(x - 0.01 * s, y), Vector2(x - 0.05 * s, y - 0.04 * s - a), Vector2(x + 0.01 * s, y - 0.01 * s)], grey.darkened(0.2))
	line(x - 0.005 * s, y + 0.04 * s + bob, x - 0.005 * s, y + 0.06 * s, Color(0.9, 0.4, 0.4), 3)
	line(x + 0.015 * s, y + 0.035 * s + bob, x + 0.015 * s, y + 0.06 * s, Color(0.9, 0.4, 0.4), 3)

func _person(x: float, y: float, s: float, body: Color, head_col: Color, hat: Color) -> void:
	poly([Vector2(x - 0.05 * s, y + 0.3 * s), Vector2(x - 0.045 * s, y + 0.05 * s), Vector2(x + 0.045 * s, y + 0.05 * s), Vector2(x + 0.05 * s, y + 0.3 * s)], body)
	circ(x, y, 0.045 * s, Color(0.95, 0.8, 0.65))
	poly([Vector2(x - 0.05 * s, y - 0.01 * s), Vector2(x - 0.03 * s, y - 0.06 * s), Vector2(x + 0.03 * s, y - 0.06 * s), Vector2(x + 0.05 * s, y - 0.01 * s)], hat)
	circ(x - 0.015 * s, y + 0.005 * s, 0.006 * s, INK, false)
	circ(x + 0.015 * s, y + 0.005 * s, 0.006 * s, INK, false)
	line(x - 0.02 * s, y + 0.03 * s, x + 0.02 * s, y + 0.03 * s, INK, 3)
	line(x - 0.03 * s, y + 0.3 * s, x - 0.03 * s, y + 0.42 * s, INK, 6)
	line(x + 0.03 * s, y + 0.3 * s, x + 0.03 * s, y + 0.42 * s, INK, 6)

func _entrance() -> void:
	box(0, 0, 1, 0.45, Color(0.88, 0.88, 0.84), false)
	box(0, 0.45, 1, 0.74, Color(0.35, 0.55, 0.45), false)
	line(0, 0.45, 1, 0.45, Color(0.2, 0.35, 0.28), 6)
	box(0, 0.74, 1, 1, Color(0.55, 0.5, 0.45), false)
	for i in 12:
		for j in 3:
			box(i * 0.09 + (0.045 if j % 2 == 1 else 0.0), 0.74 + j * 0.087, i * 0.09 + 0.09 + (0.045 if j % 2 == 1 else 0.0), 0.74 + (j + 1) * 0.087, Color(0.6, 0.55, 0.5).darkened(fmod(i * 0.07 + j * 0.11, 0.12)))
	# лестница
	for k in 6:
		box(0.0, 0.7 - k * 0.07, 0.18 - k * 0.02, 0.74 - k * 0.07, Color(0.5, 0.48, 0.45))
	line(0.18, 0.3, 0.05, 0.05, Color(0.4, 0.25, 0.15), 8)
	# надписи на стенах
	text(0.22, 0.2, "ЗИНА - ТОП", int(size.y * 0.035), Color(0.3, 0.3, 0.8, 0.6))
	# лифт
	box(0.4, 0.14, 0.56, 0.74, Color(0.55, 0.55, 0.58))
	line(0.48, 0.14, 0.48, 0.74, INK, 4)
	box(0.44, 0.08, 0.52, 0.12, Color(0.15, 0.15, 0.15))
	text(0.445, 0.115, "НЕ РАБ", int(size.y * 0.02), Color(1, 0.3, 0.2))
	# почтовые ящики
	box(0.6, 0.22, 0.76, 0.48, Color(0.3, 0.45, 0.65))
	for i in 3:
		for j in 3:
			box(0.61 + i * 0.05, 0.235 + j * 0.08, 0.65 + i * 0.05, 0.3 + j * 0.08, Color(0.35, 0.5, 0.7))
	if not flags.get("read_mail", false):
		poly([Vector2(0.66, 0.31), Vector2(0.69, 0.3), Vector2(0.695, 0.33), Vector2(0.665, 0.335)], Color.WHITE)
	# велосипед
	if not flags.get("has_bicycle", false):
		var bx := 0.86
		draw_arc(P(bx - 0.06, 0.7), size.y * 0.06, 0, TAU, 24, INK, 5)
		draw_arc(P(bx + 0.07, 0.7), size.y * 0.06, 0, TAU, 24, INK, 5)
		line(bx - 0.06, 0.7, bx, 0.62, Color(0.2, 0.6, 0.8), 6)
		line(bx, 0.62, bx + 0.07, 0.7, Color(0.2, 0.6, 0.8), 6)
		line(bx - 0.02, 0.7, bx, 0.62, Color(0.2, 0.6, 0.8), 6)
		line(bx, 0.62, bx + 0.05, 0.6, Color(0.2, 0.6, 0.8), 6)
		line(bx - 0.03, 0.6, bx + 0.0, 0.6, INK, 6)
		circ(bx - 0.06, 0.66, 0.012, Color(0.85, 0.8, 0.3))
	# Бабка Зина
	if not flags.get("zina_left", false):
		var zx := 0.27 + sin(_t * 0.5) * 0.005
		_person(zx, 0.38, 1.0, Color(0.45, 0.25, 0.5), Color.WHITE, Color(0.85, 0.15, 0.2))

func _yard() -> void:
	box(0, 0, 1, 0.55, Color(0.55, 0.75, 0.95), false)
	for i in 4:
		var hx := i * 0.27 - 0.02
		box(hx, 0.08 + fmod(i * 0.07, 0.1), hx + 0.24, 0.6, Color(0.72, 0.7, 0.66).darkened(i * 0.05))
		for fx in 4:
			for fy in 7:
				var lit := fmod(i * 7.3 + fx * 3.1 + fy * 1.7, 1.0) > 0.75
				box(hx + 0.02 + fx * 0.055, 0.13 + fmod(i * 0.07, 0.1) + fy * 0.06, hx + 0.05 + fx * 0.055, 0.16 + fmod(i * 0.07, 0.1) + fy * 0.06, Color(1, 0.85, 0.45) if lit else Color(0.3, 0.38, 0.48), false)
	box(0, 0.6, 1, 1, Color(0.35, 0.35, 0.37), false)
	box(0, 0.6, 0.38, 0.75, Color(0.35, 0.55, 0.3), false)
	# лавочка с дядей Толей
	box(0.12, 0.64, 0.34, 0.66, Color(0.6, 0.38, 0.2))
	box(0.12, 0.58, 0.34, 0.6, Color(0.6, 0.38, 0.2))
	line(0.14, 0.66, 0.14, 0.72, INK, 5)
	line(0.32, 0.66, 0.32, 0.72, INK, 5)
	if not flags.get("tolya_left", false):
		_person(0.23, 0.42, 0.8, Color(0.95, 0.95, 0.92), Color.WHITE, Color(0.3, 0.3, 0.32))
		var smoke_y := 0.44 - fmod(_t * 0.04, 0.08)
		circ(0.27 + sin(_t * 2.0) * 0.005, smoke_y, 0.008, Color(1, 1, 1, 0.5), false)
	# качели и песочница
	line(0.5, 0.42, 0.5, 0.66, INK, 5)
	line(0.62, 0.42, 0.62, 0.66, INK, 5)
	line(0.49, 0.42, 0.63, 0.42, INK, 5)
	var swing := sin(_t * 1.5) * 0.015
	line(0.54, 0.42, 0.54 + swing, 0.58, INK, 2)
	line(0.58, 0.42, 0.58 + swing, 0.58, INK, 2)
	box(0.53 + swing, 0.58, 0.59 + swing, 0.6, Color(0.8, 0.3, 0.3))
	# стая голубей
	for k in 4:
		_pigeon(0.4 + k * 0.05, 0.86 + fmod(k * 0.37, 0.04), 0.7, false)
	# микроавтобус
	if not flags.get("van_left", false):
		box(0.68, 0.48, 0.98, 0.7, Color(0.95, 0.95, 0.95))
		box(0.7, 0.52, 0.76, 0.58, Color(0.15, 0.15, 0.2))
		box(0.78, 0.52, 0.96, 0.58, Color(0.15, 0.15, 0.2))
		circ(0.74, 0.7, 0.035, INK)
		circ(0.92, 0.7, 0.035, INK)
		text(0.8, 0.66, "БУС", int(size.y * 0.035), Color(0.4, 0.45, 0.35))

func _jump() -> void:
	# Кат-сцена: фасад, окно второго этажа, сальто и приземление на дорогу.
	box(0, 0, 1, 1, Color(0.55, 0.75, 0.95), false)
	box(0.05, 0.0, 0.55, 0.78, Color(0.75, 0.72, 0.68))
	for fx in 4:
		for fy in 4:
			box(0.09 + fx * 0.12, 0.05 + fy * 0.18, 0.17 + fx * 0.12, 0.15 + fy * 0.18, Color(0.3, 0.38, 0.48))
	box(0.33, 0.41, 0.41, 0.51, Color(0.95, 0.95, 0.95))
	box(0, 0.78, 1, 1, Color(0.3, 0.3, 0.32), false)
	for i in 8:
		box(i * 0.14, 0.885, i * 0.14 + 0.07, 0.9, Color(0.95, 0.9, 0.4), false)
	# траектория
	var k := clampf(cut_t, 0.0, 1.0)
	var start := Vector2(0.37, 0.46)
	var land := Vector2(0.72, 0.72)
	var pos := start.lerp(land, k)
	pos.y -= sin(k * PI) * 0.3
	if k >= 1.0:
		pos.x += (cut_t - 1.0) * 0.6
	var ang := k * TAU * 3.0
	var c := P(pos.x, pos.y)
	var s := size.y * 0.06
	draw_set_transform(c, ang, Vector2.ONE)
	draw_rect(Rect2(Vector2(-s * 0.5, -s * 0.6), Vector2(s, s * 1.2)), Color(1.0, 0.5, 0.12))
	draw_circle(Vector2(0, -s * 1.0), s * 0.45, Color(0.97, 0.8, 0.66))
	draw_colored_polygon(PackedVector2Array([Vector2(-s * 0.45, -s * 1.1), Vector2(-s * 0.35, -s * 1.7), Vector2(-s * 0.05, -s * 1.35)]), Color(0.16, 0.16, 0.2))
	draw_colored_polygon(PackedVector2Array([Vector2(s * 0.45, -s * 1.1), Vector2(s * 0.35, -s * 1.7), Vector2(s * 0.05, -s * 1.35)]), Color(0.16, 0.16, 0.2))
	var leg := sin(_t * 30.0) * s * 0.5
	draw_line(Vector2(-s * 0.2, s * 0.6), Vector2(-s * 0.2 + leg, s * 1.3), Color(0.2, 0.25, 0.4), 8)
	draw_line(Vector2(s * 0.2, s * 0.6), Vector2(s * 0.2 - leg, s * 1.3), Color(0.2, 0.25, 0.4), 8)
	draw_line(Vector2(-s * 0.5, -s * 0.4), Vector2(-s * 1.1, -s * 0.9), Color(1.0, 0.5, 0.12), 8)
	draw_line(Vector2(s * 0.5, -s * 0.4), Vector2(s * 1.1, -s * 0.9), Color(1.0, 0.5, 0.12), 8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if flags.get("pigeon_friend", false):
		_pigeon(pos.x + 0.08, pos.y - 0.12, 0.9, true)
