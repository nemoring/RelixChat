class_name CraftingUI
extends OverlayPanel
## Крафт: рецепты, требования (зелёный/красный), время, станция, очередь с отменой.

var game
var station_filter := "" # "" — все рецепты
var _list: VBoxContainer
var _queue_box: VBoxContainer

func _ready() -> void:
	var title := "Крафт"
	if station_filter != "":
		title = RecipeDB.STATION_NAMES[station_filter]
	setup(title, Vector2(0.92, 0.92))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)
	var sc := OverlayPanel.make_scroll()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 2.2
	body.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	sc.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UIStyle.make_label("Очередь изготовления", 24, UIStyle.ACCENT, true))
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 6)
	right.add_child(_queue_box)
	game.crafting.queue_changed.connect(_rebuild)
	game.inventory.changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in _list.get_children():
		c.queue_free()
	var ids := RecipeDB.RECIPES.keys()
	ids.sort_custom(func(a, b): return _station_order(RecipeDB.RECIPES[a].station) < _station_order(RecipeDB.RECIPES[b].station))
	for id in ids:
		var r: Dictionary = RecipeDB.RECIPES[id]
		if station_filter != "" and r.station != station_filter and r.station != "hand":
			continue
		_list.add_child(_recipe_row(id, r))
	_rebuild_queue()

func _station_order(s: String) -> int:
	if s == station_filter:
		return -1
	return ["hand", "campfire", "workbench", "furnace"].find(s)

func _recipe_row(id: String, r: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(1, 1, 1, 0.05), 14))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	var icon := TextureRect.new()
	icon.texture = ItemDB.icon(r.result)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(UIStyle.make_label("%s ×%d" % [ItemDB.item_name(r.result), int(r.n)], 24, Color.WHITE, true))
	var cost := RecipeDB.cost_for(id)
	var req := RichTextLabel.new()
	req.bbcode_enabled = true
	req.fit_content = true
	req.scroll_active = false
	req.custom_minimum_size.x = 380
	req.add_theme_font_size_override("normal_font_size", 19)
	var parts := []
	for k in cost:
		var have: int = game.inventory.count(k)
		var col := "#66e57a" if have >= cost[k] else "#ff5a4d"
		parts.append("[color=%s]%s %d/%d[/color]" % [col, ItemDB.item_name(k), have, cost[k]])
	var st_ok: bool = game.crafting.station_available(r.station)
	var st_col := "#66e57a" if st_ok else "#ff5a4d"
	req.text = ", ".join(parts) + "\n[color=%s]Станция: %s[/color] · %.0f с" % [st_col, RecipeDB.STATION_NAMES[r.station], RecipeDB.time_for(id)]
	vb.add_child(req)
	var b := UIStyle.make_button("Изготовить", Vector2(200, 76), 24)
	b.disabled = not game.crafting.can_craft(id)
	b.pressed.connect(func():
		game.crafting.enqueue(id)
		_rebuild())
	hb.add_child(b)
	return panel

func _rebuild_queue() -> void:
	for c in _queue_box.get_children():
		c.queue_free()
	if game.crafting.queue.is_empty():
		_queue_box.add_child(UIStyle.make_label("Пусто", 20, UIStyle.MUTED))
		return
	for i in game.crafting.queue.size():
		var e: Dictionary = game.crafting.queue[i]
		var row := HBoxContainer.new()
		var lbl := UIStyle.make_label(ItemDB.item_name(RecipeDB.RECIPES[e.recipe].result), 20)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(110, 18)
		pb.show_percentage = false
		pb.value = (1.0 - e.left / e.total) * 100.0
		pb.set_meta("entry", e)
		row.add_child(pb)
		var cancel := UIStyle.make_button("×", Vector2(56, 56), 24)
		cancel.pressed.connect(func(): game.crafting.cancel(i))
		row.add_child(cancel)
		_queue_box.add_child(row)

func _process(_delta: float) -> void:
	for row in _queue_box.get_children():
		for c in row.get_children():
			if c is ProgressBar and c.has_meta("entry"):
				var e: Dictionary = c.get_meta("entry")
				c.value = (1.0 - e.left / e.total) * 100.0

func close() -> void:
	if game.crafting.queue_changed.is_connected(_rebuild):
		game.crafting.queue_changed.disconnect(_rebuild)
	if game.inventory.changed.is_connected(_rebuild):
		game.inventory.changed.disconnect(_rebuild)
	super.close()
