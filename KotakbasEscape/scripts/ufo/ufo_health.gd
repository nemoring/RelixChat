class_name UFOHealth
extends Node
## Прочность кабины НЛО ТЦК: количество необходимых попаданий зависит от сложности
## (10 / 13 / 17 / 20). Засчитываются только попадания в кабину.

signal hit(left: int, max_hits: int)
signal destroyed

var max_hits := 13
var hits := 0

func setup(saved_hits := 0) -> void:
	max_hits = int(DifficultyManager.p("ufo_hits"))
	hits = clampi(saved_hits, 0, max_hits)

func left() -> int:
	return max_hits - hits

func ratio() -> float:
	return float(left()) / float(max_hits)

func is_destroyed() -> bool:
	return hits >= max_hits

func register_hit() -> void:
	if is_destroyed():
		return
	hits += 1
	hit.emit(left(), max_hits)
	if is_destroyed():
		destroyed.emit()
