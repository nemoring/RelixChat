class_name DeskUI
extends CanvasLayer
## Компьютер на стойке: камеры, база заказов, возвраты, почта, задания, пульт.
## Окно не закрывает экран целиком — по краям видно зал.

var world
var visible_ui := false
var root: Control
var tabs: TabContainer
var auto_open_card := false
var cam_view: TextureRect
var cam_title: Label
var cam_clock: Label
var cam_buttons: Array[Button] = []
var rec_list: HBoxContainer
var orders_list: VBoxContainer
var search_edit: LineEdit
var card_view: Label
var return_view: VBoxContainer
var mail_list: VBoxContainer
var mail_view: VBoxContainer
var tasks_list: VBoxContainer
var panel_box: VBoxContainer
var _refresh_t := 0.0
var _lock_indicator_lies := false
var _lie_t := 0.0
var _sigs := {}


func setup(w) -> void:
	world = w
	layer = 4
	visible = false
	root = Control.new()
	UIKit.full_rect(root)
	root.theme = UIKit.theme()
	add_child(root)
	var margin := MarginContainer.new()
	UIKit.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70 if side in ["left", "right"] else 40)
	root.add_child(margin)
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.95)
	sb.border_color = Color(0.15, 0.25, 0.35)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	margin.add_child(frame)
	var v := VBoxContainer.new()
	frame.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := UIKit.label("ПВЗ «ПОСЫЛКА» · Рабочее место № 1 · смена " + GameState.player_name(), 15, UIKit.DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(UIKit.button("Встать из-за стола  [Esc]", func(): world.close_desk(), 36))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	_build_cameras()
	_build_orders()
	_build_returns()
	_build_mail()
	_build_tasks()
	_build_panel()
	tabs.tab_changed.connect(_on_tab)


func open() -> void:
	visible = true
	visible_ui = true
	Sfx.play_ui("keyboard", -16.0)
	if auto_open_card:
		auto_open_card = false
		tabs.current_tab = 1
		var last: Dictionary = world.orders.orders[world.orders.orders.size() - 1]
		_show_order(last)
		world.subtitle("[на экране уже открыта карточка. Вы её не открывали]", 4.0)
	_refresh_all()
	_on_tab(tabs.current_tab)


func close() -> void:
	visible = false
	visible_ui = false


func _process(delta: float) -> void:
	if not visible:
		return
	if Input.is_action_just_pressed("pause"):
		world.close_desk()
		return
	if tabs.current_tab == 0:
		cam_view.texture = world.cctv.texture()
		cam_title.text = Level.CAMERAS[world.cctv.current]["title"] + ("   [НЕТ СИГНАЛА]" if world.cctv.signal_lost.has(world.cctv.current) else "")
		cam_clock.text = "● REC  %s  %s" % [Story.NIGHT_DATES[clampi(world.night_index, 1, 6)], world.cctv.clock_for_feed()]
		for i in cam_buttons.size():
			cam_buttons[i].modulate = Color(0.6, 0.9, 1.0) if i == world.cctv.current else Color.WHITE
	# На поздних ночах индикатор двери иногда «врёт» — несколько десятков секунд подряд.
	_lie_t -= delta
	if _lie_t <= 0.0:
		_lie_t = randf_range(20.0, 40.0)
		_lock_indicator_lies = world.night_index >= 4 and randf() < 0.3
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_refresh_all(false)


func _on_tab(i: int) -> void:
	world.cctv.set_active(i == 0 and visible)
	_refresh_all()


## Перестраивает разделы только при изменении данных: иначе кнопка под курсором
## пересоздаётся между нажатием и отпусканием, и клик теряется.
func _refresh_all(force := true) -> void:
	if force:
		_sigs.clear()
	var orders_sig := str(world.orders.active_cards.map(func(c): return [c["no"], c.get("opened", false)]))
	if _changed("orders", orders_sig):
		_refresh_orders()
	var r = world.entities.get("returner")
	if _changed("return", str([r.state, r.request.get("no", "")]) if r else ""):
		_refresh_return()
	if _changed("mail", str(world.night.mails.map(func(m): return [m["id"], m["read"], m["reported"]]))):
		_refresh_mail_list()
	if _changed("tasks", str([world.night.violations, int(world.night.minute()), world.night.tasks.map(func(t): return [t["id"], t["done"], t["failed"], t["title"], t.get("progress", "")])])):
		_refresh_tasks()
	if _changed("panel", _panel_sig()):
		_refresh_panel()


func _changed(key: String, sig: String) -> bool:
	if _sigs.get(key, null) == sig:
		return false
	_sigs[key] = sig
	return true


func _panel_sig() -> String:
	var lt: Lighting = world.level.lighting
	var z := []
	for zone in ["hall", "workstation", "warehouse", "corridor", "fitting"]:
		z.append([lt.switches[zone], lt.is_zone_powered(zone)])
	return str([z, world.level.doors["front"].locked, _lock_indicator_lies, lt.tripped_breakers(), int(world.player.battery)])


# ------------------------------------------------------------------ Камеры

func _build_cameras() -> void:
	var h := HBoxContainer.new()
	h.name = "Камеры"
	tabs.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var view_box := Control.new()
	view_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_box.custom_minimum_size = Vector2(480, 270)
	left.add_child(view_box)
	cam_view = TextureRect.new()
	UIKit.full_rect(cam_view)
	cam_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cam_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cam_view.material = world.cctv.material
	view_box.add_child(cam_view)
	cam_title = UIKit.label("", 16, Color(1, 1, 1, 0.85))
	cam_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	cam_title.position = Vector2(12, 8)
	view_box.add_child(cam_title)
	cam_clock = UIKit.label("", 15, Color(1, 0.4, 0.35, 0.9))
	cam_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	cam_clock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cam_clock.position = Vector2(12, -30)
	view_box.add_child(cam_clock)
	rec_list = HBoxContainer.new()
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 70)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(rec_list)
	left.add_child(sc)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(220, 0)
	h.add_child(right)
	right.add_child(UIKit.label("Каналы", 15, UIKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	right.add_child(grid)
	for i in Level.CAMERAS.size():
		var idx := i
		var b := UIKit.button("CAM %d" % (i + 1), func(): world.cctv.switch_to(idx), 40)
		b.custom_minimum_size.x = 100
		b.tooltip_text = Level.CAMERAS[i]["title"]
		grid.add_child(b)
		cam_buttons.append(b)
	var nv := CheckButton.new()
	nv.text = "Ночное видение"
	nv.toggled.connect(func(on): world.cctv.night_vision = on)
	right.add_child(nv)
	right.add_child(UIKit.button("● Записать кадр", func():
		world.cctv.record()
		_refresh_recordings(), 40))
	right.add_child(UIKit.label("Если часы на изображении отстают — картинка устарела. Переключите канал.", 13, UIKit.DIM))


func _refresh_recordings() -> void:
	for c in rec_list.get_children():
		c.queue_free()
	for r in world.cctv.recordings:
		var vb := VBoxContainer.new()
		var tr := TextureRect.new()
		tr.texture = r["image"]
		tr.custom_minimum_size = Vector2(96, 54)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vb.add_child(tr)
		vb.add_child(UIKit.label("%s %s" % [str(r["cam"]).substr(0, 5), r["time"]], 11, UIKit.DIM))
		rec_list.add_child(vb)


# ------------------------------------------------------------------ Заказы

func _build_orders() -> void:
	var h := HBoxContainer.new()
	h.name = "Заказы"
	tabs.add_child(h)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	left.add_child(UIKit.label("Клиенты у стойки", 16, UIKit.ACCENT))
	orders_list = VBoxContainer.new()
	left.add_child(orders_list)
	left.add_child(HSeparator.new())
	var sh := HBoxContainer.new()
	left.add_child(sh)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Поиск: номер заказа или фамилия"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_submitted.connect(func(_t): _do_search())
	sh.add_child(search_edit)
	sh.add_child(UIKit.button("Найти", _do_search, 36))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.name = "Results"
	left.add_child(sc)
	var res := VBoxContainer.new()
	res.name = "List"
	res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(res)
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	h.add_child(right)
	card_view = UIKit.label("Карточка заказа не выбрана.", 17)
	right.add_child(card_view)


func _refresh_orders() -> void:
	for c in orders_list.get_children():
		c.queue_free()
	var cards: Array = world.orders.active_cards
	if cards.is_empty():
		orders_list.add_child(UIKit.label("Нет ожидающих клиентов.", 15, UIKit.DIM))
	for card in cards:
		var hb := HBoxContainer.new()
		var who: String = "клиент без лица" if card["kind"] == "faceless" else str(card["recipient"])
		var l := UIKit.label("%s — %s" % [card["no"], who], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		var cc: Dictionary = card
		hb.add_child(UIKit.button("Открыть карточку", func(): _open_card(cc), 36))
		orders_list.add_child(hb)


func _open_card(card: Dictionary) -> void:
	world.orders.open_card(card)
	var o: Dictionary = world.orders.find(card["no"])
	_show_order(o if not o.is_empty() else card)
	Sfx.play_ui("beep", -14.0)


func _show_order(o: Dictionary) -> void:
	var txt := "ЗАКАЗ %s\n\nПолучатель: %s\nТовар: %s\nЯчейка: %s\nСтатус: %s\nДата: %s" % [o.get("no", "—"), o.get("recipient", "—"), o.get("product", "—"), o.get("cell", "—"), o.get("status", "—"), o.get("date", "—")]
	if o.has("note"):
		txt += "\n\n" + str(o["note"])
	if o.get("kind", "") == "player" or o.get("kind", "") == "player_ghost":
		txt += "\n\n[получатель совпадает с сотрудником смены]"
	card_view.text = txt


func _do_search() -> void:
	var list: VBoxContainer = tabs.get_node("Заказы").find_child("List", true, false)
	for c in list.get_children():
		c.queue_free()
	var found: Array = world.orders.search(search_edit.text)
	found.reverse()
	for o in found.slice(0, 40):
		var oo: Dictionary = o
		var b := UIKit.button("%s · %s · %s · %s" % [o["no"], o["recipient"], o["status"], o["date"]], func(): _show_order(oo), 32)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	if found.is_empty():
		list.add_child(UIKit.label("Ничего не найдено.", 15, UIKit.DIM))


# ------------------------------------------------------------------ Возвраты

func _build_returns() -> void:
	var v := VBoxContainer.new()
	v.name = "Возвраты"
	tabs.add_child(v)
	return_view = VBoxContainer.new()
	return_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(return_view)
	v.add_child(UIKit.label("Регламент: заказ есть в базе · статус «Выдан» · не более 14 дней с выдачи · тот же товар. Иначе — отказ.", 14, UIKit.DIM))


func _refresh_return() -> void:
	for c in return_view.get_children():
		c.queue_free()
	var r = world.entities.get("returner")
	if r == null or r.state != "waiting":
		return_view.add_child(UIKit.label("Заявок на возврат нет.", 16, UIKit.DIM))
		return
	var req: Dictionary = r.request
	return_view.add_child(UIKit.label("ЗАЯВКА НА ВОЗВРАТ", 18, UIKit.ACCENT))
	return_view.add_child(UIKit.label("Номер заказа (со слов клиента): %s\nТовар: %s\nДата выдачи (со слов клиента): %s\nСегодня: %s" % [req["no"], req["item"], req["date"], world.orders.today], 17))
	var hb := HBoxContainer.new()
	return_view.add_child(hb)
	hb.add_child(UIKit.button("Найти заказ в базе", func():
		search_edit.text = req["no"]
		tabs.current_tab = 1
		_do_search(), 40))
	hb.add_child(UIKit.button("Принять возврат", func():
		r.decide(true)
		_refresh_return(), 40))
	hb.add_child(UIKit.button("Отказать", func():
		r.decide(false)
		_refresh_return(), 40))


# ------------------------------------------------------------------ Почта

func _build_mail() -> void:
	var h := HBoxContainer.new()
	h.name = "Почта"
	tabs.add_child(h)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(380, 0)
	h.add_child(sc)
	mail_list = VBoxContainer.new()
	mail_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(mail_list)
	var sc2 := ScrollContainer.new()
	sc2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sc2)
	mail_view = VBoxContainer.new()
	mail_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(mail_view)


func _refresh_mail_list() -> void:
	for c in mail_list.get_children():
		c.queue_free()
	var mails: Array = world.night.mails.duplicate()
	mails.reverse()
	for m in mails:
		var mm: Dictionary = m
		var b := UIKit.button("%s %s · %s" % ["●" if not m["read"] else " ", m["time"], m["subject"]], func(): _show_mail(mm), 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		mail_list.add_child(b)
	if mails.is_empty():
		mail_list.add_child(UIKit.label("Писем нет.", 15, UIKit.DIM))


func _show_mail(m: Dictionary) -> void:
	m["read"] = true
	for c in mail_view.get_children():
		c.queue_free()
	mail_view.add_child(UIKit.label(m["subject"], 19, UIKit.ACCENT))
	mail_view.add_child(UIKit.label("От: %s\nВремя: %s" % [m["sender"], m["time"]], 15, UIKit.DIM))
	mail_view.add_child(UIKit.label(m["body"], 17))
	if not m["reported"]:
		mail_view.add_child(UIKit.button("Пометить как подозрительное", func():
			world.night.report_mail(m)
			_show_mail(m), 36))
	else:
		mail_view.add_child(UIKit.label("[отмечено как подозрительное]", 14, UIKit.DANGER))
	_refresh_mail_list()


# ------------------------------------------------------------------ Задания

func _build_tasks() -> void:
	var sc := ScrollContainer.new()
	sc.name = "Задания"
	tabs.add_child(sc)
	tasks_list = VBoxContainer.new()
	tasks_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(tasks_list)


func _refresh_tasks() -> void:
	for c in tasks_list.get_children():
		c.queue_free()
	tasks_list.add_child(UIKit.label("Нарушений: %d / %d" % [world.night.violations, NightController.MAX_VIOLATIONS], 16, UIKit.DANGER if world.night.violations > 0 else UIKit.DIM))
	var ts: Array = world.night.tasks.duplicate()
	ts.reverse()
	for t in ts:
		var status := "✓" if t["done"] else ("✗" if t["failed"] else "…")
		var line := "%s %s" % [status, t["title"]]
		if t["deadline"] > 0 and not t["done"] and not t["failed"]:
			line += "  (до %s)" % world.night.clock_text(t["deadline"] - world.night.minute())
		tasks_list.add_child(UIKit.label(line, 16, UIKit.TEXT if not (t["done"] or t["failed"]) else UIKit.DIM))


# ------------------------------------------------------------------ Пульт

func _build_panel() -> void:
	var v := VBoxContainer.new()
	v.name = "Пульт"
	tabs.add_child(v)
	panel_box = VBoxContainer.new()
	v.add_child(panel_box)


func _refresh_panel() -> void:
	if panel_box == null:
		return
	for c in panel_box.get_children():
		c.queue_free()
	var lt: Lighting = world.level.lighting
	panel_box.add_child(UIKit.label("Освещение", 17, UIKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	panel_box.add_child(grid)
	for z in ["hall", "workstation", "warehouse", "corridor", "fitting"]:
		var zz: String = z
		var on: bool = lt.switches[z]
		var powered: bool = lt.is_zone_powered(z)
		var b := UIKit.button("%s: %s" % [Lighting.ZONE_NAMES[z], ("ВКЛ" if powered else "НЕТ ПИТАНИЯ") if on else "ВЫКЛ"], func():
			lt.set_switch(zz, not lt.switches[zz])
			_refresh_panel(), 40)
		b.custom_minimum_size.x = 230
		grid.add_child(b)
	panel_box.add_child(HSeparator.new())
	var locked: bool = world.level.doors["front"].locked
	var shown_locked := locked if not _lock_indicator_lies else true
	panel_box.add_child(UIKit.label("Входная дверь: %s" % ("ЗАБЛОКИРОВАНА" if shown_locked else "РАЗБЛОКИРОВАНА"), 17, UIKit.TEXT if shown_locked else UIKit.DANGER))
	var tripped := lt.tripped_breakers()
	panel_box.add_child(UIKit.label("Автоматы щитка: %s" % ("в норме" if tripped.is_empty() else "ОТКЛЮЧЕНЫ " + ", ".join(PackedStringArray(tripped))), 17, UIKit.TEXT if tripped.is_empty() else UIKit.DANGER))
	panel_box.add_child(UIKit.label("Фонарик: %d%% (заряжается, пока вы за столом)" % int(world.player.battery), 16, UIKit.DIM))
