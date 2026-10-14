extends Node
## Локализация. Ключи — русские строки интерфейса, английский перевод
## подставляется автоматически через TranslationServer (auto_translate у Control).
## Сюжетные тексты остаются на русском (оригинальная озвучка/текст игры).

const EN_TABLE := preload("res://localization/strings_en.gd")

func _ready() -> void:
	var ru := Translation.new()
	ru.locale = "ru"
	TranslationServer.add_translation(ru)
	var en := Translation.new()
	en.locale = "en"
	for k in EN_TABLE.STRINGS:
		en.add_message(k, EN_TABLE.STRINGS[k])
	TranslationServer.add_translation(en)
	TranslationServer.set_locale("ru")

func set_language(code: String) -> void:
	TranslationServer.set_locale(code)
