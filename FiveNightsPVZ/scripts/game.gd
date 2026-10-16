class_name GameWorld
extends Node3D
## Корневой узел игровой сцены: собирает уровень, игрока, системы и сущностей,
## маршрутизирует события между ними.

signal night_finished(win)

static var instance: GameWorld

var level: Level
var player: Player
var night: NightController
var director: HorrorDirector
var orders: OrderSystem
var cctv: CCTVSystem
var hud: HUD
var desk: DeskUI
var touch: TouchControls
var jumpscare: Jumpscare
var env: WorldEnvironment
var entities := {}
var clients: Array = []
var night_index := 1
var game_over := false
var phone_ringing := false
var _phone_call := 0
var _phone_player: AudioStreamPlayer3D
var _receipt_text := ""
var _fps_t := 0.0
var _fps_low := 0.0
var _fps_high := 0.0
var _clothes_sizes := ["42", "44", "46", "48", "50", "52"]
var stare_value := 0.0
var headless_test := false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	night_index = GameState.current_night
	_build_environment()
	level = Level.new()
	level.name = "Level"
	add_child(level)
	level.build(1979)
	level.apply_quality(GameState.quality())
	_build_clothes()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = level.spawn["player"]
	player.rotation.y = PI  # лицом к стойке/залу
	orders = OrderSystem.new()
	orders.name = "Orders"
	add_child(orders)
	night = NightController.new()
	night.name = "Night"
	add_child(night)
	director = HorrorDirector.new()
	director.name = "Director"
	add_child(director)
	cctv = CCTVSystem.new()
	cctv.name = "CCTV"
	add_child(cctv)
	cctv.setup(self)
	orders.setup(self, night_index, GameState.run_seed)
	orders.order_issued.connect(on_order_issued)
	orders.card_opened.connect(_on_card_opened)
	night.setup(self, night_index)
	_spawn_entities()
	director.setup(self, night_index)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
	desk = DeskUI.new()
	desk.name = "Desk"
	add_child(desk)
	desk.setup(self)
	touch = TouchControls.new()
	touch.name = "Touch"
	add_child(touch)
	touch.setup(self)
	jumpscare = Jumpscare.new()
	jumpscare.name = "Jumpscare"
	add_child(jumpscare)
	jumpscare.setup(self)
	GameState.settings_changed.connect(_on_settings)
	_on_settings()
	if not headless_test:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not GameState.use_touch_controls() else Input.MOUSE_MODE_VISIBLE
	level.compute_camera_coverage.call_deferred()
	hud.show_intro(night_index)
	await get_tree().create_timer(0.1).timeout
	night.start()


func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.36, 0.45)
	e.ambient_light_energy = 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.06, 0.08)
	e.fog_density = 0.035
	e.glow_enabled = GameState.quality() >= 1
	e.glow_intensity = 0.5
	e.glow_bloom = 0.05
	env.environment = e
	add_child(env)


func _on_settings() -> void:
	if level:
		level.apply_quality(GameState.quality())
	if env:
		env.environment.glow_enabled = GameState.quality() >= 1
		env.environment.ambient_light_energy = 0.2 + 0.1 * (float(GameState.settings["brightness"]) - 1.0)


func _spawn_entities() -> void:
	var defs := {"faceless": Faceless, "woman": FittingWoman, "courier": Courier, "returner": Returner, "inspector": Inspector}
	for id in defs.keys():
		var e: Entity = defs[id].new()
		e.name = id.capitalize()
		add_child(e)
		e.setup(self, id, NightData.aggression(night_index, id))
		entities[id] = e


func _build_clothes() -> void:
	for i in _clothes_sizes.size():
		_spawn_clothes(i)


func _spawn_clothes(i: int) -> void:
	var b := CarryBox.new()
	b.size_label = _clothes_sizes[i]
	b.build(Vector3(0.08, 0.9, 0.45), "clothes")
	b.box_id = "clothes_" + b.size_label
	level.clothes_rail.add_child(b)
	b.position = Vector3(0, 0.85, 0.2 + i * 0.38)
	b.rotation.y = PI * 0.5


# ------------------------------------------------------------------ Служебное

func _process(delta: float) -> void:
	_adaptive_quality(delta)
	if Input.is_action_just_pressed("pause") and not game_over and not desk.visible and not jumpscare.active and Engine.get_process_frames() != _desk_closed_frame and not hud.paused:
		hud.toggle_pause()


func _adaptive_quality(delta: float) -> void:
	_fps_t += delta
	if _fps_t < 1.0:
		return
	_fps_t = 0.0
	var fps := Engine.get_frames_per_second()
	var target := 30.0 if OS.has_feature("mobile") else 50.0
	if fps < target - 5:
		_fps_low += 1
		_fps_high = 0
	elif fps > target + 15:
		_fps_high += 1
		_fps_low = 0
	if _fps_low >= 4:
		GameState.adapt_quality(-1)
		_fps_low = 0
	elif _fps_high >= 10:
		GameState.adapt_quality(1)
		_fps_high = 0


func emit_noise(pos: Vector3, loudness: float, source: String) -> void:
	if director:
		director.on_noise(pos, loudness, source)


func hud_message(text: String, duration := 3.0) -> void:
	if hud:
		hud.message(text, duration)


func subtitle(text: String, duration := 4.0) -> void:
	if hud and GameState.settings.get("subtitles", true):
		hud.subtitle(text, duration)


func show_document(title: String, body: String) -> void:
	if hud:
		hud.show_document(title, body)


func on_item_picked(box: CarryBox) -> void:
	if box.kind == "clothes":
		var idx := _clothes_sizes.find(box.size_label)
		if idx >= 0:
			get_tree().create_timer(25.0).timeout.connect(func():
				if is_instance_valid(level) and not _rail_has(box.size_label):
					_spawn_clothes(idx))


func _rail_has(size: String) -> bool:
	for c in level.clothes_rail.get_children():
		if c is CarryBox and (c as CarryBox).size_label == size:
			return true
	return false


# ------------------------------------------------------------------ Клиенты

func spawn_client(kind: String) -> void:
	var c := Client.new()
	c.name = "Client%d" % clients.size()
	add_child(c)
	c.setup(self, "client", 1)
	c.begin(kind)
	clients.append(c)


func on_counter_item(box: CarryBox) -> void:
	orders.on_counter_item(box)


func _on_card_opened(card: Dictionary) -> void:
	for c in clients:
		if is_instance_valid(c) and c.card == card:
			c.on_card_opened()
	if entities["faceless"].card == card:
		entities["faceless"].on_card_opened()


func on_order_issued(card: Dictionary) -> void:
	for c in clients:
		if is_instance_valid(c) and c.card == card:
			c.on_issued()
			return
	if entities["faceless"].card == card:
		entities["faceless"].on_issued()


func on_task_expired(t: Dictionary) -> void:
	match t["kind"]:
		"issue":
			var card: Dictionary = t["data"].get("card", {})
			orders.cancel_card(card.get("no", ""))
			for c in clients:
				if is_instance_valid(c) and c.card == card:
					c.leave_unserved()
			if entities["faceless"].card == card:
				entities["faceless"].on_timeout()
		"woman":
			entities["woman"].on_timeout()
		"return":
			entities["returner"].on_timeout()


# ------------------------------------------------------------------ Телефон, принтер

func ring_phone(call_index: int) -> void:
	if phone_ringing:
		return
	phone_ringing = true
	_phone_call = call_index
	level.phone.enabled = true
	_phone_player = Sfx.play_3d("phone", level.phone.global_position, -6.0, 1.0, 30.0)
	if _phone_player:
		_phone_player.stream = Sfx.get_stream("phone")
		_phone_player.finished.disconnect(_phone_player.queue_free)
	get_tree().create_timer(22.0).timeout.connect(_stop_phone)


func _stop_phone() -> void:
	phone_ringing = false
	level.phone.enabled = false
	if is_instance_valid(_phone_player):
		_phone_player.queue_free()


func answer_phone() -> void:
	if not phone_ringing:
		return
	_stop_phone()
	Sfx.play_3d("click", level.phone.global_position, -8.0)
	var text: String = Story.PHONE_CALLS[clampi(_phone_call, 0, Story.PHONE_CALLS.size() - 1)]
	if text.contains("%s"):
		text = text % GameState.player_name()
	subtitle(text, 8.0)
	Sfx.play_3d("whisper", level.phone.global_position, -14.0, 0.8)
	director.on_phone_answered(_phone_call)


func print_receipt(text: String) -> void:
	_receipt_text = text
	Sfx.play_3d("printer", level.printer.global_position, -6.0)
	level.printer.enabled = true


func take_receipt() -> void:
	if _receipt_text == "":
		return
	level.printer.enabled = false
	show_document("Чек из принтера", _receipt_text)
	_receipt_text = ""


# ------------------------------------------------------------------ Электрика и замок

func trip_breaker(id: String) -> void:
	if not level.lighting.breakers.get(id, true):
		return
	level.lighting.trip_breaker(id)
	Sfx.play_3d("breaker", Vector3(17.8, 1.5, 5.6), 0.0, 1.0, 30.0)
	var zones: Array = Lighting.BREAKERS.get(id, [])
	var names := PackedStringArray()
	for z in zones:
		names.append(Lighting.ZONE_NAMES[z])
	var t := night.add_task("breaker", "Восстановить питание (щиток в подсобке): %s" % ", ".join(names), -1.0, {"id": id})
	t["no_penalty"] = true


func reset_breakers() -> void:
	var tripped := level.lighting.tripped_breakers()
	if tripped.is_empty():
		hud_message("Все автоматы включены.")
		return
	if night.finale and night.minute() < 345.0:
		Sfx.play_3d("relay", player.global_position, -6.0)
		hud_message("Автоматы не держат. Что-то тянет ток.")
		return
	for b in tripped:
		level.lighting.set_breaker(b, true)
	Sfx.play_3d("breaker", Vector3(17.8, 1.5, 5.6), -6.0, 1.3)
	var t := night.find_task("breaker")
	while not t.is_empty():
		night.complete_task(t)
		t = night.find_task("breaker")


func maglock_fail() -> void:
	var d: Door = level.doors["front"]
	if not d.locked:
		return
	d.locked = false
	_update_maglock_led()
	Sfx.play_3d("relay", level.maglock.global_position, -4.0, 1.0, 25.0)
	director.on_door_unlocked()


func toggle_maglock() -> void:
	var d: Door = level.doors["front"]
	if d.locked:
		d.locked = false
		hud_message("Магнитный замок отключён.")
		director.on_door_unlocked()
	else:
		if d.is_open:
			d.set_open(false)
		d.locked = true
		hud_message("Магнитный замок включён.")
	Sfx.play_3d("relay", level.maglock.global_position, -6.0)
	_update_maglock_led()


func _update_maglock_led() -> void:
	var led := level.maglock.get_node_or_null("Led") as MeshInstance3D
	if led == null:
		return
	var locked: bool = level.doors["front"].locked
	led.material_override = Mats.emissive(Color(1, 0.1, 0.1) if locked else Color(0.1, 1, 0.2), 3.0)
	level.maglock.prompt_text = "Отключить магнитный замок" if locked else "Включить магнитный замок"


# ------------------------------------------------------------------ Ночь 5

var _drawer: Interactable


func enable_tech_key() -> void:
	_drawer = Interactable.new()
	_drawer.position = Vector3(9.9, 0.85, 9.78)
	level.add_child(_drawer)
	Build.box(_drawer, Vector3(0.4, 0.12, 0.05), Vector3.ZERO, Mats.color(Color(0.5, 0.48, 0.45)))
	_drawer.setup_shape(Vector3(0.45, 0.2, 0.15))
	_drawer.prompt_text = "Открыть ящик стойки"
	_drawer.action = func(_p):
		night.tech_key_taken = true
		level.doors["tech"].locked = false
		_drawer.enabled = false
		Sfx.play_3d("handle", _drawer.global_position, -6.0, 1.4)
		hud_message("Ключ от технического помещения. Бирка: «Ключников».", 5.0)


func on_own_order_arrived() -> void:
	for o in orders.orders:
		if o.get("kind", "") == "player":
			o["status"] = "Прибыл. Ожидает получения"
	hud_message("Компьютер: «Ваш заказ прибыл в пункт выдачи».", 5.0)
	Sfx.play_ui("beep", -8.0, 0.7)
	var sign := Interactable.new()
	level.own_box.add_child(sign)
	sign.setup_shape(Vector3(0.8, 0.7, 0.6), Vector3(0, 0.3, 0))
	sign.prompt_text = "Расписаться в получении"
	sign.action = func(_p): end_night(false, "received")


func start_finale() -> void:
	director.start_finale()
	for b in Lighting.BREAKERS.keys():
		level.lighting.trip_breaker(b)
	Sfx.play_3d("breaker", Vector3(17.8, 1.5, 5.6), 0.0, 0.8, 40.0)
	hud_message("Свет пропал во всём здании.", 4.0)


func open_tech_terminal() -> void:
	if night_index != 5 or GameState.is_custom_night:
		show_document("Терминал «Стол заказов № 7»", "НЕТ СВЯЗИ С БАЗОЙ.\n\n> _")
		return
	hud.open_terminal()


func submit_terminal_code(code: String) -> void:
	if code.strip_edges() != Story.CANCEL_CODE:
		Sfx.play_ui("beep", -8.0, 0.5)
		hud_message("НЕВЕРНАЯ ДАТА.")
		return
	if not GameState.has_all_documents():
		show_document("Терминал", "ОТМЕНА ВОЗМОЖНА ТОЛЬКО ДЛЯ ВЫДАННОГО ЗАКАЗА.\nНЕДОСТАТОЧНО ДАННЫХ О ПОЛУЧАТЕЛЕ.\n\n(Найдено документов: %d из %d)" % [(GameState.data["documents"] as Array).size(), GameState.DOCUMENT_COUNT])
		return
	end_night(true, "returned")


# ------------------------------------------------------------------ Рабочее место

func open_desk() -> void:
	if game_over or player.seated:
		return
	player.sit(level.spawn["seat"], level.pc_screen.global_position)
	desk.open()
	if not GameState.use_touch_controls():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


var _desk_closed_frame := -1


func close_desk() -> void:
	_desk_closed_frame = Engine.get_process_frames()
	desk.close()
	cctv.set_active(false)
	player.stand()
	if not GameState.use_touch_controls() and not headless_test:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ Итог

func kill_player(entity_id: String, hint: String) -> void:
	if game_over:
		return
	game_over = true
	night.running = false
	if player.seated:
		desk.close()
		cctv.set_active(false)
	player.controls_locked = true
	GameState.register_death(entity_id)
	jumpscare.play(entity_id, entities.get(entity_id))
	await jumpscare.finished
	hud.show_game_over(entity_id, hint)


func fired() -> void:
	if game_over:
		return
	game_over = true
	night.running = false
	player.controls_locked = true
	GameState.register_death("fired")
	hud.show_game_over("fired", "Три нарушения за смену. Выполняйте задания и не путайте настоящие письма с поддельными.")


func end_night(win: bool, ending: String) -> void:
	if game_over:
		return
	game_over = true
	night.running = false
	player.controls_locked = true
	if player.seated:
		desk.close()
	var n := night_index
	if ending == "received":
		GameState.unlock_ending("received")
		hud.show_ending("received")
	elif ending == "returned":
		GameState.complete_night(n, night.violations, night.used_cameras)
		GameState.unlock_ending("returned")
		hud.show_ending("returned")
	elif win:
		GameState.complete_night(n, night.violations, night.used_cameras)
		if n == 5 and not GameState.is_custom_night:
			GameState.unlock_ending("shift_over")
			hud.show_ending("shift_over")
		else:
			hud.show_night_complete(n, night.violations)
	night_finished.emit(win)
