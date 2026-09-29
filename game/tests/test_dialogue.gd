extends SceneTree
const Catalog = preload("res://game/domain/investigation/dialogue_catalog.gd")
const Rules = preload("res://game/domain/investigation/investigation_rules.gd")
const CONTENT = preload("res://game/core/services/content_db.gd")
const TARGETS := ["DOC_HOME_NOTE", "NPC_DOCK_WORKER", "DOC_STREET_NOTICE"]
var checks := 0
var failures: Array[String] = []
var main: Node
var session: Node
var content: Node
var app: Node
var captures := false
var source: Dictionary
var rules: InvestigationRules
var keys: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("DIALOGUE_FAIL ", label)

func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	app = root.get_node("App")
	captures = "--capture-dialogue" in OS.get_cmdline_user_args()
	source = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/dialogue/investigation.json"))
	rules = Rules.new()
	check(rules.configure(content.get_investigation_definitions()).is_empty(), "real investigation registry")
	keys = content.dialogue_text_keys()
	_definitions()
	_services()
	await _ui()
	print("DIALOGUE: %d checks, %d failures (scripted input; not human playtest)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _definitions() -> void:
	var catalog := Catalog.new()
	check(catalog.configure(source, rules, keys, TARGETS).is_empty(), "real bilingual graph loads")
	check(keys.has("D_START_TEXT") and keys.has("EV_INDEX_01_TITLE"), "both locale keys loaded")
	var file := FileAccess.open("res://game/content/localization/investigation.csv", FileAccess.READ)
	check(file.get_csv_line() == PackedStringArray(["keys", "zh_CN", "en"]), "exact bilingual CSV header")
	var seen: Dictionary = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		check(row.size() == 3 and not seen.has(row[0]), "CSV unique key and column count")
		if row.size() == 3:
			check(keys.has(row[0]) and not row[1].strip_edges().is_empty() and not row[2].strip_edges().is_empty(), "CSV key exists in both imported locales")
			seen[row[0]] = true
	file.close()
	var mutations: Array[Dictionary] = []
	for bad_node: Variant in [null, 7, {}, {"id": "bad space"}]:
		var bad := source.duplicate(true)
		bad["nodes"].append(bad_node)
		mutations.append(bad)
	var bad := source.duplicate(true)
	bad["nodes"].append(bad["nodes"][0])
	mutations.append(bad)
	for field: String in ["speaker_key", "text_key"]:
		bad = source.duplicate(true)
		bad["nodes"][0][field] = "MISSING_KEY"
		mutations.append(bad)
	for field: String in ["command", "next", "text_key"]:
		bad = source.duplicate(true)
		bad["nodes"][0]["choices"][0][field] = "UNKNOWN"
		mutations.append(bad)
	for choices: Variant in [null, [], [source["nodes"][0]["choices"][0]], source["nodes"][0]["choices"] + source["nodes"][0]["choices"]]:
		bad = source.duplicate(true)
		bad["nodes"][0]["choices"] = choices
		mutations.append(bad)
	for condition: Variant in [null, [{"op":"eval","id":"FACT_WEST_GRAVES"}], [{"op":"fact_is","id":"FACT_WEST_GRAVES","value":"true"}], [{"op":"quest_is","id":"QUEST_UNKNOWN","value":"active"}]]:
		bad = source.duplicate(true)
		bad["nodes"][0]["choices"][0]["requires"] = condition
		mutations.append(bad)
	bad = source.duplicate(true)
	bad["nodes"][0]["choices"][0]["script"] = "arbitrary/path"
	mutations.append(bad)
	bad = source.duplicate(true)
	bad["nodes"][0]["choices"][1]["id"] = bad["nodes"][0]["choices"][0]["id"]
	mutations.append(bad)
	for routes: Variant in [null, [], [{"node":"MISSING","requires":[]}], [{"node":"D_START","requires":[]},{"node":"D_HOME","requires":[]}], [{"node":"D_HOME","requires":[{"op":"fact_is","id":"FACT_WEST_GRAVES","value":true}]}]]:
		bad = source.duplicate(true)
		bad["entries"]["DOC_HOME_NOTE"] = routes
		mutations.append(bad)
	bad = source.duplicate(true)
	bad["entries"]["NPC_UNKNOWN"] = [{"node":"D_START","requires":[]}]
	mutations.append(bad)
	bad = source.duplicate(true)
	var orphan: Dictionary = bad["nodes"][0].duplicate(true)
	orphan["id"] = "D_UNREACHABLE"
	bad["nodes"].append(orphan)
	mutations.append(bad)
	for mutation: Dictionary in mutations:
		check(not catalog.configure(mutation, rules, keys, TARGETS).is_empty(), "invalid graph rejected")
		check(catalog.definitions() == source, "failed graph reload is atomic")
	var copy := catalog.definitions()
	copy.clear()
	check(catalog.definitions() == source, "definition access cannot mutate registry")
	var missing_locale := keys.duplicate()
	missing_locale.erase("D_START_TEXT")
	check(not catalog.configure(source, rules, missing_locale, TARGETS).is_empty(), "missing either locale blocks graph")
	var registry := CONTENT.new()
	check(registry.reload_content() == OK, "new ContentDB loads all registries")
	var bootstrap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTENT.BOOTSTRAP_PATH))
	check(registry.load_definitions(bootstrap, null, null, bad) == ERR_INVALID_DATA, "ContentDB rejects broken graph")
	check(registry.get_dialogue_definitions() == source and registry.get_investigation_definitions() == rules.definitions() and registry.has_spawn("SCENE_TOWN_STREET", "SPAWN_START"), "all ContentDB registries preserved")
	registry.free()

func _services() -> void:
	session.start_new_game()
	var before: Dictionary = session.state.to_dict()
	check(content.dialogue_entry("DOC_HOME_NOTE", session.state) == "D_START", "empty old save routes to intro")
	for index: int in 3:
		var view: Dictionary = content.dialogue_view("D_START", session.state)
		check(view["choices"][0]["enabled"], "receive option available")
		view.clear()
	check(session.state.to_dict() == before, "entry and choice inspection are read-only")
	check(session.choose_dialogue("D_START", "bogus")["error"] != OK, "unknown choice rejected")
	check(session.choose_dialogue("D_HOME", "read")["error"] != OK, "missing evidence cannot be read via command")
	check(session.state.to_dict() == before, "invalid commands have no effects")
	check(session.choose_dialogue("D_START", "receive")["error"] == OK, "dialogue submits registered command")
	check(content.dialogue_entry("NPC_DOCK_WORKER", session.state) == "D_ACCEPT", "both entrances share quest")
	before = session.state.to_dict()
	check(session.choose_dialogue("D_START", "receive")["error"] != OK and session.state.to_dict() == before, "stale repeated choice grants no second reward")
	check(session.choose_dialogue("D_ACCEPT", "accept")["error"] == OK, "accept quest command")
	check(content.dialogue_entry("DOC_HOME_NOTE", session.state) == "D_HOME", "active quest routes home")
	check(content.dialogue_entry("NPC_DOCK_WORKER", session.state) == "D_DOCK", "active quest routes dock")
	check(session.choose_dialogue("D_HOME", "inspect")["error"] == OK, "acquire blank record via dialogue")
	before = session.state.to_dict()
	check(session.choose_dialogue("D_HOME", "inspect")["error"] != OK and session.state.to_dict() == before, "duplicate acquisition fails atomically")
	check(session.choose_dialogue("D_HOME", "read")["error"] == OK and session.state.to_dict() == before, "read known evidence is free")
	check(session.apply_investigation_step("STEP_COMPARE_INDEX_BLANK")["error"] == OK, "existing comparison command")
	check(session.apply_investigation_step("STEP_HAND_OVER_BLANK")["error"] == OK, "existing handover command")
	before = session.state.to_dict()
	check(session.choose_dialogue("D_HOME", "inspect")["error"] != OK and session.state.to_dict() == before, "revisiting cannot reclaim transferred original")
	check(content.dialogue_view("D_HOME", session.state)["choices"][1]["enabled"], "knowledge remains readable without original")

func _ui() -> void:
	TranslationServer.set_locale("zh_CN")
	var saves: Node = root.get_node("SaveService")
	var prior_test_root: String = saves.test_root
	saves.test_root = "user://tests/dialogue_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	main._start_game()
	await _frames()
	await _open_home()
	var panel: Control = main.reading_panel
	if not is_instance_valid(panel):
		check(false, "dialogue panel created")
		saves.test_root = prior_test_root
		return
	check(panel.visible and panel.node_id == "D_START", "real exploration target opens graph through keyboard")
	var before: Dictionary = session.state.to_dict()
	var player: CharacterBody2D = main.get_node("SceneHost").get_child(0).player
	var stopped := player.position
	_key(KEY_D, true)
	await _frames(6)
	check(player.position == stopped, "dialogue locks movement")
	_key(KEY_D, false)
	await _tap(KEY_F5)
	check(session.state.to_dict() == before, "reading and unrelated hotkey do not grant evidence")
	check(not FileAccess.file_exists(saves.slot_path("quick")), "dialogue blocks quick save in isolated directory")
	_key(KEY_E, true, true)
	await _frames()
	_key(KEY_E, false)
	check(panel.node_id == "D_START" and session.state.to_dict() == before, "echo cannot confirm")
	await _capture("dialogue_intro")
	await _tap(KEY_ESCAPE)
	check(not panel.visible and app.current_context() == &"exploration" and not main.menu.visible, "cancel closes without pause input-through")
	check(session.state.to_dict() == before, "cancel grants no reward")
	await _tap(KEY_E)
	panel = main.reading_panel
	await _tap(KEY_S)
	await _tap(KEY_ENTER)
	check(panel.node_id == "D_CONTEXT" and session.state.to_dict() == before, "keyboard branch has no command side effects")
	await _tap(KEY_E)
	check(panel.node_id == "D_START" and panel.cursor == 1, "return remembers previous choice")
	await _tap(KEY_W)
	await _tap(KEY_E)
	check(panel.node_id == "D_ACCEPT" and session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "available", "one press only receives index")
	await _tap(KEY_E)
	check(panel.node_id == "D_HOME" and session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "active", "second press accepts quest")
	await _tap(KEY_S)
	before = session.state.to_dict()
	await _tap(KEY_E)
	check(panel.node_id == "D_HOME" and session.state.to_dict() == before and not panel.feedback.text.is_empty(), "disabled option inspectable but not executable")
	await _tap(KEY_W)
	await _tap(KEY_E)
	check(panel.node_id == "D_BLANK" and session.state.evidence_states.has("EV_BLANK_DEATH_01"), "keyboard acquires real record")
	await _capture("dialogue_record")
	await _tap(KEY_E)
	check(panel.node_id == "D_HOME" and not panel.view["choices"][0]["enabled"] and panel.view["choices"][1]["enabled"], "post-command options refresh")
	await _capture("dialogue_recorded")
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for node: Dictionary in source["nodes"]:
			panel.go_to(node["id"])
			await _frames()
			check(root.get_visible_rect().encloses(panel.get_global_rect()), "panel fits 640x360 " + locale)
			check(panel.heading.get_global_rect().end.y <= panel.body.get_global_rect().position.y, "speaker and body do not overlap")
			check(panel.body.get_global_rect().end.y <= panel.choices[0].get_global_rect().position.y, "scrollable text does not cover options")
			for label: Label in panel.choices:
				if label.visible:
					check(panel.get_global_rect().encloses(label.get_global_rect()) and label.get_line_count() == 1 and label.get_minimum_size().x <= label.size.x, "choice fits one readable row")
			check(panel.feedback.get_global_rect().end.y <= panel.hint.get_global_rect().position.y, "feedback and controls separate")
			check(panel.hint.text == TranslationServer.translate("INV_DIALOGUE_KEYS"), "controls refresh with locale")
			for option: Dictionary in panel.view["choices"]:
				check(panel.get_theme_font("font").get_string_size(TranslationServer.translate(option["text_key"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 24 <= 588, "complete option text fits without ellipsis")
		await _capture("dialogue_" + locale)
	panel.body.text = "这是用于检查长文滚动与中文边界的测试文本。".repeat(40)
	await _frames()
	var scroll_before: float = panel.body.get_v_scroll_bar().value
	await _tap(KEY_PAGEDOWN)
	check(panel.body.get_v_scroll_bar().value > scroll_before, "long Chinese text scrolls using keyboard")
	check(panel.body.get_global_rect().end.y <= panel.choices[0].get_global_rect().position.y, "long text stays within scroll area")
	await _tap(KEY_PAGEUP)
	check(is_equal_approx(panel.body.get_v_scroll_bar().value, scroll_before), "scroll can return without selecting option")
	TranslationServer.set_locale("zh_CN")
	main._close_reading()
	root.remove_child(main)
	main.queue_free()
	await _frames()
	saves.test_root = prior_test_root

func _open_home() -> void:
	check(session.enter_region("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN") == OK, "enter real home registry")
	check(main._enter_yard() == OK, "instantiate real region")
	await _frames()
	var region: Node = main.get_node("SceneHost").get_child(0)
	# Explicit placement is a UI integration fixture, not a physical walkthrough.
	region.player.position = Vector2(448, 392)
	region.player.facing = "up"
	await _frames()
	await _tap(KEY_E)

func _key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _tap(code: Key) -> void:
	_key(code, true)
	await _frames()
	_key(code, false)
	await _frames()

func _frames(count := 2) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

func _capture(label: String) -> void:
	if not captures:
		return
	await RenderingServer.frame_post_draw
	var path := "res://docs/week4_evidence/" + label + ".png"
	DirAccess.make_dir_recursive_absolute("res://docs/week4_evidence")
	check(root.get_texture().get_image().save_png(path) == OK, "actual rendered capture " + label)
