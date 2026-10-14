class_name BuildMenu
extends OverlayPanel
## Выбор постройки: иконка, стоимость с учётом сложности, описание. Режим разбора.

signal piece_chosen(id: String)

var game

func _ready() -> void:
	setup("Строительство", Vector2(0.94, 0.92))
	var sc := OverlayPanel.make_scroll()
	content.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	for id in BuildDB.ORDER:
		grid.add_child(_card(id))
	grid.add_child(_card("demolish"))

func _card(id: String) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(340, 130)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -10
	b.add_child(hb)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/textures/icons/build_%s.png" % id)
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	if id == "demolish":
		vb.add_child(_lbl("Разобрать", 24, Color.WHITE))
		vb.add_child(_lbl("Вернёт половину ресурсов", 17, UIStyle.MUTED))
		b.pressed.connect(func():
			AudioManager.play_sfx("click")
			piece_chosen.emit("demolish")
			close())
		return b
	var piece: Dictionary = BuildDB.PIECES[id]
	vb.add_child(_lbl(piece.name, 24, Color.WHITE))
	var cost := BuildDB.cost_for(id)
	var parts := []
	var ok := true
	for k in cost:
		var have: int = game.inventory.count(k)
		if have < cost[k]:
			ok = false
		parts.append("%s %d/%d" % [ItemDB.item_name(k), have, cost[k]])
	vb.add_child(_lbl(", ".join(parts), 17, UIStyle.GOOD if ok else UIStyle.BAD))
	vb.add_child(_lbl(BuildDB.DESCRIPTIONS.get(id, ""), 15, UIStyle.MUTED))
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		piece_chosen.emit(id)
		close())
	return b

func _lbl(t: String, s: int, c: Color) -> Label:
	var l := UIStyle.make_label(t, s, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
