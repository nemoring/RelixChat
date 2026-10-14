class_name UIStyle
extends RefCounted
## Единый стиль интерфейса: крупные сенсорные кнопки, тёмные панели, оранжевый акцент.

const ACCENT := Color(1.0, 0.55, 0.12)
const ACCENT_DARK := Color(0.75, 0.33, 0.05)
const BG := Color(0.07, 0.07, 0.09, 0.92)
const TEXT := Color(0.96, 0.95, 0.92)
const MUTED := Color(0.65, 0.65, 0.7)
const GOOD := Color(0.4, 0.9, 0.45)
const BAD := Color(1.0, 0.35, 0.3)

const FONT_BODY_PATH := "res://assets/fonts/Rubik.ttf"
const FONT_TITLE_PATH := "res://assets/fonts/RussoOne-Regular.ttf"

static var _body: Font
static var _bold: Font
static var _title: Font

static func body_font() -> Font:
	if _body == null:
		var base: FontFile = load(FONT_BODY_PATH)
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
		_body = fv
	return _body

static func bold_font() -> Font:
	if _bold == null:
		var base: FontFile = load(FONT_BODY_PATH)
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		_bold = fv
	return _bold

static func title_font() -> Font:
	if _title == null:
		_title = load(FONT_TITLE_PATH)
	return _title

static func panel_style(color: Color = BG, radius := 18, border: Color = Color(0, 0, 0, 0), border_w := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func button_style(color: Color, border: Color, radius := 16) -> StyleBoxFlat:
	var sb := panel_style(color, radius, border, 3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 26
	# Кнопки — крупные, под палец.
	t.set_stylebox("normal", "Button", button_style(Color(0.13, 0.13, 0.16, 0.95), Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "Button", button_style(Color(0.2, 0.17, 0.14, 0.97), ACCENT))
	t.set_stylebox("pressed", "Button", button_style(ACCENT_DARK, ACCENT))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", button_style(Color(0.1, 0.1, 0.1, 0.6), Color(1, 1, 1, 0.05)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", 28)
	t.set_constant("h_separation", "Button", 10)
	# Панели
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	# Метки
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 0)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font_size("normal_font_size", "RichTextLabel", 28)
	t.set_font_size("bold_font_size", "RichTextLabel", 28)
	# Слайдеры с крупным захватом
	var grab := _circle_texture(44, ACCENT)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(1, 1, 1, 0.15)
	slider_bg.set_corner_radius_all(8)
	slider_bg.content_margin_top = 8
	slider_bg.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := slider_bg.duplicate()
	slider_fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	# Переключатели
	t.set_font_size("font_size", "CheckButton", 26)
	t.set_icon("checked", "CheckButton", _toggle_texture(true))
	t.set_icon("unchecked", "CheckButton", _toggle_texture(false))
	t.set_stylebox("normal", "CheckButton", panel_style(Color(0.13, 0.13, 0.16, 0.9), 14))
	t.set_stylebox("hover", "CheckButton", panel_style(Color(0.18, 0.16, 0.14, 0.95), 14))
	t.set_stylebox("pressed", "CheckButton", panel_style(Color(0.18, 0.16, 0.14, 0.95), 14))
	t.set_stylebox("hover_pressed", "CheckButton", panel_style(Color(0.18, 0.16, 0.14, 0.95), 14))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	# Полосы прокрутки — толстые, чтобы их можно было тянуть пальцем.
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(1, 1, 1, 0.06)
	sc.set_corner_radius_all(8)
	sc.content_margin_left = 10
	sc.content_margin_right = 10
	t.set_stylebox("scroll", "VScrollBar", sc)
	var gr := StyleBoxFlat.new()
	gr.bg_color = Color(1, 1, 1, 0.35)
	gr.set_corner_radius_all(8)
	gr.content_margin_left = 10
	gr.content_margin_right = 10
	t.set_stylebox("grabber", "VScrollBar", gr)
	t.set_stylebox("grabber_highlight", "VScrollBar", gr)
	t.set_stylebox("grabber_pressed", "VScrollBar", gr)
	# Прогресс-бары
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0, 0, 0, 0.55)
	pb_bg.set_corner_radius_all(8)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = ACCENT
	pb_fill.set_corner_radius_all(8)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_font_size("font_size", "ProgressBar", 16)
	return t

static func _circle_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(size * 0.5 - d, 0.0, 1.0)
			var col := color if d < size * 0.36 else Color.WHITE
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

static func _toggle_texture(on: bool) -> ImageTexture:
	var w := 76
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := ACCENT if on else Color(0.35, 0.35, 0.4)
	var r := h * 0.5
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(px.x, r, w - r)
			var d := px.distance_to(Vector2(cx, r))
			var a := clampf(r - d, 0.0, 1.0)
			var col := bg
			var knob_c := Vector2(w - r if on else r, r)
			if px.distance_to(knob_c) < r - 4:
				col = Color.WHITE
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Быстрое создание крупной кнопки.
static func make_button(text: String, min_size := Vector2(300, 84), font_size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func make_label(text: String, size := 26, color: Color = TEXT, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font())
	return l

static func outline(l: Control, size := 6) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", size)
