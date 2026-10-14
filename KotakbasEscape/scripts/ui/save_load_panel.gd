class_name SaveLoadPanel
extends OverlayPanel
## Список слотов. Режим загрузки (из меню) или сохранения (из паузы).

var save_mode := false

const CHAPTER_NAMES := {
	"novel": "Глава 1: Обычное утро",
	"runner": "Глава 2: БЕГИ, КОТАКБАС!",
	"survival": "Глава 3: Лес Котакбаса",
}

func _ready() -> void:
	setup("Сохранить игру" if save_mode else "Загрузить игру")
	var sc := OverlayPanel.make_scroll()
	content.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	for slot in SaveManager.SLOTS:
		if save_mode and slot == "auto":
			continue
		list.add_child(_slot_row(slot))

func _slot_row(slot: String) -> Control:
	var meta := SaveManager.slot_meta(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slot_name := "Автосохранение" if slot == "auto" else "Слот %s" % slot
	info.add_child(UIStyle.make_label(slot_name, 28, UIStyle.ACCENT, true))
	if meta.is_empty():
		info.add_child(UIStyle.make_label("Пусто", 22, UIStyle.MUTED))
	else:
		var pt := int(meta.playtime)
		var line := "%s · %s · %s · %d:%02d" % [CHAPTER_NAMES.get(meta.chapter, meta.chapter), DifficultyManager.level_name(meta.difficulty), meta.datetime, pt / 3600, (pt / 60) % 60]
		var l := UIStyle.make_label(line, 20, UIStyle.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(l)
	row.add_child(info)
	if save_mode:
		var b := UIStyle.make_button("Сохранить", Vector2(220, 80))
		b.pressed.connect(func():
			if GameManager.save_game(slot):
				GameManager.toast("Игра сохранена: слот %s" % slot, UIStyle.GOOD)
				AudioManager.play_sfx("craft_done")
			else:
				GameManager.toast("Не удалось сохранить", UIStyle.BAD)
			close())
		row.add_child(b)
	else:
		var b := UIStyle.make_button("Загрузить", Vector2(220, 80))
		b.disabled = meta.is_empty()
		b.pressed.connect(func():
			AudioManager.play_sfx("click")
			if not GameManager.load_game(slot):
				GameManager.toast("Сохранение повреждено", UIStyle.BAD))
		row.add_child(b)
		if not meta.is_empty():
			var del := UIStyle.make_button("Удалить", Vector2(170, 80), 22)
			del.pressed.connect(func():
				SaveManager.delete_slot(slot)
				GameManager.toast("Слот удалён")
				var p := get_parent()
				var again := SaveLoadPanel.new()
				p.add_child(again)
				queue_free())
			row.add_child(del)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(1, 1, 1, 0.05), 16))
	panel.add_child(row)
	return panel
