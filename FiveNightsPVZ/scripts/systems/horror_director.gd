class_name HorrorDirector
extends Node
## HorrorDirector — управляет напряжением.
##
## Учитывает: ночь, положение игрока, уровень шума, освещённость, использование
## камер, недавние встречи, повторяющиеся действия, время с последней опасности.
##
## Фазы: QUIET (тишина) → BUILD (нарастание) → THREAT (разрешена эскалация)
## → RELIEF (передышка после встречи). Длительности случайны, поэтому момент
## следующей угрозы не угадывается, но поведение сущностей подчиняется их
## собственным правилам — директор лишь «разрешает» им действовать.

signal phase_changed(phase)

enum Phase { QUIET, BUILD, THREAT, RELIEF }

var world
var night := 1
var phase := Phase.QUIET
var phase_time := 0.0
var phase_len := 60.0
var tension := 0.0
var fear := 0.0
var rng := RandomNumberGenerator.new()

# Метрики игрока.
var noise_avg := 0.0
var cam_history: Array[float] = []   # 1 = камеры включены (по секунде)
var room_dwell := 0.0
var _last_room := ""
var last_threat_time := -999.0
var encounters := 0
var in_encounter := false
var _time := 0.0
var _sec_t := 0.0
var _ambient_t := 10.0
var _random_t := 60.0
var _returns := {}  # entity -> time left
var _silhouette: Node3D
var _silhouette_t := 0.0
var _cam_ghost: Node3D
var _cam_ghost_t := 0.0
var _finale := false
var _recent_events: Array[String] = []
var event_log: Array = []  # для тестов и отладки

const AMBIENT := ["steps_wall", "rustle", "creak", "thud", "drip", "flicker", "whisper_cabin", "move_prop", "silhouette", "breath_near", "steps_multi", "pc_card", "cam_figure", "knock_cabin", "silence"]
## Минимальная ночь для каждого фонового события (уровни 1 и 2).
const AMBIENT_MIN_NIGHT := {
	"steps_wall": 1, "rustle": 1, "creak": 1, "thud": 1, "drip": 1, "flicker": 1,
	"whisper_cabin": 1, "move_prop": 2, "silhouette": 2, "breath_near": 2,
	"steps_multi": 2, "pc_card": 2, "cam_figure": 2, "knock_cabin": 2, "silence": 1,
}
const RANDOM_EVENTS := ["printer", "pc_player_order", "box_today", "phone", "knock_locked_cabin", "cam_player_double", "future_order"]


func setup(w, n: int) -> void:
	world = w
	night = n
	rng.seed = GameState.run_seed ^ 0x5eed
	_enter(Phase.QUIET)
	_random_t = rng.randf_range(70.0, 140.0)
	_build_silhouette()


func _build_silhouette() -> void:
	_silhouette = HumanoidModel.new()
	world.add_child(_silhouette)
	_silhouette.build({"height": 1.05, "thin": 0.85})
	_silhouette.set_material_all(Mats.color(Color(0.01, 0.01, 0.012), 1.0))
	_silhouette.visible = false
	_cam_ghost = HumanoidModel.new()
	world.add_child(_cam_ghost)
	_cam_ghost.build({"jacket": Color(0.15, 0.2, 0.17), "skin": Color(0.75, 0.6, 0.5)})
	Build.set_visual_layers(_cam_ghost, Build.VIS_CAM_ONLY)
	_cam_ghost.visible = false


# ------------------------------------------------------------------ Фазы

func _enter(p: Phase) -> void:
	phase = p
	phase_time = 0.0
	var k := 1.0 - (night - 1) * 0.08
	match p:
		Phase.QUIET:
			phase_len = rng.randf_range(40.0, 110.0) * k
		Phase.BUILD:
			phase_len = rng.randf_range(25.0, 60.0)
		Phase.THREAT:
			phase_len = rng.randf_range(35.0, 75.0)
		Phase.RELIEF:
			phase_len = rng.randf_range(25.0, 55.0)
	phase_changed.emit(p)


func _process(delta: float) -> void:
	if world == null or world.game_over or not world.night.running:
		return
	_time += delta
	phase_time += delta
	_metrics(delta)
	match phase:
		Phase.QUIET:
			tension = move_toward(tension, 0.15, delta * 0.02)
			if phase_time > phase_len:
				_enter(Phase.BUILD)
		Phase.BUILD:
			tension = move_toward(tension, 0.6, delta * 0.015)
			if phase_time > phase_len:
				# Иногда перед угрозой «гаснет» гул — но не всегда.
				if rng.randf() < 0.4:
					_do_ambient("silence")
				_enter(Phase.THREAT)
		Phase.THREAT:
			tension = move_toward(tension, 0.9, delta * 0.02)
			if phase_time > phase_len:
				_enter(Phase.RELIEF if rng.randf() < 0.6 else Phase.QUIET)
		Phase.RELIEF:
			tension = move_toward(tension, 0.1, delta * 0.04)
			if phase_time > phase_len:
				_enter(Phase.QUIET)
	_tick_ambient(delta)
	_tick_random(delta)
	_tick_returns(delta)
	_tick_visuals(delta)
	_update_fear(delta)


func _metrics(delta: float) -> void:
	var p: Player = world.player
	noise_avg = lerpf(noise_avg, p.noise_level, delta * 0.5)
	_sec_t += delta
	if _sec_t >= 1.0:
		_sec_t = 0.0
		cam_history.append(1.0 if world.cctv.active else 0.0)
		if cam_history.size() > 90:
			cam_history.pop_front()
		if world.cctv.active:
			world.night.used_cameras = true
	if p.current_room == _last_room:
		room_dwell += delta
	else:
		_last_room = p.current_room
		room_dwell = 0.0


func cam_usage() -> float:
	if cam_history.is_empty():
		return 0.0
	var s := 0.0
	for v in cam_history:
		s += v
	return s / cam_history.size()


## Игрок «окопался»: слишком долго в одном месте или почти всё время в камерах.
func player_camping() -> bool:
	return room_dwell > 240.0 - night * 20.0 or cam_usage() > 0.7


func since_threat() -> float:
	return _time - last_threat_time


# ------------------------------------------------------------------ Эскалация

## Сущность просит разрешения на опасное действие. Логика сущности не ломается:
## отказ лишь откладывает действие.
func request_escalation(entity: String, cost: int) -> bool:
	if _finale:
		return true
	if phase == Phase.RELIEF:
		return false
	var aggr: int = NightData.aggression(night, entity.split("_")[0]) if entity.split("_")[0] in NightData.ENTITIES else night * 2
	var chance := aggr / 20.0
	match phase:
		Phase.QUIET:
			chance *= 0.15
		Phase.BUILD:
			chance *= 0.45
		Phase.THREAT:
			chance *= 1.0
		Phase.RELIEF:
			chance *= 0.0
	if player_camping():
		chance += 0.25
	if since_threat() > 180.0:
		chance += 0.2
	if in_encounter and cost >= 2:
		chance *= 0.2  # не наваливаемся всеми сразу
	var ok := rng.randf() < clampf(chance, 0.0, 0.95)
	if ok:
		_log("escalate", entity)
		last_threat_time = _time
	return ok


func on_encounter_start(entity: String) -> void:
	in_encounter = true
	encounters += 1
	last_threat_time = _time
	tension = 1.0
	_log("encounter", entity)


func on_encounter_end(entity: String) -> void:
	in_encounter = false
	_log("encounter_end", entity)
	_enter(Phase.RELIEF)


func schedule_return(entity: String, seconds: float) -> void:
	_returns[entity] = maxf(25.0, seconds)


func _tick_returns(delta: float) -> void:
	for e in _returns.keys():
		_returns[e] -= delta
		if _returns[e] <= 0.0:
			_returns.erase(e)
			if e == "courier" and world.entities.has("courier"):
				world.entities["courier"].activate()


func note_event(kind: String) -> void:
	_log("note", kind)
	if kind in ["faceless_inside", "faceless_stalk", "woman_hunt", "courier_in"]:
		last_threat_time = _time


func on_scripted(kind: String) -> void:
	_log("script", kind)


func on_client_arrived(_c) -> void:
	pass


func on_phone_answered(call_index: int) -> void:
	# Пока игрок слушает трубку, что-то может сдвинуться.
	if night >= 3 and rng.randf() < 0.4:
		get_tree().create_timer(4.0).timeout.connect(func(): _do_ambient("steps_wall"))
	_log("phone", str(call_index))


func on_door_unlocked() -> void:
	var f = world.entities.get("faceless")
	if f and f.aggression > 0 and f.state == "hidden" and night >= 2:
		get_tree().create_timer(rng.randf_range(6.0, 20.0)).timeout.connect(func():
			if is_instance_valid(f) and world.level.doors["front"].locked == false and f.state == "hidden":
				f.appear_outside())


func on_fake_followed(action: String) -> void:
	_log("fake_followed", action)
	var insp = world.entities.get("inspector")
	if insp:
		get_tree().create_timer(rng.randf_range(3.0, 7.0)).timeout.connect(func():
			if is_instance_valid(insp) and not world.game_over:
				insp.behind_event())
	if action == "unlock_door":
		on_door_unlocked()
	if action == "warehouse_dark" and world.entities.has("courier"):
		world.entities["courier"].activate()


func on_threat_signal(_pos: Vector3, kind: String) -> void:
	tension = minf(1.0, tension + 0.05)
	_log("signal", kind)


func on_noise(pos: Vector3, loudness: float, source: String) -> void:
	if source == "player" or source == "drop" or source == "door" or source == "hide":
		for id in ["woman", "courier"]:
			var e = world.entities.get(id)
			if e and e.has_method("on_noise"):
				e.on_noise(pos, loudness)


func start_finale() -> void:
	_finale = true
	_enter(Phase.THREAT)
	phase_len = 9999.0
	var f = world.entities.get("faceless")
	if f:
		f.aggression = maxi(f.aggression, 12)
		f.appear_inside()
	var c = world.entities.get("courier")
	if c:
		c.activate()
	var w = world.entities.get("woman")
	if w:
		w.request()


# ------------------------------------------------------------------ Фоновые события

func _tick_ambient(delta: float) -> void:
	if phase == Phase.RELIEF and phase_time < phase_len * 0.7:
		return
	_ambient_t -= delta
	if _ambient_t > 0.0:
		return
	var base := 30.0
	match phase:
		Phase.QUIET:
			base = rng.randf_range(22.0, 45.0)
		Phase.BUILD:
			base = rng.randf_range(9.0, 20.0)
		Phase.THREAT:
			base = rng.randf_range(12.0, 25.0)
		Phase.RELIEF:
			base = rng.randf_range(30.0, 50.0)
	_ambient_t = base * (1.15 - night * 0.05)
	var options := []
	for a in AMBIENT:
		if night >= int(AMBIENT_MIN_NIGHT[a]) and not (a in _recent_events):
			if phase == Phase.QUIET and AMBIENT_MIN_NIGHT[a] >= 2 and rng.randf() < 0.7:
				continue
			options.append(a)
	if options.is_empty():
		_recent_events.clear()
		return
	var pick: String = options[rng.randi() % options.size()]
	_do_ambient(pick)


func _do_ambient(kind: String) -> void:
	_recent_events.append(kind)
	if _recent_events.size() > 4:
		_recent_events.pop_front()
	_log("ambient", kind)
	var p: Player = world.player
	var lv: Level = world.level
	match kind:
		"steps_wall":
			# Шаги в соседнем помещении, глушёные стеной.
			var pos := _occluded_point(4.0, 9.0)
			_step_sequence(pos, rng.randi_range(3, 6), "step", -10.0)
		"steps_multi":
			_step_sequence(_occluded_point(4.0, 10.0), 5, "step_heavy", -8.0)
			_step_sequence(_occluded_point(4.0, 10.0), 5, "step_heavy", -9.0)
		"rustle":
			Sfx.play_3d("rustle", _point_in_room("warehouse"), -6.0, rng.randf_range(0.8, 1.2))
		"creak":
			Sfx.play_3d("creak", _point_in_room("warehouse") + Vector3.UP * 1.8, -6.0, rng.randf_range(0.8, 1.1))
		"thud":
			Sfx.play_3d("thud", _occluded_point(6.0, 14.0), -6.0, rng.randf_range(0.7, 1.0))
		"drip":
			for i in 3:
				get_tree().create_timer(i * 0.9 + rng.randf() * 0.3).timeout.connect(func(): Sfx.play_3d("drip", Vector3(15.2, 0.9, 11.6), -10.0, rng.randf_range(0.9, 1.2)))
		"flicker":
			var zone := Level.room_zone(p.current_room)
			if zone in Lighting.ZONES:
				lv.lighting.flicker_zone(zone, rng.randf_range(0.6, 2.0))
		"whisper_cabin":
			Sfx.play_3d("whisper", lv.cabins[rng.randi() % 2]["inside"] + Vector3.UP * 1.5, -18.0, 1.1, 10.0)
		"knock_cabin":
			Sfx.play_3d("knock", lv.cabins[rng.randi() % 2]["inside"] + Vector3.UP * 1.2, -12.0, 1.1)
		"breath_near":
			var bp := _occluded_point(2.0, 5.0)
			var b := Sfx.play_3d("breath", bp, -14.0, 0.9, 8.0)
			if b:
				get_tree().create_timer(4.0).timeout.connect(func():
					if is_instance_valid(b):
						b.queue_free())
		"move_prop":
			_move_unseen_prop()
		"silhouette":
			_show_silhouette()
		"pc_card":
			if not p.seated:
				Sfx.play_3d("beep", lv.pc_screen.global_position, -12.0, 0.9)
				Sfx.play_3d("keyboard", lv.pc_screen.global_position, -16.0)
				world.desk.auto_open_card = true
		"cam_figure":
			_show_cam_figure(false)
		"silence":
			_silence(rng.randf_range(5.0, 9.0))


func _occluded_point(min_d: float, max_d: float) -> Vector3:
	var p: Player = world.player
	var nav: NavGraph = world.level.nav
	var best := Vector3.ZERO
	var names := nav.all_names()
	for i in 12:
		var n := names[rng.randi() % names.size()]
		var pos := nav.pos_of(n) + Vector3.UP * 1.0
		var d := pos.distance_to(p.global_position)
		if d >= min_d and d <= max_d and not p.has_los(pos):
			return pos
		best = pos
	return best


func _point_in_room(room: String) -> Vector3:
	var pts: PackedStringArray = world.level.nav.points_in_room(room)
	if pts.is_empty():
		return Vector3.ZERO
	return world.level.nav.pos_of(pts[rng.randi() % pts.size()]) + Vector3.UP


func _step_sequence(pos: Vector3, count: int, sound: String, vol: float) -> void:
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	for i in count:
		var at := pos + dir * 0.7 * i
		get_tree().create_timer(i * rng.randf_range(0.55, 0.75)).timeout.connect(func(): Sfx.play_3d(sound, at, vol, rng.randf_range(0.85, 1.0)))


func _move_unseen_prop() -> void:
	var p: Player = world.player
	var props: Array = world.level.movable_props.duplicate()
	props.shuffle()
	for prop in props:
		var n := prop as Node3D
		if not p.in_view(n.global_position + Vector3.UP * 0.4) and n.global_position.distance_to(p.global_position) < 12.0:
			n.rotate_y(rng.randf_range(-0.8, 0.8))
			n.position += Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			_log("moved", n.name)
			return


func _show_silhouette() -> void:
	var p: Player = world.player
	var spots: Array = world.level.dark_spots.duplicate()
	spots.shuffle()
	for s in spots:
		var pos: Vector3 = s
		var d := pos.distance_to(p.global_position)
		if d < 4.0 or d > 13.0:
			continue
		if world.level.lighting.is_zone_lit(Level.room_zone(Level.room_at(pos))):
			continue
		# На периферии: в кадре, но не по центру.
		var head := pos + Vector3.UP * 1.6
		if not p.has_los(head):
			continue
		var to := (head - p.eye_pos()).normalized()
		var ang := rad_to_deg((-p.cam.global_basis.z).angle_to(to))
		if ang < 25.0 or ang > 60.0:
			continue
		_silhouette.global_position = pos
		_silhouette.look_at(Vector3(p.global_position.x, pos.y, p.global_position.z), Vector3.UP)
		_silhouette.visible = true
		_silhouette_t = rng.randf_range(1.0, 3.0)
		return


func _show_cam_figure(player_double: bool) -> void:
	var nav: NavGraph = world.level.nav
	var covered := []
	for n in nav.all_names():
		if nav.is_covered(n) and Level.room_at(nav.pos_of(n)) != world.player.current_room:
			covered.append(n)
	if covered.is_empty():
		return
	var n: String = covered[rng.randi() % covered.size()]
	_cam_ghost.global_position = nav.pos_of(n)
	var cams: Array = nav.cam_coverage[n]
	_cam_ghost.look_at(Vector3(world.level.cam_mount_nodes[cams[0]].global_position.x, 0, world.level.cam_mount_nodes[cams[0]].global_position.z), Vector3.UP)
	_cam_ghost.visible = true
	_cam_ghost_t = rng.randf_range(15.0, 30.0)
	_log("cam_figure", "double" if player_double else n)


func _tick_visuals(delta: float) -> void:
	if _silhouette.visible:
		_silhouette_t -= delta
		var head := _silhouette.global_position + Vector3.UP * 1.6
		if _silhouette_t <= 0.0 or world.player.is_looking_at(head, 14.0, false):
			_silhouette.visible = false
	if _cam_ghost.visible:
		_cam_ghost_t -= delta
		if _cam_ghost_t <= 0.0:
			_cam_ghost.visible = false


func _silence(seconds: float) -> void:
	var idx := AudioServer.get_bus_index("Ambience")
	if idx < 0:
		return
	var base := AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, base - 30.0)
	get_tree().create_timer(seconds).timeout.connect(func(): AudioServer.set_bus_volume_db(idx, base))


# ------------------------------------------------------------------ Случайные события

func _tick_random(delta: float) -> void:
	_random_t -= delta
	if _random_t > 0.0:
		return
	_random_t = rng.randf_range(80.0, 160.0) * (1.1 - night * 0.06)
	random_event(RANDOM_EVENTS[rng.randi() % RANDOM_EVENTS.size()])


## Случайное событие. Безвредность определяется броском, а не типом события.
func random_event(kind: String) -> bool:
	var lv: Level = world.level
	var handled := true
	match kind:
		"printer":
			var r: String = Story.RECEIPTS[rng.randi() % Story.RECEIPTS.size()]
			if r.contains("%s"):
				var n := r.count("%s")
				var args := []
				for i in n:
					args.append(GameState.player_name())
				r = r % args
			world.print_receipt(r)
		"pc_player_order":
			world.orders.add_player_card()
			Sfx.play_3d("beep", lv.pc_screen.global_position, -10.0, 0.8)
			world.desk.auto_open_card = true
		"box_today":
			var o := {"no": "П-%06d" % rng.randi_range(100000, 999999), "recipient": GameState.player_name(), "product": "—", "cell": "", "status": "Принят на ПВЗ", "date": world.orders.today, "kind": "intake"}
			world.orders.orders.append(o)
			var b: CarryBox = world.orders.make_box(o)
			lv.add_child(b)
			b.position = Vector3(rng.randf_range(2.0, 9.0), 0, 6.3)
			b._label.text = "%s\nДАТА: %s" % [GameState.player_name(), world.orders.today]
		"phone":
			world.ring_phone(0)
		"knock_locked_cabin":
			var cab: Dictionary = lv.cabins[rng.randi() % 2]
			Sfx.play_3d("knock", cab["inside"] + Vector3.UP * 1.0, -6.0, 0.9)
		"cam_player_double":
			_show_cam_figure(true)
		"future_order":
			world.orders.add_future_order()
		_:
			handled = false
	if not handled:
		return false
	var harm_p := clampf(0.08 * night, 0.0, 0.5)
	if rng.randf() < harm_p:
		get_tree().create_timer(rng.randf_range(6.0, 18.0)).timeout.connect(_harmful_followup)
	_log("random", kind)
	return true


func _harmful_followup() -> void:
	if world.game_over:
		return
	var opts := ["breaker"]
	if night >= 2:
		opts += ["maglock", "courier"]
	if night >= 3:
		opts.append("woman")
	if night >= 4:
		opts.append("inspector")
	match opts[rng.randi() % opts.size()]:
		"breaker":
			world.trip_breaker(["A1", "A2", "A3", "A4"][rng.randi() % 4])
		"maglock":
			world.maglock_fail()
		"courier":
			if world.entities.has("courier"):
				world.entities["courier"].activate()
		"woman":
			if world.entities.has("woman"):
				world.entities["woman"].request()
		"inspector":
			if world.entities.has("inspector"):
				world.entities["inspector"].behind_event()
	_log("harm", "followup")


# ------------------------------------------------------------------ Страх игрока

func _update_fear(delta: float) -> void:
	var p: Player = world.player
	var near := 0.0
	for e in world.entities.values():
		var ent := e as Entity
		if ent.visible and ent.active:
			var d := ent.global_position.distance_to(p.global_position)
			near = maxf(near, clampf(1.0 - d / 8.0, 0.0, 1.0))
	var dark := 0.0 if world.level.lighting.is_zone_lit(Level.room_zone(p.current_room)) else 0.25
	var target := clampf(tension * 0.35 + near * 0.7 + dark, 0.0, 1.0)
	fear = lerpf(fear, target, delta * 1.5)


func _log(kind: String, detail: String) -> void:
	event_log.append([snappedf(_time, 0.1), kind, detail])
	if event_log.size() > 300:
		event_log.pop_front()
