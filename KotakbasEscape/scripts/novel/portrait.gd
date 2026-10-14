class_name Portrait
extends Control
## Анимированный 2D-портрет персонажа, нарисованный в коде. Эмоции, моргание,
## движение рта при разговоре, покачивание, тряска при сильных эмоциях.

const SPEAKERS := {
	"kot": {"name": "Котакбас", "color": Color(1.0, 0.55, 0.12)},
	"zina": {"name": "Бабка Зина", "color": Color(0.85, 0.3, 0.45)},
	"tolya": {"name": "Дядя Толя", "color": Color(0.5, 0.7, 0.95)},
	"tck": {"name": "Человек в форме", "color": Color(0.55, 0.65, 0.45)},
	"seryoga": {"name": "Серёга (телефон)", "color": Color(0.4, 0.85, 0.6)},
	"pigeon": {"name": "Голубь", "color": Color(0.7, 0.75, 0.85)},
	"tv": {"name": "Телевизор", "color": Color(0.8, 0.8, 0.8)},
	"radio": {"name": "Радио", "color": Color(0.9, 0.4, 0.4)},
	"mikhalych": {"name": "Дед Михалыч", "color": Color(0.8, 0.7, 0.5)},
	"gena": {"name": "Лесник Гена", "color": Color(0.45, 0.75, 0.35)},
	"interpol": {"name": "Агент Интерпола", "color": Color(0.6, 0.6, 0.9)},
	"interpol2": {"name": "Стажёр Интерпола", "color": Color(0.9, 0.6, 0.9)},
	"narrator": {"name": "", "color": Color(0.9, 0.9, 0.9)},
}

var speaker := "kot"
var emotion := "normal"
var talking := false
var _t := 0.0
var _blink := 0.0
var _next_blink := 3.0
var _shake := 0.0
var _mouth := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_character(id: String, emo: String) -> void:
	var changed := id != speaker or emo != emotion
	speaker = id
	emotion = emo
	if changed and emo in ["angry", "scared", "surprised", "shock"]:
		_shake = 0.35
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.12
		_next_blink = randf_range(2.5, 5.0)
	_blink = maxf(0.0, _blink - delta)
	_shake = maxf(0.0, _shake - delta)
	_mouth = (absf(sin(_t * 16.0)) if talking else 0.0)
	queue_redraw()

func _draw() -> void:
	if speaker == "narrator":
		return
	var w := size.x
	var h := size.y
	var bob := sin(_t * 2.2) * 4.0
	var off := Vector2(randf_range(-6, 6), randf_range(-4, 4)) * (_shake / 0.35) if _shake > 0.0 else Vector2.ZERO
	var c := Vector2(w * 0.5, h * 0.42 + bob) + off
	var r := minf(w, h) * 0.28
	match speaker:
		"pigeon":
			_draw_pigeon(c, r)
		"tv":
			_draw_tv(c, r)
		"radio":
			_draw_radio(c, r)
		_:
			_draw_human(c, r)

func _ol(points: PackedVector2Array, fill: Color, width := 4.0) -> void:
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color(0.08, 0.06, 0.05), width, true)

func _circle(c: Vector2, r: float, fill: Color, outline := true) -> void:
	draw_circle(c, r, fill)
	if outline:
		draw_arc(c, r, 0, TAU, 32, Color(0.08, 0.06, 0.05), 4.0, true)

func _ellipse(c: Vector2, rx: float, ry: float, fill: Color, outline := true) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if outline:
		_ol(pts, fill, 3.0)
	else:
		draw_colored_polygon(pts, fill)
	return pts

func _body_color() -> Color:
	match speaker:
		"kot": return Color(1.0, 0.5, 0.12)
		"zina": return Color(0.45, 0.25, 0.5)
		"tolya": return Color(0.95, 0.95, 0.92)
		"tck": return Color(0.38, 0.45, 0.32)
		"seryoga": return Color(0.15, 0.2, 0.55)
		"mikhalych": return Color(0.35, 0.3, 0.25)
		"gena": return Color(0.3, 0.45, 0.25)
		"interpol", "interpol2": return Color(0.15, 0.15, 0.2)
	return Color(0.5, 0.5, 0.5)

func _draw_human(c: Vector2, r: float) -> void:
	var skin := Color(0.97, 0.8, 0.66)
	if speaker == "mikhalych":
		skin = Color(0.92, 0.74, 0.6)
	# Плечи / тело
	var bc := _body_color()
	var sh := PackedVector2Array([
		c + Vector2(-r * 1.6, r * 2.6), c + Vector2(-r * 1.45, r * 1.3), c + Vector2(-r * 0.6, r * 0.95),
		c + Vector2(r * 0.6, r * 0.95), c + Vector2(r * 1.45, r * 1.3), c + Vector2(r * 1.6, r * 2.6)])
	_ol(sh, bc)
	if speaker == "seryoga":
		for sx in [-1.0, 1.0]:
			for k in 3:
				var x: float = c.x + sx * r * (0.9 + k * 0.14)
				draw_line(Vector2(x, c.y + r * 1.2), Vector2(x + sx * r * 0.2, c.y + r * 2.6), Color.WHITE, 5.0)
	if speaker == "tck":
		draw_rect(Rect2(c + Vector2(r * 0.55, r * 1.45), Vector2(r * 0.45, r * 0.3)), Color(0.9, 0.8, 0.2))
	if speaker == "kot":
		draw_line(c + Vector2(-r * 0.25, r * 1.0), c + Vector2(-r * 0.3, r * 1.8), Color.WHITE, 4.0)
		draw_line(c + Vector2(r * 0.25, r * 1.0), c + Vector2(r * 0.3, r * 1.8), Color.WHITE, 4.0)
	if speaker in ["interpol", "interpol2"]:
		_ol(PackedVector2Array([c + Vector2(-r * 0.25, r * 0.95), c + Vector2(0, r * 1.7), c + Vector2(r * 0.25, r * 0.95)]), Color.WHITE)
		_ol(PackedVector2Array([c + Vector2(-r * 0.08, r * 1.0), c + Vector2(0, r * 1.6), c + Vector2(r * 0.08, r * 1.0)]), Color(0.7, 0.1, 0.1), 2.0)
	# Шея и голова
	draw_rect(Rect2(c + Vector2(-r * 0.25, r * 0.6), Vector2(r * 0.5, r * 0.45)), skin)
	_ellipse(c, r * 0.95, r * 1.05, skin)
	# Причёски, головные уборы
	match speaker:
		"kot":
			var cap := Color(0.16, 0.16, 0.2)
			_ol(PackedVector2Array([c + Vector2(-r * 0.98, -r * 0.15), c + Vector2(-r * 0.85, -r * 0.75), c + Vector2(-r * 0.4, -r * 1.05), c + Vector2(r * 0.4, -r * 1.05), c + Vector2(r * 0.85, -r * 0.75), c + Vector2(r * 0.98, -r * 0.15)]), cap)
			_ol(PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.6), c + Vector2(-r * 0.8, -r * 1.55), c + Vector2(-r * 0.3, -r * 1.0)]), cap)
			_ol(PackedVector2Array([c + Vector2(r * 0.9, -r * 0.6), c + Vector2(r * 0.8, -r * 1.55), c + Vector2(r * 0.3, -r * 1.0)]), cap)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.78, -r * 0.75), c + Vector2(-r * 0.74, -r * 1.3), c + Vector2(-r * 0.45, -r * 0.98)]), Color(1, 0.6, 0.7))
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.78, -r * 0.75), c + Vector2(r * 0.74, -r * 1.3), c + Vector2(r * 0.45, -r * 0.98)]), Color(1, 0.6, 0.7))
		"zina":
			var scarf := Color(0.85, 0.15, 0.2)
			_ol(PackedVector2Array([c + Vector2(-r * 1.15, r * 0.6), c + Vector2(-r * 1.1, -r * 0.6), c + Vector2(-r * 0.5, -r * 1.2), c + Vector2(r * 0.5, -r * 1.2), c + Vector2(r * 1.1, -r * 0.6), c + Vector2(r * 1.15, r * 0.6), c + Vector2(r * 0.85, r * 0.2), c + Vector2(r * 0.8, -r * 0.45), c + Vector2(-r * 0.8, -r * 0.45), c + Vector2(-r * 0.85, r * 0.2)]), scarf)
			for d in [Vector2(-0.6, -0.8), Vector2(0.1, -1.0), Vector2(0.65, -0.7), Vector2(-0.95, 0.1), Vector2(0.95, 0.15)]:
				draw_circle(c + d * r, r * 0.08, Color.WHITE)
		"tolya":
			_ol(PackedVector2Array([c + Vector2(-r * 1.0, -r * 0.45), c + Vector2(-r * 0.8, -r * 1.05), c + Vector2(r * 0.8, -r * 1.05), c + Vector2(r * 1.25, -r * 0.5)]), Color(0.3, 0.3, 0.32))
		"tck":
			_ol(PackedVector2Array([c + Vector2(-r * 1.05, -r * 0.5), c + Vector2(-r * 0.9, -r * 1.2), c + Vector2(r * 0.9, -r * 1.2), c + Vector2(r * 1.05, -r * 0.5)]), Color(0.32, 0.4, 0.28))
			_ol(PackedVector2Array([c + Vector2(-r * 1.2, -r * 0.45), c + Vector2(r * 1.2, -r * 0.45), c + Vector2(r * 0.9, -r * 0.3), c + Vector2(-r * 0.9, -r * 0.3)]), Color(0.15, 0.15, 0.15))
			draw_circle(c + Vector2(0, -r * 0.85), r * 0.12, Color(0.95, 0.8, 0.2))
		"seryoga":
			_ellipse(c + Vector2(0, -r * 0.55), r * 0.9, r * 0.5, Color(0.6, 0.45, 0.35, 0.5), false)
		"mikhalych":
			_ol(PackedVector2Array([c + Vector2(-r * 1.0, -r * 0.4), c + Vector2(-r * 0.95, -r * 1.1), c + Vector2(r * 0.95, -r * 1.1), c + Vector2(r * 1.0, -r * 0.4)]), Color(0.4, 0.3, 0.25))
			_ol(PackedVector2Array([c + Vector2(-r * 1.25, -r * 0.7), c + Vector2(-r * 0.95, -r * 0.2), c + Vector2(-r * 0.95, -r * 1.0)]), Color(0.4, 0.3, 0.25))
			_ol(PackedVector2Array([c + Vector2(r * 1.25, -r * 0.7), c + Vector2(r * 0.95, -r * 0.2), c + Vector2(r * 0.95, -r * 1.0)]), Color(0.4, 0.3, 0.25))
			_ellipse(c + Vector2(0, r * 0.75), r * 0.7, r * 0.55, Color(0.92, 0.92, 0.9))
		"gena":
			_ol(PackedVector2Array([c + Vector2(-r * 1.3, -r * 0.55), c + Vector2(-r * 0.7, -r * 1.3), c + Vector2(r * 0.7, -r * 1.3), c + Vector2(r * 1.3, -r * 0.55)]), Color(0.35, 0.5, 0.25))
			_ellipse(c + Vector2(0, r * 0.7), r * 0.75, r * 0.45, Color(0.55, 0.35, 0.2))
		"interpol", "interpol2":
			_ol(PackedVector2Array([c + Vector2(-r * 0.95, -r * 0.3), c + Vector2(-r * 0.7, -r * 1.05), c + Vector2(r * 0.7, -r * 1.05), c + Vector2(r * 0.95, -r * 0.3), c + Vector2(r * 0.6, -r * 0.7), c + Vector2(-r * 0.6, -r * 0.7)]), Color(0.2, 0.15, 0.1) if speaker == "interpol" else Color(0.9, 0.75, 0.3))
	_draw_face(c, r)

func _draw_face(c: Vector2, r: float) -> void:
	var ink := Color(0.08, 0.06, 0.05)
	var eye_y := c.y - r * 0.05
	var eye_dx := r * 0.38
	var blink := _blink > 0.0
	var eye_open := 1.0
	match emotion:
		"surprised", "scared", "shock":
			eye_open = 1.35
		"suspicious", "smug", "tired":
			eye_open = 0.45
		"happy":
			eye_open = 0.8
	var sunglasses := speaker == "tck" and emotion != "surprised"
	for sx in [-1.0, 1.0]:
		var ec := Vector2(c.x + sx * eye_dx, eye_y)
		if sunglasses:
			_ol(PackedVector2Array([ec + Vector2(-r * 0.28, -r * 0.14), ec + Vector2(r * 0.28, -r * 0.14), ec + Vector2(r * 0.22, r * 0.16), ec + Vector2(-r * 0.22, r * 0.16)]), Color(0.05, 0.05, 0.08))
			draw_line(ec + Vector2(-r * 0.12, -r * 0.08), ec + Vector2(-r * 0.02, -r * 0.08), Color(1, 1, 1, 0.6), 3.0)
			continue
		if blink or emotion == "happy":
			draw_arc(ec, r * 0.14, PI * 1.1 if emotion == "happy" else 0.1, PI * 1.9 if emotion == "happy" else PI - 0.1, 10, ink, 5.0)
		else:
			_ellipse(ec, r * 0.17, r * 0.2 * eye_open, Color.WHITE)
			var pupil_off := Vector2(sin(_t * 0.7) * r * 0.04, 0)
			if emotion == "suspicious":
				pupil_off.x = sx * -r * 0.06 + r * 0.05
			draw_circle(ec + pupil_off, r * (0.11 if emotion != "scared" else 0.06), ink)
			draw_circle(ec + pupil_off + Vector2(-r * 0.03, -r * 0.04), r * 0.03, Color.WHITE)
		if speaker == "zina":
			draw_arc(ec, r * 0.24, 0, TAU, 16, Color(0.3, 0.3, 0.3), 3.0)
		# Брови
		var brow_y := eye_y - r * 0.32
		var tilt := 0.0
		match emotion:
			"angry": tilt = 0.12
			"sad", "scared": tilt = -0.12
			"surprised", "shock": brow_y -= r * 0.1
			"suspicious": tilt = 0.06 * sx
		var inner := Vector2(ec.x - sx * r * 0.18, brow_y + tilt * r)
		var outer := Vector2(ec.x + sx * r * 0.18, brow_y - tilt * r)
		draw_line(inner, outer, ink, 5.0)
	if speaker == "tolya" or speaker == "mikhalych":
		_ol(PackedVector2Array([c + Vector2(-r * 0.45, r * 0.3), c + Vector2(0, r * 0.22), c + Vector2(r * 0.45, r * 0.3), c + Vector2(r * 0.35, r * 0.42), c + Vector2(-r * 0.35, r * 0.42)]), Color(0.3, 0.2, 0.12) if speaker == "tolya" else Color(0.9, 0.9, 0.88), 2.0)
	# Нос
	draw_line(c + Vector2(0, r * 0.05), c + Vector2(-r * 0.06, r * 0.25), ink, 3.0)
	# Рот
	var my := c.y + r * 0.5
	var mouth_open := _mouth * r * 0.14
	match emotion:
		"happy", "smug":
			draw_arc(Vector2(c.x, my - r * 0.12), r * 0.28, 0.3, PI - 0.3, 12, ink, 5.0)
			if mouth_open > 2.0:
				_ellipse(Vector2(c.x, my + r * 0.02), r * 0.14, mouth_open * 0.6 + 2.0, Color(0.5, 0.1, 0.1))
		"sad", "angry", "tired":
			draw_arc(Vector2(c.x, my + r * 0.12), r * 0.25, PI + 0.4, TAU - 0.4, 12, ink, 5.0)
			if mouth_open > 2.0:
				_ellipse(Vector2(c.x, my + r * 0.02), r * 0.12, mouth_open * 0.6 + 2.0, Color(0.5, 0.1, 0.1))
		"surprised", "scared", "shock":
			_ellipse(Vector2(c.x, my), r * 0.13, r * 0.16 + mouth_open * 0.3, Color(0.45, 0.08, 0.08))
		_:
			if mouth_open > 2.0:
				_ellipse(Vector2(c.x, my), r * 0.18, mouth_open * 0.7 + 2.0, Color(0.5, 0.1, 0.1))
			else:
				draw_line(Vector2(c.x - r * 0.2, my), Vector2(c.x + r * 0.2, my), ink, 5.0)
	if speaker == "tolya":
		draw_line(Vector2(c.x + r * 0.2, my), Vector2(c.x + r * 0.6, my + r * 0.08), Color.WHITE, 6.0)
		draw_circle(Vector2(c.x + r * 0.62, my + r * 0.08), r * 0.04, Color(1, 0.4, 0.1))
	if emotion in ["scared", "shock"]:
		draw_circle(c + Vector2(r * 0.85, -r * 0.6), r * 0.08, Color(0.5, 0.8, 1.0))

func _draw_pigeon(c: Vector2, r: float) -> void:
	var grey := Color(0.6, 0.63, 0.7)
	_ellipse(c + Vector2(0, r * 1.5), r * 1.3, r * 1.0, grey)
	_ellipse(c + Vector2(0, r * 0.75), r * 0.7, r * 0.55, Color(0.45, 0.6, 0.55))
	_ellipse(c, r * 0.8, r * 0.75, Color(0.45, 0.5, 0.6))
	var eye := c + Vector2(r * 0.3, -r * 0.1)
	_circle(eye, r * 0.17, Color(1.0, 0.55, 0.1))
	draw_circle(eye, r * 0.07 if _blink <= 0.0 else r * 0.02, Color.BLACK)
	var beak_open := _mouth * r * 0.15
	_ol(PackedVector2Array([c + Vector2(r * 0.7, -r * 0.05), c + Vector2(r * 1.25, r * 0.1), c + Vector2(r * 0.7, r * 0.15)]), Color(0.95, 0.75, 0.35))
	if beak_open > 1.0:
		_ol(PackedVector2Array([c + Vector2(r * 0.7, r * 0.18), c + Vector2(r * 1.15, r * 0.2 + beak_open), c + Vector2(r * 0.7, r * 0.26)]), Color(0.95, 0.75, 0.35))
	draw_circle(c + Vector2(r * 0.72, -r * 0.05), r * 0.08, Color(0.95, 0.95, 0.9))

func _draw_tv(c: Vector2, r: float) -> void:
	_ol(PackedVector2Array([c + Vector2(-r * 1.6, -r * 1.1), c + Vector2(r * 1.6, -r * 1.1), c + Vector2(r * 1.6, r * 1.3), c + Vector2(-r * 1.6, r * 1.3)]), Color(0.2, 0.18, 0.16))
	draw_rect(Rect2(c + Vector2(-r * 1.4, -r * 0.95), Vector2(r * 2.4, r * 2.05)), Color(0.3, 0.45, 0.6))
	for i in 12:
		var y := c.y - r * 0.95 + fmod(_t * 60.0 + i * 17.0, r * 2.05)
		draw_line(Vector2(c.x - r * 1.4, y), Vector2(c.x + r * 1.0, y), Color(1, 1, 1, 0.06), 2.0)
	# Диктор
	var dc := c + Vector2(-r * 0.2, -r * 0.05)
	_ellipse(dc + Vector2(0, r * 0.95), r * 0.8, r * 0.4, Color(0.2, 0.2, 0.3))
	_ellipse(dc, r * 0.45, r * 0.5, Color(0.95, 0.8, 0.7))
	draw_circle(dc + Vector2(-r * 0.15, -r * 0.05), r * 0.06, Color.BLACK)
	draw_circle(dc + Vector2(r * 0.15, -r * 0.05), r * 0.06, Color.BLACK)
	draw_line(dc + Vector2(-r * 0.12, r * 0.25), dc + Vector2(r * 0.12, r * 0.25 + _mouth * 6.0), Color.BLACK, 4.0)
	draw_circle(c + Vector2(r * 1.3, -r * 0.5), r * 0.1, Color(0.6, 0.6, 0.6))
	draw_circle(c + Vector2(r * 1.3, -r * 0.1), r * 0.1, Color(0.6, 0.6, 0.6))

func _draw_radio(c: Vector2, r: float) -> void:
	_ol(PackedVector2Array([c + Vector2(-r * 1.5, -r * 0.8), c + Vector2(r * 1.5, -r * 0.8), c + Vector2(r * 1.5, r * 1.2), c + Vector2(-r * 1.5, r * 1.2)]), Color(0.35, 0.3, 0.25))
	for i in 6:
		draw_line(c + Vector2(-r * 1.3, -r * 0.5 + i * r * 0.25), c + Vector2(-r * 0.1, -r * 0.5 + i * r * 0.25), Color(0.15, 0.12, 0.1), 5.0)
	_circle(c + Vector2(r * 0.75, r * 0.1), r * 0.45 + _mouth * 6.0, Color(0.6, 0.55, 0.45))
	draw_line(c + Vector2(r * 1.2, -r * 0.8), c + Vector2(r * 1.8, -r * 1.8), Color(0.7, 0.7, 0.7), 5.0)
