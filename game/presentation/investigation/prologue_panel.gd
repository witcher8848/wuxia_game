extends "res://game/presentation/investigation/dialogue_panel.gd"
## Linear graybox staging; the final choice selects guidance, not a locked route.
signal departed(lead: String)
var page := 0
var journal_seen := false
var skip_pending := false
var _skip_return_cursor := 0
const PAGES := ["INTRO_FATHER", "INTRO_EXECUTION", "INTRO_ESCAPE", "INTRO_CONFLICT", "INTRO_REASON", "INTRO_INDEX", "INTRO_ROUTE"]

func _ready() -> void:
	_build_layout()
	position = Vector2(12, 8)
	size = Vector2(616, 344)
	get_child(0).custom_minimum_size.y = 342
	body.position.y = 112
	body.size.y = 126
	for index: int in choices.size(): choices[index].position.y = 242 + index * 26
	feedback.position.y = 294
	feedback.size.y = 20
	hint.position.y = 318
	refresh()

func refresh() -> void:
	heading.text = tr("INTRO_TITLE") + " · %d/7" % (page + 1)
	body.text = tr(PAGES[page]).replace("\\n", "\n")
	hint.text = tr("INTRO_KEYS")
	if skip_pending:
		heading.text = tr("INTRO_SKIP_TITLE")
		body.text = tr("INTRO_SKIP_SUMMARY")
		for index: int in choices.size():
			choices[index].visible = index < 2
			if index < 2: choices[index].text = ("▶ " if index == cursor else "   ") + tr("INTRO_SKIP_CONFIRM" if index == 0 else "INTRO_SKIP_CANCEL")
		return
	var labels: Array = ["INTRO_NEXT", "INTRO_PREVIOUS"]
	if page == 0: labels = ["INTRO_CALL", "INTRO_WATCH"]
	if page == 5: labels = ["INTRO_JOURNAL", "INTRO_CHOOSE_ROUTE"] if journal_seen else ["INTRO_JOURNAL", "INTRO_PREVIOUS"]
	if page == 6: labels = ["INTRO_HOME", "INTRO_DOCK"]
	for index: int in choices.size():
		choices[index].visible = index < 2
		if index < 2: choices[index].text = ("▶ " if index == cursor else "   ") + tr(labels[index])
	queue_redraw()

func go_to(_identifier: String) -> void:
	refresh()

func _draw() -> void:
	# Deliberately modest silhouettes, not a replacement for future formal art.
	draw_rect(Rect2(12, 40, 590, 62), Color("#303a43"))
	if page < 2:
		draw_rect(Rect2(222, 79, 148, 12), Color("#654d45"))
		_person(Vector2(290, 72), Color("#b9ac90"))
		_person(Vector2(332, 69), Color("#725950"))
		_person(Vector2(134, 84), Color("#84aab3"))
	elif page == 2:
		for x: int in [130, 245, 425]: draw_rect(Rect2(x, 42, 35, 58), Color("#555b5e"))
		_person(Vector2(298, 80), Color("#84aab3"))
		_person(Vector2(348, 76), Color("#bc9575"))
	else:
		for x: int in [80, 514]: draw_rect(Rect2(x, 42, 14, 58), Color("#66534a"))
		draw_rect(Rect2(279, 56, 54, 29), Color("#66534a"))
		_person(Vector2(238, 81), Color("#84aab3"))
		_person(Vector2(365, 81), Color("#bc9575"))

func _person(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at - Vector2(5, 21), Vector2(10, 10)), color)
	draw_rect(Rect2(at - Vector2(7, 10), Vector2(14, 17)), color)

func handle_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		# Repeat is safe only across narration; never confirm a route or evidence.
		if not skip_pending and page < 5: _advance_narration()
		else: feedback.text = tr("INV_FASTREAD_READY")
		return
	if event.is_echo(): return
	if skip_pending:
		if event.is_action_pressed("cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB):
			_cancel_skip()
		elif event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
			cursor = 1 - cursor
			refresh()
		elif event.is_action_pressed("confirm"):
			if cursor == 1: _cancel_skip()
			else:
				var result: Dictionary = GameSession.apply_investigation_step("STEP_RECEIVE_INDEX")
				if result["error"] not in [OK, ERR_ALREADY_EXISTS]:
					feedback.text = tr("INV_COMMAND_FAILED")
					return
				skip_pending = false
				page = 6
				cursor = 0
				feedback.text = ""
				refresh()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
		_skip_return_cursor = cursor
		skip_pending = true
		cursor = 1 # Cancel by default; skipping never happens on a stray confirm.
		refresh()
		return
	if event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
		cursor = 1 - cursor
		refresh()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
		feedback.text = tr("INTRO_NO_SKIP")
	elif event.is_action_pressed("open_codex") and page == 5:
		_show_journal()
	elif event.is_action_pressed("confirm"):
		feedback.text = ""
		if page == 6:
			departed.emit("home" if cursor == 0 else "dock")
			return
		if page == 5 and cursor == 0:
			_show_journal()
			return
		if page > 0 and cursor == 1 and not (page == 5 and journal_seen): page -= 1
		else: page += 1
		if page == 5:
			var result: Dictionary = GameSession.apply_investigation_step("STEP_RECEIVE_INDEX")
			if result["error"] not in [OK, ERR_ALREADY_EXISTS]:
				page = 4
				feedback.text = tr("INV_COMMAND_FAILED")
		cursor = 0
		body.scroll_to_line(0)
		refresh()
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
		body.get_v_scroll_bar().value += 56 if event.physical_keycode == KEY_PAGEDOWN else -56

func _show_journal() -> void:
	journal_seen = true
	activity_requested.emit("@journal")

func _cancel_skip() -> void:
	skip_pending = false
	cursor = _skip_return_cursor
	feedback.text = ""
	refresh()

func _advance_narration() -> void:
	page += 1
	if page == 5:
		var result: Dictionary = GameSession.apply_investigation_step("STEP_RECEIVE_INDEX")
		if result["error"] not in [OK, ERR_ALREADY_EXISTS]:
			page = 4
			feedback.text = tr("INV_COMMAND_FAILED")
	cursor = 0
	body.scroll_to_line(0)
	refresh()
