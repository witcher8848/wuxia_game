extends SceneTree
const Inquiry = preload("res://game/domain/investigation/inquiry_rules.gd")
const Rules = preload("res://game/domain/investigation/investigation_rules.gd")
const Journal = preload("res://game/presentation/investigation/journal_view.gd")
const Content = preload("res://game/core/services/content_db.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var app: Node
var main: Node
var data: Dictionary
var rules: InvestigationRules
var inquiry: InquiryRules
var captures := false

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("INQUIRY_FAIL ", label)

func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	app = root.get_node("App")
	captures = "--capture-inquiry" in OS.get_cmdline_user_args()
	data = content.get_investigation_definitions()
	rules = Rules.new()
	check(rules.configure(data).is_empty(), "canonical rules")
	inquiry = Inquiry.new()
	check(inquiry.configure(data["inquiries"], rules, content.dialogue_text_keys()).is_empty(), "canonical inquiries")
	_definitions()
	_domain()
	await _ui()
	print("INQUIRY: %d checks, %d failures (scripted UI and domain; no human-play claim)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _definitions() -> void:
	var mutations: Array = [null, {}, [null], [{}]]
	var bad: Array = data["inquiries"].duplicate(true)
	bad.append(bad[0])
	mutations.append(bad)
	for field: String in ["id", "kind", "claim_id", "proof_id", "step_id", "prompt_key", "wrong_key", "title_key"]:
		bad = data["inquiries"].duplicate(true)
		bad[0][field] = "bad unknown value"
		mutations.append(bad)
	for candidates: Variant in [null, [], ["EV_INDEX_01"], ["EV_INDEX_01", "EV_INDEX_01"], ["EV_INDEX_01", "EV_MISSING"], [[], "EV_INDEX_01"]]:
		bad = data["inquiries"].duplicate(true)
		bad[0]["candidates"] = candidates
		mutations.append(bad)
	for pair: Variant in [null, [], ["EV_INDEX_01"], ["EV_INDEX_01", "EV_INDEX_01"], ["EV_INDEX_01", "EV_MISSING"], [[], "EV_INDEX_01"]]:
		bad = data["inquiries"].duplicate(true)
		bad[1]["pair"] = pair
		mutations.append(bad)
	bad = data["inquiries"].duplicate(true)
	bad[0]["script"] = "arbitrary"
	mutations.append(bad)
	var state := GameState.new()
	var before := inquiry.view("INQ_INDEX", state)
	for mutation: Variant in mutations:
		check(not inquiry.configure(mutation, rules, content.dialogue_text_keys()).is_empty(), "bad inquiry rejected")
		check(inquiry.view("INQ_INDEX", state) == before, "failed reload retains inquiry registry")
	var registry := Content.new()
	check(registry.reload_content() == OK, "registry loads")
	var bootstrap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.BOOTSTRAP_PATH))
	var invalid := data.duplicate(true)
	invalid["inquiries"][0]["proof_id"] = "EV_UNKNOWN"
	check(registry.load_definitions(bootstrap, null, invalid) == ERR_INVALID_DATA, "ContentDB rejects inquiry reference")
	check(registry.get_investigation_definitions() == data and not registry.get_dialogue_definitions().is_empty(), "transaction retains all content")
	registry.free()

func _begin() -> void:
	session.start_new_game()
	for step: String in ["STEP_RECEIVE_INDEX", "STEP_ACCEPT_SEARCH"]:
		check(session.apply_investigation_step(step)["error"] == OK, "setup via real command " + step)

func _domain() -> void:
	_begin()
	var before: Dictionary = session.state.to_dict()
	for selected: Array in [[], ["EV_FERRY_TOKEN_01"], ["EV_UNKNOWN"], [null], ["EV_INDEX_01", "EV_FERRY_TOKEN_01"]]:
		check(session.resolve_inquiry("INQ_BOATMAN", selected)["error"] != OK, "missing proof/claim or invalid selection rejected")
		check(session.state.to_dict() == before, "invalid challenge read-only")
	check(session.apply_investigation_step("STEP_RECORD_BOATMAN")["error"] == OK, "record testimony")
	before = session.state.to_dict()
	var view: Dictionary = content.inquiry_view("INQ_BOATMAN", session.state)
	check(view["candidates"].size() == 2 and not view.has("proof_id") and not view.has("step_id"), "view lists relevant known clues without answer marker")
	view["candidates"].clear()
	check(content.inquiry_view("INQ_BOATMAN", session.state)["candidates"].size() == 2, "view owns copy")
	for attempt: int in 3:
		check(session.resolve_inquiry("INQ_BOATMAN", ["EV_INDEX_01"])["feedback_key"] == "INV_CHALLENGE_WRONG", "wrong proof explained")
		check(session.state.to_dict() == before, "repeated wrong proof costs no time/trust and creates no facts")
	check(session.apply_investigation_step("STEP_TAKE_FERRY_TOKEN")["error"] == OK, "acquire token")
	var prepared: Dictionary = content.prepare_inquiry(session.state, "INQ_BOATMAN", ["EV_FERRY_TOKEN_01"])
	check(prepared["error"] == OK and not session.state.world_flags.get("FACT_FERRY_ROUTE", false), "preview candidate does not mutate live state")
	check(session.resolve_inquiry("INQ_BOATMAN", ["EV_FERRY_TOKEN_01"])["error"] == OK, "token disproves claim")
	check(session.state.world_flags.get("FACT_WEST_GRAVES", false) and session.state.world_flags.get("FACT_FERRY_ROUTE", false) and not session.state.world_flags.get("FACT_YAMEN_FORMATION", false), "dock route reaches same destination with distinct advantage")
	check(session.state.evidence_states["CL_BOATMAN_01"]["knowledge_state"] == "doubt", "false statement not mislabeled verified")
	before = session.state.to_dict()
	check(session.resolve_inquiry("INQ_BOATMAN", ["EV_FERRY_TOKEN_01"])["error"] == ERR_ALREADY_EXISTS and session.state.to_dict() == before, "challenge result once only")
	for selected: Array in [["EV_INDEX_01", "EV_INDEX_01"], ["EV_INDEX_01", "EV_BLANK_DEATH_01"], ["EV_INDEX_01", "EV_FERRY_TOKEN_01"]]:
		check(session.resolve_inquiry("INQ_INDEX", selected)["error"] != OK, "same/missing/wrong pair rejected")
		check(session.state.to_dict() == before, "bad pair is atomic")
	check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] == OK, "can supplement other entrance")
	check(session.resolve_inquiry("INQ_INDEX", ["EV_BLANK_DEATH_01", "EV_INDEX_01"])["error"] == OK, "reverse-order correct pair works")
	check(session.state.world_flags["FACT_YAMEN_FORMATION"] and session.state.world_flags["FACT_FERRY_ROUTE"], "supplement retains both advantages")
	check(session.apply_investigation_step("STEP_HAND_OVER_BLANK")["error"] == OK, "transfer original with domain command")
	before = session.state.to_dict()
	var items := Journal.evidence_entries(session.state, data)
	check(items.size() == 4 and items[1]["detail"].contains(TranslationServer.translate("INV_HOLDER_FACTION_INSPECTOR")), "journal preserves knowledge and current ownership")
	var quests := Journal.quest_entries(session.state, data)
	check(quests[0]["detail"].contains(TranslationServer.translate("INV_REWARD_FORMATION")) and quests[0]["detail"].contains(TranslationServer.translate("INV_REWARD_FERRY")), "journal displays actual rewards")
	check(session.state.to_dict() == before, "journal projections are read-only")
	_begin()
	check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] == OK, "home-only preparation")
	check(session.resolve_inquiry("INQ_INDEX", ["EV_INDEX_01", "EV_BLANK_DEATH_01"])["error"] == OK, "home route does not require ferry token")
	check(session.state.world_flags.get("FACT_WEST_GRAVES", false) and not session.state.world_flags.get("FACT_FERRY_ROUTE", false), "both routes independently locate gravekeeper")

func _ui() -> void:
	var saves: Node = root.get_node("SaveService")
	var prior_root: String = saves.test_root
	saves.test_root = "user://tests/inquiry_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	TranslationServer.set_locale("zh_CN")
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	await _frames()
	await _tap(KEY_J)
	check(main.activity_panel.visible and app.current_context() == &"codex", "journal opens from exploration input")
	var before: Dictionary = session.state.to_dict()
	await _tap(KEY_R)
	check(main.activity_panel.entries.is_empty(), "unknown evidence is not leaked")
	await _tap(KEY_R)
	check(main.activity_panel.tab == 0, "only usable journal tabs cycle back to case")
	await _tap(KEY_R)
	check(main.activity_panel.tab == 1, "unimplemented people and routes do not interrupt evidence navigation")
	await _tap(KEY_F5)
	check(not FileAccess.file_exists(saves.slot_path("quick")), "journal blocks quick save in isolated root")
	check(main._save_game() == ERR_UNAVAILABLE, "service-facing UI save method also blocks codex")
	await _tap(KEY_ESCAPE)
	check(session.state.to_dict() == before and app.current_context() == &"exploration" and not main.menu.visible, "journal cancel is free and does not open pause")
	await _open_dock()
	await _tap(KEY_E) # receive
	await _tap(KEY_E) # accept
	await _tap(KEY_E) # ask and record
	check(main.reading_panel.node_id == "D_BOAT", "boatman's statement entered via real dialogue")
	await _choose_dialogue("challenge")
	check(main.activity_panel.mode == "challenge" and not main.reading_panel.visible, "nested challenge owns input")
	before = session.state.to_dict()
	await _tap(KEY_E)
	await _tap(KEY_E)
	check(main.activity_panel.wrong_attempts == 2 and not main.activity_panel.feedback.text.is_empty(), "two wrong proofs explain exit without lock")
	check(session.state.to_dict() == before, "UI wrong proofs have no permanent cost")
	await _capture("inquiry_wrong")
	await _tap(KEY_ESCAPE)
	check(main.reading_panel.visible and main.reading_panel.node_id == "D_BOAT" and main.reading_panel.view["choices"][main.reading_panel.cursor]["id"] == "challenge", "nested cancel restores dialogue focus")
	await _choose_dialogue("token")
	check(main.reading_panel.node_id == "D_TOKEN", "token acquired via dialogue")
	await _choose_dialogue("challenge")
	await _choose_item("EV_FERRY_TOKEN_01")
	await _capture("inquiry_token")
	await _tap(KEY_E)
	check(session.state.world_flags.get("FACT_FERRY_ROUTE", false), "actual UI token challenge commits fact")
	await _capture("inquiry_admission")
	before = session.state.to_dict()
	await _tap(KEY_E)
	check(session.state.to_dict() == before and main.activity_panel.message_key == "INV_ALREADY_RECORDED", "UI repeat cannot duplicate fact")
	await _tap(KEY_ESCAPE)
	check(main.reading_panel.node_id == "D_DOCK_ADMITS", "changed dialogue acknowledges admission")
	await _tap(KEY_ESCAPE)
	await _open_home()
	await _choose_dialogue("inspect")
	await _choose_dialogue("compare")
	check(main.activity_panel.mode == "compare", "home opens comparison")
	before = session.state.to_dict()
	await _choose_item("EV_INDEX_01")
	await _tap(KEY_E)
	check(main.activity_panel.first_selected == "EV_INDEX_01" and session.state.to_dict() == before, "first selection is only a preview")
	await _choose_item("EV_FERRY_TOKEN_01")
	await _tap(KEY_E)
	check(session.state.to_dict() == before, "wrong UI pair creates no facts")
	await _tap(KEY_ESCAPE)
	check(main.activity_panel.first_selected.is_empty() and session.state.to_dict() == before, "cancel clears first selection only")
	await _choose_item("EV_INDEX_01")
	await _tap(KEY_E)
	await _choose_item("EV_BLANK_DEATH_01")
	await _capture("inquiry_compare")
	await _tap(KEY_E)
	check(session.state.world_flags.get("FACT_YAMEN_FORMATION", false), "actual UI comparison grants intelligence")
	await _capture("inquiry_compared")
	await _tap(KEY_ESCAPE) # first selection
	await _tap(KEY_ESCAPE) # nested panel
	await _tap(KEY_ESCAPE) # dialogue
	await _tap(KEY_J)
	await _capture("journal_case")
	await _tap(KEY_R)
	check(main.activity_panel.entries.size() == 4, "journal contains all four actual records")
	await _capture("journal_evidence")
	before = session.state.to_dict()
	await _choose_item("EV_INDEX_01")
	await _tap(KEY_E)
	check(main.activity_panel.mode == "compare" and main.activity_panel.first_selected == "EV_INDEX_01", "journal links directly to chosen comparison")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)
	check(main.activity_panel.mode == "journal" and session.state.to_dict() == before, "cancel journal comparison returns without effects")
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for tab_index: int in 4:
			main.activity_panel.tab = tab_index
			main.activity_panel.refresh()
			await _frames()
			check(root.get_visible_rect().encloses(main.activity_panel.get_global_rect()), "journal fits viewport " + locale)
			check(main.activity_panel.body.get_global_rect().end.y <= main.activity_panel.choices[0].get_global_rect().position.y, "journal details scroll without overlap")
			check(main.activity_panel.hint.get_theme_font("font").get_string_size(main.activity_panel.hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 588, "complete keyboard hints fit")
			for label: Label in main.activity_panel.choices:
				if label.visible:
					check(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= 588, "complete row visible " + locale)
		main.activity_panel.tab = 1
		main.activity_panel.refresh()
		await _capture("journal_" + locale)
	TranslationServer.set_locale("zh_CN")
	main._close_activity()
	root.remove_child(main)
	main.queue_free()
	await _frames()
	saves.test_root = prior_root

func _choose_dialogue(identifier: String) -> void:
	for count: int in 5:
		var panel: Control = main.reading_panel
		if panel.view["choices"][panel.cursor]["id"] == identifier:
			await _tap(KEY_E)
			return
		await _tap(KEY_S)
	check(false, "missing dialogue option " + identifier)

func _choose_item(identifier: String) -> void:
	for count: int in 5:
		var panel: Control = main.activity_panel
		if not panel.entries.is_empty() and panel.entries[panel.cursor]["id"] == identifier: return
		await _tap(KEY_S)
	check(false, "missing inquiry item " + identifier)

func _open_dock() -> void:
	await _open("SCENE_RIVER_DOCK", Vector2(704, 396))

func _open_home() -> void:
	await _open("SCENE_HOME_COURTYARD", Vector2(448, 392))

func _open(scene: String, position: Vector2) -> void:
	check(session.enter_region(scene, "SPAWN_FROM_TOWN") == OK, "registered scene")
	check(main._enter_yard() == OK, "real scene entry")
	await _frames()
	var region: Node = main.get_node("SceneHost").get_child(0)
	# UI fixture placement only; not a physical walkthrough claim.
	region.player.position = position
	region.player.facing = "up"
	await _frames()
	await _tap(KEY_E)

func _tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames()

func _frames() -> void:
	for index: int in 2:
		await physics_frame
		await process_frame

func _capture(label: String) -> void:
	if not captures: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://docs/week4_evidence")
	check(root.get_texture().get_image().save_png("res://docs/week4_evidence/" + label + ".png") == OK, "actual rendered " + label)
