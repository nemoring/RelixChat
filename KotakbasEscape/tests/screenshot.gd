extends Node
## Отладочный инструмент: загружает сцену, ждёт и сохраняет скриншоты.
## godot --path . res://tests/screenshot.tscn -- scene=res://... times=1,3 out=/path/prefix [setup=method]

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var scene_path: String = args.get("scene", "res://scenes/menu/main_menu.tscn")
	var times: PackedStringArray = str(args.get("times", "2")).split(",")
	var out: String = args.get("out", "/tmp/shot")
	if args.has("difficulty"):
		DifficultyManager.restore_level(int(args.difficulty))
		GameManager.state.difficulty = int(args.difficulty)
	if args.has("chapter"):
		GameManager.state.chapter = args.chapter
		GameManager.in_game = true
	var inst: Node = load(scene_path).instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = inst
	if args.has("setup") and inst.has_method(args.setup):
		inst.call(args.setup)
	var elapsed := 0.0
	var i := 0
	for ts in times:
		var target := float(ts)
		while elapsed < target:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [out, i])
		print("saved ", "%s_%d.png" % [out, i])
		i += 1
	get_tree().quit()
