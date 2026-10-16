extends PanelContainer
## A keyboard view only. Permanent changes go through GameSession commands.
signal close_requested
signal activity_requested(activity: String)

var target_id := ""
var node_id := ""
var cursor := 0
var view: Dictionary = {}
var heading: Label
var body: RichTextLabel
var choices: Array[Label] = []
var feedback: Label
var hint: Label
var _focus_by_node: Dictionary = {}

func _ready() -> void:
	_build_layout()
	go_to(ContentDB.dialogue_entry(target_id, GameSession.state))

func _build_layout() -> void:
	position = Vector2(12, 54)
	size = Vector2(616, 294)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Control.new()
	box.custom_minimum_size = Vector2(614, 292)
	add_child(box)
	heading = Label.new()
	heading.position = Vector2(12, 8)
	heading.size = Vector2(588, 26)
	heading.add_theme_font_size_override("font_size", 18)
	box.add_child(heading)
	body = RichTextLabel.new()
	body.position = Vector2(12, 38)
	body.size = Vector2(588, 86)
	body.bbcode_enabled = false
	body.scroll_active = true
	body.add_theme_font_size_override("normal_font_size", 16)
	box.add_child(body)
	for index: int in 4:
		var label := Label.new()
		label.position = Vector2(12, 130 + index * 25)
		label.size = Vector2(588, 25)
		label.add_theme_font_size_override("font_size", 16)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(label)
		choices.append(label)
	feedback = Label.new()
	feedback.position = Vector2(12, 234)
	feedback.size = Vector2(588, 32)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 12)
	box.add_child(feedback)
	hint = Label.new()
	hint.position = Vector2(12, 270)
	hint.size = Vector2(588, 18)
	hint.add_theme_font_size_override("font_size", 12)
	hint.text = tr("INV_DIALOGUE_KEYS")
	box.add_child(hint)

func go_to(identifier: String) -> void:
	if identifier in DialogueCatalog.ACTIVITIES:
		activity_requested.emit(identifier)
		return
	if identifier == "@entry":
		identifier = ContentDB.dialogue_entry(target_id, GameSession.state)
	if identifier.is_empty():
		close_requested.emit()
		return
	node_id = identifier
	cursor = _focus_by_node.get(node_id, 0)
	refresh()
	body.scroll_to_line(0)

func refresh() -> void:
	view = ContentDB.dialogue_view(node_id, GameSession.state)
	if view.is_empty():
		close_requested.emit()
		return
	cursor = clampi(cursor, 0, view["choices"].size() - 1)
	heading.text = tr(view["speaker_key"])
	body.text = tr(view["text_key"])
	if node_id == "D_TOKEN" and GameSession.state.evidence_states.has("CL_BOATMAN_01"):
		body.text += "\n" + tr("INV_TRACE_HINT")
	hint.text = tr("INV_DIALOGUE_KEYS")
	var greeting := ContentDB.world_greeting(GameSession.state, target_id)
	if not greeting.is_empty():
		var npc: Dictionary = ContentDB.world_npc(GameSession.state, target_id)["npc"]
		# Keep the current answer/instructions first and retain its actual speaker.
		# Repeating four ambient lines before every answer hides the quest text in
		# this short reading viewport. Only the entry adds local chatter afterwards;
		# H still opens the complete time/relationship conversation at any node.
		if node_id == ContentDB.dialogue_entry(target_id, GameSession.state):
			body.text += "\n\n" + tr(npc["name_key"]) + ": " + greeting
		hint.text = tr("WORLD_DIALOGUE_KEYS")
	for index: int in choices.size():
		choices[index].visible = index < view["choices"].size()
		if not choices[index].visible:
			continue
		var option: Dictionary = view["choices"][index]
		choices[index].text = ("▶ " if index == cursor else "   ") + tr(option["text_key"])
		if not option["enabled"] and option["reason"] == "INV_ALREADY_RECORDED":
			choices[index].text += " · " + tr("INV_DONE")
		choices[index].modulate = Color.WHITE if option["enabled"] else Color("#92939c")

func handle_input(event: InputEvent) -> void:
	# Consume all events while open: no quick save, held movement or GUI fallback.
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		body.scroll_to_line(maxi(0, body.get_line_count() - 1))
		feedback.text = tr("INV_FASTREAD_READY")
		return
	if event.is_echo():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
		close_requested.emit()
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		close_requested.emit()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
		cursor = posmod(cursor + (1 if event.is_action_pressed("move_down") else -1), view["choices"].size())
		_focus_by_node[node_id] = cursor
		refresh()
		feedback.text = "" if view["choices"][cursor]["enabled"] else tr(view["choices"][cursor]["reason"])
	elif event.is_action_pressed("confirm"):
		var choice_id: String = view["choices"][cursor]["id"]
		var result: Dictionary = GameSession.choose_dialogue(node_id, choice_id)
		feedback.text = tr(result.get("feedback_key", "INV_COMMAND_FAILED"))
		if result["error"] == OK:
			go_to(result["next"])
		else:
			refresh()
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		body.get_v_scroll_bar().value += 56 if event.physical_keycode == KEY_PAGEDOWN else -56
