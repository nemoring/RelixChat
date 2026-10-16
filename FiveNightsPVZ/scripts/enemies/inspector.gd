class_name Inspector
extends Entity
## Проверяющий. Пишет поддельные письма, появляется только на камерах,
## а потом — за спиной. Правило: если за спиной дышат — не оборачиваться.

var state := "off"   # off | camera | behind | leaving
var _timer := 0.0
var _onset_yaw := 0.0
var _breath: AudioStreamPlayer3D
var pending_behind := -1.0

const CAM_SPOTS := ["cor_2", "wh_mid", "hall_center", "util", "cor_4", "wh_sw"]


func model_options() -> Dictionary:
	return {"jacket": Color(0.85, 0.85, 0.82), "pants": Color(0.15, 0.15, 0.17), "skin": Color(0.66, 0.6, 0.56), "tie": true, "height": 1.06, "thin": 0.92}


func _on_setup() -> void:
	step_sound = "step"
	step_volume = -12.0
	var clip := Build.box(model.fore_r, Vector3(0.22, 0.3, 0.02), Vector3(0, -0.3, -0.08), Mats.color(Color(0.4, 0.3, 0.2)))
	clip.name = "Clipboard"
	Build.box(model.spine, Vector3(0.08, 0.1, 0.01), Vector3(0.12, 0.45, -0.19), Mats.color(Color(0.95, 0.95, 0.95)))


func appear_on_camera() -> void:
	if aggression <= 0 or state != "off":
		return
	var spot: String = CAM_SPOTS[rng.randi() % CAM_SPOTS.size()]
	show_at(spot)
	set_vis_layers(Build.VIS_CAM_ONLY)
	# Смотрит в ближайшую камеру.
	var cams: Array = world.level.nav.cam_coverage.get(spot, [])
	if cams.size() > 0:
		face(world.level.cam_mount_nodes[cams[0]].global_position)
	state = "camera"
	_timer = rng.randf_range(30.0, 50.0)
	if rng.randf() < 0.4 + aggression * 0.03:
		pending_behind = _timer + rng.randf_range(30.0, 80.0)


func behind_event() -> void:
	if state == "behind" or world.game_over:
		return
	var p: Player = world.player
	state = "behind"
	active = true
	visible = true
	set_vis_layers(Build.VIS_ALL)
	_onset_yaw = p.view_yaw()
	_timer = 9.0 - minf(aggression * 0.1, 2.0)
	_place_behind()
	_breath = Sfx.make_loop("breath", self, Vector3(0, 1.6, 0), -12.0, "SFX", 6.0)
	_breath.pitch_scale = 0.8
	world.subtitle("[за спиной кто-то дышит]", 4.0)
	world.director.on_encounter_start("inspector")


func _place_behind() -> void:
	var p: Player = world.player
	var back := p.global_basis.z
	back.y = 0
	back = back.normalized()
	global_position = p.global_position + back * 0.75
	face(p.global_position)


func _process(delta: float) -> void:
	super._process(delta)
	if pending_behind > 0.0 and state != "behind":
		pending_behind -= delta
		if pending_behind <= 0.0:
			pending_behind = -1.0
			if world.director.request_escalation("inspector", 2) or aggression >= 12:
				behind_event()


func _tick(delta: float) -> void:
	match state:
		"camera":
			_timer -= delta
			if _timer <= 0.0:
				hide_entity()
				state = "off"
		"behind":
			var p: Player = world.player
			_timer -= delta
			var turned := absf(wrapf(p.view_yaw() - _onset_yaw, -PI, PI))
			if turned > deg_to_rad(100.0) or p.is_looking_at(head_pos(), 35.0, false):
				attack("Если за спиной дышат — не оборачивайтесь, пока дыхание не стихнет. Проверяющий появляется после поддельных писем и показывается на камерах.")
				return
			# Держится за спиной, даже если игрок идёт.
			if global_position.distance_to(p.global_position) > 1.2:
				var yaw := _onset_yaw
				var back := Vector3(sin(yaw), 0, cos(yaw))
				global_position = p.global_position + back * 0.75
				face(p.global_position)
			if _timer <= 0.0:
				_finish()
		"leaving":
			if not seen_by_player():
				hide_entity()
				state = "off"


func _finish() -> void:
	if is_instance_valid(_breath):
		_breath.queue_free()
	world.subtitle("Шёпот за спиной: «Нарушений не выявлено».", 3.0)
	Sfx.play_3d("step", global_position, -14.0)
	set_vis_layers(Build.VIS_CAM_ONLY)
	state = "leaving"
	world.director.on_encounter_end("inspector")
