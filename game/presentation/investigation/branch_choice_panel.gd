extends "res://game/presentation/investigation/dialogue_panel.gd"
## The UI never mutates a route. Session owns preview, immutable anchor,
## one-time confirmation and retrying persistence of an already committed choice.
signal title_requested

var activity := "@branch"
var mode := "branch"
var phase := "choose"
var selected_choice := "home"
var preview: Dictionary = {}
var entries: Array[Dictionary] = []
var message_key := ""
var last_save_error: int = OK

func _ready() -> void:
	_build_layout()
	position.y = 8
	size.y = 344
	get_child(0).custom_minimum_size.y = 342
	body.size.y = 130
	for index: int in choices.size(): choices[index].position.y = 174 + index * 25
	feedback.position.y = 278
	hint.position.y = 318
	if GameSession.pending_branch_save(): phase = "pending"
	refresh()

func refresh() -> void:
	entries.clear()
	heading.text = tr("W8_CHOICE_CONFIRM_TITLE" if phase == "confirm" else "W8_CHOICE_TITLE")
	hint.text = tr("W8_CHOICE_KEYS")
	if phase == "pending":
		body.text = tr("W8_CHOICE_SAVE_PENDING")
		entries.append({"id":"retry", "title":tr("W8_CHOICE_RETRY_SAVE")})
		entries.append({"id":"title", "title":tr("W8_CHOICE_RETURN_TITLE")})
	elif phase == "confirm":
		body.text = tr("W8_CHOICE_HOME_SUMMARY" if selected_choice == "home" else "W8_CHOICE_DOCK_SUMMARY")
		entries.append({"id":"confirm", "title":tr("W8_CHOICE_CONFIRM")})
		entries.append({"id":"back", "title":tr("W8_CHOICE_BACK")})
	else:
		body.text = tr("W8_CHOICE_PROMPT")
		entries.append({"id":"home", "title":tr("W8_CHOICE_HOME")})
		entries.append({"id":"dock", "title":tr("W8_CHOICE_DOCK")})
		entries.append({"id":"cancel", "title":tr("W8_CHOICE_CANCEL")})
	cursor = clampi(cursor, 0, entries.size() - 1)
	for index: int in choices.size():
		choices[index].visible = index < entries.size()
		if choices[index].visible:
			choices[index].text = ("▶ " if cursor == index else "   ") + entries[index]["title"]
			choices[index].modulate = Color.WHITE
	feedback.text = tr(message_key) if not message_key.is_empty() else ""
	if last_save_error != OK and not feedback.text.is_empty(): feedback.text += " · " + error_string(last_save_error)
	body.scroll_to_line(0)

func cancel_preview() -> void:
	GameSession.cancel_branch_choice(preview.get("token", ""))
	preview.clear()

func handle_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		if phase == "pending":
			message_key = "W8_CHOICE_SAVE_PENDING"
			refresh()
		elif phase == "confirm":
			_back_to_choices()
		else:
			cancel_preview()
			close_requested.emit()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
		cursor = posmod(cursor + (1 if event.is_action_pressed("move_down") else -1), entries.size())
		refresh()
	elif event.is_action_pressed("confirm"):
		_confirm()
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		body.get_v_scroll_bar().value += 56 if event.physical_keycode == KEY_PAGEDOWN else -56

func _back_to_choices() -> void:
	cancel_preview()
	phase = "choose"
	cursor = 0 if selected_choice == "home" else 1
	message_key = ""
	last_save_error = OK
	refresh()

func _confirm() -> void:
	var selected: String = entries[cursor]["id"]
	if phase == "pending":
		if selected == "title":
			title_requested.emit()
			return
		_accept_result(GameSession.retry_branch_save())
		return
	if selected == "cancel":
		cancel_preview()
		close_requested.emit()
		return
	if phase == "confirm":
		if selected == "back":
			_back_to_choices()
			return
		var token: String = preview.get("token", "")
		preview.clear()
		_accept_result(GameSession.confirm_branch_choice(token))
		return
	selected_choice = selected
	preview = GameSession.preview_branch_choice(selected_choice)
	if preview.get("error", ERR_INVALID_DATA) != OK:
		message_key = "W8_CHOICE_SAVE_FAILED"
		last_save_error = preview.get("error", ERR_INVALID_DATA)
		refresh()
		return
	phase = "confirm"
	cursor = 1 # A second Enter cancels rather than committing an irreversible event.
	message_key = ""
	last_save_error = OK
	refresh()

func _accept_result(result: Dictionary) -> void:
	if result.get("error", ERR_INVALID_DATA) == OK:
		if result.get("saved", false):
			close_requested.emit()
			return
		phase = "pending"
		cursor = 0
		message_key = "W8_CHOICE_RESULT_SAVE_FAILED"
		last_save_error = result.get("save_error", ERR_CANT_CREATE)
	else:
		phase = "pending" if GameSession.pending_branch_save() else "choose"
		cursor = 0 if selected_choice == "home" else 1
		message_key = "W8_CHOICE_RESULT_SAVE_FAILED" if phase == "pending" else "W8_CHOICE_SAVE_FAILED"
		last_save_error = result.get("save_error", result.get("error", ERR_INVALID_DATA))
	refresh()
