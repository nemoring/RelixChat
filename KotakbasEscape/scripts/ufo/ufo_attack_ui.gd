class_name UFOAttackUI
extends Control
## Интерфейс налёта: «Кабина ТЦК: 7/13», полоса прочности, камни, украденное,
## подсказки и указатель направления на тарелку.

var game
var panel: PanelContainer
var title: Label
var bar: ProgressBar
var info: Label
var hint: Label
var arrow: Label
var warn_label: Label
var _warn_t := 0.0

func setup(g) -> void:
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.15, 0.02, 0.02, 0.8), 16, UIStyle.BAD))
	# Слева под характеристиками — центр экрана свободен для прицеливания.
	panel.offset_left = 10
	panel.offset_right = 430
	panel.offset_top = 128
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	title = UIStyle.make_label("Кабина ТЦК: 13/13", 28, Color(1, 0.85, 0.3), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(390, 18)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIStyle.BAD
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(bar)
	info = UIStyle.make_label("", 20, Color.WHITE)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)
	hint = UIStyle.make_label("", 19, Color(0.85, 0.95, 1.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 390
	vb.add_child(hint)
	arrow = UIStyle.make_label("", 64, UIStyle.BAD, true)
	UIStyle.outline(arrow, 8)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arrow)
	warn_label = UIStyle.make_label("", 34, Color(1, 0.3, 0.25), true)
	UIStyle.outline(warn_label, 8)
	warn_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	warn_label.position.y = 150
	warn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(warn_label)
	panel.visible = false

func show_warning(text: String, time := 4.0) -> void:
	warn_label.text = text
	warn_label.modulate.a = 1.0
	_warn_t = time

func _process(delta: float) -> void:
	if _warn_t > 0.0:
		_warn_t -= delta
		warn_label.modulate.a = clampf(_warn_t, 0.0, 1.0)
	var ufo: UFOController = game.ufo_manager.ufo
	var active := is_instance_valid(ufo) and ufo.is_active_threat()
	panel.visible = active
	if active:
		var mirror: bool = Settings.get_value("left_handed", false)
		panel.offset_left = get_viewport_rect().size.x - 430 if mirror else 10
		panel.offset_right = panel.offset_left + 420
	arrow.visible = false
	if not active:
		return
	var h := ufo.health
	title.text = "Кабина ТЦК: %d/%d" % [h.left(), h.max_hits]
	bar.value = h.ratio() * 100.0
	var stones: int = game.inventory.count("stone")
	info.text = "Камней: %d · Украдено: %d из %d" % [stones, ufo.stealer.stolen_total, maxi(ufo.stealer.budget, ufo.stealer.stolen_total)]
	if stones == 0:
		hint.text = "Камни кончились! Подбирай камни на земле — рядом появляются груды камней."
	elif game.selected_item() != "stone":
		hint.text = "Выбери камень на панели внизу и зажми «Бросок»."
	else:
		var d := Vector2(ufo.global_position.x - game.player.global_position.x, ufo.global_position.z - game.player.global_position.z).length()
		if d < 11.0:
			hint.text = "Ты под тарелкой — кабину не видно. Отойди на 13–25 м и целься в стеклянный купол!"
		else:
			hint.text = "Зажми «Бросок», наведи прицел на стеклянную КАБИНУ и отпусти. Корпус не считается!"
	# Указатель, если тарелка за кадром
	var cam: Camera3D = game.player.active_camera()
	var target := ufo.cockpit_global()
	var vp := get_viewport_rect().size
	if cam.is_position_behind(target) or not Rect2(Vector2.ZERO, vp).has_point(cam.unproject_position(target)):
		var to := target - cam.global_position
		var local := cam.global_transform.basis.inverse() * to
		var ang := atan2(local.x, local.y)
		var center := vp * 0.5
		var r := minf(vp.x, vp.y) * 0.38
		arrow.visible = true
		arrow.text = "▲"
		arrow.pivot_offset = arrow.size * 0.5
		arrow.rotation = ang
		arrow.position = center + Vector2(sin(ang), -cos(ang)) * r - arrow.size * 0.5
