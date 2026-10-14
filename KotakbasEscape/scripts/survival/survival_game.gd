class_name SurvivalGame
extends Node3D
## Глава 3. «Лес Котакбаса» — выживание в открытом мире.
## Связывает все системы: время, погоду, характеристики, ресурсы, крафт,
## строительство, ИИ, сюжет, налёты НЛО ТЦК, сохранения и сенсорное управление.

const START_POS := Vector3(0, 0, 78)
const START_TIME := 480.0 # 08:00 первого дня

var time_min := START_TIME
var time_mult := 1.0
var is_sleeping := false
var sleep_until := 0.0
var aiming := false

var terrain: SurvivalTerrain
var player: SurvivalPlayer
var stats := SurvivalStats.new()
var inventory := Inventory.new(20)
var buildings: BuildingSystem
var crafting: CraftingSystem
var creatures: CreatureSpawner
var quests: QuestManager
var events: RandomEvents
var ufo_manager: UFOSpawnManager
var pois: WorldPOIs
var weather: WeatherSystem
var day_night: DayNight
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var water: MeshInstance3D

var hud_layer: CanvasLayer
var hud: SurvivalHUD
var controls: TouchControls
var attack_ui: UFOAttackUI
var dialogue: DialogueBox
var menu_layer: CanvasLayer
var _open_menu: Control
var _pause: PauseMenu

var hotbar_index := 0
var respawn_point := Vector3.INF
var drops: Array = [] # [{node, items}]
var stone_piles: Array[Node3D] = []
var _interact_target = null # Interactable | Dictionary(ресурс) | "water"
var _interact_t := 0.0
var _attack_cd := 0.0
var _throw_cd := 0.0
var _autosave_t := 0.0
var _autosave_soon := -1.0
var _pile_t := 0.0
var _shake := 0.0
var _dialog_open := false
var _ending := false
var _traj: MultiMeshInstance3D
var _dead := false
var _intro_done := false

# ================================================================== Инициализация

func _ready() -> void:
	_build_environment()
	terrain = SurvivalTerrain.new()
	terrain.time_source = func(): return time_min
	add_child(terrain)
	var saved: Dictionary = GameManager.state.get("survival", {})
	var fresh := saved.is_empty() or not saved.has("time")
	if not fresh:
		terrain.load_data(saved.get("terrain", {}))
	# Игрок
	player = SurvivalPlayer.new()
	player.stats = stats
	add_child(player)
	stats.setup_from_difficulty()
	# Системы
	buildings = BuildingSystem.new()
	add_child(buildings)
	buildings.setup(self, terrain)
	buildings.crate_opened.connect(_open_crate)
	crafting = CraftingSystem.new()
	add_child(crafting)
	crafting.setup(self)
	creatures = CreatureSpawner.new()
	add_child(creatures)
	creatures.setup(self, terrain, player)
	quests = QuestManager.new()
	add_child(quests)
	events = RandomEvents.new()
	add_child(events)
	ufo_manager = UFOSpawnManager.new()
	add_child(ufo_manager)
	ufo_manager.setup(self)
	ufo_manager.warning.connect(_on_ufo_warning)
	ufo_manager.raid_started.connect(_on_raid_started)
	ufo_manager.raid_ended.connect(_on_raid_ended)
	day_night = DayNight.new()
	add_child(day_night)
	day_night.setup(sun, env, sky_mat)
	weather = WeatherSystem.new()
	add_child(weather)
	weather.setup(env, day_night, player)
	weather.weather_changed.connect(func(k): events.on_weather(k))
	pois = WorldPOIs.new()
	add_child(pois)
	_build_ui()
	if GameManager.state.flags.get("has_backpack", false) or int(GameManager.state.carry_items.get("backpack", 0)) > 0:
		inventory.resize(30)
	if fresh:
		_new_survival()
	else:
		_load_survival(saved)
	terrain.load_around_now(player.global_position)
	_snap_player_to_ground()
	inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed()
	GameManager.back_requested.connect(_on_back)
	GameManager.app_paused.connect(_on_app_paused)
	_update_music(true)
	weather._apply_sound()
	_build_trajectory()

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 2.2 / Settings.view_distance()
	env.fog_sky_affect = 0.6
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Settings.shadows_enabled()
	sun.directional_shadow_max_distance = 35.0 if Settings.quality() < Settings.Quality.HIGH else 55.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	# Вода: одна плоскость на весь мир на уровне реки/болота
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(520, 520)
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	water.material_override = wm
	water.position.y = SurvivalTerrain.WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _build_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = SurvivalHUD.new()
	hud_layer.add_child(hud)
	hud.setup(self)
	attack_ui = UFOAttackUI.new()
	hud_layer.add_child(attack_ui)
	attack_ui.setup(self)
	controls = TouchControls.new()
	hud_layer.add_child(controls)
	controls.button_pressed.connect(_on_button_pressed)
	controls.button_released.connect(_on_button_released)
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	dialogue = DialogueBox.new()
	menu_layer.add_child(dialogue)

func _new_survival() -> void:
	time_min = START_TIME
	var p := START_POS
	player.global_position = Vector3(p.x, terrain.height(p.x, p.z) + 0.5, p.z)
	player.yaw = 0.0
	player.look(Vector2.ZERO)
	stats.health = 80.0
	# Перенос предметов из новеллы и раннера
	var carry: Dictionary = GameManager.state.carry_items
	for k in carry:
		if k != "backpack" and ItemDB.ITEMS.has(k) and int(carry[k]) > 0:
			inventory.add(k, int(carry[k]))
	inventory.add("stone", 2)
	quests.setup(self, {})
	events.setup(self, {})
	pois.setup(self, terrain, {})
	ufo_manager.init_first(time_min)
	_intro_sequence()

func _intro_sequence() -> void:
	player.frozen = true
	player.set_third_person(true)
	player.model.play("fall", 2.5)
	await get_tree().create_timer(1.2).timeout
	subtitle("Котакбас: Где я?.. Кусты. Лес. Ни одного человека в форме. Идеально.")
	await get_tree().create_timer(2.2).timeout
	player.set_third_person(false)
	player.frozen = false
	_intro_done = true
	subtitle("Подсказка: джойстик слева — ходьба, свайп справа — обзор. «Удар» рубит деревья.")
	autosave_soon()

func _load_survival(d: Dictionary) -> void:
	time_min = float(d.get("time", START_TIME))
	var pp: Array = d.get("player_pos", [START_POS.x, 0, START_POS.z])
	player.global_position = Vector3(pp[0], pp[1], pp[2])
	player.yaw = float(d.get("player_yaw", 0.0))
	player.pitch = float(d.get("player_pitch", 0.0))
	player.look(Vector2.ZERO)
	player.set_third_person(d.get("third_person", false))
	stats.from_dict(d.get("stats", {}))
	inventory.from_array(d.get("inventory", []))
	hotbar_index = int(d.get("hotbar", 0))
	var rp = d.get("respawn", null)
	if rp is Array:
		respawn_point = Vector3(rp[0], rp[1], rp[2])
	buildings.load_data(d.get("buildings", []))
	crafting.load_data(d.get("crafting", {}))
	quests.setup(self, d.get("quests", {}))
	events.setup(self, d.get("events", {}))
	pois.setup(self, terrain, d.get("pois", {}))
	weather.kind = str(d.get("weather", "clear"))
	weather.next_change = float(d.get("weather_next", 240.0))
	ufo_manager.load_data(d.get("ufo", {}))
	ufo_manager.init_first(time_min)
	for dr in d.get("drops", []):
		var dp: Array = dr.pos
		_spawn_drop(dr.items, Vector3(dp[0], dp[1], dp[2]))
	_intro_done = true
	# Налёт, который шёл во время сохранения, продолжается.
	call_deferred("_restore_raid", d.get("ufo", {}))

func _restore_raid(u: Dictionary) -> void:
	ufo_manager.restore_active(u)

func _snap_player_to_ground() -> void:
	var p := player.global_position
	var h := terrain.height(p.x, p.z)
	if p.y < h + 0.2:
		player.global_position.y = h + 0.5

# ================================================================== Сохранение

func save_state() -> Dictionary:
	var p := player.global_position
	var drop_data := []
	for dr in drops:
		if is_instance_valid(dr.node):
			var np: Vector3 = dr.node.global_position
			drop_data.append({"pos": [np.x, np.y, np.z], "items": dr.items})
	return {
		"time": time_min,
		"player_pos": [p.x, p.y, p.z],
		"player_yaw": player.yaw,
		"player_pitch": player.pitch,
		"third_person": player.third_person,
		"stats": stats.to_dict(),
		"inventory": inventory.to_array(),
		"hotbar": hotbar_index,
		"respawn": [respawn_point.x, respawn_point.y, respawn_point.z] if respawn_point != Vector3.INF else null,
		"buildings": buildings.save_data(),
		"crafting": crafting.save_data(),
		"quests": quests.save_data(),
		"events": events.save_data(),
		"pois": pois.save_data(),
		"terrain": terrain.save_data(),
		"weather": weather.kind,
		"weather_next": weather.next_change,
		"ufo": ufo_manager.save_data(),
		"drops": drop_data,
	}

func autosave_soon() -> void:
	_autosave_soon = 1.0

# ================================================================== Цикл

func is_paused_gameplay() -> bool:
	return get_tree().paused or _dialog_open or _ending or _dead

func is_night() -> bool:
	return DayNight.is_night(time_min)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if not _dialog_open and not _ending:
		var dt_min := delta * DayNight.MINUTES_PER_SECOND * time_mult
		time_min += dt_min
		stats.tick(dt_min, env_temperature(), is_sleeping)
		weather.tick(dt_min, time_min)
		events.tick(dt_min)
		ufo_manager.tick(time_min)
		_tick_sleep()
	day_night.apply(time_min)
	terrain.update_around(player.global_position)
	water.global_position = Vector3(snappedf(player.global_position.x, 8.0), SurvivalTerrain.WATER_LEVEL, snappedf(player.global_position.z, 8.0))
	_handle_input(delta)
	_interact_t -= delta
	if _interact_t <= 0.0:
		_interact_t = 0.15
		_update_interact()
	_attack_cd -= delta
	_throw_cd -= delta
	if aiming:
		_update_trajectory()
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		player.active_camera().h_offset = randf_range(-1, 1) * _shake * 0.15
		player.active_camera().v_offset = randf_range(-1, 1) * _shake * 0.15
	if stats.is_dead() and not _dead:
		_on_death()
	# Автосохранение каждые 3 игровых часа и после важных событий
	_autosave_t += delta * time_mult
	if _autosave_t > 180.0 and not is_sleeping:
		_autosave_t = 0.0
		GameManager.autosave()
	if _autosave_soon > 0.0:
		_autosave_soon -= delta
		if _autosave_soon <= 0.0 and not ufo_manager.is_raid_active():
			GameManager.autosave()
	if ufo_manager.is_raid_active():
		_tick_stone_supply(delta)
	if Engine.get_process_frames() % 30 == 0:
		_update_music(false)
		_check_shelter_quest_hint()

func env_temperature() -> float:
	var t := DayNight.base_temperature(time_min) + weather.temperature_mod()
	var p := player.global_position
	if buildings.near_fire(p, 5.5):
		t += 14.0
	if buildings.is_under_roof(p):
		t += 6.0
	if player.in_water:
		t -= 6.0
	if is_sleeping:
		t += 4.0
	return t

func _update_music(force: bool) -> void:
	if ufo_manager.is_raid_active():
		AudioManager.play_music("ufo")
	elif is_night():
		AudioManager.play_music("survival_night")
	else:
		AudioManager.play_music("survival_day")

func _check_shelter_quest_hint() -> void:
	pass

# ================================================================== Ввод

func _handle_input(delta: float) -> void:
	var menu_open := is_instance_valid(_open_menu) or _dialog_open or is_sleeping or _ending or _dead
	controls.enabled = not menu_open
	controls.visible = not (is_sleeping or _ending)
	if menu_open:
		player.input_move = Vector2.ZERO
		return
	var mv := controls.move_vec
	# Клавиатура (отладка на ПК)
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if kb.length() > 0.1:
		mv = kb
	player.input_move = mv if not player.frozen else Vector2.ZERO
	var look := controls.consume_look()
	if look != Vector2.ZERO and not player.frozen:
		player.look(look)
	if controls.is_held("attack") and _attack_cd <= 0.0 and not buildings.is_active():
		_attack()

func _on_button_pressed(id: String) -> void:
	match id:
		"attack":
			_attack()
		"jump":
			player.try_jump()
		"crouch":
			player.set_crouch(not player.crouching)
			controls.set_label("crouch", "Встать" if player.crouching else "Присесть")
		"interact":
			_do_interact()
		"throw":
			_start_aim()
		"use":
			var s = inventory.slots[hotbar_index]
			if s != null:
				use_item_slot(inventory, hotbar_index)
		"pause":
			_open_pause()
		"inv":
			_open_inventory(null)
		"craft":
			open_crafting("")
		"build":
			_open_build_menu()
		"cam":
			player.set_third_person(not player.third_person)
			AudioManager.play_sfx("click")
		"map":
			_open_overlay(_make_map())
		"place":
			if buildings.confirm():
				_on_built()
		"rotate":
			buildings.rotate_piece()
		"cancel":
			buildings.cancel()
			controls.set_build_mode(false)
		"pieces":
			_open_build_menu()
		_:
			if id.begins_with("hot"):
				select_hotbar(int(id.substr(3)))

func _on_button_released(id: String) -> void:
	if id == "throw" and aiming:
		_release_throw()

func select_hotbar(i: int) -> void:
	hotbar_index = clampi(i, 0, 5)
	controls.hotbar_selected = hotbar_index
	AudioManager.play_sfx("click", -10.0)
	_on_inventory_changed()

func selected_item() -> String:
	var s = inventory.slots[hotbar_index]
	return "" if s == null else str(s.id)

func _on_inventory_changed() -> void:
	var items := []
	for i in 6:
		items.append(inventory.slots[i])
	controls.hotbar_items = items
	controls.hotbar_selected = hotbar_index
	var sel := selected_item()
	controls.set_visible_button("throw", ItemDB.get_item(sel).get("throwable", false) if sel != "" else false)
	var item := ItemDB.get_item(sel) if sel != "" else {}
	var usable: bool = item.has("food")
	controls.set_visible_button("use", usable and not buildings.is_active())
	if usable:
		var verb := "Съесть"
		if item.type == "medical":
			verb = "Лечить"
		elif item.food.has("thirst") and not item.food.has("hunger"):
			verb = "Выпить"
		controls.set_label("use", verb)
	controls.queue_redraw()

# ================================================================== Взаимодействие

func _update_interact() -> void:
	_interact_target = null
	var text := ""
	if player.frozen:
		controls.set_visible_button("interact", false)
		return
	var pos := player.global_position + Vector3(0, 1.0, 0)
	var fwd := player.forward()
	var best_d := 99.0
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.is_inside_tree():
			continue
		var t := it.get_text()
		if t == "":
			continue
		var to := it.global_position - pos
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length()
		if d > it.radius or absf(to.y) > 2.5:
			continue
		if d > 0.8 and fwd.dot(flat.normalized()) < 0.2:
			continue
		if d < best_d:
			best_d = d
			_interact_target = it
			text = t
	if _interact_target == null:
		var res := terrain.find_resource(player.global_position, fwd, 2.4)
		if not res.is_empty():
			_interact_target = res
			text = _resource_text(res.kind)
	if _interact_target == null:
		var wp := player.global_position + fwd * 1.8
		if terrain.height(wp.x, wp.z) < SurvivalTerrain.WATER_LEVEL - 0.05:
			_interact_target = "water"
			text = "Попить и набрать воды"
	controls.set_visible_button("interact", text != "")
	controls.set_label("interact", text)

func _resource_text(kind: String) -> String:
	match kind:
		"tree", "pine", "dead": return "Рубить дерево"
		"rock": return "Бить камень"
		"bush": return "Собрать ягоды"
		"stone": return "Подобрать камень"
		"mushroom": return "Сорвать гриб"
		"scrap": return "Разобрать хлам"
		"reeds": return "Нарвать камыш"
	return "Собрать"

func _do_interact() -> void:
	var t = _interact_target
	if t == null:
		return
	if t is Interactable:
		t.interact()
		AudioManager.play_sfx("click", -8.0)
	elif t is Dictionary:
		_harvest(t, 1.0, true)
	elif t is String and t == "water":
		collect_water(true)
	_interact_t = 0.0

func _harvest(res: Dictionary, base_power: float, from_interact: bool) -> void:
	var tool := selected_item()
	var power := base_power
	var kind: String = res.kind
	if kind in ["tree", "pine", "dead"] and tool == "axe":
		power *= 2.0
	if kind == "rock" and tool == "pickaxe":
		power *= 2.0
	var drop := terrain.hit_resource(res, power)
	match kind:
		"tree", "pine", "dead":
			AudioManager.play_sfx("chop", -2.0)
		"rock", "scrap":
			AudioManager.play_sfx("mine", -2.0)
		_:
			AudioManager.play_sfx("pickup", -4.0)
	player.model.play("attack")
	if drop.is_empty() or drop.has("partial"):
		return
	drop_or_add(drop)
	_interact_t = 0.0

func collect_water(from_river: bool) -> void:
	AudioManager.play_sfx("drink")
	stats.apply_food({"thirst": 25.0, "health": -2.0 if from_river and DifficultyManager.level() >= 2 else 0.0})
	var item := "water_dirty" if from_river else "water_clean"
	var left := inventory.add(item, 1)
	subtitle("Котакбас попил и набрал воды." if left == 0 else "Котакбас попил. Набрать некуда — инвентарь полон.")

func drop_or_add(items: Dictionary) -> void:
	var parts := []
	for k in items:
		var n := int(items[k])
		var left := inventory.add(k, n)
		if left > 0:
			drop_items(k, left, player.global_position + player.forward() * 1.2)
		parts.append("%s +%d" % [ItemDB.item_name(k), n])
	if not parts.is_empty():
		GameManager.toast(", ".join(parts), UIStyle.GOOD, 1.2)
		AudioManager.play_sfx("pickup", -4.0)

# --- Выброшенные предметы (мешки на земле)

func drop_items(id: String, n: int, pos: Vector3) -> void:
	drop_items_dict({id: n}, pos)

func drop_items_dict(items: Dictionary, pos: Vector3) -> void:
	if items.is_empty():
		return
	var p := Vector3(pos.x, terrain.height(pos.x, pos.z), pos.z)
	_spawn_drop(items.duplicate(), p)

func _spawn_drop(items: Dictionary, p: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	MK.sphere(n, 0.32, Color(0.6, 0.45, 0.3), Vector3(0, 0.28, 0), 7).scale = Vector3(1, 0.85, 1)
	MK.box(n, Vector3(0.12, 0.2, 0.12), Color(0.5, 0.35, 0.2), Vector3(0, 0.62, 0))
	var it := Interactable.new()
	it.position.y = 0.5
	it.radius = 2.4
	n.add_child(it)
	var entry := {"node": n, "items": items}
	var first: String = items.keys()[0]
	it.label = "Подобрать: %s%s" % [ItemDB.item_name(first), "…" if items.size() > 1 else ""]
	it.action = func():
		var rest := {}
		for k in entry.items:
			var left := inventory.add(k, int(entry.items[k]))
			if left > 0:
				rest[k] = left
		AudioManager.play_sfx("pickup")
		if rest.is_empty():
			drops.erase(entry)
			n.queue_free()
		else:
			entry.items = rest
			GameManager.toast("Инвентарь полон", UIStyle.BAD, 1.0)
	drops.append(entry)

func use_item_slot(inv: Inventory, i: int) -> void:
	var s = inv.slots[i]
	if s == null:
		return
	var item := ItemDB.get_item(s.id)
	if not item.has("food"):
		return
	inv.remove_from_slot(i, 1)
	stats.apply_food(item.food)
	AudioManager.play_sfx("drink" if item.food.has("thirst") and not item.food.has("hunger") else "eat")
	if s.id == "pryanik":
		subtitle("Котакбас: Тульский пряник — топливо чемпионов.")

# ================================================================== Бой

func _attack() -> void:
	if _attack_cd > 0.0 or player.frozen:
		return
	_attack_cd = 0.45
	player.model.play("attack")
	AudioManager.play_sfx("swipe", -8.0)
	var pos := player.global_position + Vector3(0, 1.0, 0)
	var tool := selected_item()
	var dmg := 8.0
	if tool != "":
		dmg = float(ItemDB.get_item(tool).get("damage", 8.0))
	var c := creatures.target_in_front(player.global_position, player.forward(), 2.6)
	if c != null:
		c.take_damage(dmg, player.global_position)
		_shake = 0.2
		GameManager.vibrate(25)
		return
	var res := terrain.find_resource(player.global_position, player.forward(), 2.4)
	if not res.is_empty() and res.kind in ["tree", "pine", "dead", "rock", "scrap"]:
		_harvest(res, 1.0, false)

func damage_player(amount: float, msg := "") -> void:
	if is_sleeping:
		_wake_up("Котакбаса разбудили. Не по-доброму.")
	stats.health = maxf(0.0, stats.health - amount)
	hud.flash_damage()
	AudioManager.play_sfx("hurt", -2.0)
	GameManager.vibrate(80)
	_shake = 0.35
	if msg != "":
		subtitle(msg, 2.0)

func camera_shake(amount: float) -> void:
	_shake = amount

func _on_death() -> void:
	_dead = true
	aiming = false
	controls.release_all()
	subtitle("Котакбас отключился... Очнулся он уже в другом месте.", 4.0)
	await SceneManager.fade_out(0.8)
	var bed := buildings.nearest_bed(player.global_position)
	var p: Vector3
	if not bed.is_empty():
		p = bed.pos + Vector3(1.5, 0.5, 0)
	elif respawn_point != Vector3.INF:
		p = respawn_point
	else:
		var c: Vector2 = SurvivalTerrain.REGIONS.clearing.c
		p = Vector3(c.x, terrain.height(c.x, c.y) + 0.5, c.y)
	terrain.load_around_now(p)
	player.global_position = p + Vector3(0, 0.5, 0)
	player.velocity = Vector3.ZERO
	stats.health = 60.0
	stats.hunger = maxf(stats.hunger, 50.0)
	stats.thirst = maxf(stats.thirst, 50.0)
	stats.body_temp = 36.6
	time_min += 120.0
	creatures.clear_all()
	_dead = false
	await SceneManager.fade_in(0.8)

# ================================================================== Бросок камней

func _start_aim() -> void:
	if inventory.count("stone") <= 0 or selected_item() != "stone":
		subtitle("Нет камней! Ищи на земле.", 1.5)
		return
	aiming = true
	_traj.visible = true
	player.model.play("aim")
	player.active_camera().fov = 60.0

func _release_throw() -> void:
	aiming = false
	_traj.visible = false
	player.active_camera().fov = 72.0 if not player.third_person else 70.0
	if player.model.anim == "aim":
		player.model.play("throw")
	if _throw_cd > 0.0 or inventory.count("stone") <= 0:
		return
	_throw_cd = 0.35
	var shot := _compute_throw()
	if shot.is_empty():
		return
	inventory.remove("stone", 1)
	StoneProjectile.launch(self, shot.from, shot.vel, self)
	AudioManager.play_sfx("throw")

func _hand_pos() -> Vector3:
	var cam := player.active_camera()
	return cam.global_position + (-cam.global_transform.basis.z) * 0.7 + cam.global_transform.basis.x * 0.25 - Vector3(0, 0.2, 0)

## Расчёт броска: баллистика в точку прицела; если в прицеле НЛО — выбирается
## дуга, которая долетает до кабины, не задевая корпус (умный бросок).
func _compute_throw() -> Dictionary:
	var cam := player.active_camera()
	var from := _hand_pos()
	var hit := camera_raycast(160.0, 1 | 8 | 16)
	var target: Vector3
	if hit.is_empty():
		target = cam.global_position + (-cam.global_transform.basis.z) * 70.0
	else:
		target = hit.position
	var sols := StoneProjectile.solve(from, target)
	var vel: Vector3
	var ufo := ufo_manager.ufo
	var outcome := ""
	if sols.is_empty():
		var dir := -cam.global_transform.basis.z
		dir.y = maxf(dir.y, 0.0) + 0.6
		vel = dir.normalized() * StoneProjectile.SPEED
	else:
		vel = sols[0]
		if is_instance_valid(ufo) and not hit.is_empty() and hit.collider is Area3D:
			# Цель — НЛО: целимся в купол с упреждением и выбираем дугу,
			# которая долетает до кабины, не задевая корпус (умный бросок).
			var aim := ufo.cockpit_global()
			var sols2 := StoneProjectile.solve(from, aim)
			var flight := 0.0
			if not sols2.is_empty():
				var hv: Vector3 = sols2[0]
				flight = Vector2(aim.x - from.x, aim.z - from.z).length() / maxf(0.1, Vector2(hv.x, hv.z).length())
				var lead := aim + ufo.velocity * flight
				var sols3 := StoneProjectile.solve(from, lead)
				if not sols3.is_empty():
					sols2 = sols3
			else:
				sols2 = sols
			vel = sols2[0]
			var xf: Transform3D = ufo.tilt.global_transform
			xf.origin += ufo.velocity * flight
			for s in sols2:
				var r := StoneProjectile.predict(from, s, xf, UFOController.COCKPIT_C, UFOController.COCKPIT_R, UFOController.HULL_R, UFOController.HULL_Y, UFOController.HULL_H, ufo.ground_y())
				if r == "cockpit":
					vel = s
					outcome = r
					break
	# Разброс по сложности
	var spread_deg: float = [0.0, 0.6, 1.0, 1.4][DifficultyManager.level()]
	if spread_deg > 0.0:
		var axis := vel.cross(Vector3.UP).normalized()
		if axis.length() < 0.1:
			axis = Vector3.RIGHT
		vel = vel.rotated(axis, deg_to_rad(randf_range(-spread_deg, spread_deg)))
		vel = vel.rotated(Vector3.UP, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	return {"from": from, "vel": vel, "outcome": outcome}

func camera_raycast(dist: float, mask: int) -> Dictionary:
	var cam := player.active_camera()
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * dist
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, [player.get_rid()])
	q.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(q)

func aim_point(dist: float) -> Vector3:
	var hit := camera_raycast(dist, 1)
	if not hit.is_empty():
		return hit.position
	var cam := player.active_camera()
	var p := player.global_position + player.forward() * 4.0
	p.y = terrain.height(p.x, p.z)
	return p

func player_yaw() -> float:
	return player.yaw

func _build_trajectory() -> void:
	_traj = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MK.sphere_mesh(0.07, 6, 3)
	mm.instance_count = 28
	_traj.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	_traj.material_override = m
	_traj.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_traj.visible = false
	add_child(_traj)

func _update_trajectory() -> void:
	var shot := _compute_throw()
	if shot.is_empty():
		return
	var p: Vector3 = shot.from
	var v: Vector3 = shot.vel
	var col := Color(0.4, 1.0, 0.5) if shot.outcome == "cockpit" else Color(1, 1, 1)
	var mm := _traj.multimesh
	var dt := 0.06
	for i in mm.instance_count:
		for k in 2:
			v.y -= StoneProjectile.GRAVITY * dt * 0.5
			p += v * dt * 0.5
		var hidden := p.y < terrain.height(p.x, p.z)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO if hidden else Vector3.ONE), p))
		mm.set_instance_color(i, col)

# ================================================================== Меню

func _open_overlay(panel: Control) -> void:
	if is_instance_valid(_open_menu):
		_open_menu.queue_free()
	aiming = false
	_traj.visible = false
	controls.release_all()
	_open_menu = panel
	menu_layer.add_child(panel)

func _open_inventory(crate: Inventory) -> void:
	var ui := InventoryUI.new()
	ui.game = self
	ui.crate_inv = crate
	_open_overlay(ui)

func _open_crate(inv: Inventory, _node: Node3D) -> void:
	AudioManager.play_sfx("door", -8.0)
	_open_inventory(inv)

func open_crafting(station: String) -> void:
	var ui := CraftingUI.new()
	ui.game = self
	ui.station_filter = station
	_open_overlay(ui)

func _open_build_menu() -> void:
	var ui := BuildMenu.new()
	ui.game = self
	ui.piece_chosen.connect(func(id):
		if id == "demolish":
			buildings.start_demolish()
			controls.set_label("place", "Разобрать")
		else:
			buildings.start_placement(id)
			controls.set_label("place", "Ставить")
		controls.set_build_mode(true)
		controls.set_visible_button("use", false))
	_open_overlay(ui)

func _make_map() -> Control:
	var m := MapUI.new()
	m.game = self
	return m

func _on_built() -> void:
	autosave_soon()

func _open_pause() -> void:
	if is_instance_valid(_pause) or SceneManager.is_busy() or _ending:
		return
	controls.release_all()
	_pause = PauseMenu.new()
	if GameManager.debug_enabled:
		_pause.extra_buttons = [
			["[Отладка] Вызвать НЛО сейчас", func():
				_pause.close()
				ufo_manager.debug_now(time_min)],
			["[Отладка] +20 камней, +ресурсы", func():
				inventory.add("stone", 20)
				inventory.add("wood", 30)
				inventory.add("fabric", 6)
				inventory.add("rope", 4)
				inventory.add("metal", 6)
				inventory.add("electronics", 6)],
			["[Отладка] +6 игровых часов", func(): time_min += 360.0],
			["[Отладка] Выполнить задание", func(): quests._complete()],
		]
	menu_layer.add_child(_pause)

func _on_back() -> void:
	if is_instance_valid(_open_menu):
		return # панель сама закроется
	if buildings.is_active():
		buildings.cancel()
		controls.set_build_mode(false)
		return
	_open_pause()

func _on_app_paused() -> void:
	controls.release_all()
	aiming = false
	_open_pause()

# ================================================================== Сон

func open_sleep_menu(bed: Dictionary) -> void:
	respawn_point = bed.pos + Vector3(1.5, 0.5, 0)
	var p := OverlayPanel.new()
	p.setup("Кровать", Vector2(0.5, 0.7))
	var info := UIStyle.make_label("Точка возрождения сохранена.\nСейчас %s." % DayNight.clock_text(time_min), 22)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.content.add_child(info)
	var left := ufo_manager.minutes_until(time_min)
	if ufo_manager.is_raid_active():
		p.content.add_child(UIStyle.make_label("Какой сон — над головой НЛО!", 22, UIStyle.BAD))
	else:
		var b1 := UIStyle.make_button("Спать до утра", Vector2(380, 80))
		b1.pressed.connect(func():
			p.close()
			_start_sleep(DayNight.next_morning(time_min)))
		p.content.add_child(b1)
		var b2 := UIStyle.make_button("Вздремнуть 2 часа", Vector2(380, 80))
		b2.pressed.connect(func():
			p.close()
			_start_sleep(time_min + 120.0))
		p.content.add_child(b2)
		if left < 600.0:
			p.content.add_child(UIStyle.make_label("Неспокойно... что-то будет в небе.", 18, UIStyle.BAD))
	_open_overlay(p)

func _start_sleep(until: float) -> void:
	if ufo_manager.minutes_until(time_min) <= 35.0:
		subtitle("Котакбас не может уснуть. В небе что-то гудит.")
		return
	is_sleeping = true
	sleep_until = until
	time_mult = 60.0 # 1 игровой час в секунду
	player.frozen = true
	hud.sleep_overlay.visible = true
	AudioManager.play_sfx("sleep")
	creatures.clear_all()

func _tick_sleep() -> void:
	if not is_sleeping:
		return
	if time_min >= sleep_until:
		_wake_up("Котакбас выспался. Почти.")
	elif ufo_manager.minutes_until(time_min) <= 31.0 and not ufo_manager.is_raid_active():
		_wake_up("Котакбас просыпается от странного гула...")

func _wake_up(msg: String) -> void:
	if not is_sleeping:
		return
	is_sleeping = false
	time_mult = 1.0
	player.frozen = false
	hud.sleep_overlay.visible = false
	subtitle(msg)
	GameManager.autosave()

# ================================================================== НЛО

func raid_base(final: bool) -> Vector3:
	if final:
		var c: Vector2 = SurvivalTerrain.REGIONS.radio.c
		return Vector3(c.x + 4, terrain.height(c.x + 4, c.y + 4), c.y + 4)
	var b := buildings.base_center()
	if b == Vector3.INF:
		# Нет базы — НЛО выбирает место около игрока.
		var p := player.global_position + player.forward() * 6.0
		return Vector3(p.x, terrain.height(p.x, p.z), p.z)
	return Vector3(b.x, terrain.height(b.x, b.z), b.z)

func _on_ufo_warning(minutes: int) -> void:
	AudioManager.play_sfx("alert")
	GameManager.vibrate(150)
	if minutes >= 30:
		attack_ui.show_warning("ВНИМАНИЕ! Обнаружена подозрительная активность в небе", 5.0)
	else:
		attack_ui.show_warning("Неопознанный объект приближается", 5.0)
		if inventory.count("stone") < 5:
			subtitle("Котакбас: Надо срочно набрать камней. Много камней.")

func _on_raid_started(ufo: UFOController) -> void:
	if is_sleeping:
		_wake_up("Котакбас вскакивает: над лесом гудит тарелка!")
	AudioManager.play_sfx("ufo_alarm")
	AudioManager.play_music("ufo", 0.5)
	attack_ui.show_warning("ТЦК ПРИЛЕТЕЛО ЗА ТВОИМИ РЕСУРСАМИ!", 5.0)
	GameManager.vibrate(300)
	_pile_t = 0.0
	if inventory.count("stone") < 4:
		for i in 2:
			_spawn_stone_pile()
	# Камень сразу на панель быстрого доступа, если он есть
	for i in 6:
		var s = inventory.slots[i]
		if s != null and s.id == "stone":
			select_hotbar(i)
			break

func _on_raid_ended(defeated: bool, summary: String, total: int) -> void:
	for p in stone_piles:
		if is_instance_valid(p):
			p.queue_free()
	stone_piles.clear()
	if defeated:
		attack_ui.show_warning("ТЦК ОТСТУПИЛО. ПОКА ЧТО...", 5.0)
		AudioManager.play_sfx("fanfare")
		GameManager.unlock_achievement("pvo")
		if total > 0:
			subtitle("Отбились! Но кое-что они всё же утащили: %s" % summary, 6.0)
	else:
		if total > 0:
			attack_ui.show_warning("ТЦК УКРАЛО ТВОИ РЕСУРСЫ", 5.0)
			subtitle("Украдено: %s" % summary, 6.0)
			GameManager.unlock_achievement("robbed")
		else:
			attack_ui.show_warning("ТЦК улетело ни с чем", 4.0)
	_update_music(true)
	GameManager.autosave()

func on_ufo_hit(left: int, max_hits: int) -> void:
	GameManager.toast("Попадание в кабину! %d/%d" % [left, max_hits], UIStyle.GOOD, 1.0)
	if left == max_hits / 2:
		subtitle("НЛО дымится! Ещё немного!")

func on_ufo_hull_hit() -> void:
	subtitle("Дзынь! По корпусу не считается — целься в стеклянную кабину!", 2.0)

func on_resource_stolen(id: String, n: int) -> void:
	GameManager.toast("НЛО утащило: %s ×%d" % [ItemDB.item_name(id), n], UIStyle.BAD, 1.2)

## Во время налёта рядом появляются груды камней — безвыходных ситуаций нет.
func _tick_stone_supply(delta: float) -> void:
	_pile_t -= delta
	if _pile_t > 0.0:
		return
	_pile_t = 16.0
	stone_piles = stone_piles.filter(func(p): return is_instance_valid(p))
	if inventory.count("stone") < 6 and stone_piles.size() < 3:
		_spawn_stone_pile()

func _spawn_stone_pile() -> void:
	var a := randf() * TAU
	var r := randf_range(4.0, 8.0)
	var p := player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
	p.y = terrain.height(p.x, p.z)
	if p.y < SurvivalTerrain.WATER_LEVEL:
		p = player.global_position + player.forward() * 3.0
		p.y = terrain.height(p.x, p.z)
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	for k in 5:
		var m := MeshInstance3D.new()
		m.mesh = MeshMerge.resource_mesh("stone")
		m.material_override = MeshMerge.vertex_color_material()
		m.position = Vector3(randf_range(-0.4, 0.4), 0.1 * k, randf_range(-0.4, 0.4))
		n.add_child(m)
	var glow := MK.add(n, MK.cyl_mesh(0.9, 0.9, 0.04, 16), Color(0.4, 1.0, 0.5, 0.5), Vector3(0, 0.02, 0), Vector3.ZERO, true, 1.5)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var it := Interactable.new()
	it.position.y = 0.5
	it.radius = 2.6
	it.label = "Груда камней (+6)"
	it.action = func():
		inventory.add("stone", 6)
		AudioManager.play_sfx("pickup")
		stone_piles.erase(n)
		n.queue_free()
	n.add_child(it)
	stone_piles.append(n)

# ================================================================== NPC и сюжет

func subtitle(text: String, time := 4.5) -> void:
	hud.show_subtitle(text, time)

func _food_total() -> int:
	var c := 0
	for s in inventory.slots:
		if s != null and ItemDB.get_item(s.id).type == "food":
			c += int(s.n)
	return c

func _take_food(n: int) -> void:
	var order := ["berries", "mushroom", "meat_raw", "water_dirty", "meat_cooked", "water_clean", "sandwich", "canned", "pryanik"]
	for id in order:
		if n <= 0:
			return
		n -= inventory.remove(id, n)

func talk_to_npc(id: String) -> void:
	if _dialog_open:
		return
	_dialog_open = true
	controls.release_all()
	player.input_move = Vector2.ZERO
	if id == "mikhalych":
		await _talk_mikhalych()
	else:
		await _talk_gena()
	dialogue.hide_box()
	_dialog_open = false

func _talk_mikhalych() -> void:
	var has_map := inventory.count("map") > 0 or quests.is_done("map")
	if not has_map:
		await dialogue.say("mikhalych", "surprised", "Ох ты ж! Живой человек! Давно тут никого не было. Только тарелка эта летает, дрова ворует.")
		await dialogue.say("kot", "normal", "Дед, мне бы карту. И радио. И чтобы ТЦК не нашло.")
		await dialogue.say("mikhalych", "smug", "Карта есть. Но за просто так — только простуда. Принеси поесть: три любых еды. Или пряник, если есть — я их с детства люблю.")
		var opts := [
			{"text": "Дать тульский пряник", "enabled": inventory.count("pryanik") > 0},
			{"text": "Дать три еды (есть: %d)" % _food_total(), "enabled": _food_total() >= 3},
			{"text": "Что за тарелка?", "enabled": true},
			{"text": "Потом зайду", "enabled": true},
		]
		var idx := await dialogue.choose(opts)
		match idx:
			0:
				inventory.remove("pryanik", 1)
				await _give_map("Тульский! Настоящий! Эх, молодость... Держи карту, сынок.")
			1:
				_take_food(3)
				await _give_map("Вот это я понимаю — уважение. Держи карту.")
			2:
				await dialogue.say("mikhalych", "normal", "Тарелка с буквами «ТЦК». Прилетает раз в полтора-два дня, светит лучом и тащит всё, что плохо лежит. Особенно из ящиков.")
				await dialogue.say("mikhalych", "smug", "Гонять её надо камнями. В кабину! В стекляшку сверху. По железу — бесполезно, только звенит.")
			_:
				await dialogue.say("mikhalych", "normal", "Заходи. Я тут. Мне идти некуда — меня сорок лет ищут.")
	else:
		await dialogue.say("mikhalych", "happy", NPC.STORIES.pick_random())
		if not quests.is_done("radio_find"):
			await dialogue.say("mikhalych", "normal", "Радиостанция — на холмах к северу. Красная вышка. Генератор там, правда, давно сдох.")

func _give_map(line: String) -> void:
	await dialogue.say("mikhalych", "happy", line)
	inventory.add("map", 1)
	AudioManager.play_sfx("achievement")
	GameManager.toast("Получена карта! Кнопка «Карта» вверху.", UIStyle.GOOD, 3.0)
	await dialogue.say("mikhalych", "normal", "На карте всё отмечено: завод за рекой, пещера, болото, радиостанция. Кружочком — куда тебе надо.")
	autosave_soon()

func _talk_gena() -> void:
	await dialogue.say("gena", "surprised", "А? Кто здесь? А, человек. Я думал, опять дерево ответило.")
	if not quests.flags.get("gena_gift", false):
		quests.flags["gena_gift"] = true
		await dialogue.say("gena", "happy", "Держи верёвку. Мне она ни к чему, я с деревьями и так связан. Духовно.")
		drop_or_add({"rope": 2, "berries": 3})
	await dialogue.say("gena", "normal", NPC.STORIES.pick_random())
	if quests.index >= 7 and not quests.is_done("parts"):
		await dialogue.say("gena", "smug", "Детали для радио? Антенну видел на заводе за мостом. Лампа светится в пещере на холмах. А катушка — в лодке на болоте, там где гуси орут.")

# --- Радиостанция и генератор

func generator_cost() -> Dictionary:
	return DifficultyManager.scaled_cost({"metal": 4, "electronics": 3, "rope": 2}, "craft")

func generator_label() -> String:
	if pois.generator_fixed:
		return "Генератор работает"
	return "Починить генератор"

func use_generator() -> void:
	if pois.generator_fixed:
		subtitle("Генератор тарахтит и пахнет соляркой. Красота.")
		return
	var cost := generator_cost()
	if not inventory.has_all(cost):
		var parts := []
		for k in cost:
			parts.append("%s %d/%d" % [ItemDB.item_name(k), inventory.count(k), cost[k]])
		subtitle("Для ремонта нужно: " + ", ".join(parts), 5.0)
		AudioManager.play_sfx("xp_error", -6.0)
		return
	inventory.remove_all(cost)
	pois.set_generator_fixed()
	AudioManager.play_sfx("build")
	AudioManager.play_sfx("craft_done")
	subtitle("Генератор ожил! Свет на радиостанции загорелся.", 4.0)
	autosave_soon()

func radio_label() -> String:
	if not pois.generator_fixed:
		return "Радиостанция (нет питания)"
	if not pois.radio_fixed:
		return "Включить радиостанцию"
	if not ufo_manager.final_done:
		return "Радио: сигнал глушат!"
	return "Выйти на связь"

func use_radio() -> void:
	if not pois.generator_fixed:
		subtitle("Радио молчит. Нужно питание — почини генератор рядом.", 4.0)
		return
	if not pois.radio_fixed:
		var missing := []
		for k in ["antenna", "radio_lamp", "coil"]:
			if inventory.count(k) == 0:
				missing.append(ItemDB.item_name(k))
		if not missing.is_empty():
			subtitle("Не хватает деталей: " + ", ".join(missing), 4.0)
			return
		_open_overlay(_tuning_panel())
		return
	if not ufo_manager.final_done:
		subtitle("В эфире только помехи и гул тарелки. Сначала разберись с ТЦК!", 4.0)
		if not ufo_manager.is_raid_active():
			_start_final_event()
		return
	_ending_sequence()

## Мини-игра: настройка частоты ползунком.
func _tuning_panel() -> Control:
	var p := OverlayPanel.new()
	p.setup("Настройка частоты", Vector2(0.7, 0.7))
	var target := randf_range(88.0, 107.0)
	var l := UIStyle.make_label("Поймай сигнал: двигай ползунок, пока полоска сигнала не заполнится, и удерживай 2 секунды.", 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.content.add_child(l)
	var freq := UIStyle.make_label("87.5 МГц", 40, UIStyle.ACCENT, true)
	freq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.content.add_child(freq)
	var slider := HSlider.new()
	slider.min_value = 87.5
	slider.max_value = 108.0
	slider.step = 0.1
	slider.custom_minimum_size = Vector2(600, 70)
	p.content.add_child(slider)
	var sig := ProgressBar.new()
	sig.custom_minimum_size = Vector2(600, 26)
	sig.show_percentage = false
	p.content.add_child(sig)
	var tol: float = [3.0, 2.0, 1.5, 1.0][DifficultyManager.level()]
	var state := {"hold": 0.0, "done": false}
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	p.add_child(timer)
	timer.timeout.connect(func():
		if state.done:
			return
		var d := absf(slider.value - target)
		freq.text = "%.1f МГц" % slider.value
		sig.value = clampf(1.0 - d / 8.0, 0.0, 1.0) * 100.0
		if randf() < 0.3:
			AudioManager.play_sfx("radio", -18.0 + sig.value * 0.12, 0.8 + sig.value / 200.0)
		if d < tol:
			state.hold += 0.1
			if state.hold >= 2.0:
				state.done = true
				p.close()
				_radio_fixed()
		else:
			state.hold = 0.0)
	return p

func _radio_fixed() -> void:
	for k in ["antenna", "radio_lamp", "coil"]:
		inventory.remove(k, 1)
	pois.set_radio_fixed()
	AudioManager.play_sfx("fanfare")
	GameManager.unlock_achievement("radio")
	subtitle("Связь есть! ...Но в эфире резко нарастает знакомый гул.", 5.0)
	autosave_soon()
	await get_tree().create_timer(4.0).timeout
	_start_final_event()

func _start_final_event() -> void:
	if ufo_manager.is_raid_active() or ufo_manager.final_done:
		return
	weather.forced = true
	weather.set_weather("storm")
	attack_ui.show_warning("ТЦК ЗАСЕКЛО СИГНАЛ! ФИНАЛЬНЫЙ НАЛЁТ!", 5.0)
	ufo_manager.start_raid(true)

func _ending_sequence() -> void:
	if _ending:
		return
	_ending = true
	weather.forced = false
	controls.release_all()
	_dialog_open = true
	AudioManager.play_music("ending")
	AudioManager.play_sfx("radio")
	await dialogue.say("radio", "normal", "Ш-ш-ш... Котакбас... Котакбас, приём...")
	await dialogue.say("radio", "normal", "Котакбас, мы знаем, где ты.")
	await dialogue.say("kot", "shock", "Кто это, блять?")
	await dialogue.say("radio", "normal", "Это только начало.")
	dialogue.hide_box()
	# Камера показывает голубя
	var pg := PigeonModel.new()
	pg.flapping = false
	add_child(pg)
	pg.global_position = pois.radio_pos + Vector3(0, 2.2, -0.6)
	pg.scale = Vector3.ONE * 1.5
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = pg.global_position + Vector3(2.5, 0.6, 2.5)
	cam.look_at(pg.global_position)
	cam.fov = 50
	cam.current = true
	AudioManager.play_sfx("pigeon")
	var tw := create_tween()
	tw.tween_property(cam, "fov", 22.0, 3.5)
	await tw.finished
	quests.flags["finished"] = true
	GameManager.unlock_achievement("finish")
	SaveManager.profile.completed = true
	SaveManager.save_profile()
	await get_tree().create_timer(0.8).timeout
	GameManager.state.survival = save_state()
	GameManager.save_game("auto")
	GameManager.start_chapter("ending", false)

# ================================================================== Отладка (только debug-сборки)

## Сцена для проверки налёта: база, камни, тарелка сразу в режиме луча.
func debug_ufo_scene() -> void:
	if not GameManager.debug_enabled:
		return
	_intro_done = true
	player.frozen = false
	var p := player.global_position + player.forward() * 3.0
	buildings.place("crate", Vector3(p.x, terrain.height(p.x, p.z), p.z), 0.0, {"items": [{"id": "wood", "n": 20}, {"id": "stone", "n": 10}]})
	inventory.add("stone", 20)
	inventory.add("wood", 15)
	ufo_manager.start_raid(false, {"state": 3, "hits": 0})
	await get_tree().create_timer(0.5).timeout
	# Отходим и смотрим на кабину
	var u := ufo_manager.ufo
	var away := (player.global_position - u.global_position)
	away.y = 0
	var np := u.global_position + away.normalized() * 16.0
	player.global_position = Vector3(np.x, terrain.height(np.x, np.z) + 0.3, np.z)
	var to := u.cockpit_global() - player.active_camera().global_position
	player.yaw = atan2(-to.x, -to.z)
	player.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	player.look(Vector2.ZERO)
	select_hotbar(0)
	_start_aim()

func debug_third_person() -> void:
	player.set_third_person(true)
	player.pitch = -0.35
	player.look(Vector2.ZERO)

func debug_ui(which: String) -> void:
	if not GameManager.debug_enabled:
		return
	inventory.add("wood", 25)
	inventory.add("stone", 12)
	inventory.add("berries", 4)
	inventory.add("map", 1)
	inventory.add("fabric", 3)
	match which:
		"inv": _open_inventory(null)
		"craft": open_crafting("")
		"build": _open_build_menu()
		"map": _open_overlay(_make_map())

func debug_inv() -> void: debug_ui("inv")
func debug_craft() -> void: debug_ui("craft")
func debug_build() -> void: debug_ui("build")
func debug_map() -> void: debug_ui("map")
