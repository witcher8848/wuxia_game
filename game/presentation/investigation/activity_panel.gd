extends "res://game/presentation/investigation/dialogue_panel.gd"
const Journal = preload("res://game/presentation/investigation/journal_view.gd")
const TABS := ["INV_TAB_CASE", "INV_TAB_EVIDENCE", "INV_TAB_PEOPLE", "INV_TAB_ROUTES"]
var activity := "@journal"
var mode := "journal"
var tab := 0
var first_selected := ""
var entries: Array[Dictionary] = []
var message_key := ""
var wrong_attempts := 0
var _tab_focus: Dictionary = {}
var _first_cursor := 0
var handover_preview: Dictionary = {}
var onboarding := false

func _ready() -> void:
	_build_layout()
	# Evidence needs more reading space than short dialogue. Keep a fixed four-row
	# list and scroll long descriptions without covering the choice area.
	position.y = 8
	size.y = 344
	get_child(0).custom_minimum_size.y = 342
	body.size.y = 130
	for index: int in choices.size(): choices[index].position.y = 174 + index * 25
	feedback.position.y = 278
	hint.position.y = 318
	mode = "challenge" if activity == "@challenge" else "compare" if activity == "@compare" else "graves_compare" if activity == "@graves_compare" else "journal"
	if activity == "@handover":
		mode = "handover"
		handover_preview = GameSession.preview_original_handover()
		cursor = 1 # Keep original is the safe initial selection.
	GameSession.state_replaced.connect(_on_session_state_replaced)
	refresh()

func _on_session_state_replaced() -> void:
	if mode == "journal":
		refresh()

func refresh() -> void:
	var evidence: Array[Dictionary] = Journal.evidence_entries(GameSession.state, ContentDB.get_investigation_definitions())
	entries.clear()
	var prompt := ""
	if mode == "handover":
		heading.text = tr("INV_HANDOVER_TITLE")
		hint.text = tr("INV_INQUIRY_KEYS")
		if handover_preview.get("error") == OK:
			prompt = tr("INV_HANDOVER_EFFECT")
			entries.append({"id":"confirm", "title":tr("INV_HANDOVER_CONFIRM"), "detail":""})
		else:
			prompt = tr(handover_preview.get("feedback_key", "INV_COMMAND_FAILED"))
		entries.append({"id":"cancel", "title":tr("INV_HANDOVER_KEEP") if handover_preview.get("error") == OK else tr("INV_BACK"), "detail":""})
	elif mode == "journal":
		var tab_key: String = "W8_ROUTES_TITLE" if tab == 3 and GameSession.state.world_flags.get("FACT_W8_ACTIVE", false) else TABS[tab]
		heading.text = tr("INV_CODEX_TITLE") + " · " + tr(tab_key)
		hint.text = tr("INV_CODEX_KEYS" if tab == 1 else "INV_JOURNAL_NAV_KEYS")
		if tab == 0:
			entries = Journal.quest_entries(GameSession.state, ContentDB.get_investigation_definitions())
			# Future locked quests are not actionable and spoil the first objective.
			entries = entries.filter(func(item: Dictionary) -> bool: return GameSession.state.quest_states.has(item["id"]))
		elif tab == 1:
			entries = evidence
		elif tab == 2:
			entries = Journal.people_entries(ContentDB.people_entries(GameSession.state))
			if entries.is_empty(): prompt = tr("INV_EMPTY_PEOPLE")
		else:
			entries = Journal.route_entries(GameSession.state)
			if entries.is_empty(): prompt = tr("W8_ROUTES_EMPTY")
		if onboarding:
			prompt = tr("INTRO_JOURNAL_HELP")
			if tab == 0 and not entries.is_empty():
				entries[0]["detail"] = tr("INTRO_JOURNAL_GOAL").replace("\\n", "\n")
	else:
		var identifier := "INQ_BOATMAN" if mode == "challenge" else "INQ_W8_GRAVES" if mode == "graves_compare" else "INQ_INDEX"
		view = ContentDB.inquiry_view(identifier, GameSession.state, first_selected)
		if view.is_empty():
			close_requested.emit()
			return
		heading.text = tr(view["title_key"])
		hint.text = tr("INV_INQUIRY_KEYS")
		prompt = tr(view["prompt_key"])
		for candidate: String in view["candidates"]:
			for item: Dictionary in evidence:
				if item["id"] == candidate: entries.append(item)
		if not first_selected.is_empty():
			for item: Dictionary in evidence:
				if item["id"] == first_selected:
					prompt = tr("INV_FIRST_SELECTED") % item["title"]
	cursor = clampi(cursor, 0, maxi(0, entries.size() - 1))
	if entries.is_empty() and prompt.is_empty():
		prompt = tr("INV_EMPTY_EVIDENCE")
	if mode in ["compare", "graves_compare", "challenge"] and entries.is_empty():
		prompt += "\n" + tr("INV_NO_ITEMS")
	body.text = (tr(message_key) + "\n" if not message_key.is_empty() else prompt + "\n" if not prompt.is_empty() else "")
	if not entries.is_empty():
		body.text += entries[cursor]["detail"]
	for index: int in choices.size():
		var row: int = int(cursor / 4) * 4 + index
		choices[index].visible = row < entries.size()
		if choices[index].visible:
			choices[index].text = ("▶ " if row == cursor else "   ") + entries[row]["title"]
			choices[index].modulate = Color.WHITE
	if entries.size() > 4:
		heading.text += " %d/%d" % [int(cursor / 4) + 1, ceili(entries.size() / 4.0)]
	feedback.text = tr("INV_CHALLENGE_RETRY") if wrong_attempts >= 2 else ""
	body.scroll_to_line(0)

func handle_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		if mode == "handover":
			GameSession.cancel_original_handover(handover_preview.get("token", ""))
		if not first_selected.is_empty():
			first_selected = ""
			cursor = _first_cursor
			message_key = ""
			refresh()
		elif mode != "journal" and activity == "@journal":
			mode = "journal"
			cursor = _tab_focus.get(tab, 0)
			message_key = ""
			refresh()
		else: close_requested.emit()
	elif mode == "journal" and (event.is_action_pressed("tab_next") or event.is_action_pressed("tab_previous")):
		_tab_focus[tab] = cursor
		# Keep future page definitions, but cycle only through usable pages.
		var page_count := 2 if onboarding else 4 if GameSession.state.world_flags.get("FACT_W8_ACTIVE", false) else 3
		tab = posmod(tab + (1 if event.is_action_pressed("tab_next") else -1), page_count)
		cursor = _tab_focus.get(tab, 0)
		message_key = ""
		refresh()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
		if not entries.is_empty():
			cursor = posmod(cursor + (1 if event.is_action_pressed("move_down") else -1), entries.size())
			message_key = ""
			refresh()
	elif event.is_action_pressed("confirm"):
		_confirm()
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		body.get_v_scroll_bar().value += 56 if event.physical_keycode == KEY_PAGEDOWN else -56

func _confirm() -> void:
	if entries.is_empty(): return
	var selected: String = entries[cursor]["id"]
	if mode == "handover":
		if selected == "cancel":
			GameSession.cancel_original_handover(handover_preview.get("token", ""))
			close_requested.emit()
			return
		var result: Dictionary = GameSession.confirm_original_handover(handover_preview.get("token", ""))
		message_key = result["feedback_key"]
		handover_preview = {"error": ERR_ALREADY_EXISTS, "feedback_key": message_key}
		cursor = 0
		refresh()
		return
	if mode == "journal":
		if tab != 1: return
		var inquiry_id := "INQ_W8_GRAVES" if selected in ["EV_GRAVE_TAG_03", "EV_BURIAL_PAGE_01"] else "INQ_INDEX"
		var comparison: Dictionary = ContentDB.inquiry_view(inquiry_id, GameSession.state)
		if not selected in comparison.get("candidates", []):
			message_key = "INV_COMPARE_WRONG"
			refresh()
			return
		_tab_focus[tab] = cursor
		mode = "graves_compare" if inquiry_id == "INQ_W8_GRAVES" else "compare"
		first_selected = selected
		_first_cursor = 0
		cursor = 0
		message_key = ""
		refresh()
		return
	if mode in ["compare", "graves_compare"] and first_selected.is_empty():
		first_selected = selected
		_first_cursor = cursor
		cursor = 0
		message_key = ""
		refresh()
		return
	var identifier := "INQ_BOATMAN" if mode == "challenge" else "INQ_W8_GRAVES" if mode == "graves_compare" else "INQ_INDEX"
	var result: Dictionary = GameSession.resolve_inquiry(identifier, [selected] if mode == "challenge" else [first_selected, selected])
	message_key = result["feedback_key"]
	if result.has("saved") and not result["saved"]: message_key = "W8_PROGRESS_SAVE_FAILED"
	if result["error"] == ERR_INVALID_PARAMETER:
		wrong_attempts += 1
	refresh()
