extends Control
## Глава 1. Визуальная новелла (полностью 2D): исследование квартиры через
## интерактивные сцены, интерпретатор сценария, флаги, подозрение, последствия.

const Story := preload("res://scripts/novel/novel_story.gd")

const ITEM_NAMES := {
	"sandwich": "Бутерброд",
	"canned": "Тушёнка",
	"pryanik": "Тульский пряник",
	"backpack": "Рюкзак",
}

var flags: Dictionary
var location := "bedroom"
var art: NovelArt
var hotspot_layer: Control
var dialogue: DialogueBox
var nav_bar: HBoxContainer
var loc_label: Label
var goal_label: Label
var sus_label: Label
var items_label: Label
var title_overlay: ColorRect
var title_text: Label
var top_bar: Control
var _busy := false
var _knock_timer := -1.0
var _pause: PauseMenu

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flags = GameManager.state.flags
	for k in Story.DEFAULT_FLAGS:
		if not flags.has(k):
			flags[k] = Story.DEFAULT_FLAGS[k]
	_build_ui()
	resized.connect(_refresh)
	GameManager.back_requested.connect(_open_pause)
	GameManager.app_paused.connect(_on_app_paused)
	AudioManager.play_music("novel")
	AudioManager.stop_ambient()
	var saved: Dictionary = GameManager.state.get("novel", {})
	if saved.has("location"):
		_enter(saved.location, false)
		if flags.knocking:
			_run("knock")
		elif flags.knock_pending:
			_knock_timer = float(saved.get("knock_timer", _knock_time()))
	else:
		_enter("bedroom", false)
		_run("intro")

func _build_ui() -> void:
	art = NovelArt.new()
	art.flags = flags
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	hotspot_layer = Control.new()
	hotspot_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hotspot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hotspot_layer)
	# Верхняя панель
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0, 0, 0, 0.55), 0))
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 86
	add_child(top_bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	top_bar.add_child(hb)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(left)
	loc_label = UIStyle.make_label("", 28, UIStyle.ACCENT, true)
	left.add_child(loc_label)
	goal_label = UIStyle.make_label("", 19, Color(0.9, 0.9, 0.9))
	left.add_child(goal_label)
	var mid := VBoxContainer.new()
	hb.add_child(mid)
	sus_label = UIStyle.make_label("", 20, UIStyle.BAD)
	mid.add_child(sus_label)
	items_label = UIStyle.make_label("", 18, UIStyle.MUTED)
	items_label.custom_minimum_size.x = 380
	items_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(items_label)
	var pause_btn := UIStyle.make_button("II", Vector2(76, 70), 30)
	pause_btn.pressed.connect(_open_pause)
	hb.add_child(pause_btn)
	# Нижняя навигация
	nav_bar = HBoxContainer.new()
	nav_bar.anchor_top = 1.0
	nav_bar.anchor_bottom = 1.0
	nav_bar.anchor_right = 1.0
	nav_bar.offset_top = -104
	nav_bar.offset_bottom = -14
	nav_bar.offset_left = 20
	nav_bar.offset_right = -20
	nav_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_bar.add_theme_constant_override("separation", 16)
	add_child(nav_bar)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	title_overlay = ColorRect.new()
	title_overlay.color = Color(0, 0, 0, 0.92)
	title_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_overlay.visible = false
	add_child(title_overlay)
	title_text = UIStyle.make_label("", 54, UIStyle.ACCENT, true)
	title_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_overlay.add_child(title_text)

# ------------------------------------------------------------------ Локации

func _enter(loc: String, run_events := true) -> void:
	var prev := location
	location = loc
	art.location = loc
	_refresh()
	if not run_events:
		return
	AudioManager.play_sfx("swipe", -6.0)
	if loc == "yard" and not flags.visited_yard:
		flags.visited_yard = true
		_run("yard_enter")
	elif loc == "entrance":
		flags.visited_entrance = true
	elif loc == "corridor" and prev == "entrance" and flags.visited_yard and not flags.knock_pending and not flags.knock_done:
		flags.knock_pending = true
		_knock_timer = _knock_time()
		_run("home_return")

func _knock_time() -> float:
	return float(DifficultyManager.p("novel_choice_time")) * 4.0

func _refresh() -> void:
	var data: Dictionary = Story.LOCATIONS.get(location, {})
	loc_label.text = data.get("name", "")
	for c in hotspot_layer.get_children():
		c.queue_free()
	for c in nav_bar.get_children():
		c.queue_free()
	if location in ["jump", "black"]:
		return
	for h in data.get("hotspots", []):
		if h.has("if") and not _cond(h["if"]):
			continue
		var b := HotspotButton.new()
		b.caption = h.label
		var p: Vector2 = h.pos
		b.position = Vector2(p.x * size.x, p.y * size.y) - Vector2(75, 61)
		b.pressed.connect(_on_hotspot.bind(h.script))
		b.disabled = _busy
		hotspot_layer.add_child(b)
	for e in data.get("exits", []):
		var ename: String = Story.LOCATIONS[e].name
		if e == "entrance" and location == "corridor":
			ename = "Подъезд"
		var b := UIStyle.make_button("→ " + ename, Vector2(250, 84), 28)
		b.pressed.connect(_on_exit.bind(e))
		b.disabled = _busy or (e == "entrance" and location == "corridor" and (flags.knock_pending or flags.knock_done))
		nav_bar.add_child(b)
	_update_hud()

func _update_hud() -> void:
	var s: int = int(flags.suspicion)
	var bar := ""
	for i in 8:
		bar += "■" if i < s else "□"
	sus_label.text = "Подозрение: " + bar
	var items := []
	for k in GameManager.state.carry_items:
		var n: int = int(GameManager.state.carry_items[k])
		if n > 0:
			items.append("%s ×%d" % [ITEM_NAMES.get(k, k), n] if n > 1 else ITEM_NAMES.get(k, k))
	if flags.has_phone: items.append("Телефон")
	if flags.has_spravka: items.append("Справка")
	if flags.has_bike_key and not flags.has_bicycle: items.append("Ключ")
	if flags.has_bicycle: items.append("Велосипед")
	if flags.pigeon_friend: items.append("Голубь Гоша")
	items_label.text = "Вещи: " + (", ".join(items) if items.size() > 0 else "—")
	if flags.knock_pending:
		goal_label.text = "Скоро постучат! Подготовься: %d c" % maxi(0, int(ceil(_knock_timer)))
		goal_label.add_theme_color_override("font_color", UIStyle.BAD)
	elif not flags.visited_yard:
		goal_label.text = "Цель: собраться и выйти во двор (Коридор → Подъезд → Двор)"
	else:
		goal_label.text = "Цель: вернуться домой"
	if DifficultyManager.p("novel_hints") and not flags.knock_pending:
		if not flags.has_backpack:
			goal_label.text += " · Подсказка: в шкафу есть рюкзак"
		elif not flags.pigeon_friend and not flags.has_bread:
			goal_label.text += " · Подсказка: голуби любят хлеб"
		elif not flags.balcony_open:
			goal_label.text += " · Подсказка: открой окно на балконе"

func _on_hotspot(script_name: String) -> void:
	if _busy:
		return
	AudioManager.play_sfx("click")
	_run(script_name)

func _on_exit(loc: String) -> void:
	if _busy:
		return
	_enter(loc)

func _process(delta: float) -> void:
	if flags.knock_pending and _knock_timer > 0.0:
		_knock_timer -= delta
		if Engine.get_process_frames() % 15 == 0:
			_update_hud()
		if _knock_timer <= 0.0:
			_knock_timer = 0.0
	if flags.knock_pending and _knock_timer <= 0.0 and not _busy:
		_run("knock")

# ------------------------------------------------------------------ Интерпретатор

func _run(script_name: String) -> void:
	_busy = true
	_refresh()
	var next := script_name
	while next != "":
		var cmds: Array = Story.SCRIPTS.get(next, [])
		var res: String = await _exec(cmds, next)
		next = ""
		if res.begins_with("goto:"):
			next = res.substr(5)
		elif res == "jump":
			await _jump_cutscene()
			return
	dialogue.hide_box()
	_busy = false
	_refresh()

func _exec(cmds: Array, sid: String) -> String:
	for i in cmds.size():
		var c: Dictionary = cmds[i]
		var line_id := "%s:%d:%d" % [sid, i, cmds.size()]
		if c.has("item"):
			GameManager.add_carry_item(c.item, int(c.get("n", 1)))
			if int(c.get("n", 1)) > 0:
				AudioManager.play_sfx("pickup")
			_update_hud()
		elif c.has("s"):
			await dialogue.say(c.s, c.get("e", "normal"), c.t, line_id)
		elif c.has("n"):
			await dialogue.say("narrator", "normal", c.n, line_id)
		elif c.has("title"):
			await _title_card(c.title)
		elif c.has("choice"):
			var opts := []
			var visible_map := []
			for o in c.choice:
				var enabled: bool = (not o.has("if")) or _cond(o["if"])
				var hint := ""
				if DifficultyManager.p("novel_hints") and o.has("hint"):
					hint = o.hint
				opts.append({"text": o.t, "enabled": enabled, "hint": hint})
				visible_map.append(o)
			var timer := 0.0
			if c.get("timed", false):
				timer = float(DifficultyManager.p("novel_choice_time"))
			var default_i: int = int(c.get("default", 0))
			if not opts[default_i].enabled:
				for k in opts.size():
					if opts[k].enabled:
						default_i = k
						break
			var idx: int = await dialogue.choose(opts, timer, default_i)
			var r: String = await _exec(visible_map[idx].get("do", []), sid + ">%d" % idx)
			if r != "":
				return r
		elif c.has("set"):
			for k in c.set:
				flags[k] = c.set[k]
			art.flags = flags
		elif c.has("add"):
			for k in c.add:
				var v: float = float(c.add[k])
				if k == "suspicion" and v > 0:
					v = ceil(v * float(DifficultyManager.p("novel_suspicion_mult")))
				flags[k] = maxi(0, int(flags.get(k, 0)) + int(v))
				if k == "suspicion" and v != 0:
					GameManager.toast("Подозрение %s" % ("растёт!" if v > 0 else "снижается"), UIStyle.BAD if v > 0 else UIStyle.GOOD, 1.6)
			_update_hud()
		elif c.has("if"):
			var branch: Array = c.get("do", []) if _cond(c["if"]) else c.get("else", [])
			var r2: String = await _exec(branch, sid + "?%d" % i)
			if r2 != "":
				return r2
		elif c.has("check"):
			var ok := int(flags.suspicion) <= int(c.check) + int(DifficultyManager.p("novel_check_bonus"))
			var r3: String = await _exec(c.get("do", []) if ok else c.get("else", []), sid + "!%d" % i)
			if r3 != "":
				return r3
		elif c.has("sfx"):
			AudioManager.play_sfx(c.sfx)
		elif c.has("music"):
			AudioManager.play_music(c.music)
		elif c.has("shake"):
			_shake(float(c.shake))
			GameManager.vibrate(120)
		elif c.has("loc"):
			location = c.loc
			art.location = c.loc
			_refresh()
		elif c.has("ach"):
			GameManager.unlock_achievement(c.ach)
		elif c.has("toast"):
			GameManager.toast(c.toast, UIStyle.ACCENT)
		elif c.has("wait"):
			await get_tree().create_timer(float(c.wait)).timeout
		elif c.has("goto"):
			return "goto:" + str(c["goto"])
		elif c.has("jump"):
			return "jump"
	return ""

func _cond(expr_text: String) -> bool:
	var names := PackedStringArray()
	var values := []
	for k in flags:
		names.append(k)
		values.append(flags[k])
	names.append("lock")
	values.append(int(DifficultyManager.p("novel_suspicion_lock")))
	names.append("difficulty")
	values.append(DifficultyManager.level())
	var e := Expression.new()
	if e.parse(expr_text, names) != OK:
		push_error("Ошибка условия: " + expr_text)
		return false
	var r = e.execute(values, null, false)
	if e.has_execute_failed():
		return false
	return bool(r)

func _shake(amount: float) -> void:
	var tw := create_tween()
	for i in 8:
		tw.tween_property(art, "position", Vector2(randf_range(-14, 14), randf_range(-8, 8)) * amount, 0.04)
	tw.tween_property(art, "position", Vector2.ZERO, 0.05)

func _title_card(text: String) -> void:
	title_text.text = text
	title_overlay.visible = true
	title_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(title_overlay, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.8)
	tw.tween_property(title_overlay, "modulate:a", 0.0, 0.6)
	await tw.finished
	title_overlay.visible = false

func _jump_cutscene() -> void:
	dialogue.hide_box()
	art.location = "jump"
	art.cut_t = 0.0
	_refresh()
	top_bar.visible = false
	AudioManager.play_sfx("whoosh")
	var tw := create_tween()
	tw.tween_property(art, "cut_t", 1.0, 2.4).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
	AudioManager.play_sfx("thud")
	_shake(1.2)
	GameManager.vibrate(200)
	await dialogue.say("narrator", "normal", "Шесть сальто. Идеальное приземление на дорогу. Почти идеальное.")
	var tw2 := create_tween()
	tw2.tween_property(art, "cut_t", 2.0, 1.0)
	await dialogue.say("kot", "angry", "А теперь — БЕЖАТЬ!")
	dialogue.hide_box()
	_finish_chapter()

func _finish_chapter() -> void:
	flags.knocking = false
	flags.knock_done = true
	GameManager.state.novel = {"done": true}
	GameManager.state.runner = {}
	GameManager.start_chapter("runner")

# ------------------------------------------------------------------ Сохранение / пауза

func save_state() -> Dictionary:
	return {"location": location if not location in ["jump", "black"] else "balcony", "knock_timer": _knock_timer}

func _open_pause() -> void:
	if is_instance_valid(_pause) or SceneManager.is_busy():
		return
	_pause = PauseMenu.new()
	if GameManager.debug_enabled:
		_pause.extra_buttons = [["[Отладка] Пропустить главу", func():
			get_tree().paused = false
			_finish_chapter()]]
	add_child(_pause)

func _on_app_paused() -> void:
	_open_pause()
