class_name Lighting
extends Node
## Управление зонами освещения: выключатели + автоматы щитка.

signal zone_changed(zone, lit)

const ZONES := ["hall", "workstation", "warehouse", "corridor", "utility", "toilet", "fitting", "tech", "street"]
const ZONE_NAMES := {
	"hall": "Зал", "workstation": "Рабочее место", "warehouse": "Склад", "corridor": "Коридор",
	"utility": "Подсобка", "toilet": "Туалет", "fitting": "Примерочные", "tech": "Техническая", "street": "Улица",
}
## Какие зоны питаются от какого автомата.
const BREAKERS := {
	"A1": ["hall", "fitting"],
	"A2": ["warehouse"],
	"A3": ["corridor", "utility", "toilet"],
	"A4": ["workstation"],
}

var fixtures := {}  # zone -> Array[LightFixture]
var switches := {}  # zone -> bool
var breakers := {}  # id -> bool
var extra_lights := {}  # zone -> Array[Light3D] (лампы монитора, аварийные)


func _init() -> void:
	for z in ZONES:
		fixtures[z] = []
		switches[z] = z != "tech"
		extra_lights[z] = []
	for b in BREAKERS.keys():
		breakers[b] = true


func register(f: LightFixture) -> void:
	(fixtures[f.zone] as Array).append(f)
	f.set_powered(is_zone_powered(f.zone))


func register_extra(zone: String, l: Node3D) -> void:
	(extra_lights[zone] as Array).append(l)


func breaker_for(zone: String) -> String:
	for b in BREAKERS.keys():
		if zone in BREAKERS[b]:
			return b
	return ""


func is_zone_powered(zone: String) -> bool:
	var b := breaker_for(zone)
	var bon: bool = breakers.get(b, true) if b != "" else true
	return bool(switches.get(zone, true)) and bon


## Есть ли в зоне хоть один реально горящий светильник.
func is_zone_lit(zone: String) -> bool:
	for f in fixtures.get(zone, []):
		if (f as LightFixture).is_lit():
			return true
	return false


func set_switch(zone: String, on: bool) -> void:
	switches[zone] = on
	_refresh(zone)
	Sfx.play_ui("click", -14.0)


func set_breaker(id: String, on: bool) -> void:
	breakers[id] = on
	for z in BREAKERS.get(id, []):
		_refresh(z)


func trip_breaker(id: String) -> void:
	if not breakers.get(id, true):
		return
	set_breaker(id, false)


func tripped_breakers() -> Array:
	var r := []
	for b in breakers.keys():
		if not breakers[b]:
			r.append(b)
	return r


func flicker_zone(zone: String, seconds: float) -> void:
	for f in fixtures.get(zone, []):
		(f as LightFixture).burst(seconds)


func _refresh(zone: String) -> void:
	var on := is_zone_powered(zone)
	for f in fixtures.get(zone, []):
		(f as LightFixture).set_powered(on)
	for l in extra_lights.get(zone, []):
		(l as Node3D).visible = on
	zone_changed.emit(zone, on)
