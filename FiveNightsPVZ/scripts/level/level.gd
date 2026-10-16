class_name Level
extends Node3D
## Процедурно построенный пункт выдачи заказов на первом этаже старого дома.
##
## План (вид сверху, x вправо, z вниз, метры):
##   Склад            x 0..12,  z 0..7    (стеллажи, приёмка у рольставни)
##   Примерочные A/B  x 0..4.4, z 7..10
##   Рабочее место    x 6..12,  z 7..10   (стойка по линии z=10)
##   Зал выдачи       x 0..12,  z 10..16  (вход x 1..2.2 на z=16, витрина)
##   Коридор          x 12..14, z 0..12
##   Техническая      x 14..18, z 0..3.5  (заперта)
##   Подсобка         x 14..18, z 3.5..7.5 (щиток, шкафчики)
##   Туалет           x 14..18, z 7.5..12

const H := 3.0
const T := 0.2

## name -> {rect: Rect2, zone, title, reverb}
const ROOMS := [
	{"id": "vestibule", "rect": Rect2(0, 13.8, 3.4, 2.2), "zone": "hall", "title": "Входная зона", "reverb": "RevSmall"},
	{"id": "cab_a", "rect": Rect2(0, 7, 2.2, 3), "zone": "fitting", "title": "Примерочная 1", "reverb": "RevSmall"},
	{"id": "cab_b", "rect": Rect2(2.2, 7, 2.2, 3), "zone": "fitting", "title": "Примерочная 2", "reverb": "RevSmall"},
	{"id": "workstation", "rect": Rect2(6, 7, 6, 3), "zone": "workstation", "title": "Рабочее место", "reverb": "RevSmall"},
	{"id": "hall", "rect": Rect2(0, 10, 12, 6), "zone": "hall", "title": "Зал выдачи", "reverb": "RevSmall"},
	{"id": "warehouse", "rect": Rect2(0, 0, 12, 7), "zone": "warehouse", "title": "Склад", "reverb": "RevLarge"},
	{"id": "corridor", "rect": Rect2(12, 0, 2, 12), "zone": "corridor", "title": "Служебный коридор", "reverb": "RevCorridor"},
	{"id": "tech", "rect": Rect2(14, 0, 4, 3.5), "zone": "tech", "title": "Техническая", "reverb": "RevTile"},
	{"id": "utility", "rect": Rect2(14, 3.5, 4, 4), "zone": "utility", "title": "Подсобка", "reverb": "RevSmall"},
	{"id": "toilet", "rect": Rect2(14, 7.5, 4, 4.5), "zone": "toilet", "title": "Туалет", "reverb": "RevTile"},
	{"id": "street", "rect": Rect2(-20, 16, 60, 30), "zone": "street", "title": "Улица", "reverb": ""},
]

const CAMERAS := [
	{"title": "CAM 1 · Вход", "pos": Vector3(3.2, 2.7, 13.95), "look": Vector3(1.4, 0.9, 16.6), "room": "vestibule"},
	{"title": "CAM 2 · Зал", "pos": Vector3(11.75, 2.75, 15.75), "look": Vector3(4.0, 0.7, 11.0), "room": "hall"},
	{"title": "CAM 3 · Примерочные", "pos": Vector3(6.2, 2.7, 13.2), "look": Vector3(2.2, 0.9, 9.9), "room": "hall"},
	{"title": "CAM 4 · Склад, ряды", "pos": Vector3(0.3, 2.7, 3.95), "look": Vector3(9.5, 0.6, 4.0), "room": "warehouse"},
	{"title": "CAM 5 · Склад, приёмка", "pos": Vector3(11.75, 2.7, 0.3), "look": Vector3(4.0, 0.6, 2.2), "room": "warehouse"},
	{"title": "CAM 6 · Коридор", "pos": Vector3(13.0, 2.75, 0.25), "look": Vector3(13.0, 0.8, 8.0), "room": "corridor"},
	{"title": "CAM 7 · Подсобка", "pos": Vector3(17.8, 2.7, 7.3), "look": Vector3(15.0, 0.6, 4.0), "room": "utility"},
	{"title": "CAM 8 · Техническая", "pos": Vector3(17.8, 2.7, 0.2), "look": Vector3(14.6, 0.7, 3.0), "room": "tech"},
]

var nav := NavGraph.new()
var lighting := Lighting.new()
var doors := {}
var cells := {}           # "Б-3" -> DropSpot
var cabins := []          # [{curtain, spot, room, point}]
var hide_spots := []
var checkpoints := {}     # id -> Interactable
var dark_spots: Array[Vector3] = []
var movable_props: Array[Node3D] = []
var mirrors: Array = []
var spawn := {}
var desk_seat: Interactable
var counter_spot: DropSpot
var scanner_spot: DropSpot
var intake_spot: DropSpot
var clothes_rail: Node3D
var breaker_panel: Interactable
var maglock: Interactable
var phone: Interactable
var printer: Interactable
var pc_screen: MeshInstance3D
var cctv_screen: MeshInstance3D
var clock_labels: Array[Label3D] = []
var tech_terminal: Interactable
var own_box: Node3D
var room_areas := {}
var cam_mount_nodes: Array[Node3D] = []

var _card_xforms: Array[Transform3D] = []
var _rng := RandomNumberGenerator.new()


func build(seed_v := 7) -> void:
	_rng.seed = seed_v
	add_child(lighting)
	_build_shell()
	_build_floors_and_ceiling()
	_build_street()
	_build_warehouse()
	_build_workstation()
	_build_hall()
	_build_fitting()
	_build_corridor()
	_build_utility()
	_build_toilet()
	_build_tech()
	_build_lights()
	_build_room_areas()
	_build_nav()
	_build_camera_mounts()
	_flush_multimesh()


# ======================================================================= Стены

## Стена вдоль оси. axis "x": стена идёт по x на z=fixed; "z": по z на x=fixed.
## holes: [{a, b, bottom, top}] в координатах вдоль оси.
func wall(axis: String, fixed: float, from: float, to: float, holes: Array, mat_neg: Material, mat_pos: Material = null) -> void:
	if mat_pos == null:
		mat_pos = mat_neg
	holes.sort_custom(func(p, q): return p["a"] < q["a"])
	var cur := from
	for h in holes:
		if h["a"] > cur:
			_wall_piece(axis, fixed, cur, h["a"], 0.0, H, mat_neg, mat_pos)
		var top: float = h.get("top", 2.15)
		var bottom: float = h.get("bottom", 0.0)
		if top < H:
			_wall_piece(axis, fixed, h["a"], h["b"], top, H, mat_neg, mat_pos)
		if bottom > 0.0:
			_wall_piece(axis, fixed, h["a"], h["b"], 0.0, bottom, mat_neg, mat_pos)
		cur = maxf(cur, h["b"])
	if cur < to:
		_wall_piece(axis, fixed, cur, to, 0.0, H, mat_neg, mat_pos)


func _wall_piece(axis: String, fixed: float, a: float, b: float, y0: float, y1: float, mat_neg: Material, mat_pos: Material) -> void:
	var len := b - a
	var mid := (a + b) * 0.5
	var hy := y1 - y0
	var cy := (y0 + y1) * 0.5
	var size_full := Vector3(len, hy, T) if axis == "x" else Vector3(T, hy, len)
	var center := Vector3(mid, cy, fixed) if axis == "x" else Vector3(fixed, cy, mid)
	if mat_neg == mat_pos:
		Build.box(self, size_full, center, mat_neg, true)
		return
	var half := Vector3(len, hy, T * 0.5) if axis == "x" else Vector3(T * 0.5, hy, len)
	var off := Vector3(0, 0, T * 0.25) if axis == "x" else Vector3(T * 0.25, 0, 0)
	var neg := Build.box(self, half, center - off, mat_neg)
	Build.box(self, half, center + off, mat_pos)
	Build.add_box_collider(neg, size_full).position = off


func _build_shell() -> void:
	var paint := Mats.surface("wall_paint")
	var wh := Mats.surface("wall_warehouse")
	var green := Mats.surface("wall_green")
	var tile := Mats.surface("wall_tile")
	var ext := Mats.surface("exterior")
	# Наружные стены.
	wall("x", 0.0, 0.0, 18.0, [{"a": 4.2, "b": 6.6, "top": 2.6}], ext, wh)  # рольставня
	wall("z", 0.0, 0.0, 16.0, [], ext, wh)
	wall("z", 18.0, 0.0, 12.0, [], green, ext)
	# Фасад: дверь и витрина.
	wall("x", 16.0, -0.1, 12.1, [{"a": 1.0, "b": 2.2, "top": 2.2}, {"a": 4.5, "b": 11.5, "bottom": 0.6, "top": 2.6}], paint, ext)
	wall("z", 12.0, 10.0, 16.0, [], paint, ext)
	wall("x", 12.0, 12.0, 18.1, [], green, ext)
	# Склад / примерочные / рабочее место (z=7).
	wall("x", 7.0, 0.0, 12.0, [{"a": 10.5, "b": 11.5}], wh, paint)
	# Склад / коридор (x=12).
	wall("z", 12.0, 0.0, 7.0, [{"a": 1.5, "b": 2.5}], wh, green)
	# Рабочее место / коридор.
	wall("z", 12.0, 7.0, 10.0, [{"a": 8.0, "b": 9.0}], paint, green)
	# Коридор / восточные помещения (x=14).
	wall("z", 14.0, 0.0, 12.0, [{"a": 1.0, "b": 2.0}, {"a": 5.0, "b": 6.0}, {"a": 8.5, "b": 9.5}], green, paint)
	# Перегородки между восточными помещениями.
	wall("x", 3.5, 14.0, 18.0, [], paint)
	wall("x", 7.5, 14.0, 18.0, [], paint, tile)
	# Плитка внутри туалета (внутренние облицовки).
	Build.box(self, Vector3(0.02, H, 4.3), Vector3(17.88, H * 0.5, 9.75), tile)
	Build.box(self, Vector3(0.02, H, 4.3), Vector3(14.12, H * 0.5, 9.75), tile).visible = false
	# Примерочные: стена в зал с проёмами под шторы, перегородки.
	wall("x", 10.0, 0.0, 6.0, [{"a": 0.3, "b": 1.9, "top": 2.2}, {"a": 2.5, "b": 4.1, "top": 2.2}], paint)
	wall("z", 2.2, 7.0, 10.0, [], paint)
	wall("z", 4.4, 7.0, 10.0, [], paint)
	wall("z", 6.0, 7.0, 10.0, [], paint)
	# Входная зона: боковая перегородка.
	wall("z", 3.4, 13.8, 16.0, [], paint)


func _build_floors_and_ceiling() -> void:
	# Единый коллайдер пола.
	var fl := Build.box(self, Vector3(80, 0.2, 60), Vector3(9, -0.1, 18), Mats.surface("asphalt"), true)
	fl.visible = false
	var floors := [
		[Rect2(0, 0, 12, 7), "concrete"],
		[Rect2(0, 7, 12, 9), "floor_tile"],
		[Rect2(12, 0, 2, 12), "linoleum"],
		[Rect2(14, 0, 4, 3.5), "concrete"],
		[Rect2(14, 3.5, 4, 4), "linoleum"],
		[Rect2(14, 7.5, 4, 4.5), "floor_tile"],
	]
	for f in floors:
		var r: Rect2 = f[0]
		var m := Build.box(self, Vector3(r.size.x, 0.1, r.size.y), Vector3(r.position.x + r.size.x * 0.5, -0.05, r.position.y + r.size.y * 0.5), Mats.surface(f[1]))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ceil := Build.box(self, Vector3(18.2, 0.1, 16.2), Vector3(9, H + 0.05, 8), Mats.surface("ceiling"))
	ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Пятна протечек на потолке — тёмные пятна.
	for p in [Vector3(3.5, H - 0.005, 2.5), Vector3(13.0, H - 0.005, 6.0), Vector3(8.0, H - 0.005, 13.5)]:
		var s := Build.quad(self, Vector2(1.2, 0.9), p, Mats.color(Color(0.32, 0.26, 0.17), 1.0), Vector3(90, _rng.randf() * 180, 0))
		s.material_override = _stain_mat()


func _stain_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.24, 0.14, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	m.albedo_texture = g
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ======================================================================= Улица

func _build_street() -> void:
	var ground := Build.box(self, Vector3(60, 0.1, 30), Vector3(6, -0.05, 31), Mats.surface("asphalt"))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Build.box(self, Vector3(60, 0.15, 3.0), Vector3(6, 0.02, 17.5), Mats.surface("concrete"))
	Build.box(self, Vector3(60, 0.18, 0.2), Vector3(6, 0.05, 19.0), Mats.color(Color(0.4, 0.4, 0.38)))
	# Фасад дома над ПВЗ и соседние окна.
	Build.box(self, Vector3(40, 12, 0.3), Vector3(6, 9.0, 16.2), Mats.surface("exterior"))
	Build.box(self, Vector3(40, 18, 0.5), Vector3(6, 9.0, 36.0), Mats.surface("exterior"))
	for i in 18:
		var wx := -10.0 + (i % 9) * 4.0
		var wy := 3.5 + floori(i / 9.0) * 3.2
		var lit := _rng.randf() < 0.25
		var c := Color(0.95, 0.7, 0.4) if lit else Color(0.05, 0.06, 0.08)
		Build.quad(self, Vector2(1.3, 1.6), Vector3(wx, wy, 35.7), Mats.emissive(c, 0.8 if lit else 0.0), Vector3(0, 180, 0))
	# Вывеска ПВЗ над входом.
	Build.box(self, Vector3(4.0, 0.6, 0.15), Vector3(3.5, 3.4, 16.25), Mats.color(Color(0.08, 0.1, 0.12)))
	var sign := Build.label(self, "ПУНКТ ВЫДАЧИ ЗАКАЗОВ\n«ПОСЫЛКА» · КРУГЛОСУТОЧНО", Vector3(3.5, 3.4, 16.34), 0.09, Color(0.85, 0.9, 0.95))
	sign.shaded = false
	# Фонарь.
	Build.cyl(self, 0.08, 6.0, Vector3(8.0, 3.0, 18.6), Mats.metal(Color(0.2, 0.2, 0.22)))
	Build.box(self, Vector3(0.9, 0.12, 0.3), Vector3(7.6, 6.0, 18.4), Mats.color(Color(0.15, 0.15, 0.16)))
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(7.4, 5.9, 18.3)
	lamp.rotation_degrees = Vector3(-62, 180, 0)
	lamp.light_color = Color(1.0, 0.62, 0.32)
	lamp.light_energy = 3.0
	lamp.spot_range = 16.0
	lamp.spot_angle = 55.0
	lamp.spot_attenuation = 0.8
	lamp.name = "StreetLamp"
	add_child(lamp)
	lighting.register_extra("street", lamp)
	Build.box(self, Vector3(0.6, 0.04, 0.2), Vector3(7.4, 5.93, 18.3), Mats.emissive(Color(1.0, 0.7, 0.4), 3.0))
	# Припаркованная машина (силуэт).
	var car := Node3D.new()
	add_child(car)
	car.position = Vector3(-3.0, 0, 21.5)
	Build.box(car, Vector3(4.2, 0.7, 1.8), Vector3(0, 0.55, 0), Mats.color(Color(0.18, 0.2, 0.22), 0.3, 0.4))
	Build.box(car, Vector3(2.2, 0.55, 1.6), Vector3(-0.2, 1.15, 0), Mats.color(Color(0.05, 0.06, 0.07), 0.1, 0.5))
	# Тусклый фонарь над входом: фигуру за стеклом можно разглядеть.
	var door_lamp := OmniLight3D.new()
	door_lamp.position = Vector3(1.6, 2.7, 16.7)
	door_lamp.light_color = Color(0.85, 0.9, 1.0)
	door_lamp.light_energy = 0.7
	door_lamp.omni_range = 4.5
	add_child(door_lamp)
	lighting.register_extra("street", door_lamp)
	Build.box(self, Vector3(0.3, 0.08, 0.15), Vector3(1.6, 2.75, 16.42), Mats.emissive(Color(0.9, 0.95, 1.0), 1.5))
	spawn["faceless_outside"] = Vector3(1.6, 0, 17.3)
	spawn["street_far"] = Vector3(-6.0, 0, 18.0)


# ======================================================================= Склад

func _rack(origin: Vector3, sections: int, sec_w: float, depth: float, facing_z: float, letter: String, interactive_level := 1) -> void:
	var up_mat := Mats.metal(Color(0.32, 0.38, 0.5))
	var shelf_mat := Mats.metal(Color(0.55, 0.55, 0.52))
	var total := sections * sec_w
	var levels := [0.08, 0.78, 1.48, 2.18]
	var rack := Node3D.new()
	rack.position = origin
	add_child(rack)
	for s in sections + 1:
		for dz in [-depth * 0.5 + 0.03, depth * 0.5 - 0.03]:
			Build.box(rack, Vector3(0.05, 2.4, 0.05), Vector3(s * sec_w, 1.2, dz), up_mat)
	for lv in levels:
		Build.box(rack, Vector3(total, 0.03, depth), Vector3(total * 0.5, lv, 0), shelf_mat)
		Build.box(rack, Vector3(total, 0.06, 0.02), Vector3(total * 0.5, lv + 0.02, facing_z * depth * 0.5), Mats.color(Color(0.9, 0.45, 0.1), 0.6))
	var col := Node3D.new()
	rack.add_child(col)
	Build.add_box_collider(col, Vector3(total, 2.4, depth)).position = Vector3(total * 0.5, 1.2, 0)
	for s in sections:
		var cell_id := "%s-%d" % [letter, s + 1]
		var cx := s * sec_w + sec_w * 0.5
		var lbl := Build.label(rack, cell_id, Vector3(cx, levels[interactive_level] + 0.05, facing_z * (depth * 0.5 + 0.015)), 0.06, Color(0.05, 0.05, 0.05), Vector3(0, 0 if facing_z > 0 else 180, 0))
		lbl.modulate = Color(0.08, 0.08, 0.08)
		Build.box(rack, Vector3(0.22, 0.08, 0.005), Vector3(cx, levels[interactive_level] + 0.05, facing_z * (depth * 0.5 + 0.01)), Mats.color(Color(0.95, 0.92, 0.6)))
		# Декоративные коробки на прочих полках.
		for li in levels.size():
			if li == interactive_level:
				continue
			var x := s * sec_w + 0.08
			while x < (s + 1) * sec_w - 0.25:
				var w := _rng.randf_range(0.22, 0.5)
				if x + w > (s + 1) * sec_w - 0.05:
					break
				var h := _rng.randf_range(0.15, 0.5) if li < 3 else _rng.randf_range(0.15, 0.45)
				var d := _rng.randf_range(0.25, depth - 0.05)
				if _rng.randf() < 0.85:
					var xf := Transform3D(Basis().scaled(Vector3(w, h, d)).rotated(Vector3.UP, _rng.randf_range(-0.08, 0.08) + (0.0 if facing_z > 0 else PI)), rack.position + Vector3(x + w * 0.5, levels[li] + 0.015 + h * 0.5, 0))
					_card_xforms.append(xf)
				x += w + _rng.randf_range(0.02, 0.1)
		# Интерактивная ячейка.
		var spot := DropSpot.new()
		spot.spot_id = cell_id
		spot.verb = "Положить в ячейку %s" % cell_id
		rack.add_child(spot)
		spot.position = Vector3(cx, levels[interactive_level] + 0.02, 0)
		spot.rotation_degrees.y = 0 if facing_z > 0 else 180
		spot.setup_shape(Vector3(sec_w - 0.1, 0.6, depth), Vector3(0, 0.3, 0))
		spot.place_offset = Vector3(-sec_w * 0.25, 0, 0)
		cells[cell_id] = spot


func _build_warehouse() -> void:
	# Ряды: А (у северной стены), Б и В (центральный проход), Г — старый у западной стены.
	_rack(Vector3(7.2, 0, 0.7), 4, 1.1, 0.6, 1.0, "А")
	_rack(Vector3(1.6, 0, 3.0), 6, 1.3, 0.6, 1.0, "Б")
	_rack(Vector3(1.6, 0, 4.9), 6, 1.3, 0.6, -1.0, "В")
	# Старый стеллаж у западной стены (декор, пыльные коробки).
	var old := Node3D.new()
	add_child(old)
	old.position = Vector3(0.4, 0, 1.0)
	old.rotation_degrees.y = -90
	for s in 5:
		for dz in [-0.27, 0.27]:
			Build.box(old, Vector3(0.05, 2.4, 0.05), Vector3(s * 1.2, 1.2, dz), Mats.metal(Color(0.3, 0.3, 0.28)))
	for lv in [0.1, 0.9, 1.7]:
		Build.box(old, Vector3(4.8, 0.03, 0.6), Vector3(2.4, lv, 0), Mats.color(Color(0.35, 0.3, 0.22)))
		for i in 6:
			if _rng.randf() < 0.75:
				var w := _rng.randf_range(0.3, 0.6)
				var h := _rng.randf_range(0.25, 0.6)
				_card_xforms.append(Transform3D(Basis().scaled(Vector3(w, h, 0.5)).rotated(Vector3.UP, -PI * 0.5 + _rng.randf_range(-0.2, 0.2)), Vector3(0.4, lv + h * 0.5 + 0.02, 1.0 + i * 0.8 + 0.3)))
	Build.add_box_collider(old, Vector3(4.8, 2.4, 0.6)).position = Vector3(2.4, 1.2, 0)
	# Рольставня приёмки.
	var sh := Node3D.new()
	add_child(sh)
	for i in 13:
		Build.box(sh, Vector3(2.4, 0.18, 0.05), Vector3(5.4, 0.1 + i * 0.2, 0.06), Mats.metal(Color(0.5, 0.52, 0.5)))
	Build.add_box_collider(sh, Vector3(2.4, 2.6, 0.1)).position = Vector3(5.4, 1.3, 0.06)
	Build.label(self, "ПРИЁМКА", Vector3(5.4, 2.75, 0.12), 0.12, Color(0.9, 0.2, 0.1))
	# Поддон приёмки.
	var pallet := Build.box(self, Vector3(1.4, 0.14, 1.0), Vector3(5.4, 0.07, 1.0), Mats.color(Color(0.55, 0.42, 0.26)), true)
	pallet.name = "Pallet"
	intake_spot = DropSpot.new()
	intake_spot.spot_id = "intake"
	intake_spot.verb = "Вернуть на поддон"
	add_child(intake_spot)
	intake_spot.position = Vector3(5.4, 0.14, 1.0)
	intake_spot.setup_shape(Vector3(1.4, 0.5, 1.0), Vector3(0, 0.25, 0))
	intake_spot.place_offset = Vector3(-0.35, 0, 0)
	# Вешала с одеждой у восточной стены.
	clothes_rail = Node3D.new()
	clothes_rail.position = Vector3(11.65, 0, 3.4)
	add_child(clothes_rail)
	Build.box(clothes_rail, Vector3(0.04, 1.8, 0.04), Vector3(0, 0.9, 0), Mats.metal())
	Build.box(clothes_rail, Vector3(0.04, 1.8, 0.04), Vector3(0, 0.9, 2.4), Mats.metal())
	Build.cyl(clothes_rail, 0.015, 2.4, Vector3(0, 1.78, 1.2), Mats.metal(), Vector3(90, 0, 0))
	Build.label(self, "ОДЕЖДА / ПРИМЕРКА", Vector3(11.85, 2.2, 4.6), 0.07, Color(0.1, 0.1, 0.1), Vector3(0, -90, 0))
	# Мусор, коробки на полу.
	for p in [Vector3(9.9, 0, 6.3), Vector3(2.5, 0, 6.4), Vector3(0.9, 0, 6.5), Vector3(8.4, 0, 1.6)]:
		var w := _rng.randf_range(0.4, 0.7)
		var h := _rng.randf_range(0.3, 0.6)
		_card_xforms.append(Transform3D(Basis().scaled(Vector3(w, h, w * 0.8)).rotated(Vector3.UP, _rng.randf() * PI), p + Vector3(0, h * 0.5, 0)))
	# Сдвигаемая коробка для событий «предмет сместился».
	var mv := Build.box(self, Vector3(0.5, 0.45, 0.4), Vector3(7.8, 0.225, 6.3), Mats.cardboard(42.0))
	mv.name = "LooseBox"
	movable_props.append(mv)
	# Стремянка.
	var ladder := Node3D.new()
	ladder.position = Vector3(9.95, 0, 2.0)
	ladder.rotation_degrees = Vector3(0, 0, 0)
	add_child(ladder)
	for dz in [-0.2, 0.2]:
		Build.box(ladder, Vector3(0.04, 1.8, 0.05), Vector3(0, 0.9, dz), Mats.metal(Color(0.7, 0.7, 0.7)), false, Vector3(8, 0, 0))
	for i in 5:
		Build.box(ladder, Vector3(0.05, 0.03, 0.42), Vector3(0.0, 0.3 + i * 0.32, 0), Mats.metal(Color(0.7, 0.7, 0.7)))
	movable_props.append(ladder)
	# Огнетушитель.
	_extinguisher(Vector3(0.25, 0, 6.6))
	_poster(Vector3(6.0, 1.7, 6.88), Vector3(0, 180, 0), ["ТЕХНИКА БЕЗОПАСНОСТИ", "Не загромождать проходы."], Color(0.85, 0.85, 0.75), Color(0.6, 0.1, 0.1))
	dark_spots.append_array([Vector3(1.0, 0, 5.8), Vector3(9.9, 0, 6.5), Vector3(1.0, 0, 1.6), Vector3(10.6, 0, 1.6)])
	spawn["courier"] = Vector3(5.4, 0, 1.9)


# ======================================================================= Рабочее место

func _build_workstation() -> void:
	# Стойка выдачи вдоль z=10, проход-откидушка x 6..7.
	var counter_mat := Mats.color(Color(0.62, 0.6, 0.56), 0.5)
	var top_mat := Mats.color(Color(0.82, 0.8, 0.75), 0.35)
	Build.box(self, Vector3(5.0, 1.0, 0.55), Vector3(9.5, 0.5, 10.0), counter_mat, true)
	Build.box(self, Vector3(5.1, 0.05, 0.7), Vector3(9.5, 1.025, 10.0), top_mat)
	Build.box(self, Vector3(5.0, 0.12, 0.02), Vector3(9.5, 0.9, 10.29), Mats.color(Color(0.1, 0.35, 0.6)))
	Build.label(self, "ВЫДАЧА ЗАКАЗОВ", Vector3(9.5, 0.7, 10.29), 0.09, Color(0.95, 0.95, 0.95))
	# Монитор ПК.
	var mon := Node3D.new()
	mon.position = Vector3(10.4, 1.05, 9.85)
	add_child(mon)
	Build.box(mon, Vector3(0.18, 0.02, 0.15), Vector3(0, 0.01, 0), Mats.color(Color(0.08, 0.08, 0.08)))
	Build.box(mon, Vector3(0.04, 0.25, 0.04), Vector3(0, 0.13, 0.03), Mats.color(Color(0.08, 0.08, 0.08)))
	Build.box(mon, Vector3(0.56, 0.36, 0.04), Vector3(0, 0.42, 0.0), Mats.color(Color(0.06, 0.06, 0.06)))
	pc_screen = Build.box(mon, Vector3(0.52, 0.31, 0.005), Vector3(0, 0.42, -0.022), Mats.emissive(Color(0.25, 0.4, 0.6), 0.9, "pc_screen"))
	var glow := OmniLight3D.new()
	glow.position = Vector3(10.4, 1.45, 9.5)
	glow.light_color = Color(0.5, 0.65, 1.0)
	glow.light_energy = 0.35
	glow.omni_range = 2.2
	add_child(glow)
	lighting.register_extra("workstation", glow)
	# Монитор видеонаблюдения.
	var cm := Node3D.new()
	cm.position = Vector3(11.35, 1.05, 9.8)
	cm.rotation_degrees.y = -25
	add_child(cm)
	Build.box(cm, Vector3(0.42, 0.33, 0.25), Vector3(0, 0.17, 0.0), Mats.color(Color(0.12, 0.12, 0.11)))
	cctv_screen = Build.box(cm, Vector3(0.36, 0.26, 0.005), Vector3(0, 0.18, -0.128), Mats.emissive(Color(0.1, 0.15, 0.1), 0.6, "cctv_screen"))
	# Клавиатура, сканер, терминал, звонок, принтер.
	Build.box(self, Vector3(0.42, 0.02, 0.14), Vector3(10.4, 1.06, 9.6), Mats.color(Color(0.1, 0.1, 0.1)))
	var sc := Node3D.new()
	sc.position = Vector3(9.5, 1.05, 9.8)
	add_child(sc)
	Build.box(sc, Vector3(0.12, 0.03, 0.12), Vector3(0, 0.015, 0), Mats.color(Color(0.15, 0.15, 0.15)))
	Build.box(sc, Vector3(0.05, 0.16, 0.06), Vector3(0, 0.1, 0), Mats.color(Color(0.95, 0.75, 0.1)), false, Vector3(-20, 0, 0))
	Build.box(sc, Vector3(0.04, 0.01, 0.02), Vector3(0, 0.16, -0.04), Mats.emissive(Color(1, 0.1, 0.1), 2.0))
	scanner_spot = DropSpot.new()
	scanner_spot.spot_id = "scanner"
	scanner_spot.verb = "Отсканировать"
	scanner_spot.takes_item = false
	add_child(scanner_spot)
	scanner_spot.position = Vector3(9.4, 1.05, 9.75)
	scanner_spot.setup_shape(Vector3(0.6, 0.4, 0.45), Vector3(0, 0.2, 0))
	counter_spot = DropSpot.new()
	counter_spot.spot_id = "counter"
	counter_spot.verb = "Выдать"
	add_child(counter_spot)
	counter_spot.position = Vector3(8.2, 1.05, 10.0)
	counter_spot.setup_shape(Vector3(1.4, 0.4, 0.6), Vector3(0, 0.2, 0))
	counter_spot.place_offset = Vector3(0, 0, 0)
	Build.box(self, Vector3(0.08, 0.04, 0.16), Vector3(8.4, 1.07, 10.25), Mats.color(Color(0.12, 0.12, 0.12)))  # терминал оплаты
	Build.box(self, Vector3(0.06, 0.005, 0.04), Vector3(8.4, 1.09, 10.22), Mats.emissive(Color(0.3, 0.8, 0.5), 0.6))
	Build.cyl(self, 0.05, 0.03, Vector3(9.0, 1.07, 10.25), Mats.metal(Color(0.8, 0.8, 0.82)))
	Build.sphere(self, 0.045, Vector3(9.0, 1.09, 10.25), Mats.metal(Color(0.8, 0.8, 0.82)), Vector3(1, 0.6, 1))
	var pr := Node3D.new()
	pr.position = Vector3(11.75, 1.05, 9.3)
	add_child(pr)
	Build.box(pr, Vector3(0.35, 0.18, 0.3), Vector3(0, 0.09, 0), Mats.color(Color(0.85, 0.85, 0.82)))
	Build.box(pr, Vector3(0.22, 0.005, 0.12), Vector3(0, 0.19, -0.1), Mats.color(Color(0.97, 0.97, 0.95)))
	# Стол под принтер (у стены рабочего места).
	Build.box(self, Vector3(0.6, 1.05, 0.9), Vector3(11.65, 0.525, 9.3), Mats.color(Color(0.4, 0.38, 0.35)), true)
	printer = Interactable.new()
	printer.prompt_text = "Взять чек"
	printer.enabled = false
	pr.add_child(printer)
	printer.setup_shape(Vector3(0.4, 0.3, 0.35), Vector3(0, 0.15, 0))
	# Место за компьютером.
	var chair := Node3D.new()
	chair.position = Vector3(10.4, 0, 9.0)
	add_child(chair)
	Build.box(chair, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.5, 0), Mats.color(Color(0.1, 0.1, 0.12)))
	Build.box(chair, Vector3(0.5, 0.55, 0.06), Vector3(0, 0.85, -0.25), Mats.color(Color(0.1, 0.1, 0.12)))
	Build.cyl(chair, 0.03, 0.45, Vector3(0, 0.25, 0), Mats.metal())
	desk_seat = Interactable.new()
	desk_seat.prompt_text = "Сесть за компьютер"
	desk_seat.position = Vector3(10.4, 1.05, 9.85)
	add_child(desk_seat)
	desk_seat.setup_shape(Vector3(1.6, 0.6, 0.4), Vector3(0.2, 0.35, 0))
	spawn["seat"] = Vector3(10.4, 0, 9.05)
	# Полка «к выдаче» у задней стены.
	var shelf := Node3D.new()
	shelf.position = Vector3(6.4, 0, 7.35)
	add_child(shelf)
	for x in [0.0, 1.5, 3.0]:
		Build.box(shelf, Vector3(0.04, 2.0, 0.4), Vector3(x, 1.0, 0), Mats.metal(Color(0.6, 0.6, 0.6)))
	for y in [0.4, 1.0, 1.6]:
		Build.box(shelf, Vector3(3.0, 0.03, 0.4), Vector3(1.5, y, 0), Mats.metal(Color(0.65, 0.65, 0.62)))
		for i in 5:
			if _rng.randf() < 0.6:
				var w := _rng.randf_range(0.2, 0.4)
				var h := _rng.randf_range(0.12, 0.3)
				_card_xforms.append(Transform3D(Basis().scaled(Vector3(w, h, 0.3)).rotated(Vector3.UP, PI), shelf.position + Vector3(0.2 + i * 0.58, y + 0.015 + h * 0.5, 0)))
	Build.add_box_collider(shelf, Vector3(3.0, 2.0, 0.4)).position = Vector3(1.5, 1.0, 0)
	# Телефон на стене.
	var ph := Node3D.new()
	ph.position = Vector3(11.88, 1.4, 7.6)
	ph.rotation_degrees.y = -90
	add_child(ph)
	Build.box(ph, Vector3(0.2, 0.25, 0.08), Vector3.ZERO, Mats.color(Color(0.75, 0.7, 0.6)))
	Build.box(ph, Vector3(0.05, 0.22, 0.06), Vector3(-0.07, 0.0, 0.06), Mats.color(Color(0.7, 0.65, 0.55)))
	phone = Interactable.new()
	phone.prompt_text = "Снять трубку"
	phone.enabled = false
	ph.add_child(phone)
	phone.setup_shape(Vector3(0.3, 0.35, 0.3))
	Build.label(self, "Тел. отключён 12.03", Vector3(11.89, 1.15, 7.6), 0.025, Color(0.2, 0.2, 0.2), Vector3(0, -90, 0))
	# Часы.
	_clock(Vector3(11.88, 2.3, 8.6), Vector3(0, -90, 0))
	_clock(Vector3(5.2, 2.4, 10.12), Vector3(0, 0, 0))
	# Укрытие под стойкой.
	var hs := HideSpot.new()
	hs.spot_name = "под стойкой"
	hs.position = Vector3(7.6, 0.4, 9.55)
	add_child(hs)
	hs.setup_shape(Vector3(0.9, 0.7, 0.5))
	hs.view_point = _marker(Vector3(7.6, 0.55, 9.75), Vector3(0, 180, 0))
	hs.exit_point = _marker(Vector3(7.6, 0, 9.0), Vector3(0, 180, 0))
	hide_spots.append(hs)
	_poster(Vector3(8.0, 1.8, 7.12), Vector3.ZERO, ["РЕГЛАМЕНТ НОЧНОЙ СМЕНЫ", "1. Не открывайте дверь.", "2. Отвечайте клиентам."], Color(0.95, 0.95, 0.92), Color(0.1, 0.2, 0.5))
	# Выключатели.
	_switch("workstation", Vector3(6.12, 1.3, 7.7), Vector3(0, 90, 0))
	_switch("hall", Vector3(6.12, 1.3, 8.0), Vector3(0, 90, 0))
	_switch("fitting", Vector3(6.12, 1.3, 8.3), Vector3(0, 90, 0))
	spawn["player"] = Vector3(9.0, 0, 8.3)


func _clock(pos: Vector3, rot: Vector3) -> void:
	var c := Node3D.new()
	c.position = pos
	c.rotation_degrees = rot
	add_child(c)
	Build.cyl(c, 0.17, 0.04, Vector3.ZERO, Mats.color(Color(0.95, 0.95, 0.92)), Vector3(90, 0, 0), 20)
	var l := Build.label(c, "00:00", Vector3(0, 0, 0.025), 0.1, Color(0.05, 0.05, 0.05))
	clock_labels.append(l)


func _marker(pos: Vector3, rot: Vector3) -> Node3D:
	var m := Marker3D.new()
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)
	return m


func _switch(zone: String, pos: Vector3, rot: Vector3) -> void:
	var s := Interactable.new()
	s.position = pos
	s.rotation_degrees = rot
	add_child(s)
	Build.box(s, Vector3(0.08, 0.12, 0.02), Vector3.ZERO, Mats.color(Color(0.9, 0.9, 0.86)))
	s.setup_shape(Vector3(0.12, 0.16, 0.08))
	s.prompt_text = "Свет: " + Lighting.ZONE_NAMES[zone]
	s.tag = zone
	s.action = func(_p): lighting.set_switch(zone, not lighting.switches[zone])


func _extinguisher(pos: Vector3) -> void:
	Build.cyl(self, 0.08, 0.5, pos + Vector3(0, 0.25, 0), Mats.color(Color(0.75, 0.08, 0.06), 0.4))
	Build.cyl(self, 0.02, 0.08, pos + Vector3(0, 0.53, 0), Mats.color(Color(0.1, 0.1, 0.1)))


func _poster(pos: Vector3, rot: Vector3, lines: Array, bg: Color, fg: Color, size := Vector2(0.6, 0.8)) -> void:
	var p := Node3D.new()
	p.position = pos
	p.rotation_degrees = rot
	add_child(p)
	Build.box(p, Vector3(size.x, size.y, 0.005), Vector3.ZERO, Mats.color(bg, 0.9))
	var txt := "\n".join(PackedStringArray(lines))
	Build.label(p, txt, Vector3(0, size.y * 0.3, 0.006), 0.035, fg, Vector3.ZERO, size.x * 0.9)
	var bars := Build.quad(p, Vector2(size.x * 0.8, size.y * 0.35), Vector3(0, -size.y * 0.2, 0.006), Mats.color(fg.lerp(bg, 0.6), 0.9))
	bars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ======================================================================= Зал

func _build_hall() -> void:
	# Входная стеклянная дверь.
	var front := Door.new()
	front.door_id = "front"
	front.glass = true
	front.width = 1.2
	front.position = Vector3(1.0, 0, 16.0)
	add_child(front)
	front.build(null)
	front.capture_base()
	front.locked = true
	front.lock_reason = "Магнитный замок включён. Ночью вход закрыт."
	doors["front"] = front
	# Магнитный замок у двери (изнутри).
	maglock = Interactable.new()
	maglock.position = Vector3(0.12, 1.4, 15.3)
	maglock.rotation_degrees.y = 90
	add_child(maglock)
	Build.box(maglock, Vector3(0.14, 0.2, 0.05), Vector3.ZERO, Mats.color(Color(0.2, 0.2, 0.2)))
	var led := Build.box(maglock, Vector3(0.03, 0.03, 0.01), Vector3(0, 0.05, 0.03), Mats.emissive(Color(1, 0.1, 0.1), 3.0, "maglock_led"))
	led.name = "Led"
	maglock.setup_shape(Vector3(0.25, 0.3, 0.15))
	Build.label(self, "ЗАМОК", Vector3(0.13, 1.6, 15.3), 0.03, Color(0.1, 0.1, 0.1), Vector3(0, 90, 0))
	# Витрина.
	var win := Build.box(self, Vector3(7.0, 2.0, 0.03), Vector3(8.0, 1.6, 16.0), Mats.glass(), true)
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Build.label(self, "ПУНКТ ВЫДАЧИ · 24/7", Vector3(8.0, 2.2, 15.98), 0.12, Color(0.9, 0.9, 0.85), Vector3(0, 180, 0))
	# Жалюзи (наполовину опущены).
	for i in 10:
		Build.box(self, Vector3(7.0, 0.002, 0.06), Vector3(8.0, 2.55 - i * 0.07, 15.9), Mats.color(Color(0.8, 0.8, 0.78)), false, Vector3(55, 0, 0), false)
	# Коврик у входа.
	Build.box(self, Vector3(1.6, 0.015, 1.0), Vector3(1.6, 0.008, 15.3), Mats.color(Color(0.15, 0.12, 0.1)))
	# Скамья, растение, стойка с правилами, урна, ограждение очереди.
	Build.box(self, Vector3(2.0, 0.08, 0.4), Vector3(8.0, 0.45, 15.4), Mats.color(Color(0.3, 0.22, 0.15)), true)
	for x in [7.2, 8.8]:
		Build.box(self, Vector3(0.05, 0.45, 0.35), Vector3(x, 0.22, 15.4), Mats.metal())
	var plant := Node3D.new()
	plant.position = Vector3(11.4, 0, 15.3)
	add_child(plant)
	Build.cyl(plant, 0.18, 0.4, Vector3(0, 0.2, 0), Mats.color(Color(0.3, 0.2, 0.15)))
	for i in 7:
		var a := i * TAU / 7.0
		Build.box(plant, Vector3(0.06, 0.6, 0.02), Vector3(cos(a) * 0.1, 0.65, sin(a) * 0.1), Mats.color(Color(0.25, 0.32, 0.15)), false, Vector3(sin(a) * 25, a * 57.0, cos(a) * 25))
	movable_props.append(plant)
	for x in [5.5, 7.0]:
		Build.cyl(self, 0.03, 0.95, Vector3(x, 0.475, 11.6), Mats.metal(Color(0.7, 0.7, 0.72)))
		Build.cyl(self, 0.15, 0.03, Vector3(x, 0.015, 11.6), Mats.metal(Color(0.3, 0.3, 0.3)))
	Build.box(self, Vector3(1.5, 0.05, 0.01), Vector3(6.25, 0.88, 11.6), Mats.color(Color(0.1, 0.15, 0.5)))
	var chair := Node3D.new()
	chair.position = Vector3(3.8, 0, 12.6)
	chair.rotation_degrees.y = 20
	add_child(chair)
	Build.box(chair, Vector3(0.45, 0.05, 0.45), Vector3(0, 0.45, 0), Mats.color(Color(0.2, 0.3, 0.45)))
	Build.box(chair, Vector3(0.45, 0.45, 0.04), Vector3(0, 0.7, -0.22), Mats.color(Color(0.2, 0.3, 0.45)))
	for dx in [-0.2, 0.2]:
		for dz in [-0.2, 0.2]:
			Build.box(chair, Vector3(0.03, 0.45, 0.03), Vector3(dx, 0.22, dz), Mats.metal())
	movable_props.append(chair)
	Build.cyl(self, 0.17, 0.5, Vector3(11.5, 0.25, 10.6), Mats.color(Color(0.25, 0.25, 0.25)))
	_extinguisher(Vector3(11.75, 0, 11.2))
	# Знак «мокрый пол».
	var wet := Node3D.new()
	wet.position = Vector3(5.0, 0, 14.2)
	add_child(wet)
	Build.box(wet, Vector3(0.3, 0.6, 0.02), Vector3(0, 0.3, 0.08), Mats.color(Color(0.95, 0.8, 0.1)), false, Vector3(-12, 0, 0))
	Build.box(wet, Vector3(0.3, 0.6, 0.02), Vector3(0, 0.3, -0.08), Mats.color(Color(0.95, 0.8, 0.1)), false, Vector3(12, 0, 0))
	Build.label(wet, "ОСТОРОЖНО\nМОКРЫЙ ПОЛ", Vector3(0, 0.35, 0.1), 0.03, Color(0.1, 0.1, 0.1), Vector3(-12, 0, 0))
	movable_props.append(wet)
	# Плакаты.
	_poster(Vector3(5.2, 1.6, 10.12), Vector3.ZERO, ["ВОЗВРАТ ТОВАРА", "В течение 14 дней.", "Только при наличии заказа в системе."], Color(0.95, 0.95, 0.92), Color(0.6, 0.1, 0.1), Vector2(0.7, 0.9))
	_poster(Vector3(11.88, 1.6, 13.5), Vector3(0, -90, 0), ["СКИДКИ ДО 90%", "Каждую ночь!"], Color(0.85, 0.2, 0.45), Color(1, 1, 1), Vector2(0.8, 1.1))
	_poster(Vector3(0.12, 1.6, 12.0), Vector3(0, 90, 0), ["ПРИМЕРКА", "Не более 5 вещей.", "Не оставляйте вещи без присмотра."], Color(0.92, 0.92, 0.88), Color(0.15, 0.15, 0.15))
	_poster(Vector3(3.28, 1.5, 15.0), Vector3(0, -90, 0), ["ВНИМАНИЕ", "Ночью вход по звонку.", "Звонок не работает."], Color(0.95, 0.95, 0.9), Color(0.6, 0.1, 0.1), Vector2(0.5, 0.65))
	# Камеры-купола на потолке.
	dark_spots.append_array([Vector3(0.5, 0, 15.5), Vector3(11.3, 0, 13.8), Vector3(4.9, 0, 10.6)])
	spawn["client"] = Vector3(9.0, 0, 10.85)


# ======================================================================= Примерочные

func _build_fitting() -> void:
	for i in 2:
		var x0 := 0.0 if i == 0 else 2.2
		var cx := x0 + 1.1
		var room := "cab_a" if i == 0 else "cab_b"
		var curtain := Curtain.new()
		curtain.cabin_index = i
		curtain.position = Vector3(cx, 0, 10.0)
		add_child(curtain)
		curtain.build(1.6)
		# Зеркало в кабинке (тёмное, глянцевое).
		Build.box(self, Vector3(0.6, 1.5, 0.02), Vector3(cx, 1.3, 7.13), Mats.mirror())
		Build.box(self, Vector3(0.66, 1.56, 0.015), Vector3(cx, 1.3, 7.12), Mats.color(Color(0.3, 0.25, 0.2)))
		var stool := Build.cyl(self, 0.18, 0.45, Vector3(cx + 0.55, 0.225, 8.0), Mats.color(Color(0.3, 0.3, 0.32)))
		if i == 1:
			movable_props.append(stool)
		Build.box(self, Vector3(0.03, 0.03, 0.12), Vector3(x0 + 0.15, 1.7, 8.3), Mats.metal(), false)
		var spot := DropSpot.new()
		spot.spot_id = room
		spot.verb = "Передать за шторку"
		spot.keep_item = false
		add_child(spot)
		spot.position = Vector3(cx, 0, 10.25)
		spot.setup_shape(Vector3(1.4, 2.0, 0.2), Vector3(0, 1.0, 0))
		spot.enabled = false
		cabins.append({"curtain": curtain, "spot": spot, "room": room, "inside": Vector3(cx, 0, 8.4)})
		# Тусклая тёплая лампа в кабинке.
		var l := OmniLight3D.new()
		l.position = Vector3(cx, 2.7, 8.4)
		l.light_color = Color(1.0, 0.85, 0.65)
		l.light_energy = 0.5
		l.omni_range = 2.6
		add_child(l)
		lighting.register_extra("fitting", l)
		Build.box(self, Vector3(0.25, 0.05, 0.25), Vector3(cx, 2.97, 8.4), Mats.emissive(Color(1.0, 0.85, 0.6), 1.0))


# ======================================================================= Коридор

func _build_corridor() -> void:
	var paint := Mats.color(Color(0.55, 0.5, 0.42), 0.7)
	var defs := [
		["wh_cor", Vector3(12.0, 0, 1.5), -90.0, paint, "Дверь на склад"],
		["ws_cor", Vector3(12.0, 0, 8.0), -90.0, paint, ""],
		["util", Vector3(14.0, 0, 5.0), -90.0, paint, ""],
		["toilet", Vector3(14.0, 0, 8.5), -90.0, Mats.color(Color(0.8, 0.8, 0.78), 0.6), ""],
		["tech", Vector3(14.0, 0, 1.0), -90.0, Mats.metal(Color(0.32, 0.3, 0.27)), ""],
		["wh_ws", Vector3(10.5, 0, 7.0), 0.0, paint, ""],
	]
	for d in defs:
		var door := Door.new()
		door.door_id = d[0]
		door.width = 1.0
		door.position = d[1]
		door.rotation_degrees.y = d[2]
		add_child(door)
		door.build(d[3])
		door.capture_base()
		doors[d[0]] = door
	doors["tech"].locked = true
	doors["tech"].lock_reason = "Техническое помещение. Ключа у вас нет."
	Build.label(self, "ТЕХНИЧЕСКОЕ\nПОМЕЩЕНИЕ\nВХОД ЗАПРЕЩЁН", Vector3(13.89, 1.7, 1.5), 0.05, Color(0.8, 0.1, 0.1), Vector3(0, -90, 0))
	Build.label(self, "WC", Vector3(13.89, 1.9, 9.0), 0.1, Color(0.1, 0.1, 0.1), Vector3(0, -90, 0))
	Build.label(self, "ПОДСОБКА", Vector3(13.89, 1.9, 5.5), 0.06, Color(0.1, 0.1, 0.1), Vector3(0, -90, 0))
	# Трубы под потолком.
	for zx in [[12.25, 2.75], [12.4, 2.6]]:
		Build.cyl(self, 0.05, 12.0, Vector3(zx[0], zx[1], 6.0), Mats.metal(Color(0.4, 0.38, 0.35)), Vector3(90, 0, 0), 8)
	Build.box(self, Vector3(0.15, 0.6, 0.4), Vector3(12.18, 1.6, 4.0), Mats.metal(Color(0.6, 0.6, 0.55)))  # распред. коробка
	_extinguisher(Vector3(13.75, 0, 11.75))
	_poster(Vector3(12.12, 1.6, 10.8), Vector3(0, 90, 0), ["ПАМЯТКА", "НОЧНОМУ СОТРУДНИКУ", "Если клиент внутри,", "а дверь заперта —", "выдайте заказ."], Color(0.9, 0.88, 0.8), Color(0.15, 0.15, 0.15))
	var mop := Node3D.new()
	mop.position = Vector3(13.7, 0, 10.6)
	add_child(mop)
	Build.cyl(mop, 0.15, 0.3, Vector3(0, 0.15, 0), Mats.color(Color(0.2, 0.3, 0.6)))
	Build.cyl(mop, 0.015, 1.4, Vector3(-0.05, 0.75, 0), Mats.color(Color(0.6, 0.5, 0.3)), Vector3(0, 0, 8))
	movable_props.append(mop)
	_switch("corridor", Vector3(12.12, 1.3, 7.6), Vector3(0, 90, 0))
	_switch("warehouse", Vector3(11.88, 1.3, 2.9), Vector3(0, -90, 0))
	dark_spots.append_array([Vector3(13.0, 0, 11.6), Vector3(13.0, 0, 0.4)])


# ======================================================================= Подсобка

func _build_utility() -> void:
	# Электрощиток.
	var panel := Node3D.new()
	panel.position = Vector3(17.88, 1.5, 5.6)
	panel.rotation_degrees.y = -90
	add_child(panel)
	Build.box(panel, Vector3(0.6, 0.8, 0.15), Vector3.ZERO, Mats.metal(Color(0.55, 0.57, 0.55)))
	Build.label(panel, "⚡ ЩР-1", Vector3(0, 0.3, 0.08), 0.05, Color(0.8, 0.1, 0.1))
	for i in 4:
		var b := Build.box(panel, Vector3(0.06, 0.12, 0.04), Vector3(-0.2 + i * 0.13, 0.0, 0.09), Mats.color(Color(0.1, 0.1, 0.1)))
		b.name = "Breaker%d" % i
	Build.label(panel, "A1  A2  A3  A4", Vector3(0, -0.15, 0.08), 0.03, Color(0.1, 0.1, 0.1))
	breaker_panel = Interactable.new()
	panel.add_child(breaker_panel)
	breaker_panel.setup_shape(Vector3(0.7, 0.9, 0.3))
	breaker_panel.prompt_text = "Электрощиток"
	# Шкафчики (укрытие).
	for i in 2:
		var lx := 15.0 + i * 0.65
		Build.box(self, Vector3(0.6, 1.9, 0.5), Vector3(lx, 0.95, 3.85), Mats.metal(Color(0.45, 0.5, 0.48)), true)
		for k in 4:
			Build.box(self, Vector3(0.3, 0.01, 0.01), Vector3(lx, 1.6 - k * 0.04, 4.105), Mats.color(Color(0.1, 0.1, 0.1)))
	var hs := HideSpot.new()
	hs.spot_name = "в шкафчике"
	hs.position = Vector3(15.0, 0.95, 4.15)
	add_child(hs)
	hs.setup_shape(Vector3(0.6, 1.8, 0.2))
	hs.view_point = _marker(Vector3(15.0, 1.6, 3.85), Vector3(0, 180, 0))
	hs.exit_point = _marker(Vector3(15.0, 0, 4.7), Vector3(0, 180, 0))
	hide_spots.append(hs)
	# Стеллаж с химией, ведро, чайник.
	Build.box(self, Vector3(0.4, 1.6, 1.2), Vector3(17.7, 0.8, 6.9), Mats.metal(Color(0.5, 0.5, 0.48)), true)
	for i in 6:
		Build.cyl(self, 0.05, 0.22, Vector3(17.65, 0.95 + floori(i / 3.0) * 0.5, 6.5 + (i % 3) * 0.35), Mats.color(Color.from_hsv(_rng.randf(), 0.5, 0.7)))
	Build.box(self, Vector3(0.4, 0.45, 0.4), Vector3(14.6, 0.225, 7.0), Mats.color(Color(0.35, 0.3, 0.25)))
	Build.cyl(self, 0.09, 0.2, Vector3(14.6, 0.55, 7.0), Mats.metal(Color(0.8, 0.8, 0.8)))
	_poster(Vector3(16.5, 1.7, 3.62), Vector3(0, 0, 0), ["ГРАФИК СМЕН", "Ночь: Ключников А.", "Ночь: Ключников А.", "Ночь: Ключников А.", "Ночь: —"], Color(0.95, 0.95, 0.9), Color(0.1, 0.1, 0.1))
	_switch("utility", Vector3(14.12, 1.3, 6.4), Vector3(0, 90, 0))
	dark_spots.append(Vector3(17.4, 0, 4.0))


# ======================================================================= Туалет

func _build_toilet() -> void:
	# Кабинка.
	Build.box(self, Vector3(0.05, 2.0, 2.4), Vector3(16.2, 1.1, 10.8), Mats.color(Color(0.55, 0.6, 0.62)), true)
	Build.box(self, Vector3(1.7, 2.0, 0.05), Vector3(17.05, 1.1, 9.6), Mats.color(Color(0.55, 0.6, 0.62)), true)
	# Унитаз.
	var wc := Node3D.new()
	wc.position = Vector3(17.2, 0, 11.4)
	add_child(wc)
	Build.cyl(wc, 0.2, 0.4, Vector3(0, 0.2, 0), Mats.color(Color(0.9, 0.9, 0.88), 0.2))
	Build.box(wc, Vector3(0.4, 0.4, 0.18), Vector3(0, 0.6, 0.35), Mats.color(Color(0.9, 0.9, 0.88), 0.2))
	var hs := HideSpot.new()
	hs.spot_name = "в кабинке"
	hs.position = Vector3(17.05, 1.0, 9.65)
	add_child(hs)
	hs.setup_shape(Vector3(1.6, 1.8, 0.2))
	hs.view_point = _marker(Vector3(17.1, 1.55, 10.7), Vector3(0, 0, 0))
	hs.exit_point = _marker(Vector3(16.9, 0, 9.0), Vector3(0, 0, 0))
	hide_spots.append(hs)
	# Раковина и зеркало (настоящее отражение на среднем/высоком качестве).
	Build.box(self, Vector3(0.55, 0.15, 0.4), Vector3(15.2, 0.85, 11.75), Mats.color(Color(0.9, 0.9, 0.88), 0.2))
	Build.cyl(self, 0.02, 0.15, Vector3(15.2, 0.98, 11.88), Mats.metal(Color(0.8, 0.8, 0.8)))
	var mirror := PlanarMirror.new()
	mirror.position = Vector3(15.2, 1.6, 11.88)
	mirror.rotation_degrees.y = 180
	add_child(mirror)
	mirror.build(Vector2(0.7, 0.9), "toilet")
	mirrors.append(mirror)
	_switch("toilet", Vector3(14.12, 1.3, 8.0), Vector3(0, 90, 0))
	dark_spots.append(Vector3(17.1, 0, 10.9))


# ======================================================================= Техническая

func _build_tech() -> void:
	# Советская картотека, стол, старый терминал, коробка с вашим именем.
	Build.box(self, Vector3(1.6, 1.3, 0.5), Vector3(16.6, 0.65, 0.35), Mats.color(Color(0.4, 0.3, 0.2), 0.7), true)
	for r in 4:
		for c in 6:
			Build.box(self, Vector3(0.22, 0.25, 0.01), Vector3(15.95 + c * 0.26, 0.2 + r * 0.3, 0.605), Mats.color(Color(0.48, 0.36, 0.24)))
			Build.box(self, Vector3(0.05, 0.02, 0.02), Vector3(15.95 + c * 0.26, 0.25 + r * 0.3, 0.62), Mats.metal(Color(0.7, 0.6, 0.3)))
	Build.label(self, "СТОЛ ЗАКАЗОВ № 7\nКАРТОТЕКА 1979–1991", Vector3(16.6, 1.45, 0.61), 0.05, Color(0.85, 0.8, 0.6))
	Build.box(self, Vector3(1.2, 0.05, 0.6), Vector3(17.3, 0.75, 2.5), Mats.color(Color(0.35, 0.25, 0.18)), true)
	var term := Node3D.new()
	term.position = Vector3(17.4, 0.78, 2.5)
	term.rotation_degrees.y = -90
	add_child(term)
	Build.box(term, Vector3(0.4, 0.35, 0.35), Vector3(0, 0.18, 0), Mats.color(Color(0.75, 0.72, 0.62)))
	Build.box(term, Vector3(0.3, 0.22, 0.01), Vector3(0, 0.2, 0.18), Mats.emissive(Color(0.2, 0.8, 0.3), 0.5, "tech_screen"))
	tech_terminal = Interactable.new()
	tech_terminal.prompt_text = "Старый терминал"
	term.add_child(tech_terminal)
	tech_terminal.setup_shape(Vector3(0.5, 0.5, 0.5), Vector3(0, 0.2, 0))
	own_box = Node3D.new()
	own_box.position = Vector3(15.3, 0, 2.9)
	add_child(own_box)
	Build.box(own_box, Vector3(0.7, 0.55, 0.5), Vector3(0, 0.275, 0), Mats.cardboard(99.0))
	Build.label(own_box, "ПОЛУЧАТЕЛЬ:\n" + GameState.player_name().to_upper(), Vector3(0, 0.35, 0.26), 0.035, Color(0.05, 0.05, 0.05))
	# Аварийная красная лампа (не зависит от щитка).
	var em := OmniLight3D.new()
	em.position = Vector3(16.0, 2.8, 1.8)
	em.light_color = Color(1.0, 0.15, 0.1)
	em.light_energy = 0.6
	em.omni_range = 4.0
	add_child(em)
	Build.box(self, Vector3(0.15, 0.08, 0.15), Vector3(16.0, 2.95, 1.8), Mats.emissive(Color(1.0, 0.1, 0.05), 2.0))
	lighting.register_extra("tech", em)
	spawn["tech"] = Vector3(16.0, 0, 1.8)


# ======================================================================= Свет

func _build_lights() -> void:
	var defs := [
		["hall", Vector3(3.0, 2.95, 12.8), 1.4, 7.0, false],
		["hall", Vector3(8.5, 2.95, 13.0), 1.4, 7.0, true],
		["workstation", Vector3(9.0, 2.95, 8.5), 1.2, 6.0, false],
		["warehouse", Vector3(2.8, 2.95, 3.95), 1.0, 6.5, true],
		["warehouse", Vector3(6.4, 2.95, 3.95), 1.2, 6.5, false],
		["warehouse", Vector3(10.4, 2.95, 2.0), 1.0, 6.0, false],
		["corridor", Vector3(13.0, 2.95, 2.5), 0.9, 5.0, false],
		["corridor", Vector3(13.0, 2.95, 9.0), 0.8, 5.0, true],
		["utility", Vector3(16.0, 2.95, 5.5), 0.9, 5.0, false],
		["toilet", Vector3(15.8, 2.95, 9.5), 0.9, 5.0, true],
	]
	for d in defs:
		var f := LightFixture.new()
		f.position = d[1]
		if d[0] == "corridor":
			f.rotation_degrees.y = 90
		add_child(f)
		f.build(d[0], d[2], d[3], Color(0.84, 0.92, 1.0), d[4])
		lighting.register(f)
	# Тусклый «дежурный» свет: чтобы при выключенных лампах можно было ориентироваться.
	var night := OmniLight3D.new()
	night.position = Vector3(6.0, 2.5, 13.0)
	night.light_color = Color(0.4, 0.5, 0.7)
	night.light_energy = 0.12
	night.omni_range = 9.0
	add_child(night)


func apply_quality(q: int) -> void:
	# Тени: низкое — только фонарик, среднее — 2 лампы, высокое — 5.
	var shadowed := []
	if q >= 1:
		shadowed = [Vector3(9.0, 2.95, 8.5), Vector3(6.4, 2.95, 3.95)]
	if q >= 2:
		shadowed += [Vector3(3.0, 2.95, 12.8), Vector3(13.0, 2.95, 2.5), Vector3(10.4, 2.95, 2.0)]
	for z in lighting.fixtures.keys():
		for f in lighting.fixtures[z]:
			(f as LightFixture).set_shadow((f as LightFixture).position in shadowed)
	var lamp := get_node_or_null("StreetLamp") as SpotLight3D
	if lamp:
		lamp.shadow_enabled = q >= 2
	for m in mirrors:
		(m as PlanarMirror).set_enabled_quality(q)


# ======================================================================= Зоны помещений

func _build_room_areas() -> void:
	for r in ROOMS:
		if r["id"] == "street":
			continue
		var a := Area3D.new()
		a.name = "Room_" + r["id"]
		var rect: Rect2 = r["rect"]
		a.position = Vector3(rect.position.x + rect.size.x * 0.5, H * 0.5, rect.position.y + rect.size.y * 0.5)
		a.collision_layer = 0
		a.collision_mask = 0
		a.monitoring = false
		a.monitorable = false
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(rect.size.x, H, rect.size.y)
		cs.shape = sh
		a.add_child(cs)
		if r["reverb"] != "":
			a.reverb_bus_enabled = true
			a.reverb_bus_name = r["reverb"]
			a.reverb_bus_amount = 0.7
			a.reverb_bus_uniformity = 0.3
		add_child(a)
		room_areas[r["id"]] = a
	# Фоновые зацикленные звуки: вентиляция, улица, капель.
	Sfx.make_loop("vent", self, Vector3(6.0, 2.8, 3.0), -16.0, "Ambience", 14.0)
	Sfx.make_loop("vent", self, Vector3(13.0, 2.8, 6.0), -18.0, "Ambience", 9.0)
	Sfx.make_loop("street", self, Vector3(5.0, 1.5, 18.0), -8.0, "Ambience", 20.0)
	Sfx.make_loop("room_tone", self, Vector3(9.0, 1.5, 10.0), -14.0, "Ambience", 30.0)


static func room_at(pos: Vector3) -> String:
	for r in ROOMS:
		if (r["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)):
			return r["id"]
	return "street"


static func room_title(id: String) -> String:
	for r in ROOMS:
		if r["id"] == id:
			return r["title"]
	return id


static func room_zone(id: String) -> String:
	for r in ROOMS:
		if r["id"] == id:
			return r["zone"]
	return "street"


# ======================================================================= Навигация

func _build_nav() -> void:
	var P := {
		# склад
		"wh_shutter": [Vector3(5.4, 0, 1.9), "warehouse"],
		"wh_nw": [Vector3(1.1, 0, 1.9), "warehouse"],
		"wh_ne": [Vector3(10.4, 0, 1.9), "warehouse"],
		"wh_door_cor": [Vector3(11.4, 0, 2.0), "warehouse"],
		"wh_w": [Vector3(1.1, 0, 3.95), "warehouse"],
		"wh_mid": [Vector3(5.5, 0, 3.95), "warehouse"],
		"wh_e": [Vector3(10.4, 0, 3.95), "warehouse"],
		"wh_sw": [Vector3(1.1, 0, 6.1), "warehouse"],
		"wh_s": [Vector3(5.5, 0, 6.1), "warehouse"],
		"wh_se": [Vector3(9.9, 0, 6.2), "warehouse"],
		"wh_door_ws": [Vector3(11.0, 0, 6.4), "warehouse"],
		# рабочее место
		"ws_door_wh": [Vector3(11.0, 0, 7.6), "workstation"],
		"ws_center": [Vector3(8.6, 0, 8.4), "workstation"],
		"ws_desk": [Vector3(10.4, 0, 8.9), "workstation"],
		"ws_door_cor": [Vector3(11.5, 0, 8.5), "workstation"],
		"ws_flap": [Vector3(6.5, 0, 9.3), "workstation"],
		# зал
		"hall_flap": [Vector3(6.5, 0, 10.7), "hall"],
		"hall_counter": [Vector3(9.0, 0, 10.85), "hall"],
		"hall_center": [Vector3(6.0, 0, 12.6), "hall"],
		"hall_w": [Vector3(2.2, 0, 12.0), "hall"],
		"hall_e": [Vector3(10.5, 0, 13.0), "hall"],
		"hall_window": [Vector3(8.0, 0, 14.6), "hall"],
		"cab_a_front": [Vector3(1.1, 0, 10.7), "hall"],
		"cab_b_front": [Vector3(3.3, 0, 10.7), "hall"],
		"vest": [Vector3(1.6, 0, 14.8), "vestibule"],
		"outside": [Vector3(1.6, 0, 16.9), "street"],
		"street": [Vector3(1.6, 0, 18.4), "street"],
		"street_e": [Vector3(8.0, 0, 17.5), "street"],
		# примерочные
		"cab_a": [Vector3(1.1, 0, 8.6), "cab_a"],
		"cab_b": [Vector3(3.3, 0, 8.6), "cab_b"],
		# коридор
		"cor_1": [Vector3(13.0, 0, 2.0), "corridor"],
		"cor_2": [Vector3(13.0, 0, 5.5), "corridor"],
		"cor_3": [Vector3(13.0, 0, 8.7), "corridor"],
		"cor_4": [Vector3(13.0, 0, 11.2), "corridor"],
		# восточные помещения
		"util": [Vector3(15.8, 0, 5.6), "utility"],
		"util_lockers": [Vector3(15.6, 0, 4.6), "utility"],
		"toilet": [Vector3(15.3, 0, 9.0), "toilet"],
		"toilet_sink": [Vector3(15.2, 0, 11.0), "toilet"],
		"tech_in": [Vector3(15.0, 0, 1.6), "tech"],
		"tech": [Vector3(16.3, 0, 2.2), "tech"],
	}
	for k in P.keys():
		nav.add_point(k, P[k][0], P[k][1])
	var E := [
		["wh_shutter", "wh_nw"], ["wh_shutter", "wh_ne"], ["wh_ne", "wh_door_cor"], ["wh_nw", "wh_w"],
		["wh_w", "wh_mid"], ["wh_mid", "wh_e"], ["wh_e", "wh_ne"], ["wh_w", "wh_sw"], ["wh_sw", "wh_s"],
		["wh_s", "wh_se"], ["wh_se", "wh_door_ws"], ["wh_e", "wh_se"],
		["ws_door_wh", "ws_center"], ["ws_center", "ws_desk"], ["ws_desk", "ws_door_cor"], ["ws_door_wh", "ws_door_cor"],
		["ws_center", "ws_flap"], ["ws_flap", "hall_flap"], ["hall_flap", "hall_counter"], ["hall_flap", "hall_center"],
		["hall_counter", "hall_center"], ["hall_counter", "hall_e"], ["hall_center", "hall_w"], ["hall_center", "hall_e"],
		["hall_center", "hall_window"], ["hall_e", "hall_window"], ["hall_w", "cab_a_front"], ["hall_w", "cab_b_front"],
		["cab_a_front", "cab_b_front"], ["cab_b_front", "hall_center"], ["hall_w", "vest"],
		["outside", "street"], ["outside", "street_e"], ["street", "street_e"],
		["cab_a_front", "cab_a"], ["cab_b_front", "cab_b"],
		["cor_1", "cor_2"], ["cor_2", "cor_3"], ["cor_3", "cor_4"],
		["util", "util_lockers"], ["toilet", "toilet_sink"], ["tech_in", "tech"],
	]
	for e in E:
		nav.connect_points(e[0], e[1])
	nav.connect_points("wh_door_cor", "cor_1", doors["wh_cor"])
	nav.connect_points("wh_door_ws", "ws_door_wh", doors["wh_ws"])
	nav.connect_points("ws_door_cor", "cor_3", doors["ws_cor"])
	nav.connect_points("cor_2", "util", doors["util"])
	nav.connect_points("cor_3", "toilet", doors["toilet"])
	nav.connect_points("cor_1", "tech_in", doors["tech"])
	nav.connect_points("vest", "outside", doors["front"])


func _build_camera_mounts() -> void:
	for c in CAMERAS:
		var m := Node3D.new()
		m.position = c["pos"]
		add_child(m)
		m.look_at_from_position(c["pos"], c["look"], Vector3.UP)
		cam_mount_nodes.append(m)
		# Корпус камеры.
		var body := Build.box(m, Vector3(0.12, 0.1, 0.22), Vector3(0, 0, 0.05), Mats.color(Color(0.85, 0.85, 0.82)))
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var led := Build.box(m, Vector3(0.02, 0.02, 0.01), Vector3(0.04, 0.03, -0.065), Mats.emissive(Color(1, 0.05, 0.05), 2.5, "cam_led"))
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Покрытие точек камерами считается реальными лучами — так ИИ знает слепые зоны.
func compute_camera_coverage() -> void:
	var space := get_world_3d().direct_space_state
	for n in nav.all_names():
		var cov := []
		var target := nav.pos_of(n) + Vector3.UP * 1.0
		for i in cam_mount_nodes.size():
			var m := cam_mount_nodes[i]
			var dir := (target - m.global_position).normalized()
			var fwd := -m.global_basis.z
			if fwd.angle_to(dir) > deg_to_rad(36.0):
				continue
			if m.global_position.distance_to(target) > 14.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(m.global_position, target, Build.LAYER_WORLD)
			if space.intersect_ray(q).is_empty():
				cov.append(i)
		nav.cam_coverage[n] = cov


func _flush_multimesh() -> void:
	if _card_xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = _card_xforms.size()
	for i in _card_xforms.size():
		mm.set_instance_transform(i, _card_xforms[i])
		mm.set_instance_custom_data(i, Color(_rng.randf() * 100.0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Mats.cardboard(0.0, true)
	mmi.name = "Boxes"
	add_child(mmi)
	_card_xforms.clear()
