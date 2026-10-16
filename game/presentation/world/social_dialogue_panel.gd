extends "res://game/presentation/investigation/dialogue_panel.gd"
## Free local conversation for an NPC without a quest dialogue graph.
func _ready() -> void:
	_build_layout()
	refresh()

func refresh() -> void:
	var result: Dictionary = ContentDB.world_npc(GameSession.state, target_id)
	if result.get("error", ERR_INVALID_DATA) != OK:
		close_requested.emit()
		return
	heading.text = tr(result["npc"]["name_key"])
	body.text = ContentDB.world_greeting(GameSession.state, target_id)
	hint.text = tr("WORLD_SOCIAL_DIALOGUE_KEYS")
	for index: int in choices.size():
		choices[index].visible = index == 0
		if index == 0: choices[index].text = "▶ " + tr("WORLD_ACTION_LEAVE")

func handle_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	if event.is_action_pressed("confirm") or event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		close_requested.emit()
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		body.get_v_scroll_bar().value += 56 if event.physical_keycode == KEY_PAGEDOWN else -56
