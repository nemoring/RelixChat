class_name SurvivalStats
extends RefCounted
## Характеристики: здоровье, голод, жажда, выносливость, температура тела.
## Обновление идёт в игровых минутах (сон и ускорение времени учитываются).

var health := 100.0
var hunger := 85.0
var thirst := 85.0
var stamina := 100.0
var body_temp := 36.6
var hunger_rate := 3.6 # в игровой час
var thirst_rate := 4.6

func setup_from_difficulty() -> void:
	hunger_rate = float(DifficultyManager.p("hunger_rate"))
	thirst_rate = float(DifficultyManager.p("thirst_rate"))

## dt_min — прошедшие игровые минуты. env_temp — температура окружения, °C.
func tick(dt_min: float, env_temp: float, sleeping: bool) -> void:
	var h := dt_min / 60.0
	var sleep_k := 0.5 if sleeping else 1.0
	hunger = maxf(0.0, hunger - hunger_rate * h * sleep_k)
	thirst = maxf(0.0, thirst - thirst_rate * h * sleep_k)
	# Температура тела стремится к комфортной, если вокруг тепло, и падает на холоде.
	if env_temp < 10.0:
		body_temp -= (10.0 - env_temp) * 0.06 * h
	elif env_temp > 14.0:
		body_temp = move_toward(body_temp, 36.6, 1.5 * h)
	body_temp = clampf(body_temp, 32.0, 37.5)
	var dmg := 0.0
	if hunger <= 0.0:
		dmg += 6.0 * h
	if thirst <= 0.0:
		dmg += 8.0 * h
	if body_temp < 35.0:
		dmg += (5.0 if body_temp > 34.0 else 10.0) * h
	if dmg > 0.0:
		health = maxf(0.0, health - dmg)
	elif hunger > 40.0 and thirst > 40.0 and body_temp > 35.5:
		health = minf(100.0, health + (6.0 if sleeping else 2.5) * h)

func apply_food(f: Dictionary) -> void:
	hunger = clampf(hunger + float(f.get("hunger", 0)), 0.0, 100.0)
	thirst = clampf(thirst + float(f.get("thirst", 0)), 0.0, 100.0)
	health = clampf(health + float(f.get("health", 0)), 0.0, 100.0)
	stamina = clampf(stamina + float(f.get("stamina", 0)), 0.0, 100.0)

func is_dead() -> bool:
	return health <= 0.0

func to_dict() -> Dictionary:
	return {"health": health, "hunger": hunger, "thirst": thirst, "stamina": stamina, "body_temp": body_temp}

func from_dict(d: Dictionary) -> void:
	health = float(d.get("health", 100.0))
	hunger = float(d.get("hunger", 85.0))
	thirst = float(d.get("thirst", 85.0))
	stamina = float(d.get("stamina", 100.0))
	body_temp = float(d.get("body_temp", 36.6))
