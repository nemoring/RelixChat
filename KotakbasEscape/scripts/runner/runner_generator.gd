class_name RunnerGenerator
extends RefCounted
## Генератор рядов препятствий. Гарантирует проходимость: существует «безопасная
## полоса», которая за один ряд смещается максимум на одну полосу и никогда
## не перекрыта сплошным препятствием (только пусто / прыжок / подкат).

enum { NONE, BLOCK, LOW, HIGH }

var rng := RandomNumberGenerator.new()
var safe_lane := 1
var density := 0.5

func _init(seed_value := 0, dens := 0.5) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	density = dens

## Возвращает ряд из трёх ячеек [левая, центр, правая].
func next_row() -> Array:
	if rng.randf() < 0.4:
		safe_lane = clampi(safe_lane + (1 if rng.randf() < 0.5 else -1), 0, 2)
	var row := [NONE, NONE, NONE]
	for l in 3:
		if l == safe_lane:
			if rng.randf() < density * 0.55:
				row[l] = LOW if rng.randf() < 0.5 else HIGH
		elif rng.randf() < density:
			var r := rng.randf()
			row[l] = BLOCK if r < 0.55 else (LOW if r < 0.78 else HIGH)
	# Пустой ряд не нужен — хотя бы одно препятствие.
	if row == [NONE, NONE, NONE]:
		var l2 := (safe_lane + 1 + rng.randi() % 2) % 3
		row[l2] = BLOCK
	return row

## Проверка проходимости последовательности рядов: существует путь, где между
## соседними рядами игрок смещается не более чем на max_shift полос и никогда
## не стоит в сплошном препятствии.
static func is_sequence_passable(rows: Array, start_lane := 1, max_shift := 1) -> bool:
	var reachable := [false, false, false]
	for l in 3:
		reachable[l] = absi(l - start_lane) <= max_shift
	for row in rows:
		var next := [false, false, false]
		for l in 3:
			if row[l] == BLOCK:
				continue
			for p in 3:
				if reachable[p] and absi(p - l) <= max_shift:
					next[l] = true
					break
		reachable = next
		if not (reachable[0] or reachable[1] or reachable[2]):
			return false
	return true
