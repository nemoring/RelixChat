class_name UIKit
extends RefCounted
## Общий стиль интерфейса: тёмный, «служебный», без лишнего.

const BG := Color(0.03, 0.035, 0.04, 0.94)
const PANEL := Color(0.07, 0.08, 0.09, 0.96)
const ACCENT := Color(0.55, 0.78, 0.95)
const TEXT := Color(0.86, 0.87, 0.84)
const DIM := Color(0.55, 0.57, 0.55)
const DANGER := Color(0.9, 0.3, 0.25)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.14)
	sb.border_color = Color(0.3, 0.32, 0.33)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.2, 0.22, 0.24)
	sbh.border_color = ACCENT
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(0.25, 0.3, 0.35)
	for s in ["normal", "focus"]:
		t.set_stylebox(s, "Button", sb if s == "normal" else sbh)
	t.set_stylebox("hover", "Button", sbh)
	t.set_stylebox("pressed", "Button", sbp)
	t.set_stylebox("disabled", "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_color", "Label", TEXT)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = Color(0.22, 0.24, 0.25)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var le := sb.duplicate() as StyleBoxFlat
	le.bg_color = Color(0.02, 0.03, 0.03)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", sbh)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	_theme = t
	return t


static func label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, min_h := 44) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.pressed.connect(func():
		Sfx.play_ui("click", -12.0)
		cb.call())
	return b


static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


static func color_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	full_rect(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
