extends SceneTree
const Catalog = preload("res://game/domain/investigation/dialogue_catalog.gd")
const Rules = preload("res://game/domain/investigation/investigation_rules.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var main: Node
var captures := false

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("HANDOVER_FAIL ", label)

func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	captures = "--capture-handover" in OS.get_cmdline_user_args()
	_domain()
	await _ui()
	print("HANDOVER: %d checks, %d failures (scripted preview/confirm; not human playtest)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _prepare() -> void:
	session.start_new_game()
	for step: String in ["STEP_RECEIVE_INDEX", "STEP_ACCEPT_SEARCH", "STEP_INSPECT_BLANK", "STEP_COMPARE_INDEX_BLANK"]:
		check(session.apply_investigation_step(step)["error"] == OK, "real setup " + step)
	check(session.mark_inspected("DOC_STREET_NOTICE") == OK, "registered handover location inspected")

func _domain() -> void:
	session.start_new_game()
	var before: Dictionary = session.state.to_dict()
	check(session.preview_original_handover()["error"] != OK and session.state.to_dict() == before, "no original cannot preview")
	check(session.confirm_original_handover("fabricated")["error"] != OK and session.state.to_dict() == before, "cannot confirm without issued preview")
	_prepare()
	before = session.state.to_dict()
	var preview: Dictionary = session.preview_original_handover()
	check(preview["error"] == OK and preview["recipient_id"] == "FACTION_INSPECTOR" and preview["evidence_id"] == "EV_BLANK_DEATH_01", "preview identifies original and recipient")
	check(session.state.to_dict() == before and not preview.has("state"), "preview neither transfers nor exposes candidate state")
	session.cancel_original_handover(preview["token"])
	check(session.confirm_original_handover(preview["token"])["error"] != OK and session.state.to_dict() == before, "cancel invalidates issued token without transfer")
	preview = session.preview_original_handover()
	var newer: Dictionary = session.preview_original_handover()
	check(session.confirm_original_handover(preview["token"])["error"] != OK, "second preview supersedes first")
	check(session.confirm_original_handover(newer["token"])["error"] == OK, "current preview transfers once")
	check(session.state.evidence_states["EV_BLANK_DEATH_01"]["holder_id"] == "FACTION_INSPECTOR" and session.state.evidence_states["EV_BLANK_DEATH_01"]["knowledge_state"] == "fact", "ownership changes while verified knowledge remains")
	for field: String in ["time_state", "relationships", "quest_states", "player_state", "route_id"]:
		check(session.state.to_dict()[field] == before[field], "handover leaves unrelated state unchanged " + field)
	before = session.state.to_dict()
	check(session.confirm_original_handover(newer["token"])["error"] != OK and session.state.to_dict() == before, "double confirm atomic and once-only")
	check(session.preview_original_handover()["error"] != OK, "cannot preview original no longer held")
	_prepare()
	preview = session.preview_original_handover()
	check(session.update_player_position(Vector2(520,384)) == OK, "simulate intervening state update")
	before = session.state.to_dict()
	check(session.confirm_original_handover(preview["token"])["error"] == ERR_BUSY and session.state.to_dict() == before, "changed snapshot makes old confirmation stale")
	preview = session.preview_original_handover()
	check(session.replace_state(GameState.from_dict(session.state.to_dict())) == OK, "replace from independent loaded copy")
	check(session.confirm_original_handover(preview["token"])["error"] != OK, "load even identical state invalidates transient token")
	preview = session.preview_original_handover()
	session.start_new_game()
	check(session.confirm_original_handover(preview["token"])["error"] != OK, "new game cannot use old route token")
	_prepare()
	check(session.enter_region("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN") == OK, "leave town")
	check(session.preview_original_handover()["error"] != OK, "original cannot be remotely transferred from home")
	var rules := Rules.new()
	check(rules.configure(content.get_investigation_definitions()).is_empty(), "canonical rules")
	var graph: Dictionary = content.get_dialogue_definitions()
	graph["nodes"][0]["choices"][0]["command"] = "STEP_HAND_OVER_BLANK"
	check(not Catalog.new().configure(graph, rules, content.dialogue_text_keys(), ["DOC_STREET_NOTICE", "DOC_HOME_NOTE", "NPC_DOCK_WORKER"]).is_empty(), "data authors cannot bypass confirmation with a direct transfer choice")

func _ui() -> void:
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	_prepare()
	check(main._enter_yard() == OK, "real town scene")
	await _frames()
	var region: Node = main.get_node("SceneHost").get_child(0)
	region.player.position = Vector2(384,396)
	region.player.facing = "up"
	await _frames()
	await _tap(KEY_E)
	check(main.reading_panel.node_id == "D_NOTICE", "real notice interaction")
	var before: Dictionary = session.state.to_dict()
	await _tap(KEY_E)
	check(main.activity_panel.mode == "handover" and main.activity_panel.cursor == 1, "first confirmation opens preview defaulting to keep")
	check(session.state.to_dict() == before, "opening preview does not transfer")
	await _capture("handover_preview")
	await _tap(KEY_E)
	check(main.reading_panel.visible and session.state.to_dict() == before, "default keep returns without transfer")
	await _tap(KEY_E)
	await _tap(KEY_ESCAPE)
	check(main.reading_panel.visible and session.state.to_dict() == before, "Escape cancels transfer")
	await _tap(KEY_E)
	await _tap(KEY_W)
	await _tap(KEY_E)
	check(session.state.evidence_states["EV_BLANK_DEATH_01"]["holder_id"] == "FACTION_INSPECTOR", "explicit second confirmation transfers original")
	await _capture("handover_complete")
	await _tap(KEY_E)
	check(not main.reading_panel.view["choices"][0]["enabled"], "notice refresh disables original no longer held")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_J)
	await _tap(KEY_R)
	await _tap(KEY_S)
	check(main.activity_panel.body.text.contains("清籍使团") and main.activity_panel.body.text.contains("已核实"), "journal shows knowledge retained under new custody")
	await _capture("handover_journal")
	main._close_activity()
	root.remove_child(main)
	main.queue_free()
	await _frames()

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
