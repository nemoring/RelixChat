class_name MapUI
extends OverlayPanel
## Карта местности (доступна после получения карты от деда Михалыча):
## рельеф, важные места, база, игрок, текущая цель, список заданий.

var game
static var _map_tex: ImageTexture

func _ready() -> void:
	setup("Карта и задания", Vector2(0.94, 0.94))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)
	var has_map: bool = game.inventory.count("map") > 0
	var map_box := Control.new()
	map_box.custom_minimum_size = Vector2(520, 520)
	map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_box)
	if has_map:
		if _map_tex == null:
			_map_tex = _render_map()
		var mv := MapView.new()
		mv.game = game
		mv.tex = _map_tex
		mv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		map_box.add_child(mv)
	else:
		var l := UIStyle.make_label("Карты нет.\nГоворят, у деда в деревне на северо-западе есть старая карта.\n\nУказатель цели вверху экрана всё равно покажет направление.", 22, UIStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		map_box.add_child(l)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UIStyle.make_label("Задания", 28, UIStyle.ACCENT, true))
	var sc := OverlayPanel.make_scroll()
	right.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var qm: QuestManager = game.quests
	for i in QuestManager.QUESTS.size():
		var q: Dictionary = QuestManager.QUESTS[i]
		var done := i < qm.index
		var cur := i == qm.index
		if i > qm.index + 1:
			break
		var col := UIStyle.GOOD if done else (UIStyle.ACCENT if cur else UIStyle.MUTED)
		var prefix := "[готово] " if done else ("» " if cur else "")
		var l2 := UIStyle.make_label("%d. %s%s" % [i + 1, prefix, q.title if i <= qm.index else "???"], 22, col)
		list.add_child(l2)
		if cur:
			var d := UIStyle.make_label(q.desc + "\n" + qm.progress_text(), 18, Color.WHITE)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(d)
	var info := UIStyle.make_label("Налётов НЛО отбито/пережито: %d" % game.ufo_manager.raid_count, 18, UIStyle.MUTED)
	right.add_child(info)

func _render_map() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var t: SurvivalTerrain = game.terrain
	for j in n:
		for i in n:
			var x := -256.0 + (i + 0.5) * 512.0 / n
			var z := -256.0 + (j + 0.5) * 512.0 / n
			var h := t.raw_height(x, z)
			var c := Color(0.35, 0.5, 0.28)
			if h < SurvivalTerrain.WATER_LEVEL:
				c = Color(0.25, 0.45, 0.7)
			elif h > 18.0:
				c = Color(0.6, 0.58, 0.52)
			elif h > 10.0:
				c = Color(0.45, 0.52, 0.32)
			var reg := t.region_at(x, z)
			if reg == "swamp" and h >= SurvivalTerrain.WATER_LEVEL:
				c = Color(0.38, 0.4, 0.25)
			c = c.darkened(clampf(-h * 0.01, 0.0, 0.2)).lightened(clampf(h * 0.008, 0.0, 0.15))
			img.set_pixel(i, j, c)
	return ImageTexture.create_from_image(img)

class MapView extends Control:
	var game
	var tex: Texture2D

	func _process(_d: float) -> void:
		queue_redraw()

	func _w2m(p: Vector3, r: Rect2) -> Vector2:
		return r.position + Vector2((p.x + 256.0) / 512.0, (p.z + 256.0) / 512.0) * r.size

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var r := Rect2(Vector2((size.x - s) * 0.5, 0), Vector2(s, s))
		draw_texture_rect(tex, r, false)
		draw_rect(r, Color(0.1, 0.08, 0.05), false, 4.0)
		var font := UIStyle.bold_font()
		for k in SurvivalTerrain.REGIONS:
			var reg: Dictionary = SurvivalTerrain.REGIONS[k]
			var p := _w2m(Vector3(reg.c.x, 0, reg.c.y), r)
			draw_circle(p, 6, Color(0.95, 0.85, 0.3))
			draw_string_outline(font, p + Vector2(8, 5), reg.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
			draw_string(font, p + Vector2(8, 5), reg.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		var base: Vector3 = game.buildings.base_center()
		if base != Vector3.INF:
			var bp := _w2m(base, r)
			draw_rect(Rect2(bp - Vector2(7, 7), Vector2(14, 14)), Color(0.4, 0.9, 0.4))
			draw_string(font, bp + Vector2(9, -6), "База", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 1, 0.6))
		var tp: Vector3 = game.quests.target_pos()
		if tp != Vector3.INF:
			var qp := _w2m(tp, r)
			draw_arc(qp, 12 + sin(Time.get_ticks_msec() * 0.006) * 3, 0, TAU, 24, UIStyle.ACCENT, 3.0)
		var pl: Vector3 = game.player.global_position
		var pp := _w2m(pl, r)
		var yaw: float = game.player.yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		draw_colored_polygon(PackedVector2Array([pp + fwd * 12, pp - fwd * 6 + side * 7, pp - fwd * 6 - side * 7]), Color(1, 0.3, 0.2))
		draw_string(font, r.position + Vector2(8, 22), "С ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
