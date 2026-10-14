class_name RecipeDB
extends RefCounted
## Рецепты крафта. station: hand / workbench / campfire / furnace.
## Стоимость и время масштабируются сложностью (DifficultyManager).

const RECIPES := {
	"rope": {"result": "rope", "n": 2, "cost": {"fabric": 1}, "time": 2.0, "station": "hand"},
	"bandage": {"result": "bandage", "n": 1, "cost": {"fabric": 2}, "time": 2.5, "station": "hand"},
	"axe": {"result": "axe", "n": 1, "cost": {"wood": 3, "stone": 2, "rope": 1}, "time": 4.0, "station": "hand"},
	"pickaxe": {"result": "pickaxe", "n": 1, "cost": {"wood": 3, "stone": 3, "rope": 1}, "time": 4.0, "station": "hand"},
	"spear": {"result": "spear", "n": 1, "cost": {"wood": 4, "stone": 1, "rope": 1}, "time": 4.0, "station": "hand"},
	"meat_cooked": {"result": "meat_cooked", "n": 1, "cost": {"meat_raw": 1}, "time": 5.0, "station": "campfire"},
	"water_clean": {"result": "water_clean", "n": 1, "cost": {"water_dirty": 1}, "time": 4.0, "station": "campfire"},
	"mushroom_roast": {"result": "meat_cooked", "n": 1, "cost": {"mushroom": 3}, "time": 5.0, "station": "campfire"},
	"metal": {"result": "metal", "n": 1, "cost": {"scrap": 2}, "time": 6.0, "station": "furnace"},
	"electronics": {"result": "electronics", "n": 3, "cost": {"ufo_part": 1}, "time": 6.0, "station": "workbench"},
	"electronics_scrap": {"result": "electronics", "n": 1, "cost": {"scrap": 3, "rope": 1}, "time": 8.0, "station": "workbench"},
	"fabric_from_rope": {"result": "fabric", "n": 1, "cost": {"rope": 2}, "time": 2.0, "station": "workbench"},
}

const STATION_NAMES := {
	"hand": "В руках",
	"workbench": "Верстак",
	"campfire": "Костёр",
	"furnace": "Печь",
}

static func cost_for(id: String) -> Dictionary:
	return DifficultyManager.scaled_cost(RECIPES[id].cost, "craft")

static func time_for(id: String) -> float:
	return float(RECIPES[id].time) * float(DifficultyManager.p("craft_time_mult"))
