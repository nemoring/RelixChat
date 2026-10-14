class_name WorldPOIs
extends Node3D
## Сюжетные места: заброшенная деревня, старый завод, радиостанция на холме,
## пещера, болото с лодкой, мост через реку, указатели. Ключевые предметы и ящики с добычей.

var game
var terrain: SurvivalTerrain
var picked := {} # id -> true (подобранные предметы / обысканные ящики)
var nodes := {} # id -> Interactable
var generator_fixed := false
var radio_fixed := false
var mikhalych: NPC
var gena: NPC
var radio_pos := Vector3.ZERO
var generator_pos := Vector3.ZERO
var gen_light: OmniLight3D
var radio_light: MeshInstance3D

const LOOT := {
	"village_crate_1": {"fabric": 4, "rope": 2},
	"village_crate_2": {"canned": 1, "fabric": 2, "water_clean": 2},
	"village_crate_3": {"scrap": 3, "electronics": 1, "rope": 1},
	"factory_crate_1": {"metal": 3, "electronics": 2},
	"factory_crate_2": {"scrap": 4, "electronics": 2, "rope": 1},
	"radio_crate": {"water_clean": 2, "fabric": 2, "stone": 6},
}

func setup(g, t: SurvivalTerrain, saved := {}) -> void:
	game = g
	terrain = t
	picked = saved.get("picked", {}).duplicate()
	generator_fixed = saved.get("generator_fixed", false)
	radio_fixed = saved.get("radio_fixed", false)
	_build_village()
	_build_factory()
	_build_bridge()
	_build_radio()
	_build_cave()
	_build_swamp()
	_build_clearing()
	_build_gena()

func save_data() -> Dictionary:
	return {"picked": picked.duplicate(), "generator_fixed": generator_fixed, "radio_fixed": radio_fixed}

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain.height(x, z), z)

func _static_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	MK.box(parent, size, color, pos, rot)
	MK.static_box(parent, size, pos, rot)

func _house(c: Vector3, rot: float, wall: Color) -> Node3D:
	var h := Node3D.new()
	h.position = c
	h.rotation.y = rot
	add_child(h)
	_static_box(h, Vector3(6, 3.2, 5), Vector3(0, 1.4, 0), wall)
	MK.cyl(h, 0.0, 5.0, 2.6, Color(0.42, 0.3, 0.22), Vector3(0, 4.3, 0), Vector3(0, PI * 0.25, 0), 4)
	MK.box(h, Vector3(1.2, 2.0, 0.1), Color(0.3, 0.2, 0.12), Vector3(0, 1.0, -2.53))
	MK.box(h, Vector3(1.0, 0.9, 0.1), Color(0.25, 0.35, 0.45), Vector3(-2.0, 1.8, -2.53))
	MK.box(h, Vector3(1.0, 0.9, 0.1), Color(0.25, 0.35, 0.45), Vector3(2.0, 1.8, -2.53))
	return h

func _loot_crate(id: String, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	MK.box(n, Vector3(1.0, 0.7, 0.7), Color(0.5, 0.36, 0.22), Vector3(0, 0.35, 0))
	MK.box(n, Vector3(1.02, 0.08, 0.72), Color(0.35, 0.24, 0.14), Vector3(0, 0.7, 0))
	MK.static_box(n, Vector3(1.0, 0.7, 0.7), Vector3(0, 0.35, 0))
	var it := Interactable.new()
	it.position.y = 0.8
	n.add_child(it)
	it.label_func = func(): return "Ящик (пусто)" if picked.has(id) else "Обыскать ящик"
	it.action = func():
		if picked.has(id):
			game.subtitle("Тут уже пусто. Только паук, и он против.")
			return
		picked[id] = true
		game.drop_or_add(LOOT[id])
		AudioManager.play_sfx("pickup")
	nodes[id] = it

func _key_item(id: String, item: String, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	if picked.has(id):
		return
	var holder := Node3D.new()
	holder.name = "Spin"
	n.add_child(holder)
	var spr := Sprite3D.new()
	spr.texture = ItemDB.icon(item)
	spr.pixel_size = 0.014
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.position.y = 0.9
	holder.add_child(spr)
	var glow := MK.add(n, MK.cyl_mesh(0.6, 0.6, 0.05, 16), Color(1.0, 0.85, 0.2, 0.6), Vector3(0, 0.03, 0), Vector3.ZERO, true, 2.0)
	glow.name = "Glow"
	var pillar := MK.add(n, MK.cyl_mesh(0.08, 0.08, 14.0, 6), Color(1.0, 0.85, 0.3, 0.35), Vector3(0, 7.0, 0), Vector3.ZERO, true)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var it := Interactable.new()
	it.position.y = 0.8
	it.radius = 3.0
	it.label = "Подобрать: " + ItemDB.item_name(item)
	n.add_child(it)
	it.action = func():
		if picked.has(id):
			return
		picked[id] = true
		game.inventory.add(item, 1)
		AudioManager.play_sfx("achievement")
		GameManager.toast("Найдено: %s" % ItemDB.item_name(item), UIStyle.GOOD)
		n.queue_free()
		game.autosave_soon()
	nodes[id] = it

func _process(delta: float) -> void:
	for k in nodes:
		var it: Interactable = nodes[k]
		if is_instance_valid(it):
			var spin := it.get_parent().get_node_or_null("Spin")
			if spin:
				spin.rotation.y += delta * 1.5
				spin.position.y = sin(Time.get_ticks_msec() * 0.003) * 0.15

# ------------------------------------------------------------------ Деревня

func _build_village() -> void:
	var c: Vector2 = SurvivalTerrain.REGIONS.village.c
	var offsets := [[Vector2(-14, -10), 0.3], [Vector2(12, -14), -0.2], [Vector2(-16, 12), 1.4], [Vector2(14, 10), 2.9], [Vector2(0, -26), 0.0]]
	var cols := [Color(0.62, 0.5, 0.38), Color(0.55, 0.48, 0.42), Color(0.5, 0.55, 0.45), Color(0.6, 0.45, 0.4), Color(0.58, 0.52, 0.45)]
	for i in offsets.size():
		var o: Vector2 = offsets[i][0]
		_house(_ground(c.x + o.x, c.y + o.y), offsets[i][1], cols[i])
	# Колодец
	var w := _ground(c.x, c.y)
	MK.cyl(self, 0.9, 0.9, 1.0, Color(0.5, 0.5, 0.52), w + Vector3(0, 0.5, 0), Vector3.ZERO, 10)
	MK.static_box(self, Vector3(1.8, 1.0, 1.8), w + Vector3(0, 0.5, 0))
	MK.box(self, Vector3(0.1, 1.6, 0.1), Color(0.4, 0.3, 0.2), w + Vector3(-0.8, 1.3, 0))
	MK.box(self, Vector3(0.1, 1.6, 0.1), Color(0.4, 0.3, 0.2), w + Vector3(0.8, 1.3, 0))
	MK.box(self, Vector3(2.0, 0.1, 1.2), Color(0.45, 0.3, 0.2), w + Vector3(0, 2.2, 0), Vector3(0, 0, 0.2))
	var well := Interactable.new()
	well.position = w + Vector3(0, 1, 0)
	well.label = "Набрать воды из колодца"
	well.action = func(): game.collect_water(false)
	add_child(well)
	# Заборы
	for k in 8:
		var a := TAU * k / 8.0
		var fp := _ground(c.x + cos(a) * 30.0, c.y + sin(a) * 30.0)
		var f := BuildDB.build_visual("fence")
		f.position = fp
		f.rotation.y = a + PI * 0.5
		add_child(f)
	_loot_crate("village_crate_1", _ground(c.x + 9, c.y - 8))
	_loot_crate("village_crate_2", _ground(c.x - 11, c.y + 7))
	_loot_crate("village_crate_3", _ground(c.x + 10, c.y + 5))
	mikhalych = NPC.new()
	add_child(mikhalych)
	mikhalych.position = _ground(c.x - 6, c.y - 3)
	mikhalych.setup("mikhalych", game)
	var sign_p := _ground(c.x + 4, c.y + 24)
	_sign(sign_p, "Деревня «Глушь»\nНаселение: 1 дед, 3 гуся", PI)

# ------------------------------------------------------------------ Завод

func _build_factory() -> void:
	var c: Vector2 = SurvivalTerrain.REGIONS.factory.c
	var base := _ground(c.x, c.y)
	var f := Node3D.new()
	f.position = base
	add_child(f)
	var wall := Color(0.5, 0.45, 0.42)
	_static_box(f, Vector3(30, 9, 0.6), Vector3(0, 4.5, -10), wall)
	_static_box(f, Vector3(30, 9, 0.6), Vector3(0, 4.5, 10), wall)
	_static_box(f, Vector3(0.6, 9, 20), Vector3(15, 4.5, 0), wall)
	_static_box(f, Vector3(0.6, 9, 7), Vector3(-15, 4.5, -6.5), wall)
	_static_box(f, Vector3(0.6, 9, 7), Vector3(-15, 4.5, 6.5), wall)
	MK.box(f, Vector3(0.6, 3, 6), wall, Vector3(-15, 7.5, 0))
	MK.box(f, Vector3(30.6, 0.4, 9), Color(0.4, 0.38, 0.36), Vector3(0, 9.1, -5.5))
	MK.box(f, Vector3(12, 0.4, 11), Color(0.4, 0.38, 0.36), Vector3(9, 9.1, 5))
	MK.cyl(f, 1.2, 1.6, 22.0, Color(0.6, 0.35, 0.3), Vector3(10, 11.0, -14), Vector3.ZERO, 10)
	MK.static_box(f, Vector3(3, 22, 3), Vector3(10, 11, -14))
	var lbl := Label3D.new()
	lbl.text = "ЗАВОД «КРАСНЫЙ ГВОЗДЬ»"
	lbl.font = UIStyle.title_font()
	lbl.font_size = 96
	lbl.pixel_size = 0.02
	lbl.modulate = Color(0.85, 0.2, 0.15)
	lbl.position = Vector3(-15.4, 7.6, 0)
	lbl.rotation.y = -PI * 0.5
	f.add_child(lbl)
	# Станки
	for i in 3:
		_static_box(f, Vector3(3, 1.8, 2), Vector3(-6 + i * 7, 0.9, 5), Color(0.35, 0.4, 0.45))
	_static_box(f, Vector3(2.5, 1.0, 1.2), Vector3(8, 0.5, -5), Color(0.5, 0.35, 0.22))
	_key_item("antenna_item", "antenna", base + Vector3(8, 1.0, -5))
	_loot_crate("factory_crate_1", base + Vector3(-10, 0, -7))
	_loot_crate("factory_crate_2", base + Vector3(12, 0, 7))

func _build_bridge() -> void:
	var z := -60.0
	var rx := terrain.river_x(z)
	var x0 := rx - 18.0
	var x1 := rx + 18.0
	var hl := terrain.height(x0, z)
	var hr := terrain.height(x1, z)
	var y := maxf(maxf(hl, hr), SurvivalTerrain.WATER_LEVEL + 1.0) + 0.3
	var mid_len := 22.0
	var wood := Color(0.5, 0.35, 0.2)
	_static_box(self, Vector3(mid_len, 0.3, 3.5), Vector3(rx, y, z), wood)
	for side in [-1.0, 1.0]:
		var end_x: float = rx + side * mid_len * 0.5
		var bank_x: float = x0 if side < 0 else x1
		var bank_h: float = hl if side < 0 else hr
		var dx: float = absf(bank_x - end_x)
		var dy: float = y - bank_h
		var len := sqrt(dx * dx + dy * dy)
		var ang: float = atan2(dy, dx) * side
		_static_box(self, Vector3(len, 0.3, 3.5), Vector3((end_x + bank_x) * 0.5, (y + bank_h) * 0.5, z), wood, Vector3(0, 0, ang))
	for k in 6:
		MK.box(self, Vector3(0.15, 1.0, 0.15), wood.darkened(0.2), Vector3(rx - mid_len * 0.5 + k * mid_len / 5.0, y + 0.6, z - 1.7))
		MK.box(self, Vector3(0.15, 1.0, 0.15), wood.darkened(0.2), Vector3(rx - mid_len * 0.5 + k * mid_len / 5.0, y + 0.6, z + 1.7))
	MK.box(self, Vector3(mid_len, 0.1, 0.1), wood, Vector3(rx, y + 1.05, z - 1.7))
	MK.box(self, Vector3(mid_len, 0.1, 0.1), wood, Vector3(rx, y + 1.05, z + 1.7))

# ------------------------------------------------------------------ Радиостанция

func _build_radio() -> void:
	var c: Vector2 = SurvivalTerrain.REGIONS.radio.c
	var base := _ground(c.x, c.y)
	var r := Node3D.new()
	r.position = base
	add_child(r)
	# Решётчатая вышка
	var metal := Color(0.7, 0.2, 0.15)
	for p in [Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)]:
		MK.box(r, Vector3(0.2, 20, 0.2), metal, Vector3(p.x * 0.6, 10, p.z * 0.6) + Vector3(6, 0, 0), Vector3(-p.z * 0.02, 0, p.x * 0.02))
	for k in 7:
		MK.box(r, Vector3(2.0 - k * 0.15, 0.12, 0.12), Color(0.9, 0.9, 0.9) if k % 2 == 0 else metal, Vector3(6, 2 + k * 2.8, -0.9 + k * 0.05))
		MK.box(r, Vector3(2.0 - k * 0.15, 0.12, 0.12), Color(0.9, 0.9, 0.9) if k % 2 == 0 else metal, Vector3(6, 2 + k * 2.8, 0.9 - k * 0.05))
	MK.static_box(r, Vector3(2.0, 20, 2.0), Vector3(6, 10, 0))
	radio_light = MK.add(r, MK.sphere_mesh(0.35, 8, 4), Color(1, 0.15, 0.1), Vector3(6, 20.4, 0), Vector3.ZERO, true, 0.5)
	# Будка с радио
	_static_box(r, Vector3(4, 3, 4), Vector3(-3, 1.5, 0), Color(0.55, 0.55, 0.5))
	MK.box(r, Vector3(4.4, 0.25, 4.4), Color(0.4, 0.3, 0.25), Vector3(-3, 3.1, 0))
	MK.box(r, Vector3(1.6, 1.0, 0.3), Color(0.3, 0.27, 0.22), Vector3(-3, 1.3, 2.1))
	MK.box(r, Vector3(0.4, 0.4, 0.05), Color(0.6, 0.55, 0.45), Vector3(-2.6, 1.3, 2.27))
	radio_pos = r.position + Vector3(-3, 1.3, 2.5)
	var radio := Interactable.new()
	radio.position = Vector3(-3, 1.3, 2.6)
	radio.radius = 3.0
	radio.label_func = func(): return game.radio_label()
	radio.action = func(): game.use_radio()
	r.add_child(radio)
	# Генератор
	_static_box(r, Vector3(2.2, 1.5, 1.3), Vector3(1.5, 0.75, 3.5), Color(0.35, 0.45, 0.3))
	MK.cyl(r, 0.12, 0.12, 1.2, Color(0.2, 0.2, 0.2), Vector3(2.3, 2.0, 3.5))
	generator_pos = r.position + Vector3(1.5, 0.75, 3.5)
	gen_light = OmniLight3D.new()
	gen_light.light_color = Color(1.0, 0.9, 0.5)
	gen_light.omni_range = 10.0
	gen_light.light_energy = 0.0
	gen_light.position = Vector3(1.5, 2.2, 3.5)
	r.add_child(gen_light)
	var gen := Interactable.new()
	gen.position = Vector3(1.5, 1.0, 4.3)
	gen.radius = 3.0
	gen.label_func = func(): return game.generator_label()
	gen.action = func(): game.use_generator()
	r.add_child(gen)
	_loot_crate("radio_crate", base + Vector3(-6.5, 0, -3))
	_update_radio_visuals()

func _update_radio_visuals() -> void:
	gen_light.light_energy = 1.2 if generator_fixed else 0.0
	radio_light.material_override = MK.mat(Color(1, 0.15, 0.1), true, 3.0 if radio_fixed or generator_fixed else 0.3)

func set_generator_fixed() -> void:
	generator_fixed = true
	_update_radio_visuals()

func set_radio_fixed() -> void:
	radio_fixed = true
	_update_radio_visuals()

# ------------------------------------------------------------------ Пещера

func _build_cave() -> void:
	var c: Vector2 = SurvivalTerrain.REGIONS.cave.c
	var base := _ground(c.x, c.y)
	var cave := Node3D.new()
	cave.position = base
	add_child(cave)
	var rock := Color(0.42, 0.42, 0.44)
	# Кольцо скал с проходом на юг (+Z)
	for k in 9:
		var a := -PI * 0.5 + (k - 4) * 0.62 + PI
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.45:
			continue
		var p := Vector3(cos(a) * 6.5, 2.2, sin(a) * 6.5)
		var m := MK.add(cave, MK.sphere_mesh(3.4, 9, 5), rock.darkened(randf() * 0.15), p)
		m.scale = Vector3(1.0, 1.0, 0.85)
		var sb := StaticBody3D.new()
		sb.position = p
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 3.0
		cs.shape = sp
		sb.add_child(cs)
		cave.add_child(sb)
	var roof := MK.add(cave, MK.sphere_mesh(8.5, 12, 6), rock.darkened(0.1), Vector3(0, 6.8, -0.5))
	roof.scale = Vector3(1, 0.35, 1)
	MK.static_box(cave, Vector3(13, 1.5, 13), Vector3(0, 7.2, -0.5))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.3)
	lamp.omni_range = 7.0
	lamp.light_energy = 1.4
	lamp.position = Vector3(0, 2.0, -2.0)
	cave.add_child(lamp)
	_static_box(cave, Vector3(1.2, 0.8, 0.8), Vector3(0, 0.4, -3.0), Color(0.45, 0.32, 0.2))
	_key_item("lamp_item", "radio_lamp", base + Vector3(0, 0.8, -3.0))
	_sign(_ground(c.x, c.y + 14), "ПЕЩЕРА\nНЕ ВХОДИТЬ\n(ну ладно, входить)", 0.0)

# ------------------------------------------------------------------ Болото

func _build_swamp() -> void:
	var c: Vector2 = SurvivalTerrain.REGIONS.swamp.c
	var p := Vector3(c.x - 10, SurvivalTerrain.WATER_LEVEL, c.y + 5)
	var boat := Node3D.new()
	boat.position = p
	boat.rotation = Vector3(0.1, 0.6, 0.15)
	add_child(boat)
	var wood := Color(0.42, 0.3, 0.2)
	MK.box(boat, Vector3(1.8, 0.2, 4.5), wood, Vector3(0, 0, 0))
	MK.box(boat, Vector3(0.15, 0.6, 4.5), wood, Vector3(-0.9, 0.3, 0))
	MK.box(boat, Vector3(0.15, 0.6, 4.5), wood, Vector3(0.9, 0.3, 0))
	MK.box(boat, Vector3(1.8, 0.6, 0.15), wood, Vector3(0, 0.3, 2.2))
	MK.static_box(self, Vector3(1.8, 0.4, 4.5), p, Vector3(0.1, 0.6, 0.15))
	_key_item("coil_item", "coil", p + Vector3(0, 0.3, 0))
	# Мостки из досок
	for k in 6:
		var bp := _ground(c.x - 10 + k * 3.0 + 4.0, c.y + 5 + k * 2.0 + 3.0)
		_static_box(self, Vector3(2.8, 0.15, 1.0), Vector3(bp.x, maxf(bp.y, SurvivalTerrain.WATER_LEVEL) + 0.15, bp.z), wood, Vector3(0, 0.6, 0))
	_sign(_ground(c.x + 30, c.y - 20), "Болото\nтут что-то булькает", -0.7)

# ------------------------------------------------------------------ Поляна, указатели, Гена

func _build_clearing() -> void:
	var c: Vector2 = SurvivalTerrain.REGIONS.clearing.c
	_sign(_ground(c.x + 4, c.y - 6), "С — Холмы, радиостанция\nСЗ — Деревня\nВ — Завод (за рекой)\nЮЗ — Болото", 0.0)
	# Кусты, в которые упал Котакбас
	for k in 5:
		var bp := _ground(randf_range(-4, 4), 81.5 + randf_range(0.0, 2.5))
		var b := RunnerBuild.build_bush()
		b.position = bp
		b.scale = Vector3.ONE * 0.8
		add_child(b)

func _build_gena() -> void:
	var p := _ground(55, 10)
	var tree_n := Node3D.new()
	tree_n.position = p + Vector3(2.0, 0, 0)
	add_child(tree_n)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshMerge.resource_mesh("tree")
	mi.material_override = MeshMerge.vertex_color_material()
	mi.scale = Vector3.ONE * 1.5
	tree_n.add_child(mi)
	MK.static_box(tree_n, Vector3(0.8, 4, 0.8), Vector3(0, 2, 0))
	gena = NPC.new()
	add_child(gena)
	gena.position = p
	gena.rotation.y = -PI * 0.5
	gena.setup("gena", game)

func _sign(pos: Vector3, text: String, rot: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot
	add_child(n)
	MK.box(n, Vector3(0.15, 2.2, 0.15), Color(0.45, 0.32, 0.2), Vector3(0, 1.1, 0))
	MK.box(n, Vector3(2.6, 1.2, 0.1), Color(0.6, 0.45, 0.28), Vector3(0, 2.0, 0))
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font = UIStyle.bold_font()
		l.font_size = 40
		l.pixel_size = 0.0075
		l.modulate = Color(0.12, 0.08, 0.05)
		l.outline_size = 0
		l.position = Vector3(0, 2.0, 0.06 * side)
		l.rotation.y = 0.0 if side > 0 else PI
		n.add_child(l)
