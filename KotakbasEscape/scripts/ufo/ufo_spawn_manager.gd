class_name UFOSpawnManager
extends Node
## Планировщик налётов НЛО ТЦК по игровому времени: первый налёт через 1,5–2
## игровых дня после появления игрока в лесу, следующий — через случайный
## интервал 1,5–2 дня после окончания предыдущего. Предупреждения за 30 и 10
## игровых минут. Одновременно — не больше одной тарелки. Таймер сохраняется.

signal warning(minutes_left: int)
signal raid_started(ufo: UFOController)
signal raid_ended(defeated: bool, summary: String, stolen_total: int)

const MIN_DAYS := 1.5
const MAX_DAYS := 2.0

var game
var next_raid := -1.0
var warned30 := false
var warned10 := false
var raid_count := 0
var ufo: UFOController
var final_pending := false
var final_done := false

func setup(g) -> void:
	game = g

static func random_interval() -> float:
	return randf_range(MIN_DAYS, MAX_DAYS) * DayNight.DAY_MIN

func init_first(now: float) -> void:
	if next_raid < 0.0:
		next_raid = now + random_interval()
		warned30 = false
		warned10 = false

func minutes_until(now: float) -> float:
	if is_raid_active():
		return 0.0
	return next_raid - now

func is_raid_active() -> bool:
	return is_instance_valid(ufo)

func tick(now: float) -> void:
	if is_raid_active() or next_raid < 0.0:
		return
	var left := next_raid - now
	if left <= 30.0 and not warned30:
		warned30 = true
		warning.emit(30)
	if left <= 10.0 and not warned10:
		warned10 = true
		warning.emit(10)
	if left <= 0.0:
		start_raid(false)

## Немедленный вызов (отладка) или финальный налёт сюжета.
func start_raid(final := false, saved := {}) -> void:
	if is_raid_active():
		return
	var base: Vector3 = game.raid_base(final)
	ufo = UFOController.new()
	ufo.name = "UFO_TCK"
	game.add_child(ufo)
	ufo.final_raid = final
	ufo.setup(game, base, saved)
	ufo.final_raid = final or saved.get("final", false)
	ufo.left.connect(_on_ufo_left)
	raid_count += 1
	raid_started.emit(ufo)

func debug_now(now: float) -> void:
	next_raid = now
	warned30 = true
	warned10 = true
	start_raid(false)

func _on_ufo_left(defeated: bool) -> void:
	var was_final := ufo.final_raid if is_instance_valid(ufo) else false
	var summary := ufo.stealer.summary() if is_instance_valid(ufo) else ""
	var total := ufo.stealer.stolen_total if is_instance_valid(ufo) else 0
	ufo = null
	# Следующий налёт — через новый случайный интервал.
	next_raid = game.time_min + random_interval()
	warned30 = false
	warned10 = false
	if was_final:
		final_done = true
	raid_ended.emit(defeated, summary, total)

func save_data() -> Dictionary:
	var d := {
		"next_raid": next_raid,
		"warned30": warned30,
		"warned10": warned10,
		"raid_count": raid_count,
		"final_done": final_done,
	}
	if is_raid_active() and ufo.is_active_threat():
		d["active"] = ufo.save_data()
	return d

func load_data(d: Dictionary) -> void:
	next_raid = float(d.get("next_raid", -1.0))
	warned30 = bool(d.get("warned30", false))
	warned10 = bool(d.get("warned10", false))
	raid_count = int(d.get("raid_count", 0))
	final_done = bool(d.get("final_done", false))

## Восстановление активного налёта после загрузки.
func restore_active(d: Dictionary) -> void:
	if d.has("active"):
		var a: Dictionary = d.active
		start_raid(bool(a.get("final", false)), a)
		raid_count -= 1
