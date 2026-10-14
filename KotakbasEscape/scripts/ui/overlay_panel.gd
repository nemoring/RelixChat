class_name OverlayPanel
extends Control
## Базовая модальная панель на весь экран: затемнение + центральное окно + заголовок + «Назад».

signal closed

var window: PanelContainer
var content: VBoxContainer
var title_label: Label

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(title: String, size_ratio := Vector2(0.86, 0.9)) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	window = PanelContainer.new()
	window.anchor_left = (1.0 - size_ratio.x) * 0.5
	window.anchor_right = 1.0 - window.anchor_left
	window.anchor_top = (1.0 - size_ratio.y) * 0.5
	window.anchor_bottom = 1.0 - window.anchor_top
	window.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.08, 0.08, 0.1, 0.97), 24, Color(1, 0.55, 0.12, 0.6)))
	add_child(window)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	window.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	title_label = UIStyle.make_label(title, 38, UIStyle.ACCENT, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var back := UIStyle.make_button("Назад", Vector2(180, 72))
	back.pressed.connect(close)
	header.add_child(back)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	outer.add_child(content)
	GameManager.back_requested.connect(_on_back)

func _on_back() -> void:
	if is_visible_in_tree() and _is_topmost():
		close()

func _is_topmost() -> bool:
	var p := get_parent()
	if p == null:
		return false
	for i in range(p.get_child_count() - 1, -1, -1):
		var c := p.get_child(i)
		if c is OverlayPanel and c.visible:
			return c == self
	return true

func close() -> void:
	AudioManager.play_sfx("click")
	closed.emit()
	queue_free()

## Скроллируемая область для длинных списков (тянется пальцем).
static func make_scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 12
	return sc
