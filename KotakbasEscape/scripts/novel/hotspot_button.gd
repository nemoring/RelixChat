class_name HotspotButton
extends Button
## Интерактивная точка в 2D-сцене: пульсирующий круг + подпись. Крупная зона касания.

var _t := randf() * 3.0
var caption := ""

func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(150, 150)
	size = Vector2(150, 150)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, empty)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5 - Vector2(0, 14)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(c, 26.0 + pulse * 6.0, Color(1.0, 0.6, 0.15, 0.18 + 0.12 * pulse))
	draw_arc(c, 26.0 + pulse * 6.0, 0, TAU, 32, Color(1.0, 0.75, 0.3, 0.9), 3.0, true)
	draw_circle(c, 7.0, Color(1, 1, 1, 0.95))
	var font := UIStyle.bold_font()
	var fs := 22
	var tw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(size.x * 0.5 - tw * 0.5, size.y - 18)
	var bg := Rect2(pos - Vector2(10, fs), Vector2(tw + 20, fs + 12))
	draw_rect(bg, Color(0, 0, 0, 0.65))
	draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _get_minimum_size() -> Vector2:
	return Vector2(150, 150)
