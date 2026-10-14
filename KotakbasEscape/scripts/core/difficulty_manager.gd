extends Node
## Сложность выбирается один раз в начале прохождения и влияет на все три главы.
## Параметры хранятся в resources/difficulty/difficulty_profiles.gd.

signal difficulty_locked(level: int)

enum Level { EASY, NORMAL, HARD, KOTAKBAS }

const PROFILES := preload("res://resources/difficulty/difficulty_profiles.gd")

var _level: int = Level.NORMAL
var _locked := false

func set_level_for_new_game(level: int) -> void:
	_level = clampi(level, Level.EASY, Level.KOTAKBAS)
	_locked = true
	difficulty_locked.emit(_level)

## Используется только при загрузке сохранения: сложность берётся из файла.
func restore_level(level: int) -> void:
	_level = clampi(level, Level.EASY, Level.KOTAKBAS)
	_locked = true

func unlock() -> void:
	_locked = false

func is_locked() -> bool:
	return _locked

func level() -> int:
	return _level

func level_name(level: int = -1) -> String:
	if level < 0:
		level = _level
	return PROFILES.DATA[level].name

func p(key: String):
	return PROFILES.DATA[_level][key]

func p_for(level: int, key: String):
	return PROFILES.DATA[level][key]

## Цена с учётом сложности (крафт и строительство).
func scaled_cost(cost: Dictionary, kind: String = "craft") -> Dictionary:
	var mult: float = p("craft_cost_mult") if kind == "craft" else p("build_cost_mult")
	var out := {}
	for k in cost:
		out[k] = maxi(1, int(ceil(float(cost[k]) * mult)))
	return out
