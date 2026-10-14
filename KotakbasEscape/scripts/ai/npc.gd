class_name NPC
extends Node3D
## NPC выживания: дед Михалыч (деревня, карта) и лесник Гена (разговаривает с деревом).
## Простая модель, поворот к игроку, бессмысленные истории.

var npc_id := "mikhalych"
var game
var it: Interactable
var _t := 0.0
var _talk_tree_t := 4.0
var head: Node3D
var arm: Node3D

const STORIES := [
	"Был у меня в девяносто третьем телевизор. Показывал только один канал. Про меня.",
	"Однажды я поймал щуку. Она сказала, что она не щука. Я отпустил. До сих пор думаю, кто это был.",
	"Тарелка эта раньше молоко воровала. Потом перешла на дрова. Растёт, значит.",
	"Если долго смотреть на пень, пень начинает смотреть на тебя. Проверено.",
	"Голуби — они всё понимают. Просто не говорят. Кроме одного. Тот говорит «курлык», и этого достаточно.",
	"Я в армии не служил. Меня просто не нашли. Сорок лет уже ищут.",
	"Камень в кабину — лучшее средство. Мне ещё дед рассказывал. А ему — прадед. А прадеду — тарелка.",
	"Знаешь, почему Windows XP в лесу? Потому что ей тут спокойно. Как и мне.",
	"Ночью волки воют. А днём молчат. Стесняются, наверное.",
]
const TREE_LINES := [
	"Гена (дереву): ...и вот я ей говорю: «Галя, это не берёза, это осина!»",
	"Гена (дереву): Ты меня слушаешь вообще? Вот всегда ты так. Стоишь и молчишь.",
	"Гена (дереву): Ладно, извини. Я был неправ. Ты красивое дерево.",
	"Гена (дереву): Говорят, тарелка опять прилетала. Ты видела? Конечно видела, ты тут всё видишь.",
]

func setup(id: String, g) -> void:
	npc_id = id
	game = g
	_build()
	it = Interactable.new()
	it.position = Vector3(0, 1.0, 0)
	it.radius = 3.0
	it.label = "Говорить: " + ("дед Михалыч" if id == "mikhalych" else "лесник Гена")
	it.action = func(): game.talk_to_npc(npc_id)
	add_child(it)

func _build() -> void:
	var coat := Color(0.35, 0.3, 0.25) if npc_id == "mikhalych" else Color(0.3, 0.45, 0.25)
	MK.box(self, Vector3(0.55, 0.75, 0.32), coat, Vector3(0, 1.25, 0))
	MK.box(self, Vector3(0.2, 0.85, 0.22), Color(0.2, 0.2, 0.25), Vector3(-0.13, 0.43, 0))
	MK.box(self, Vector3(0.2, 0.85, 0.22), Color(0.2, 0.2, 0.25), Vector3(0.13, 0.43, 0))
	head = Node3D.new()
	head.position = Vector3(0, 1.8, 0)
	add_child(head)
	MK.sphere(head, 0.22, Color(0.92, 0.75, 0.62), Vector3.ZERO, 9)
	if npc_id == "mikhalych":
		MK.box(head, Vector3(0.48, 0.22, 0.48), Color(0.4, 0.3, 0.25), Vector3(0, 0.18, 0))
		MK.box(head, Vector3(0.3, 0.22, 0.12), Color(0.92, 0.92, 0.9), Vector3(0, -0.15, -0.16))
	else:
		MK.cyl(head, 0.32, 0.32, 0.05, Color(0.3, 0.45, 0.2), Vector3(0, 0.15, 0), Vector3.ZERO, 10)
		MK.cyl(head, 0.18, 0.2, 0.2, Color(0.3, 0.45, 0.2), Vector3(0, 0.25, 0), Vector3.ZERO, 10)
		MK.box(head, Vector3(0.3, 0.18, 0.1), Color(0.55, 0.35, 0.2), Vector3(0, -0.15, -0.17))
	MK.sphere(head, 0.03, Color.BLACK, Vector3(-0.08, 0.04, -0.2), 4)
	MK.sphere(head, 0.03, Color.BLACK, Vector3(0.08, 0.04, -0.2), 4)
	arm = Node3D.new()
	arm.position = Vector3(0.36, 1.55, 0)
	add_child(arm)
	MK.box(arm, Vector3(0.14, 0.6, 0.14), coat, Vector3(0, -0.3, 0))
	MK.box(self, Vector3(0.14, 0.6, 0.14), coat, Vector3(-0.36, 1.25, 0))

func _process(delta: float) -> void:
	_t += delta
	if game == null:
		return
	var p: Vector3 = game.player.global_position
	var to := p - global_position
	to.y = 0
	var d := to.length()
	if npc_id == "gena" and d > 5.0:
		# Разговаривает с деревом
		arm.rotation.x = -1.2 + sin(_t * 4.0) * 0.5
		head.rotation.y = sin(_t * 0.8) * 0.3
		_talk_tree_t -= delta
		if _talk_tree_t <= 0.0 and d < 22.0:
			_talk_tree_t = randf_range(7.0, 12.0)
			game.subtitle(TREE_LINES.pick_random())
		return
	arm.rotation.x = lerpf(arm.rotation.x, sin(_t * 2.0) * 0.2, delta * 4.0)
	if d < 8.0:
		var target_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 3.0)
