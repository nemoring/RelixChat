class_name Jumpscare
extends Node
## Нападения: у каждой сущности своя анимация, связанная с её положением.
## Звук ограничен лимитером; страх — в движении и паузах, а не в громкости.

signal finished

var world
var active := false
var rng := RandomNumberGenerator.new()


func setup(w) -> void:
	world = w
	rng.randomize()


func play(entity_id: String, ent) -> void:
	active = true
	var p: Player = world.player
	p.flashlight.visible = true
	p.flashlight.light_energy = 1.2
	var variant := rng.randi() % 2
	match entity_id:
		"faceless":
			await _faceless(p, ent, variant)
		"woman":
			await _woman(p, ent, variant)
		"courier":
			await _courier(p, ent, variant)
		"returner":
			await _returner(p, ent, variant)
		"inspector":
			await _inspector(p, ent, variant)
		_:
			await get_tree().create_timer(0.5).timeout
	active = false
	finished.emit()


func _place_in_front(p: Player, ent: Entity, dist: float, side := 0.0) -> void:
	var fwd := -p.cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	ent.visible = true
	ent.set_vis_layers(Build.VIS_ALL)
	ent.global_position = Vector3(p.global_position.x, 0, p.global_position.z) + fwd * dist + right * side
	ent.face(p.global_position)


func _turn_to(p: Player, target: Vector3, t: float) -> void:
	var tw := create_tween()
	var to := target - p.global_position
	var yaw := atan2(-to.x, -to.z)
	tw.tween_property(p, "rotation:y", p.rotation.y + wrapf(yaw - p.rotation.y, -PI, PI), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p.head, "rotation:x", 0.05, t)
	await tw.finished


func _black(t := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(world.hud.overlay, "color:a", 1.0, t)
	await tw.finished


func _faceless(p: Player, ent: Entity, variant: int) -> void:
	if variant == 1:
		# «Моргание»: короткая темнота — и он уже вплотную.
		world.hud.overlay.color.a = 1.0
		await get_tree().create_timer(0.35).timeout
		_place_in_front(p, ent, 0.55)
		world.hud.overlay.color.a = 0.0
	else:
		await _turn_to(p, ent.head_pos(), 0.6)
		_place_in_front(p, ent, 1.4)
	Sfx.play_3d("sting_faceless", ent.head_pos(), -4.0)
	var m: HumanoidModel = ent.model
	var tw := create_tween()
	tw.tween_property(ent, "global_position", ent.global_position + (p.global_position - ent.global_position).normalized() * 0.9, 1.8).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(v): m.set_face_intensity(v); m.head_tilt(v * 0.35); world.stare_value = v * 0.6, 0.6, 1.6, 1.8)
	tw.parallel().tween_property(p.cam, "fov", 40.0, 1.8)
	await tw.finished
	await _black(0.08)
	world.stare_value = 0.0


func _woman(p: Player, ent: Entity, variant: int) -> void:
	var side := -0.9 if variant == 0 else 0.9
	_place_in_front(p, ent, 1.6, side)
	var m: HumanoidModel = ent.model
	m.reach(1.0)
	m.head_tilt(0.5 * signf(side), -0.3)
	await _turn_to(p, ent.head_pos(), 0.18)
	Sfx.play_3d("sting_woman", ent.head_pos(), -2.0)
	var tw := create_tween()
	tw.tween_property(ent, "global_position", p.global_position + (-p.global_basis.z) * 0.35, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v): m.head_tilt(0.5 * signf(side) - v, -0.3 + v * 0.3), 0.0, 0.7, 0.35)
	await tw.finished
	p.external_shake = 0.6
	await get_tree().create_timer(0.3).timeout
	await _black(0.1)


func _courier(p: Player, ent: Entity, variant: int) -> void:
	_place_in_front(p, ent, 0.9, 0.2 if variant == 0 else -0.2)
	Sfx.play_3d("sting_courier", p.global_position + Vector3.UP, -2.0)
	p.external_shake = 0.5
	var tw := create_tween()
	# Падение на пол: камера валится, курьер нависает сверху.
	tw.tween_property(p.head, "position:y", 0.25, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p.head, "rotation:z", 1.2 if variant == 0 else -1.2, 0.45)
	tw.parallel().tween_property(p.head, "rotation:x", 0.7, 0.6)
	await tw.finished
	ent.model.reach(0.6)
	ent.model.head_tilt(0.0, 0.6)
	await get_tree().create_timer(1.2).timeout
	await _black(0.4)


func _returner(p: Player, ent: Entity, _variant: int) -> void:
	_place_in_front(p, ent, 1.1)
	var m: HumanoidModel = ent.model
	await _turn_to(p, ent.head_pos(), 0.25)
	Sfx.play_3d("sting_return", ent.head_pos(), -2.0)
	var tw := create_tween()
	tw.tween_method(func(v): m.reach(v), 0.0, 1.2, 0.5)
	tw.parallel().tween_method(func(v): m.head_tilt(v, v * 0.4), 0.3, 1.1, 1.0)
	tw.tween_property(p, "global_position", p.global_position + (ent.global_position - p.global_position).normalized() * 0.6, 0.25).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(p.head, "rotation:x", -0.5, 0.25)
	await tw.finished
	p.external_shake = 0.4
	await get_tree().create_timer(0.5).timeout
	await _black(0.1)


func _inspector(p: Player, ent: Entity, variant: int) -> void:
	# Камеру медленно разворачивают — вы видите его, хотя не хотели.
	ent.visible = true
	ent.set_vis_layers(Build.VIS_ALL)
	await _turn_to(p, ent.head_pos(), 1.6 if variant == 0 else 0.4)
	Sfx.play_3d("sting_inspector", ent.head_pos(), -4.0)
	ent.model.head_tilt(0.25, 0.1)
	world.subtitle("«Нарушение».", 2.0)
	var tw := create_tween()
	tw.tween_property(ent, "global_position", ent.global_position + (p.global_position - ent.global_position) * 0.4, 1.0)
	await tw.finished
	await get_tree().create_timer(0.6).timeout
	await _black(0.05)
