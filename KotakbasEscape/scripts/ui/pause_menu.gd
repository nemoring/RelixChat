class_name PauseMenu
extends OverlayPanel
## Пауза для всех глав. Останавливает дерево сцены, даёт сохраниться, открыть настройки, выйти в меню.

signal resumed

var extra_buttons: Array = [] # [[текст, Callable], ...] — например, отладка

func _ready() -> void:
	setup("Пауза", Vector2(0.5, 0.86))
	get_tree().paused = true
	var sc := OverlayPanel.make_scroll()
	content.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	_btn(vb, "Продолжить", close)
	_btn(vb, "Сохранить", func():
		var p := SaveLoadPanel.new()
		p.save_mode = true
		add_child(p))
	_btn(vb, "Настройки", func(): add_child(SettingsPanel.new()))
	for e in extra_buttons:
		_btn(vb, e[0], e[1])
	_btn(vb, "В главное меню", func():
		GameManager.autosave()
		get_tree().paused = false
		GameManager.go_to_menu())
	var info := UIStyle.make_label("Сложность: %s" % DifficultyManager.level_name(), 20, UIStyle.MUTED)
	vb.add_child(info)

func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := UIStyle.make_button(text, Vector2(360, 78))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call())
	parent.add_child(b)

func close() -> void:
	get_tree().paused = false
	resumed.emit()
	super.close()
