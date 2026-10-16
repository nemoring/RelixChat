extends Node
## Снимки экрана для проверки визуала: godot --path . res://tools/shot.tscn -- <сцена> <x> <y> <z> <yaw> <pitch> <out.png> [night]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var scene := a[0] if a.size() > 0 else "game"
	if a.size() > 7:
		GameState.current_night = int(a[7])
	var out := a[6] if a.size() > 6 else "user://shot.png"
	if scene == "menu":
		get_tree().root.add_child.call_deferred(load("res://scenes/main_menu.tscn").instantiate())
		await get_tree().create_timer(3.0).timeout
	else:
		var g: Node = load("res://scenes/game.tscn").instantiate()
		get_tree().root.add_child.call_deferred(g)
		await get_tree().create_timer(4.0).timeout
		var p: Player = GameWorld.instance.player
		p.global_position = Vector3(float(a[1]), float(a[2]), float(a[3]))
		p.rotation_degrees.y = float(a[4])
		p.head.rotation_degrees.x = float(a[5])
		if a.size() > 8 and a[8] == "flash":
			p.toggle_flashlight()
		if a.size() > 8 and a[8] == "desk":
			GameWorld.instance.open_desk()
		if a.size() > 8 and a[8] == "entities":
			var w := GameWorld.instance
			w.hud.overlay.color.a = 0.0
			w.entities["faceless"].show_at("hall_counter", p.global_position)
			w.entities["woman"].show_at("hall_center", p.global_position)
			w.entities["courier"].show_at("hall_e", p.global_position)
			w.entities["returner"].visits = 3
			w.entities["returner"]._apply_stage()
			w.entities["returner"].show_at("hall_w", p.global_position)
			w.entities["inspector"].show_at("hall_window", p.global_position)
			w.entities["inspector"].set_vis_layers(1)
		await get_tree().create_timer(1.5).timeout
		GameWorld.instance.hud.overlay.color.a = 0.0
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	get_tree().quit()
