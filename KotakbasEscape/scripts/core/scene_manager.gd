extends Node
## Переходы между сценами с затемнением и фоновой загрузкой.
## Главы не загружаются одновременно: старая сцена освобождается до загрузки новой.

signal scene_changed(path: String)

var _layer: CanvasLayer
var _fade: ColorRect
var _title: Label
var _tip: Label
var _busy := false

const TIPS := [
	"Совет: голуби помнят добро. И зло тоже.",
	"Совет: камни лучше бросать в кабину, а не в корпус.",
	"Совет: свайп вниз в прыжке — быстрое приземление.",
	"Совет: ящики в бункере НЛО не видит.",
	"Совет: костёр греет, кровать сохраняет точку возрождения.",
	"Совет: Котакбас не умеет летать. Пока что.",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 110
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)
	_title = UIStyle.make_label("", 40, UIStyle.ACCENT, true)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_fade.add_child(_title)
	_tip = UIStyle.make_label("", 22, UIStyle.MUTED)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip.position.y -= 70
	_fade.add_child(_tip)

func is_busy() -> bool:
	return _busy

func change_scene(path: String, title := "") -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.text = title
	_tip.text = TIPS.pick_random() if title != "" else ""
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.35)
	await tw.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioManager.stop_all_sfx()
	# Освобождаем текущую сцену до загрузки следующей — экономия памяти на 4 ГБ устройствах.
	var old := get_tree().current_scene
	if old:
		old.queue_free()
		await get_tree().process_frame
	ResourceLoader.load_threaded_request(path)
	while true:
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Не удалось загрузить сцену " + path)
			break
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	if title != "":
		await get_tree().create_timer(0.8).timeout
	if packed:
		var inst := packed.instantiate()
		get_tree().root.add_child(inst)
		get_tree().current_scene = inst
	scene_changed.emit(path)
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "modulate:a", 0.0, 0.45)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false

## Затемнение без смены сцены (для кат-сцен).
func fade_out(time := 0.5) -> void:
	_title.text = ""
	_tip.text = ""
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, time)
	await tw.finished

func fade_in(time := 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, time)
	await tw.finished
