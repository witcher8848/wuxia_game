extends PanelContainer
## Explicit world actions. No state is changed until a session token is confirmed.
signal closed
var npc_id := ""
var cursor := 0
var preview: Dictionary = {}
var confirmation := false
var heading: Label
var body: RichTextLabel
var feedback: Label
var hint: Label
var options: Array[Label] = []
var option_ids: Array[String] = []

func _ready() -> void:
	position = Vector2(12, 18)
	size = Vector2(616, 330)
	var box := Control.new()
	box.custom_minimum_size = Vector2(614, 328)
	add_child(box)
	heading = Label.new()
	heading.position = Vector2(12, 8)
	heading.size = Vector2(588, 26)
	heading.add_theme_font_size_override("font_size", 18)
	box.add_child(heading)
	body = RichTextLabel.new()
	body.position = Vector2(12, 40)
	body.size = Vector2(588, 146)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.scroll_active = true
	box.add_child(body)
	for index: int in 3:
		var line := Label.new()
		line.position = Vector2(12, 190+index*26)
		line.size = Vector2(588, 26)
		line.add_theme_font_size_override("font_size", 16)
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(line)
		options.append(line)
	feedback = Label.new()
	feedback.position = Vector2(12, 272)
	feedback.size = Vector2(588, 30)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 12)
	box.add_child(feedback)
	hint = Label.new()
	hint.position = Vector2(12, 307)
	hint.size = Vector2(588, 18)
	hint.add_theme_font_size_override("font_size", 12)
	hint.text = tr("WORLD_KEYS")
	box.add_child(hint)
	refresh()

func _clock(view: Dictionary) -> String:
	return tr("WORLD_CLOCK") % [view.get("day", 1), tr(view.get("label", "WORLD_TIME_0"))]

func refresh() -> void:
	if confirmation:
		heading.text = tr("WORLD_CONFIRM_TITLE")
		var summary: Dictionary = preview["summary"]
		body.text = tr("WORLD_CONFIRM_TIME") % [_clock(summary["before"]), _clock(summary["after"])]
		body.text += "\n\n" + tr("WORLD_CONFIRM_HELP" if summary["action_id"] == "WORLD_HELP_NPC" else "WORLD_CONFIRM_WAIT")
		body.text += "\n\n" + tr("W8_WORLD_AUTOSAVE" if GameSession.state.world_flags.get("FACT_W8_ACTIVE", false) else "WORLD_NO_AUTOSAVE")
		option_ids.assign(["cancel", "confirm"])
	else:
		heading.text = tr("WORLD_TITLE") + " · " + _clock(ContentDB.world_time(GameSession.state))
		body.text = tr("WORLD_TIME_RULE")
		option_ids.assign(["wait", "leave"])
		if not npc_id.is_empty():
			var result: Dictionary = ContentDB.world_npc(GameSession.state, npc_id)
			if result.get("error", ERR_INVALID_DATA) == OK:
				var npc: Dictionary = result["npc"]
				heading.text = tr(npc["name_key"]) + " · " + _clock(ContentDB.world_time(GameSession.state))
				if ContentDB.can_reach_world_npc(GameSession.state, npc_id):
					body.text = ContentDB.world_greeting(GameSession.state, npc_id)
				else:
					body.text = tr("WORLD_NPC_MOVED")
				body.text += "\n\n" + tr("WORLD_RELATION") % tr(npc["relationship_label"])
				option_ids.assign(["help", "wait", "leave"])
		body.text += "\n\n" + tr("WORLD_PROTOTYPE")
	cursor = clampi(cursor, 0, option_ids.size()-1)
	for index: int in options.size():
		options[index].visible = index < option_ids.size()
		if not options[index].visible: continue
		var action := option_ids[index]
		var enabled := true
		if action == "help":
			var result: Dictionary = ContentDB.world_npc(GameSession.state, npc_id)
			enabled = result.get("error", ERR_INVALID_DATA) == OK and result["npc"].get("can_help_today", false) and ContentDB.can_reach_world_npc(GameSession.state, npc_id)
		options[index].text = ("▶ " if index == cursor else "   ") + tr("WORLD_ACTION_"+action.to_upper())
		options[index].modulate = Color.WHITE if enabled else Color("#92939c")

func handle_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause") or event.is_action_pressed("open_world"):
		if confirmation:
			GameSession.cancel_world_action(preview.get("token", ""))
			preview.clear()
			confirmation = false
			cursor = 0
			feedback.text = tr("WORLD_CANCELLED")
			refresh()
		else: closed.emit()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
		cursor = posmod(cursor+(1 if event.is_action_pressed("move_down") else -1), option_ids.size())
		refresh()
	elif event.is_action_pressed("confirm"):
		_choose()
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		body.get_v_scroll_bar().value += 64 if event.physical_keycode == KEY_PAGEDOWN else -64

func _choose() -> void:
	var action := option_ids[cursor]
	if action == "leave": closed.emit(); return
	if action == "cancel":
		GameSession.cancel_world_action(preview.get("token", ""))
		preview.clear()
		confirmation = false
		cursor = 0
		feedback.text = tr("WORLD_CANCELLED")
	elif action == "confirm":
		var result: Dictionary = GameSession.confirm_world_action(preview.get("token", ""))
		preview.clear()
		confirmation = false
		cursor = 0
		feedback.text = tr("WORLD_APPLIED" if result["error"] == OK else "WORLD_STALE")
		if result["error"] == OK and result.has("saved"):
			feedback.text = tr("UI_SAVE_SLOT_OK") % (tr("UI_AUTO_SLOT") % int(str(result.get("slot", "auto_01")).trim_prefix("auto_"))) if result["saved"] else tr("W8_PROGRESS_SAVE_FAILED")
	else:
		var result: Dictionary = GameSession.preview_world_action(action, npc_id if action == "help" else "")
		if result["error"] == OK:
			preview = result
			confirmation = true
			cursor = 0 # Cancel is the safe default; Enter cannot double-spend time.
			feedback.text = ""
		else: feedback.text = tr("WORLD_HELP_UNAVAILABLE" if action == "help" else "WORLD_UNAVAILABLE")
	refresh()

func _exit_tree() -> void:
	GameSession.cancel_world_action(preview.get("token", ""))
