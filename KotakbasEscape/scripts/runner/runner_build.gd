class_name RunnerBuild
extends RefCounted
## Построение переиспользуемых сегментов дороги (8 локаций), препятствий и бонусов.

const SEG_LEN := 30.0
const LANE_X := [-2.4, 0.0, 2.4]

const THEMES := [
	{"name": "Двор", "ground": Color(0.32, 0.32, 0.34), "side": Color(0.45, 0.6, 0.35), "fog": Color(0.78, 0.82, 0.88)},
	{"name": "Городская улица", "ground": Color(0.28, 0.28, 0.3), "side": Color(0.6, 0.58, 0.55), "fog": Color(0.8, 0.8, 0.85)},
	{"name": "Автобусная остановка", "ground": Color(0.3, 0.3, 0.32), "side": Color(0.62, 0.6, 0.56), "fog": Color(0.82, 0.8, 0.78)},
	{"name": "Рынок", "ground": Color(0.36, 0.34, 0.32), "side": Color(0.66, 0.55, 0.42), "fog": Color(0.9, 0.82, 0.7)},
	{"name": "Стройка", "ground": Color(0.4, 0.36, 0.3), "side": Color(0.55, 0.45, 0.32), "fog": Color(0.85, 0.78, 0.65)},
	{"name": "Промышленная зона", "ground": Color(0.26, 0.26, 0.27), "side": Color(0.4, 0.4, 0.42), "fog": Color(0.65, 0.66, 0.7)},
	{"name": "Окраина", "ground": Color(0.35, 0.33, 0.3), "side": Color(0.4, 0.55, 0.3), "fog": Color(0.75, 0.82, 0.8)},
	{"name": "Лесная дорога", "ground": Color(0.42, 0.34, 0.24), "side": Color(0.22, 0.42, 0.2), "fog": Color(0.6, 0.72, 0.62)},
]

# ------------------------------------------------------------------ Сегменты

static func build_segment(theme: int, rng: RandomNumberGenerator) -> Node3D:
	var seg := Node3D.new()
	seg.set_meta("theme", theme)
	var th: Dictionary = THEMES[theme]
	MK.box(seg, Vector3(8.0, 0.2, SEG_LEN), th.ground, Vector3(0, -0.1, -SEG_LEN * 0.5))
	MK.box(seg, Vector3(12.0, 0.3, SEG_LEN), th.side, Vector3(-10.0, -0.05, -SEG_LEN * 0.5))
	MK.box(seg, Vector3(12.0, 0.3, SEG_LEN), th.side, Vector3(10.0, -0.05, -SEG_LEN * 0.5))
	if theme != 7:
		for z in [-5.0, -15.0, -25.0]:
			MK.box(seg, Vector3(0.12, 0.02, 3.0), Color(0.95, 0.95, 0.9), Vector3(-1.2, 0.01, z))
			MK.box(seg, Vector3(0.12, 0.02, 3.0), Color(0.95, 0.95, 0.9), Vector3(1.2, 0.01, z))
		MK.box(seg, Vector3(0.3, 0.25, SEG_LEN), Color(0.7, 0.7, 0.7), Vector3(-4.1, 0.1, -SEG_LEN * 0.5))
		MK.box(seg, Vector3(0.3, 0.25, SEG_LEN), Color(0.7, 0.7, 0.7), Vector3(4.1, 0.1, -SEG_LEN * 0.5))
	for side in [-1.0, 1.0]:
		match theme:
			0: _decor_yard(seg, side, rng)
			1: _decor_street(seg, side, rng)
			2: _decor_bus(seg, side, rng)
			3: _decor_market(seg, side, rng)
			4: _decor_construction(seg, side, rng)
			5: _decor_industrial(seg, side, rng)
			6: _decor_outskirts(seg, side, rng)
			7: _decor_forest(seg, side, rng)
	return seg

static func _decor_yard(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	MK.panel_house(seg, Vector3(side * 16.0, 0, -15.0), Vector3(8.0, 15.0 + rng.randf() * 6.0, 26.0), rng.randi() % 4, 0.0)
	MK.tree(seg, Vector3(side * 7.0, 0, -6.0 - rng.randf() * 4.0), rng.randf_range(0.8, 1.2))
	if rng.randf() < 0.6:
		MK.box(seg, Vector3(0.5, 0.5, 1.8), Color(0.55, 0.35, 0.2), Vector3(side * 5.5, 0.4, -20.0))

static func _decor_street(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	for k in 2:
		var h := 6.0 + rng.randf() * 8.0
		var col := Color.from_hsv(rng.randf(), 0.35, 0.75)
		MK.box(seg, Vector3(8.0, h, 13.0), col, Vector3(side * 14.0, h * 0.5, -7.5 - k * 15.0))
		MK.box(seg, Vector3(0.2, 1.2, 8.0), Color.from_hsv(rng.randf(), 0.8, 0.9), Vector3(side * 9.9, 3.2, -7.5 - k * 15.0))
		MK.box(seg, Vector3(0.15, 2.6, 6.0), Color(0.3, 0.4, 0.5), Vector3(side * 9.95, 1.3, -7.5 - k * 15.0))
	MK.cyl(seg, 0.08, 0.08, 5.0, Color(0.25, 0.25, 0.28), Vector3(side * 5.0, 2.5, -14.0))
	MK.box(seg, Vector3(1.0, 0.15, 0.3), Color(0.25, 0.25, 0.28), Vector3(side * 4.6, 5.0, -14.0))

static func _decor_bus(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	MK.box(seg, Vector3(8.0, 10.0, 28.0), Color(0.7, 0.68, 0.64), Vector3(side * 16.0, 5.0, -15.0))
	if side < 0 or rng.randf() < 0.5:
		var st := Node3D.new()
		st.position = Vector3(side * 6.0, 0, -12.0)
		seg.add_child(st)
		MK.box(st, Vector3(1.4, 0.1, 4.0), Color(0.3, 0.5, 0.7), Vector3(0, 2.6, 0))
		MK.box(st, Vector3(0.1, 2.6, 4.0), Color(0.6, 0.8, 0.9, 0.5), Vector3(side * 0.7, 1.3, 0))
		MK.box(st, Vector3(0.6, 0.1, 3.0), Color(0.5, 0.35, 0.2), Vector3(0, 0.5, 0))
		MK.box(st, Vector3(1.4, 0.6, 0.1), Color(1, 0.85, 0.1), Vector3(0, 2.9, -2.0))
	else:
		MK.box(seg, Vector3(2.6, 3.0, 10.0), Color(0.95, 0.75, 0.15), Vector3(side * 6.5, 1.6, -14.0))
		MK.box(seg, Vector3(2.65, 0.9, 9.0), Color(0.3, 0.4, 0.5), Vector3(side * 6.5, 2.2, -14.0))
	MK.box(seg, Vector3(0.2, 3.0, 5.0), Color.from_hsv(rng.randf(), 0.6, 0.9), Vector3(side * 8.0, 4.5, -25.0))
	MK.cyl(seg, 0.1, 0.1, 3.0, Color(0.3, 0.3, 0.3), Vector3(side * 8.0, 1.5, -25.0))

static func _decor_market(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	for k in 3:
		var z := -5.0 - k * 10.0
		var col := Color.from_hsv(rng.randf(), 0.7, 0.95)
		MK.box(seg, Vector3(3.0, 0.9, 3.0), Color(0.55, 0.4, 0.25), Vector3(side * 7.0, 0.45, z))
		MK.box(seg, Vector3(3.4, 0.1, 3.4), col, Vector3(side * 7.0, 2.6, z), Vector3(0, 0, side * 0.15))
		MK.cyl(seg, 0.05, 0.05, 2.6, Color(0.4, 0.4, 0.4), Vector3(side * 5.6, 1.3, z - 1.5))
		for f in 3:
			MK.sphere(seg, 0.2, Color.from_hsv(rng.randf(), 0.8, 0.9), Vector3(side * 6.5 + f * 0.4, 1.05, z), 6)
	MK.box(seg, Vector3(8.0, 7.0, 28.0), Color(0.75, 0.6, 0.5), Vector3(side * 15.0, 3.5, -15.0))

static func _decor_construction(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	MK.box(seg, Vector3(0.1, 2.0, SEG_LEN), Color(0.4, 0.5, 0.65), Vector3(side * 5.2, 1.0, -SEG_LEN * 0.5))
	var h := 10.0 + rng.randf() * 8.0
	MK.box(seg, Vector3(7.0, h, 9.0), Color(0.6, 0.58, 0.55), Vector3(side * 12.0, h * 0.5, -12.0))
	for y in range(2, int(h), 3):
		MK.box(seg, Vector3(7.4, 0.15, 9.4), Color(0.85, 0.6, 0.15), Vector3(side * 12.0, y, -12.0))
	if rng.randf() < 0.7:
		MK.box(seg, Vector3(0.6, 24.0, 0.6), Color(0.95, 0.75, 0.1), Vector3(side * 9.0, 12.0, -24.0))
		MK.box(seg, Vector3(14.0, 0.6, 0.6), Color(0.95, 0.75, 0.1), Vector3(side * 6.0, 23.5, -24.0))
		MK.box(seg, Vector3(1.2, 1.2, 1.2), Color(0.5, 0.5, 0.5), Vector3(side * 1.0, 18.0, -24.0))
	MK.box(seg, Vector3(1.5, 1.0, 1.5), Color(0.65, 0.65, 0.65), Vector3(side * 7.0, 0.5, -4.0))

static func _decor_industrial(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	MK.box(seg, Vector3(10.0, 8.0, 24.0), Color(0.45, 0.42, 0.4), Vector3(side * 15.0, 4.0, -15.0))
	MK.cyl(seg, 0.9, 1.2, 18.0, Color(0.6, 0.35, 0.3), Vector3(side * 12.0, 9.0, -22.0), Vector3.ZERO, 8)
	MK.cyl(seg, 0.5, 0.5, SEG_LEN, Color(0.5, 0.5, 0.55), Vector3(side * 7.0, 3.0, -SEG_LEN * 0.5), Vector3(PI * 0.5, 0, 0), 6)
	if rng.randf() < 0.6:
		MK.box(seg, Vector3(2.4, 2.6, 6.0), Color.from_hsv(rng.randf(), 0.5, 0.6), Vector3(side * 7.5, 1.3, -8.0))

static func _decor_outskirts(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	var house := Node3D.new()
	house.position = Vector3(side * 11.0, 0, -12.0 - rng.randf() * 6.0)
	seg.add_child(house)
	var wall := Color.from_hsv(rng.randf_range(0.0, 0.15), 0.4, 0.7)
	MK.box(house, Vector3(5.0, 3.0, 5.0), wall, Vector3(0, 1.5, 0))
	MK.cyl(house, 0.0, 4.2, 2.2, Color(0.5, 0.25, 0.2), Vector3(0, 4.1, 0), Vector3(0, PI * 0.25, 0), 4)
	MK.box(house, Vector3(0.1, 1.0, 1.0), Color(0.6, 0.8, 0.95), Vector3(-side * 2.5, 1.7, 0))
	for z in range(0, 30, 3):
		MK.box(seg, Vector3(0.1, 1.2, 0.2), Color(0.5, 0.35, 0.2), Vector3(side * 6.0, 0.6, -float(z)))
	MK.box(seg, Vector3(0.05, 0.12, SEG_LEN), Color(0.5, 0.35, 0.2), Vector3(side * 6.0, 0.9, -SEG_LEN * 0.5))
	MK.tree(seg, Vector3(side * 8.5, 0, -25.0), 1.1)

static func _decor_forest(seg: Node3D, side: float, rng: RandomNumberGenerator) -> void:
	for k in 5:
		MK.tree(seg, Vector3(side * rng.randf_range(5.5, 14.0), 0, -rng.randf_range(0.0, SEG_LEN)), rng.randf_range(0.9, 1.6), true)
	MK.sphere(seg, 0.8, Color(0.2, 0.45, 0.2), Vector3(side * 5.0, 0.4, -rng.randf_range(2.0, 28.0)), 7)

# ------------------------------------------------------------------ Препятствия

## Создаёт препятствие. Метаданные: kind (BLOCK/LOW/HIGH), len (по Z), pit.
static func build_obstacle(kind: int, rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	n.set_meta("kind", kind)
	n.set_meta("pit", false)
	var variant := ""
	match kind:
		RunnerGenerator.BLOCK:
			variant = ["container", "car", "cart", "npc", "huge_box"][rng.randi() % 5]
		RunnerGenerator.LOW:
			variant = ["fence", "cones", "pit", "pigeons_ground"][rng.randi() % 4]
		RunnerGenerator.HIGH:
			variant = ["barrier", "strange", "pigeons_air"][rng.randi() % 3]
	n.set_meta("variant", variant)
	var length := 1.0
	match variant:
		"container":
			MK.box(n, Vector3(1.9, 1.4, 1.3), Color(0.2, 0.5, 0.3), Vector3(0, 0.75, 0))
			MK.box(n, Vector3(2.0, 0.12, 1.4), Color(0.15, 0.35, 0.2), Vector3(0, 1.5, 0.05), Vector3(0.25, 0, 0))
			length = 1.3
		"car":
			var col := Color.from_hsv(rng.randf(), 0.7, 0.85)
			MK.box(n, Vector3(1.9, 0.8, 4.0), col, Vector3(0, 0.65, 0))
			MK.box(n, Vector3(1.7, 0.7, 2.1), col.darkened(0.1), Vector3(0, 1.4, 0.2))
			MK.box(n, Vector3(1.72, 0.5, 0.05), Color(0.3, 0.4, 0.5), Vector3(0, 1.45, -0.86))
			for wp in [Vector3(-0.9, 0.32, 1.3), Vector3(0.9, 0.32, 1.3), Vector3(-0.9, 0.32, -1.3), Vector3(0.9, 0.32, -1.3)]:
				MK.cyl(n, 0.32, 0.32, 0.22, Color(0.1, 0.1, 0.1), wp, Vector3(0, 0, PI * 0.5))
			MK.box(n, Vector3(0.3, 0.15, 0.05), Color(1, 1, 0.7), Vector3(-0.6, 0.75, -2.0))
			MK.box(n, Vector3(0.3, 0.15, 0.05), Color(1, 1, 0.7), Vector3(0.6, 0.75, -2.0))
			length = 4.0
		"cart":
			MK.box(n, Vector3(1.0, 0.8, 1.4), Color(0.75, 0.75, 0.8), Vector3(0, 1.0, 0))
			MK.box(n, Vector3(1.0, 0.08, 0.08), Color(0.9, 0.2, 0.2), Vector3(0, 1.5, 0.75))
			for wp in [Vector3(-0.4, 0.1, 0.5), Vector3(0.4, 0.1, 0.5), Vector3(-0.4, 0.1, -0.5), Vector3(0.4, 0.1, -0.5)]:
				MK.sphere(n, 0.1, Color(0.1, 0.1, 0.1), wp, 5)
			MK.box(n, Vector3(0.9, 0.6, 0.06), Color(0.6, 0.6, 0.65), Vector3(0, 0.5, 0))
			length = 1.4
		"npc":
			var body := Color.from_hsv(rng.randf(), 0.5, 0.7)
			MK.box(n, Vector3(0.6, 0.8, 0.35), body, Vector3(0, 1.2, 0))
			MK.sphere(n, 0.25, Color(0.95, 0.8, 0.65), Vector3(0, 1.85, 0), 8)
			MK.box(n, Vector3(0.22, 0.8, 0.25), Color(0.2, 0.2, 0.3), Vector3(-0.15, 0.4, 0))
			MK.box(n, Vector3(0.22, 0.8, 0.25), Color(0.2, 0.2, 0.3), Vector3(0.15, 0.4, 0))
			var arm := MK.box(n, Vector3(0.15, 0.7, 0.15), body, Vector3(0.45, 1.6, 0), Vector3(0, 0, 2.6))
			arm.set_meta("wave", true)
			MK.box(n, Vector3(0.9, 0.5, 0.05), Color(1, 1, 1), Vector3(0, 2.4, 0))
			length = 0.6
		"huge_box":
			MK.box(n, Vector3(2.0, 2.2, 2.0), Color(0.72, 0.55, 0.35), Vector3(0, 1.1, 0), Vector3(0, rng.randf_range(-0.2, 0.2), 0))
			MK.box(n, Vector3(2.02, 0.2, 0.3), Color(0.85, 0.75, 0.55), Vector3(0, 2.15, 0))
			length = 2.0
		"fence":
			for x in [-0.9, -0.3, 0.3, 0.9]:
				MK.box(n, Vector3(0.12, 0.85, 0.12), Color(0.85, 0.85, 0.85), Vector3(x, 0.42, 0))
			MK.box(n, Vector3(2.1, 0.12, 0.08), Color(0.9, 0.2, 0.2), Vector3(0, 0.75, 0))
			MK.box(n, Vector3(2.1, 0.12, 0.08), Color(0.95, 0.95, 0.95), Vector3(0, 0.45, 0))
			length = 0.4
		"cones":
			for x in [-0.7, 0.0, 0.7]:
				MK.cyl(n, 0.04, 0.28, 0.75, Color(1.0, 0.45, 0.1), Vector3(x, 0.37, 0), Vector3.ZERO, 8)
				MK.cyl(n, 0.12, 0.17, 0.12, Color(1, 1, 1), Vector3(x, 0.45, 0), Vector3.ZERO, 8)
			length = 0.6
		"pit":
			MK.box(n, Vector3(2.2, 0.05, 2.4), Color(0.05, 0.04, 0.03), Vector3(0, 0.02, 0))
			MK.box(n, Vector3(2.3, 0.1, 0.15), Color(0.95, 0.8, 0.1), Vector3(0, 0.06, 1.25))
			MK.box(n, Vector3(2.3, 0.1, 0.15), Color(0.95, 0.8, 0.1), Vector3(0, 0.06, -1.25))
			n.set_meta("pit", true)
			length = 2.4
		"pigeons_ground":
			for i in 4:
				var p := PigeonModel.new()
				p.position = Vector3(-0.8 + i * 0.55, 0.3, rng.randf_range(-0.2, 0.2))
				p.scale = Vector3.ONE * 1.3
				n.add_child(p)
			length = 0.6
		"barrier":
			MK.cyl(n, 0.07, 0.07, 2.2, Color(0.3, 0.3, 0.3), Vector3(-1.05, 1.1, 0))
			MK.cyl(n, 0.07, 0.07, 2.2, Color(0.3, 0.3, 0.3), Vector3(1.05, 1.1, 0))
			MK.box(n, Vector3(2.2, 0.9, 0.08), Color(0.85, 0.15, 0.15), Vector3(0, 1.75, 0))
			var lbl := Label3D.new()
			lbl.text = "ТЦК"
			lbl.font = UIStyle.title_font()
			lbl.font_size = 96
			lbl.pixel_size = 0.006
			lbl.position = Vector3(0, 1.75, 0.06)
			lbl.modulate = Color.WHITE
			n.add_child(lbl)
			length = 0.4
		"strange":
			var kind_s := rng.randi() % 3
			var holder := Node3D.new()
			holder.position.y = 1.9
			holder.set_meta("spin", true)
			n.add_child(holder)
			if kind_s == 0: # летающий холодильник
				MK.box(holder, Vector3(0.9, 1.4, 0.8), Color(0.95, 0.95, 0.97))
				MK.box(holder, Vector3(0.05, 0.5, 0.05), Color(0.5, 0.5, 0.5), Vector3(0.35, 0.2, 0.42))
			elif kind_s == 1: # диван
				MK.box(holder, Vector3(2.0, 0.5, 0.9), Color(0.6, 0.2, 0.4))
				MK.box(holder, Vector3(2.0, 0.6, 0.25), Color(0.55, 0.18, 0.35), Vector3(0, 0.5, -0.35))
			else: # унитаз
				MK.cyl(holder, 0.35, 0.25, 0.5, Color(0.97, 0.97, 0.97), Vector3.ZERO, Vector3.ZERO, 10)
				MK.box(holder, Vector3(0.6, 0.7, 0.25), Color(0.97, 0.97, 0.97), Vector3(0, 0.35, -0.35))
			length = 0.9
		"pigeons_air":
			for i in 5:
				var p2 := PigeonModel.new()
				p2.position = Vector3(-0.9 + i * 0.45, 1.6 + rng.randf() * 0.4, rng.randf_range(-0.3, 0.3))
				p2.scale = Vector3.ONE * 1.4
				n.add_child(p2)
			length = 0.8
	n.set_meta("len", length)
	return n

# ------------------------------------------------------------------ Бонусы

const POWERUPS := ["sneakers", "helmet", "pigeon", "magnet", "nokia"]
const POWERUP_NAMES := {
	"sneakers": "Кроссовки — ускорение!",
	"helmet": "Шлем — защита!",
	"pigeon": "Голубь собирает пряники!",
	"magnet": "Магнит!",
	"nokia": "Nokia — неуязвимость!",
}

static func build_pryanik() -> Node3D:
	var n := Node3D.new()
	var m := MK.cyl(n, 0.32, 0.32, 0.12, Color(0.7, 0.42, 0.18), Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 10)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MK.cyl(n, 0.24, 0.24, 0.13, Color(0.92, 0.8, 0.6), Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 10).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

static func build_powerup(kind: String) -> Node3D:
	var n := Node3D.new()
	n.set_meta("power", kind)
	MK.add(n, MK.sphere_mesh(0.62, 10, 6), Color(1, 1, 1, 0.25), Vector3.ZERO, Vector3.ZERO, true)
	match kind:
		"sneakers":
			MK.box(n, Vector3(0.35, 0.25, 0.7), Color(0.95, 0.95, 0.95), Vector3(0, -0.05, 0))
			MK.box(n, Vector3(0.37, 0.08, 0.72), Color(0.9, 0.2, 0.2), Vector3(0, -0.18, 0))
		"helmet":
			var h := MK.add(n, MK.sphere_mesh(0.35, 10, 6), Color(0.95, 0.75, 0.1))
			h.scale = Vector3(1, 0.8, 1)
		"pigeon":
			var p := PigeonModel.new()
			p.scale = Vector3.ONE * 1.4
			n.add_child(p)
		"magnet":
			MK.box(n, Vector3(0.18, 0.5, 0.18), Color(0.9, 0.15, 0.15), Vector3(-0.2, 0, 0))
			MK.box(n, Vector3(0.18, 0.5, 0.18), Color(0.9, 0.15, 0.15), Vector3(0.2, 0, 0))
			MK.box(n, Vector3(0.58, 0.18, 0.18), Color(0.9, 0.15, 0.15), Vector3(0, 0.25, 0))
			MK.box(n, Vector3(0.18, 0.12, 0.18), Color(0.85, 0.85, 0.9), Vector3(-0.2, -0.3, 0))
			MK.box(n, Vector3(0.18, 0.12, 0.18), Color(0.85, 0.85, 0.9), Vector3(0.2, -0.3, 0))
		"nokia":
			MK.box(n, Vector3(0.28, 0.55, 0.12), Color(0.2, 0.25, 0.4))
			MK.box(n, Vector3(0.2, 0.18, 0.02), Color(0.6, 0.8, 0.4), Vector3(0, 0.12, 0.07))
	return n

static func build_bicycle() -> Node3D:
	var n := Node3D.new()
	MK.cyl(n, 0.36, 0.36, 0.06, Color(0.1, 0.1, 0.1), Vector3(0, 0.36, -0.55), Vector3(0, 0, PI * 0.5), 12)
	MK.cyl(n, 0.36, 0.36, 0.06, Color(0.1, 0.1, 0.1), Vector3(0, 0.36, 0.55), Vector3(0, 0, PI * 0.5), 12)
	MK.box(n, Vector3(0.06, 0.06, 1.1), Color(0.2, 0.6, 0.8), Vector3(0, 0.6, 0))
	MK.box(n, Vector3(0.06, 0.5, 0.06), Color(0.2, 0.6, 0.8), Vector3(0, 0.75, -0.5))
	MK.box(n, Vector3(0.6, 0.05, 0.05), Color(0.2, 0.2, 0.2), Vector3(0, 1.0, -0.5))
	MK.box(n, Vector3(0.2, 0.06, 0.3), Color(0.15, 0.15, 0.15), Vector3(0, 0.85, 0.25))
	return n

static func build_bush() -> Node3D:
	var n := Node3D.new()
	for i in 5:
		MK.sphere(n, 0.9 + randf() * 0.4, Color(0.2, 0.5, 0.2).darkened(randf() * 0.2), Vector3(randf_range(-1.2, 1.2), 0.6 + randf() * 0.4, randf_range(-0.6, 0.6)), 8)
	return n
