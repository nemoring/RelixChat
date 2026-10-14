class_name BuildDB
extends RefCounted
## Строительные элементы: стоимость, размеры коллизии, привязка к сетке.
## snap: foundation — сетка 3 м; wall — край фундамента; roof — верх; free — свободно (сетка 0,5 м).

const GRID := 3.0

const PIECES := {
	"foundation": {"name": "Фундамент", "cost": {"wood": 6}, "snap": "foundation", "size": Vector3(3, 0.4, 3)},
	"wall": {"name": "Стена", "cost": {"wood": 4}, "snap": "wall", "size": Vector3(3, 3, 0.25)},
	"door": {"name": "Дверь", "cost": {"wood": 5, "rope": 1}, "snap": "wall", "size": Vector3(3, 3, 0.25)},
	"window": {"name": "Окно", "cost": {"wood": 4}, "snap": "wall", "size": Vector3(3, 3, 0.25)},
	"roof": {"name": "Крыша", "cost": {"wood": 4}, "snap": "roof", "size": Vector3(3, 0.25, 3)},
	"campfire": {"name": "Костёр", "cost": {"wood": 3, "stone": 3}, "snap": "free", "size": Vector3(1.2, 0.5, 1.2)},
	"crate": {"name": "Ящик", "cost": {"wood": 6}, "snap": "free", "size": Vector3(1.2, 0.9, 0.9)},
	"bed": {"name": "Кровать", "cost": {"wood": 5, "fabric": 3}, "snap": "free", "size": Vector3(1.2, 0.6, 2.2)},
	"workbench": {"name": "Верстак", "cost": {"wood": 8, "stone": 4}, "snap": "free", "size": Vector3(2.0, 1.0, 1.0)},
	"furnace": {"name": "Печь", "cost": {"stone": 12}, "snap": "free", "size": Vector3(1.4, 1.6, 1.4)},
	"fence": {"name": "Забор", "cost": {"wood": 2}, "snap": "free", "size": Vector3(3, 1.4, 0.2)},
	"tower": {"name": "Сторожевая вышка", "cost": {"wood": 15, "rope": 4}, "snap": "free", "size": Vector3(3, 6, 3)},
	"bunker": {"name": "Бункер", "cost": {"stone": 20, "metal": 6, "wood": 10}, "snap": "free", "size": Vector3(5, 2.6, 5)},
}

const ORDER := ["foundation", "wall", "door", "window", "roof", "campfire", "crate", "bed", "workbench", "furnace", "fence", "tower", "bunker"]

const DESCRIPTIONS := {
	"foundation": "Основа дома. Стены и крыша цепляются к фундаменту.",
	"wall": "Стена на край фундамента.",
	"door": "Стена с дверью. Касание — открыть/закрыть.",
	"window": "Стена с окном. Видно НЛО заранее.",
	"roof": "Крыша над фундаментом. Под крышей теплее.",
	"campfire": "Тепло, свет, готовка еды и кипячение воды.",
	"crate": "Хранилище на 12 ячеек. НЛО крадёт в первую очередь отсюда!",
	"bed": "Сон до утра и точка возрождения.",
	"workbench": "Сложные рецепты: электроника из деталей НЛО.",
	"furnace": "Переплавка металлолома в металл.",
	"fence": "Просто забор. Гуси не пройдут. Наверное.",
	"tower": "Высокая точка — удобно кидать камни в кабину НЛО.",
	"bunker": "Ящики рядом с бункером (до 4 м) НЛО украсть не может.",
}

static func cost_for(id: String) -> Dictionary:
	return DifficultyManager.scaled_cost(PIECES[id].cost, "build")

## Визуал постройки из примитивов.
static func build_visual(id: String, ghost := false) -> Node3D:
	var n := Node3D.new()
	var wood := Color(0.62, 0.43, 0.25)
	var dark := Color(0.45, 0.3, 0.17)
	match id:
		"foundation":
			MK.box(n, Vector3(3, 0.4, 3), Color(0.55, 0.52, 0.48), Vector3(0, 0.2, 0))
			for k in 3:
				MK.box(n, Vector3(3, 0.05, 0.9), wood.darkened(k * 0.08), Vector3(0, 0.42, -1 + k))
		"wall":
			MK.box(n, Vector3(3, 3, 0.25), wood, Vector3(0, 1.5, 0))
			for k in 4:
				MK.box(n, Vector3(3.02, 0.06, 0.27), dark, Vector3(0, 0.4 + k * 0.75, 0))
		"door":
			MK.box(n, Vector3(1.0, 3, 0.25), wood, Vector3(-1.0, 1.5, 0))
			MK.box(n, Vector3(1.0, 3, 0.25), wood, Vector3(1.0, 1.5, 0))
			MK.box(n, Vector3(1.0, 0.8, 0.25), wood, Vector3(0, 2.6, 0))
			var hinge := Node3D.new()
			hinge.name = "Hinge"
			hinge.position = Vector3(-0.5, 0, 0)
			n.add_child(hinge)
			MK.box(hinge, Vector3(1.0, 2.2, 0.12), dark, Vector3(0.5, 1.1, 0))
			MK.sphere(hinge, 0.06, Color(0.9, 0.8, 0.3), Vector3(0.85, 1.1, -0.1), 6)
		"window":
			MK.box(n, Vector3(3, 1.0, 0.25), wood, Vector3(0, 0.5, 0))
			MK.box(n, Vector3(3, 0.9, 0.25), wood, Vector3(0, 2.55, 0))
			MK.box(n, Vector3(0.9, 1.1, 0.25), wood, Vector3(-1.05, 1.55, 0))
			MK.box(n, Vector3(0.9, 1.1, 0.25), wood, Vector3(1.05, 1.55, 0))
			MK.box(n, Vector3(1.2, 0.08, 0.3), dark, Vector3(0, 1.0, 0))
		"roof":
			MK.box(n, Vector3(3.2, 0.25, 3.2), Color(0.55, 0.3, 0.22), Vector3(0, 0.12, 0))
			for k in 4:
				MK.box(n, Vector3(3.22, 0.06, 0.1), Color(0.45, 0.22, 0.16), Vector3(0, 0.26, -1.2 + k * 0.8))
		"campfire":
			for k in 6:
				var a := TAU * k / 6.0
				MK.sphere(n, 0.18, Color(0.5, 0.5, 0.52), Vector3(cos(a) * 0.5, 0.1, sin(a) * 0.5), 6)
			MK.box(n, Vector3(0.9, 0.12, 0.14), dark, Vector3(0, 0.12, 0), Vector3(0, 0.6, 0))
			MK.box(n, Vector3(0.9, 0.12, 0.14), dark, Vector3(0, 0.14, 0), Vector3(0, -0.6, 0))
			if not ghost:
				var flame := MK.add(n, MK.cyl_mesh(0.0, 0.32, 0.8, 6), Color(1.0, 0.55, 0.1), Vector3(0, 0.5, 0), Vector3.ZERO, true)
				flame.name = "Flame"
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.6, 0.25)
				light.omni_range = 9.0
				light.light_energy = 1.6
				light.position.y = 1.0
				light.shadow_enabled = false
				light.name = "Light"
				n.add_child(light)
		"crate":
			MK.box(n, Vector3(1.2, 0.9, 0.9), wood, Vector3(0, 0.45, 0))
			MK.box(n, Vector3(1.22, 0.08, 0.92), dark, Vector3(0, 0.9, 0))
			MK.box(n, Vector3(0.08, 0.92, 0.92), dark, Vector3(-0.56, 0.45, 0))
			MK.box(n, Vector3(0.08, 0.92, 0.92), dark, Vector3(0.56, 0.45, 0))
		"bed":
			MK.box(n, Vector3(1.2, 0.35, 2.2), dark, Vector3(0, 0.22, 0))
			MK.box(n, Vector3(1.1, 0.15, 2.0), Color(0.3, 0.45, 0.8), Vector3(0, 0.45, 0.05))
			MK.box(n, Vector3(0.8, 0.15, 0.45), Color(0.95, 0.95, 0.95), Vector3(0, 0.55, -0.8))
		"workbench":
			MK.box(n, Vector3(2.0, 0.12, 1.0), wood, Vector3(0, 0.95, 0))
			for p in [Vector3(-0.9, 0.45, -0.4), Vector3(0.9, 0.45, -0.4), Vector3(-0.9, 0.45, 0.4), Vector3(0.9, 0.45, 0.4)]:
				MK.box(n, Vector3(0.12, 0.9, 0.12), dark, p)
			MK.box(n, Vector3(0.5, 0.2, 0.3), Color(0.5, 0.5, 0.55), Vector3(0.5, 1.1, 0))
			MK.box(n, Vector3(0.5, 0.45, 0.5), dark, Vector3(-1.4, 0.22, 0.6))
		"furnace":
			MK.box(n, Vector3(1.4, 1.4, 1.4), Color(0.55, 0.53, 0.5), Vector3(0, 0.7, 0))
			MK.box(n, Vector3(0.6, 0.5, 0.05), Color(0.15, 0.08, 0.05), Vector3(0, 0.45, -0.71))
			MK.add(n, MK.box_mesh(Vector3(0.5, 0.3, 0.05)), Color(1.0, 0.45, 0.1), Vector3(0, 0.38, -0.72), Vector3.ZERO, true)
			MK.cyl(n, 0.18, 0.18, 1.0, Color(0.45, 0.43, 0.4), Vector3(0.4, 1.9, 0.4))
		"fence":
			for x in [-1.3, -0.45, 0.45, 1.3]:
				MK.box(n, Vector3(0.15, 1.4, 0.15), wood, Vector3(x, 0.7, 0))
			MK.box(n, Vector3(3, 0.12, 0.08), dark, Vector3(0, 0.5, 0))
			MK.box(n, Vector3(3, 0.12, 0.08), dark, Vector3(0, 1.1, 0))
		"tower":
			for p in [Vector3(-1.3, 0, -1.3), Vector3(1.3, 0, -1.3), Vector3(-1.3, 0, 1.3), Vector3(1.3, 0, 1.3)]:
				MK.box(n, Vector3(0.2, 5.0, 0.2), dark, p + Vector3(0, 2.5, 0))
			MK.box(n, Vector3(3.0, 0.2, 3.0), wood, Vector3(0, 5.0, 0))
			MK.box(n, Vector3(3.0, 0.8, 0.1), wood, Vector3(0, 5.5, -1.45))
			MK.box(n, Vector3(3.0, 0.8, 0.1), wood, Vector3(0, 5.5, 1.45))
			MK.box(n, Vector3(0.1, 0.8, 3.0), wood, Vector3(-1.45, 5.5, 0))
			# пандус-лестница
			MK.box(n, Vector3(1.0, 0.15, 9.0), wood, Vector3(2.05, 2.45, 3.75), Vector3(0.59, 0, 0))
		"bunker":
			var dome := MK.add(n, MK.sphere_mesh(2.5, 12, 6), Color(0.45, 0.5, 0.42), Vector3(0, 0, 0))
			dome.scale = Vector3(1, 0.85, 1)
			MK.box(n, Vector3(1.2, 1.6, 0.6), Color(0.2, 0.2, 0.2), Vector3(0, 0.8, -2.2))
			MK.box(n, Vector3(5.2, 0.3, 5.2), Color(0.4, 0.38, 0.35), Vector3(0, 0.1, 0))
	if ghost:
		_make_ghost(n)
	return n

static func _make_ghost(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			c.material_override = MK.mat(Color(0.3, 1.0, 0.4, 0.45), true)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_make_ghost(c)

static func set_ghost_valid(n: Node, valid: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			c.material_override = MK.mat(Color(0.3, 1.0, 0.4, 0.45) if valid else Color(1.0, 0.25, 0.2, 0.45), true)
		set_ghost_valid(c, valid)

## Коллизии постройки (упрощённые коробки).
static func add_collision(id: String, body: StaticBody3D) -> void:
	var shapes := []
	match id:
		"foundation": shapes = [[Vector3(3, 0.4, 3), Vector3(0, 0.2, 0)]]
		"wall": shapes = [[Vector3(3, 3, 0.25), Vector3(0, 1.5, 0)]]
		"window": shapes = [[Vector3(3, 1.0, 0.25), Vector3(0, 0.5, 0)], [Vector3(3, 0.9, 0.25), Vector3(0, 2.55, 0)], [Vector3(0.9, 1.1, 0.25), Vector3(-1.05, 1.55, 0)], [Vector3(0.9, 1.1, 0.25), Vector3(1.05, 1.55, 0)]]
		"door": shapes = [[Vector3(1.0, 3, 0.25), Vector3(-1.0, 1.5, 0)], [Vector3(1.0, 3, 0.25), Vector3(1.0, 1.5, 0)], [Vector3(1.0, 0.8, 0.25), Vector3(0, 2.6, 0)]]
		"roof": shapes = [[Vector3(3.2, 0.25, 3.2), Vector3(0, 0.12, 0)]]
		"campfire": shapes = []
		"crate": shapes = [[Vector3(1.2, 0.9, 0.9), Vector3(0, 0.45, 0)]]
		"bed": shapes = [[Vector3(1.2, 0.5, 2.2), Vector3(0, 0.25, 0)]]
		"workbench": shapes = [[Vector3(2.0, 1.0, 1.0), Vector3(0, 0.5, 0)]]
		"furnace": shapes = [[Vector3(1.4, 1.4, 1.4), Vector3(0, 0.7, 0)]]
		"fence": shapes = [[Vector3(3, 1.4, 0.2), Vector3(0, 0.7, 0)]]
		"tower": shapes = [[Vector3(3.0, 0.2, 3.0), Vector3(0, 5.0, 0)], [Vector3(1.0, 0.15, 9.0), Vector3(2.05, 2.45, 3.75), Vector3(0.59, 0, 0)], [Vector3(3.0, 0.8, 0.1), Vector3(0, 5.5, -1.45)], [Vector3(0.1, 0.8, 3.0), Vector3(-1.45, 5.5, 0)]]
		"bunker": shapes = [[Vector3(4.0, 1.8, 4.0), Vector3(0, 0.9, 0)]]
	for s in shapes:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = s[0]
		cs.shape = b
		cs.position = s[1]
		if s.size() > 2:
			cs.rotation = s[2]
		body.add_child(cs)
