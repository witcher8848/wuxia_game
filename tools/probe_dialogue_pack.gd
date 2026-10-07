extends SceneTree
## External verifier; run with an exported --main-pack, never packaged itself.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("DIALOGUE_PACK_FAIL ", label)

func _run() -> void:
	if not FileAccess.file_exists("res://project.binary") or FileAccess.file_exists("res://project.godot"):
		printerr("DIALOGUE_PACK_FAIL requires exported pack")
		quit(1)
		return
	await process_frame
	var content: Node = root.get_node("ContentDB")
	var session: Node = root.get_node("GameSession")
	check(content.last_error.is_empty(), "packed registry validates")
	check(content.dialogue_text_keys().has("D_START_TEXT"), "both packed locale resources")
	var main: Node = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	await process_frame
	check(session.enter_region("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN") == OK, "packed home spawn")
	check(main._enter_yard() == OK, "packed region creation")
	await _frames()
	var region: Node = main.get_node("SceneHost").get_child(0)
	region.player.position = Vector2(448, 392)
	region.player.facing = "up"
	await _frames()
	await _tap(KEY_E)
	if not is_instance_valid(main.reading_panel):
		check(false, "packed dialogue entry")
	else:
		check(main.reading_panel.node_id == "D_START", "real packed entry")
		await _tap(KEY_E)
		check(main.reading_panel.node_id == "D_ACCEPT", "packed registered receive command")
		await _tap(KEY_E)
		check(main.reading_panel.node_id == "D_HOME", "packed quest activation")
		await _tap(KEY_E)
		check(main.reading_panel.node_id == "D_BLANK", "packed evidence branch")
		check(session.state.evidence_states.has("EV_BLANK_DEATH_01") and session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "active", "authoritative packed evidence and quest")
		await _tap(KEY_S)
		await _tap(KEY_E)
		check(main.activity_panel.mode == "compare", "packed comparison panel")
		await _tap(KEY_E)
		check(main.activity_panel.first_selected == "EV_INDEX_01", "packed first evidence selection")
		await _tap(KEY_E)
		check(session.state.world_flags.get("FACT_YAMEN_FORMATION", false), "packed two-item comparison commits real fact")
		await _tap(KEY_ESCAPE)
		await _tap(KEY_ESCAPE)
		await _tap(KEY_ESCAPE)
		check(root.get_node("App").current_context() == &"exploration" and not main.menu.visible, "packed close without input-through")
		check(session.enter_region("SCENE_TOWN_STREET", "SPAWN_START") == OK and main._enter_yard() == OK, "packed town return")
		await _frames()
		region = main.get_node("SceneHost").get_child(0)
		region.player.position = Vector2(384,396)
		region.player.facing = "up"
		await _frames()
		await _tap(KEY_E)
		check(main.reading_panel.node_id == "D_NOTICE", "packed notice interaction")
		await _tap(KEY_E)
		check(main.activity_panel.mode == "handover" and session.state.evidence_states["EV_BLANK_DEATH_01"]["holder_id"] == "PLAYER", "packed handover preview remains read-only")
		await _tap(KEY_W)
		await _tap(KEY_E)
		check(session.state.evidence_states["EV_BLANK_DEATH_01"]["holder_id"] == "FACTION_INSPECTOR", "packed second confirmation transfers custody")
		await _tap(KEY_ESCAPE)
		await _tap(KEY_ESCAPE)
		await _tap(KEY_J)
		await _tap(KEY_R)
		await _tap(KEY_S)
		check(main.activity_panel.mode == "journal" and main.activity_panel.body.text.contains("清籍使团"), "packed journal retains knowledge with new owner")
	root.remove_child(main)
	main.queue_free()
	await _frames()
	print("DIALOGUE_PACK: %d checks, %d failures (exported pack; scripted placement/input)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

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
