class_name InventoryUI
extends OverlayPanel
## Сенсорный инвентарь: перетаскивание, объединение и разделение стопок,
## выбрасывание, использование, перенос в ящик и обратно, описание предметов.
## Первые 6 ячеек — панель быстрого доступа.

var game
var crate_inv: Inventory = null
var _grid: GridContainer
var _crate_grid: GridContainer
var _slots: Array[SlotButton] = []
var _crate_slots: Array[SlotButton] = []
var _sel_inv: Inventory
var _sel_index := -1
var _name: Label
var _desc: Label
var _actions: HBoxContainer

func _ready() -> void:
	setup("Ящик" if crate_inv else "Инвентарь", Vector2(0.94, 0.92))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	left.add_child(UIStyle.make_label("Котакбас (1–6 — быстрая панель)", 20, UIStyle.MUTED))
	var sc := OverlayPanel.make_scroll()
	left.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 6 if crate_inv else 8
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(_grid)
	for i in game.inventory.capacity():
		var sb := _make_slot(game.inventory, i)
		sb.hotbar = i < 6
		_grid.add_child(sb)
		_slots.append(sb)
	if crate_inv:
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(right)
		right.add_child(UIStyle.make_label("Ящик", 20, UIStyle.MUTED))
		_crate_grid = GridContainer.new()
		_crate_grid.columns = 4
		_crate_grid.add_theme_constant_override("h_separation", 6)
		_crate_grid.add_theme_constant_override("v_separation", 6)
		right.add_child(_crate_grid)
		for i in crate_inv.capacity():
			var cb := _make_slot(crate_inv, i)
			_crate_grid.add_child(cb)
			_crate_slots.append(cb)
	# Описание и действия
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(1, 1, 1, 0.05), 14))
	content.add_child(info)
	var ivb := VBoxContainer.new()
	info.add_child(ivb)
	_name = UIStyle.make_label("Выбери предмет", 26, UIStyle.ACCENT, true)
	ivb.add_child(_name)
	_desc = UIStyle.make_label("Касание — выбрать, перетаскивание — переложить или объединить стопки.", 20)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ivb.add_child(_desc)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	ivb.add_child(_actions)
	game.inventory.changed.connect(_refresh)
	if crate_inv:
		crate_inv.changed.connect(_refresh)
	_refresh()

func _make_slot(inv: Inventory, i: int) -> SlotButton:
	var sb := SlotButton.new()
	sb.inv = inv
	sb.index = i
	sb.custom_minimum_size = Vector2(84, 84)
	sb.slot_tapped.connect(_on_tap)
	sb.slot_dropped.connect(_refresh)
	return sb

func _on_tap(inv: Inventory, i: int) -> void:
	AudioManager.play_sfx("click", -8.0)
	_sel_inv = inv
	_sel_index = i
	if inv == game.inventory and i < 6:
		game.select_hotbar(i)
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	for sb in _slots + _crate_slots:
		sb.selected = (sb.inv == _sel_inv and sb.index == _sel_index)
		sb.refresh()
	for c in _actions.get_children():
		c.queue_free()
	if _sel_inv == null or _sel_index < 0 or _sel_inv.slots[_sel_index] == null:
		_name.text = "Выбери предмет"
		_desc.text = "Касание — выбрать, перетаскивание — переложить или объединить стопки. Первые 6 ячеек — быстрая панель."
		return
	var s: Dictionary = _sel_inv.slots[_sel_index]
	var item := ItemDB.get_item(s.id)
	_name.text = "%s ×%d" % [item.name, int(s.n)]
	var extra := ""
	if item.has("food"):
		var f: Dictionary = item.food
		var parts := []
		for k in f:
			parts.append({"hunger": "сытость", "thirst": "вода", "health": "здоровье", "stamina": "бодрость"}[k] + (" %+d" % int(f[k])))
		extra = "  (" + ", ".join(parts) + ")"
	if item.get("key", false):
		extra += "  Сюжетный предмет — НЛО его не украдёт."
	_desc.text = str(item.desc) + extra
	if item.has("food"):
		_act("Использовать", func(): game.use_item_slot(_sel_inv, _sel_index))
	if int(s.n) > 1:
		_act("Разделить", func():
			if not _sel_inv.split(_sel_index):
				GameManager.toast("Нет свободной ячейки", UIStyle.BAD, 1.0))
	if not item.get("key", false):
		_act("Выбросить", func():
			var taken := _sel_inv.remove_from_slot(_sel_index, int(s.n))
			if not taken.is_empty():
				game.drop_items(taken.id, int(taken.n), game.player.global_position + game.player.forward() * 1.5))
	if crate_inv:
		if _sel_inv == game.inventory:
			_act("В ящик", func(): game.inventory.transfer_slot(_sel_index, crate_inv))
		else:
			_act("Взять", func(): crate_inv.transfer_slot(_sel_index, game.inventory))

func _act(text: String, cb: Callable) -> void:
	var b := UIStyle.make_button(text, Vector2(200, 72), 24)
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call()
		_refresh())
	_actions.add_child(b)

func close() -> void:
	if game.inventory.changed.is_connected(_refresh):
		game.inventory.changed.disconnect(_refresh)
	if crate_inv and crate_inv.changed.is_connected(_refresh):
		crate_inv.changed.disconnect(_refresh)
	super.close()
