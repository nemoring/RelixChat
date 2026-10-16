class_name NightData
extends RefCounted
## Конфигурация пяти (+1) ночей: длительность, агрессия сущностей,
## расписание сценарных событий (в игровых минутах от 00:00).

const ENTITIES := ["faceless", "woman", "courier", "returner", "inspector"]
const ENTITY_TITLES := {
	"faceless": "Клиент без лица",
	"woman": "Женщина из примерочной",
	"courier": "Курьер",
	"returner": "Возврат",
	"inspector": "Проверяющий",
}

## Реальная длительность ночи в секундах (10–15 минут).
const DURATION := [0, 600, 660, 720, 780, 840, 780]

## Агрессия 0..20.
const AGGRESSION := [
	{},
	{"faceless": 1, "woman": 2, "courier": 0, "returner": 0, "inspector": 0},
	{"faceless": 3, "woman": 5, "courier": 6, "returner": 0, "inspector": 0},
	{"faceless": 6, "woman": 8, "courier": 9, "returner": 7, "inspector": 0},
	{"faceless": 8, "woman": 10, "courier": 11, "returner": 9, "inspector": 8},
	{"faceless": 11, "woman": 12, "courier": 13, "returner": 10, "inspector": 11},
	{"faceless": 15, "woman": 15, "courier": 16, "returner": 14, "inspector": 15},
]

## Сценарий: [минута, событие, параметр]. Директор добавляет к этому динамику.
const SCRIPT := [
	[],
	[
		[1, "mail_intro", null],
		[4, "hint", "Сядьте за компьютер у стойки и прочитайте письмо руководства."],
		[18, "intake", 2],
		[45, "client", "normal"],
		[95, "woman_request", null],
		[140, "phone", 1],
		[170, "real_task", 0],
		[210, "client", "normal"],
		[250, "breaker", "A2"],
		[285, "intake", 2],
		[320, "faceless_outside", null],
	],
	[
		[1, "mail_intro", null],
		[15, "intake", 3],
		[35, "client", "normal"],
		[60, "courier_start", null],
		[80, "woman_request", null],
		[110, "phone", 2],
		[130, "real_task", 1],
		[150, "client", "normal"],
		[185, "intake", 3],
		[200, "faceless_outside", null],
		[230, "maglock_fail", null],
		[260, "woman_request", null],
		[290, "client", "normal"],
	],
	[
		[1, "mail_intro", null],
		[12, "intake", 3],
		[30, "returner", null],
		[45, "courier_start", null],
		[60, "woman_request", null],
		[90, "client", "inside"],
		[115, "phone", 3],
		[140, "returner", null],
		[160, "real_task", 2],
		[175, "maglock_fail", null],
		[200, "woman_request", null],
		[230, "returner", null],
		[250, "intake", 3],
		[280, "client", "normal"],
		[310, "returner", null],
	],
	[
		[1, "mail_intro", null],
		[8, "inventory", 6],
		[20, "courier_start", null],
		[30, "returner", null],
		[45, "fake_mail", null],
		[60, "woman_request", null],
		[85, "client", "normal"],
		[100, "phone", 4],
		[110, "real_task", 3],
		[130, "fake_mail", null],
		[150, "returner", null],
		[165, "maglock_fail", null],
		[190, "woman_request", null],
		[205, "inspector_cam", null],
		[220, "fake_mail", null],
		[240, "intake", 3],
		[270, "returner", null],
		[300, "fake_mail", null],
	],
	[
		[1, "mail_intro", null],
		[3, "tech_key", null],
		[12, "courier_start", null],
		[20, "intake", 3],
		[35, "returner", null],
		[50, "woman_request", null],
		[65, "fake_mail", null],
		[80, "client", "inside"],
		[95, "phone", 5],
		[120, "real_task", 0],
		[135, "maglock_fail", null],
		[150, "returner", null],
		[170, "fake_mail", null],
		[190, "woman_request", null],
		[210, "inspector_cam", null],
		[240, "returner", null],
		[260, "fake_mail", null],
		[300, "own_order", null],
		[310, "finale", null],
	],
	[
		[1, "mail_intro", null],
		[5, "courier_start", null],
		[10, "intake", 3],
		[20, "returner", null],
		[30, "woman_request", null],
		[40, "fake_mail", null],
		[55, "maglock_fail", null],
		[70, "client", "inside"],
		[90, "returner", null],
		[100, "woman_request", null],
		[120, "fake_mail", null],
		[140, "phone", 6],
		[150, "real_task", 1],
		[170, "maglock_fail", null],
		[180, "returner", null],
		[200, "woman_request", null],
		[220, "fake_mail", null],
		[240, "intake", 3],
		[260, "returner", null],
		[280, "maglock_fail", null],
		[300, "woman_request", null],
	],
]


static func aggression(night: int, entity: String) -> int:
	if GameState.is_custom_night and GameState.custom_difficulty.has(entity):
		return int(GameState.custom_difficulty[entity])
	var n := clampi(night, 1, 6)
	return int(AGGRESSION[n].get(entity, 0))


static func duration(night: int) -> float:
	return float(DURATION[clampi(night, 1, 6)])


static func script_for(night: int) -> Array:
	if GameState.is_custom_night:
		return SCRIPT[6]
	return SCRIPT[clampi(night, 1, 6)]
