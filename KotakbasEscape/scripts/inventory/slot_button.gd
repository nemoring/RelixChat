class_name SlotButton
extends Button
## Ячейка инвентаря: иконка, количество, перетаскивание пальцем (drag & drop).

signal slot_tapped(inv: Inventory, index: int)
signal slot_dropped

var inv: Inventory
var index := 0
var selected := false
var hotbar := false

func _init() -> void:
	custom_minimum_size = Vector2(86, 86)
	focus_mode = Control.FOCUS_NONE
	toggle_mode = false
	pressed.connect(func(): slot_tapped.emit(inv, index))

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := Color(0.12, 0.12, 0.15, 0.95) if not hotbar else Color(0.16, 0.14, 0.12, 0.95)
	draw_rect(r, bg)
	draw_rect(r, UIStyle.ACCENT if selected else Color(1, 1, 1, 0.18), false, 4.0 if selected else 2.0)
	var s = inv.slots[index] if inv and index < inv.slots.size() else null
	if s != null:
		var tex := ItemDB.icon(s.id)
		if tex:
			draw_texture_rect(tex, r.grow(-8), false)
		if int(s.n) > 1:
			var font := UIStyle.bold_font()
			var t := str(s.n)
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string_outline(font, Vector2(size.x - tw - 6, size.y - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
			draw_string(font, Vector2(size.x - tw - 6, size.y - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		if ItemDB.is_key(s.id):
			draw_circle(Vector2(12, 12), 6, Color(1, 0.85, 0.2))

func _get_drag_data(_pos: Vector2) -> Variant:
	if inv == null or inv.slots[index] == null:
		return null
	var prev := TextureRect.new()
	prev.texture = ItemDB.icon(inv.slots[index].id)
	prev.custom_minimum_size = Vector2(80, 80)
	prev.size = Vector2(80, 80)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.modulate.a = 0.85
	var c := Control.new()
	c.add_child(prev)
	prev.position = -Vector2(40, 40)
	set_drag_preview(c)
	return {"inv": inv, "index": index}

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("inv")

func _drop_data(_pos: Vector2, data: Variant) -> void:
	var from: Inventory = data.inv
	from.move_to(int(data.index), inv, index)
	AudioManager.play_sfx("click", -6.0)
	slot_dropped.emit()
