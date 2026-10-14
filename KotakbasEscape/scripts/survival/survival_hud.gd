class_name SurvivalHUD
extends Control
## Информационный HUD: характеристики, время/погода/место, задание с указателем,
## субтитры, прицел, вспышка урона, экран сна.

var game
var bars := {}
var temp_label: Label
var clock_label: Label
var quest_title: Label
var quest_prog: Label
var quest_dir: Label
var subtitle_label: Label
var crosshair: Control
var damage_flash: ColorRect
var sleep_overlay: ColorRect
var sleep_label: Label
var stats_box: VBoxContainer
var _sub_t := 0.0
var _sub_queue: Array[String] = []

func setup(g) -> void:
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(damage_flash)
	stats_box = VBoxContainer.new()
	stats_box.position = Vector2(14, 12)
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_box.add_theme_constant_override("separation", 3)
	add_child(stats_box)
	for k in [["health", "Здоровье", Color(0.9, 0.25, 0.25)], ["hunger", "Сытость", Color(0.95, 0.6, 0.2)], ["thirst", "Вода", Color(0.3, 0.6, 1.0)], ["stamina", "Силы", Color(0.95, 0.85, 0.3)]]:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UIStyle.make_label(k[1], 16, Color.WHITE)
		l.custom_minimum_size.x = 82
		UIStyle.outline(l, 4)
		row.add_child(l)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(170, 14)
		pb.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = k[2]
		fill.set_corner_radius_all(6)
		pb.add_theme_stylebox_override("fill", fill)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pb)
		stats_box.add_child(row)
		bars[k[0]] = pb
	temp_label = UIStyle.make_label("", 16, Color.WHITE)
	UIStyle.outline(temp_label, 4)
	stats_box.add_child(temp_label)
	var top := VBoxContainer.new()
	top.name = "TopInfo"
	top.anchor_left = 0.41
	top.anchor_right = 0.41
	top.offset_left = -235
	top.offset_right = 235
	top.offset_top = 8
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	clock_label = UIStyle.make_label("", 22, Color.WHITE, true)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.outline(clock_label, 6)
	top.add_child(clock_label)
	quest_title = UIStyle.make_label("", 19, UIStyle.ACCENT)
	quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.outline(quest_title, 5)
	top.add_child(quest_title)
	quest_prog = UIStyle.make_label("", 16, Color(0.92, 0.92, 0.92))
	quest_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quest_prog.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.outline(quest_prog, 4)
	top.add_child(quest_prog)
	quest_dir = UIStyle.make_label("", 20, Color(1, 0.9, 0.5), true)
	quest_dir.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.outline(quest_dir, 5)
	top.add_child(quest_dir)
	subtitle_label = UIStyle.make_label("", 22, Color.WHITE)
	subtitle_label.anchor_left = 0.18
	subtitle_label.anchor_right = 0.82
	subtitle_label.anchor_top = 1.0
	subtitle_label.anchor_bottom = 1.0
	subtitle_label.offset_top = -170
	subtitle_label.offset_bottom = -104
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyle.outline(subtitle_label, 6)
	add_child(subtitle_label)
	crosshair = Crosshair.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(crosshair)
	sleep_overlay = ColorRect.new()
	sleep_overlay.color = Color(0.02, 0.02, 0.06, 0.92)
	sleep_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sleep_overlay.visible = false
	add_child(sleep_overlay)
	sleep_label = UIStyle.make_label("", 46, Color(0.8, 0.85, 1.0), true)
	sleep_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleep_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sleep_overlay.add_child(sleep_label)
	Settings.changed.connect(_place_stats)
	_place_stats()

func _place_stats() -> void:
	var mirror: bool = Settings.get_value("left_handed", false)
	# Верхние кнопки меню — с той же стороны, что и кнопки действий; статы — с другой.
	stats_box.position = Vector2(get_viewport_rect().size.x - 290 if mirror else 14, 12)
	var top: Control = get_node_or_null("TopInfo")
	if top:
		top.anchor_left = 0.59 if mirror else 0.41
		top.anchor_right = top.anchor_left

func show_subtitle(text: String, time := 4.5) -> void:
	if not Settings.get_value("subtitles", true) and text.begins_with("["):
		return
	if _sub_t > 0.5:
		_sub_queue.append(text)
		if _sub_queue.size() > 3:
			_sub_queue.pop_front()
		return
	subtitle_label.text = text
	subtitle_label.modulate.a = 1.0
	_sub_t = time

func flash_damage() -> void:
	damage_flash.color.a = 0.35

func _process(delta: float) -> void:
	if game == null:
		return
	damage_flash.color.a = maxf(0.0, damage_flash.color.a - delta * 0.8)
	var s: SurvivalStats = game.stats
	bars.health.value = s.health
	bars.hunger.value = s.hunger
	bars.thirst.value = s.thirst
	bars.stamina.value = s.stamina
	var env_t: float = game.env_temperature()
	temp_label.text = "Тело %.1f°C · Вокруг %d°C" % [s.body_temp, roundi(env_t)]
	temp_label.add_theme_color_override("font_color", UIStyle.BAD if s.body_temp < 35.5 else Color.WHITE)
	var p: Vector3 = game.player.global_position
	clock_label.text = "День %d · %s · %s · %s" % [DayNight.day_number(game.time_min), DayNight.clock_text(game.time_min), game.weather.display_name(), game.terrain.region_name(p.x, p.z)]
	var q: Dictionary = game.quests.current()
	if q.is_empty():
		quest_title.text = ""
		quest_prog.text = ""
		quest_dir.text = ""
	else:
		quest_title.text = "» " + q.title
		if Engine.get_process_frames() % 10 == 0:
			quest_prog.text = game.quests.progress_text()
		var tp: Vector3 = game.quests.target_pos()
		if tp != Vector3.INF:
			var to := tp - p
			to.y = 0.0
			var d := to.length()
			var ang := wrapf(atan2(-to.x, -to.z) - game.player.yaw, -PI, PI)
			var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
			var idx := posmod(int(round(-ang / (PI / 4.0))), 8)
			quest_dir.text = "Цель: %s %d м" % [arrows[idx], int(d)] if d > 12.0 else "Цель рядом"
		else:
			quest_dir.text = ""
	if _sub_t > 0.0:
		_sub_t -= delta
		subtitle_label.modulate.a = clampf(_sub_t, 0.0, 1.0)
		if _sub_t <= 0.0 and not _sub_queue.is_empty():
			var t: String = _sub_queue.pop_front()
			show_subtitle(t)
	if sleep_overlay.visible:
		sleep_label.text = "Z z z\n%s" % DayNight.clock_text(game.time_min)
	crosshair.aiming = game.aiming
	crosshair.queue_redraw()

class Crosshair extends Control:
	var aiming := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if aiming:
			draw_arc(Vector2.ZERO, 22, 0, TAU, 32, Color(0.4, 1.0, 0.5, 0.9), 3.0, true)
			draw_line(Vector2(-32, 0), Vector2(-12, 0), Color(0.4, 1.0, 0.5), 3.0)
			draw_line(Vector2(12, 0), Vector2(32, 0), Color(0.4, 1.0, 0.5), 3.0)
			draw_line(Vector2(0, -32), Vector2(0, -12), Color(0.4, 1.0, 0.5), 3.0)
			draw_line(Vector2(0, 12), Vector2(0, 32), Color(0.4, 1.0, 0.5), 3.0)
		else:
			draw_circle(Vector2.ZERO, 4, Color(1, 1, 1, 0.8))
			draw_arc(Vector2.ZERO, 5, 0, TAU, 16, Color(0, 0, 0, 0.6), 1.5, true)
