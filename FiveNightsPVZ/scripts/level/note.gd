class_name Note
extends Interactable
## Документ, который можно прочитать. doc_index>=0 — коллекционный документ.

var title := ""
var body := ""
var doc_index := -1


func prompt(_p) -> String:
	return "Прочитать: " + title if enabled else ""


func interact(player) -> void:
	if GameWorld.instance:
		GameWorld.instance.show_document(title, body)
		if doc_index >= 0 and GameState.collect_document(doc_index):
			GameWorld.instance.hud_message("Документ сохранён в архив (%d/%d)." % [(GameState.data["documents"] as Array).size(), GameState.DOCUMENT_COUNT])
	Sfx.play_3d("cloth", global_position, -10.0, 1.6)
	used.emit(player)
