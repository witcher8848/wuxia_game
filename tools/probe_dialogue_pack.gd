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
	main._start_game()
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
		await _tap(KEY_ESCAPE)
		check(root.get_node("App").current_context() == &"exploration" and not main.menu.visible, "packed close without input-through")
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
