extends SceneTree
## Production-scene integration: real input dispatch, real physics, real save files.
## All writes stay inside a per-process fixture; the child process only reads that fixture.

const MAIN_SCENE := "res://game/presentation/main.tscn"
const SELF_SCRIPT := "res://game/tests/test_exploration_flow.gd"
const FIXTURE_PREFIX := "user://tests/exploration_flow_"
const EXPECTED_FILE := "expected_restart.json"
const RECEIPT_FILE := "restart_receipt.json"
const MOVE_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]

var checks: int = 0
var failures: Array[String] = []
var fixture: String = ""
var main: Node
var saves: Node
var session: Node
var content: Node
var app: Node
var interaction_log: Array[String] = []
var restart_pid: int = -1


func _initialize() -> void:
	create_timer(75.0).timeout.connect(_watchdog_timeout)
	_run.call_deferred()


func _watchdog_timeout() -> void:
	if restart_pid > 0 and OS.is_process_running(restart_pid):
		OS.kill(restart_pid)
	printerr("EXPLORATION_FLOW_FAIL bounded integration exceeded 75 seconds")
	quit(124)


func _same_json_data(left: Variant, right: Variant) -> bool:
	# JSON has one number type. Parsed whole numbers are floats, while fresh
	# GameState uses ints; normalize representation, never omit state fields.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("EXPLORATION_FLOW_FAIL ", message)


func _step(frames: int = 1) -> void:
	for _frame in range(frames):
		await physics_frame
		await process_frame


func _key(code: Key, pressed: bool, echoed: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echoed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	await _step()
	_key(code, false)
	await _step()


func _release_keys() -> void:
	for code: Key in MOVE_KEYS:
		_key(code, false)
	_key(KEY_E, false)
	_key(KEY_ESCAPE, false)
	_key(KEY_F5, false)


func _region() -> Node2D:
	if not is_instance_valid(main):
		return null
	var host: Node = main.get_node("SceneHost")
	return host.get_child(0) as Node2D if host.get_child_count() == 1 else null


func _count_players(node: Node) -> int:
	var result := 1 if node is CharacterBody2D else 0
	for child: Node in node.get_children():
		result += _count_players(child)
	return result


func _check_region(expected: String, label: String) -> bool:
	var region: Node2D = _region()
	check(region != null, label + " has exactly one region")
	if region == null:
		return false
	check(region.scene_id == expected and session.state.scene_id == expected, label + " presentation and state agree on region")
	check(_count_players(main.get_node("SceneHost")) == 1, label + " has exactly one player")
	check(is_instance_valid(region.player) and is_instance_valid(region.camera), label + " owns player and camera")
	check(content.is_walkable_position(expected, region.player_position), label + " player is safely inside walkable bounds")
	check(app.current_context() == &"exploration", label + " restores exploration input")
	return true


func _target(identifier: String) -> Dictionary:
	var region: Node2D = _region()
	if region != null:
		for target: Dictionary in region.definition.get("interactions", []):
			if target.get("id", "") == identifier:
				return target.duplicate(true)
	check(false, "fixture has interaction " + identifier)
	return {}


func _observe_region() -> void:
	var region: Node2D = _region()
	if region != null and not region.interaction_requested.is_connected(_record_interaction):
		region.interaction_requested.connect(_record_interaction)


func _record_interaction(target: Dictionary) -> void:
	interaction_log.append(str(target.get("id", "")))


func _place(point: Vector2, facing: String) -> void:
	_release_keys()
	var region: Node2D = _region()
	region.player_position = point
	region.player.facing = facing
	region.player.reset_input()
	await _step(2)


func _approach(identifier: String) -> Dictionary:
	var target: Dictionary = _target(identifier)
	if not target.is_empty():
		await _place(Vector2(target.position[0], target.position[1]) + Vector2(0, 44), "up")
	return target


func _reading_visible() -> bool:
	return is_instance_valid(main.reading_panel) and main.reading_panel.visible


func _settle_transition(label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while main.transitioning and Time.get_ticks_msec() < deadline:
		await _step()
	check(not main.transitioning, label + " transition finishes within five seconds")
	await _step(2)
	return not main.transitioning


func _exit(identifier: String, expected: String, unchanged_time: Dictionary, unchanged_flags: Dictionary) -> void:
	await _approach(identifier)
	_observe_region()
	var previous_count: int = interaction_log.size()
	await _tap(KEY_E)
	check(interaction_log.size() == previous_count + 1, identifier + " emits once through E input")
	check(main.transitioning, identifier + " enters a guarded transition")
	await _settle_transition(identifier)
	_check_region(expected, identifier)
	check(session.state.time_state == unchanged_time, identifier + " does not charge quest time")
	check(session.state.world_flags == unchanged_flags, identifier + " preserves inspected facts")


func _run() -> void:
	await process_frame
	saves = root.get_node("SaveService")
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	app = root.get_node("App")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--reload-fixture="):
			fixture = argument.trim_prefix("--reload-fixture=")
			await _run_restart_child()
			return
	fixture = FIXTURE_PREFIX + "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	saves.test_root = fixture
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await _step(2)
	check(app.current_context() == &"system_menu", "title starts with menu context")
	await _tap(KEY_E)
	check(app.current_context() == &"dialogue" and main.reading_panel.page == 0, "keyboard new game opens prologue")
	# This suite isolates free exploration; onboarding has its own keyboard suite.
	main._close_reading()
	await _step(2)
	if not _check_region("SCENE_TOWN_STREET", "keyboard new game"):
		await _finish()
		return
	_observe_region()
	session.state.time_state = {"day": 3, "slot": 2}
	var free_exploration_time: Dictionary = session.state.time_state.duplicate(true)
	var original_route: String = session.state.route_id
	await _test_interactions()
	var facts: Dictionary = session.state.world_flags.duplicate(true)
	for index in range(5):
		await _exit("EXIT_STREET_HOME", "SCENE_HOME_COURTYARD", free_exploration_time, facts)
		await _exit("EXIT_HOME_STREET", "SCENE_TOWN_STREET", free_exploration_time, facts)
		await _exit("EXIT_STREET_DOCK", "SCENE_RIVER_DOCK", free_exploration_time, facts)
		await _exit("EXIT_DOCK_STREET", "SCENE_TOWN_STREET", free_exploration_time, facts)
		check(session.state.route_id == original_route, "round trip %d retains route identity" % (index + 1))
	await _test_transition_rejection()
	await _exit("EXIT_STREET_HOME", "SCENE_HOME_COURTYARD", free_exploration_time, facts)
	await _approach("DOC_HOME_NOTE")
	await _tap(KEY_E)
	check(_reading_visible() and session.is_inspected("DOC_HOME_NOTE"), "home document is readable and marks its own fact")
	await _tap(KEY_ESCAPE)
	facts = session.state.world_flags.duplicate(true)
	await _exit("EXIT_HOME_STREET", "SCENE_TOWN_STREET", free_exploration_time, facts)
	await _exit("EXIT_STREET_DOCK", "SCENE_RIVER_DOCK", free_exploration_time, facts)
	await _approach("NPC_DOCK_WORKER")
	await _tap(KEY_E)
	check(_reading_visible() and session.is_inspected("NPC_DOCK_WORKER"), "dock NPC supports the same interaction lifecycle")
	await _tap(KEY_ESCAPE)
	await _test_save_restore()
	await _test_boundary_save_hud()
	await _test_runtime_fallback()
	main._return_to_title()
	await _step(2)
	check(main.get_node("SceneHost").get_child_count() == 0, "return to title unloads old region")
	check(not _reading_visible() and app.current_context() == &"system_menu", "return to title owns menu input with no reading overlay")
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	await _step(2)
	_check_region("SCENE_TOWN_STREET", "new route")
	check(session.state.route_id != original_route, "new route obtains a distinct identity")
	check(session.state.world_flags.is_empty(), "new route clears every inspected flag")
	check(session.state.time_state == {"day": 1, "slot": 0}, "new route resets world time")
	await _finish()


func _test_interactions() -> void:
	var region: Node2D = _region()
	var npc: Dictionary = _target("NPC_STREET_VENDOR")
	var point := Vector2(npc.position[0], npc.position[1])
	await _place(point + Vector2(0, 80), "up")
	await _tap(KEY_E)
	check(not _reading_visible() and interaction_log.is_empty(), "out-of-range E does not interact")
	await _place(point + Vector2(0, 44), "down")
	check(region.choose_target().is_empty(), "facing away has no eligible target")
	await _tap(KEY_E)
	check(not _reading_visible() and interaction_log.is_empty(), "E cannot interact behind player at a distance")
	await _place(point + Vector2(0, 44), "up")
	_key(KEY_E, true, true)
	await _step()
	_key(KEY_E, false)
	check(not _reading_visible() and interaction_log.is_empty(), "keyboard repeat alone cannot open interaction")
	var obstruction := StaticBody2D.new()
	obstruction.collision_layer = 1
	obstruction.collision_mask = 0
	obstruction.position = point + Vector2(0, 22)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 4)
	collision.shape = shape
	obstruction.add_child(collision)
	region.add_child(obstruction)
	await _step(2)
	check(region.choose_target().is_empty(), "real physics ray rejects occluded target")
	await _tap(KEY_E)
	check(not _reading_visible() and interaction_log.is_empty(), "E cannot interact through an obstruction")
	obstruction.queue_free()
	await _step(2)
	# Two candidates are in reach. Test the actual nearest/front-facing arbitration,
	# then remove the ephemeral second candidate before any other scenario.
	var second: Dictionary = npc.duplicate(true)
	second["id"] = "NPC_TEST_SECOND_CANDIDATE"
	second["position"] = [point.x + 32, point.y]
	region.definition["interactions"].append(second)
	check(region.choose_target().get("id", "") == "NPC_STREET_VENDOR", "two reachable candidates select one nearest frontal target")
	await _tap(KEY_E)
	region.definition["interactions"].pop_back()
	check(interaction_log == ["NPC_STREET_VENDOR"], "one E emits exactly one NPC interaction")
	check(_reading_visible(), "same confirm event does not immediately close newly opened reading")
	check(app.current_context() != &"exploration", "reading owns an input context")
	check(session.is_inspected("NPC_STREET_VENDOR"), "NPC interaction writes an authoritative inspected fact")
	var stopped: Vector2 = region.player_position
	_key(KEY_D, true)
	await _step(6)
	check(region.player_position == stopped, "reading blocks actual held movement events")
	_key(KEY_E, true, true)
	await _step(2)
	_key(KEY_E, false)
	check(_reading_visible() and interaction_log.size() == 1, "echo during reading cannot double-trigger or close it")
	await _tap(KEY_F5)
	check(not FileAccess.file_exists(saves.slot_path("quick")), "quick-save hotkey is blocked while reading")
	await _tap(KEY_ESCAPE)
	check(not _reading_visible() and not main.menu.visible, "Escape closes reading without also opening pause")
	check(app.current_context() == &"exploration", "Escape restores exploration context")
	await _step(4)
	check(region.player_position == stopped, "closing reading ignores stale held movement")
	_key(KEY_D, false)
	await _step(2)
	_key(KEY_D, true)
	await _step(4)
	_key(KEY_D, false)
	check(region.player_position.x > stopped.x, "fresh movement press after reading moves normally")
	await _approach("DOC_STREET_NOTICE")
	await _tap(KEY_E)
	check(_reading_visible() and session.is_inspected("DOC_STREET_NOTICE"), "document opens reading and records its distinct stable fact")
	check(interaction_log == ["NPC_STREET_VENDOR", "DOC_STREET_NOTICE"], "NPC and document remain distinct interaction targets")
	await _tap(KEY_ESCAPE)
	var flags_once: Dictionary = session.state.world_flags.duplicate(true)
	await _tap(KEY_E)
	check(_reading_visible() and session.state.world_flags == flags_once, "rereading document is allowed without duplicating permanent facts")
	await _tap(KEY_ESCAPE)
	check(session.state.time_state == {"day": 3, "slot": 2}, "walking and all reading leave quest time unchanged")


func _test_transition_rejection() -> void:
	var region: Node2D = _region()
	var before: Dictionary = session.state.to_dict()
	main.status.text = "TEST_STATUS_BEFORE_INVALID_TARGET"
	main._transition_to("SCENE_HOME_COURTYARD", "SPAWN_UNKNOWN")
	await _settle_transition("unknown spawn")
	check(_region() == region and session.state.to_dict() == before, "invalid spawn retains the existing map and complete state")
	check(not main.status.text.is_empty() and main.status.text != "TEST_STATUS_BEFORE_INVALID_TARGET", "invalid spawn gives visible error feedback")
	main._transition_to("SCENE_UNKNOWN", "SPAWN_START")
	await _settle_transition("unknown region")
	check(_region() == region and session.state.to_dict() == before, "invalid destination cannot replace a playable region")
	check(app.current_context() == &"exploration", "invalid transitions leave movement available")
	# Fault-inject a valid PackedScene of the wrong kind, then an absent resource.
	# Restore the registry immediately after dispatch so no later scenario sees it.
	var correct_path: String = content._scenes["SCENE_HOME_COURTYARD"]["path"]
	for broken_path: String in ["res://game/presentation/exploration/test_yard.tscn", "res://game/presentation/exploration/missing_flow_fixture.tscn"]:
		main.status.text = "TEST_STATUS_BEFORE_BROKEN_RESOURCE"
		content._scenes["SCENE_HOME_COURTYARD"]["path"] = broken_path
		main._transition_to("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN")
		content._scenes["SCENE_HOME_COURTYARD"]["path"] = correct_path
		await _settle_transition("rejected resource " + broken_path.get_file())
		check(_region() == region and session.state.to_dict() == before, "resource preflight preserves old scene and complete state: " + broken_path.get_file())
		check(not main.transitioning and is_zero_approx(main.transition_cover.modulate.a), "resource rejection leaves no transition lock or opaque fade: " + broken_path.get_file())
		check(app.current_context() == &"exploration", "resource rejection retains exploration input: " + broken_path.get_file())
		check(main.status.text != "TEST_STATUS_BEFORE_BROKEN_RESOURCE" and not main.status.text.is_empty(), "resource rejection displays actionable error: " + broken_path.get_file())
	# Start a real exit and try to redirect it before the fade ends.
	await _approach("EXIT_STREET_HOME")
	await _tap(KEY_E)
	check(main.transitioning, "valid exit sets transition guard before fade completes")
	main._transition_to("SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN")
	_key(KEY_D, true)
	await _settle_transition("guarded home transition")
	_check_region("SCENE_HOME_COURTYARD", "reentrant transition is ignored")
	var stopped: Vector2 = _region().player_position
	await _step(4)
	check(_region().player_position == stopped, "key held during scene transition is not reused on arrival")
	_key(KEY_D, false)
	await _step(2)
	main._transition_to("SCENE_TOWN_STREET", "SPAWN_FROM_HOME")
	await _settle_transition("return after transition guard check")
	_check_region("SCENE_TOWN_STREET", "return after transition guard check")


func _test_save_restore() -> void:
	await _tap(KEY_F5)
	check(FileAccess.file_exists(saves.slot_path("quick")), "F5 writes the real isolated save slot")
	var result: Dictionary = saves.load_game("quick")
	check(result.get("error", FAILED) == OK, "F5 output is a valid save envelope")
	if result.get("error", FAILED) != OK:
		return
	var expected: Dictionary = session.state.to_dict()
	print("EXPLORATION_SAVE_NUMBER_REPRESENTATION live_day=", type_string(typeof(expected.time_state.day)), " saved_day=", type_string(typeof(result["state"].time_state.day)), " raw_time_equal=", result["state"].time_state == expected.time_state, " json_time_equal=", _same_json_data(result["state"].time_state, expected.time_state))
	check(_same_json_data(result["state"].to_dict(), expected), "saved snapshot equals the live authoritative route")
	var expected_file := FileAccess.open(fixture.path_join(EXPECTED_FILE), FileAccess.WRITE)
	check(expected_file != null, "restart expectations written into own fixture")
	if expected_file != null:
		expected_file.store_string(JSON.stringify(expected))
		expected_file.close()
	_key(KEY_D, true)
	await _step(5)
	_key(KEY_D, false)
	check(_region().player_position.x > float(expected.player_state.position.x), "post-save movement changes the live position")
	main._show_pause()
	var stopped: Vector2 = _region().player_position
	_key(KEY_D, true)
	await _step(4)
	check(_region().player_position == stopped, "pause blocks movement in a real exploration region")
	main._resume()
	await _step(4)
	check(_region().player_position == stopped, "resume rejects pause-held movement")
	_key(KEY_D, false)
	await _dispose_main()
	session.start_new_game()
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await _step(2)
	main._load_game()
	await _settle_transition("fresh-main reload")
	_check_snapshot(expected, "fresh-main reload")
	check(main.status.text.contains("primary"), "load UI identifies save recovery source")
	await _test_process_restart()
	# Invalid content IDs can be well-formed save data. Loading them must not
	# destroy the currently playable route or its scene presentation.
	var bad: GameState = GameState.from_dict(expected)
	bad.scene_id = "SCENE_MISSING_CONTENT"
	bad.spawn_id = "SPAWN_MISSING_CONTENT"
	check(saves.save_game("quick", bad) == OK, "fixture writes structurally valid unknown-content save")
	var region: Node2D = _region()
	var before: Dictionary = session.state.to_dict()
	main.status.text = "TEST_STATUS_BEFORE_INVALID_LOAD"
	main._load_game()
	await _step(2)
	check(_region() == region and session.state.to_dict() == before, "invalid-content load preserves live scene and full state")
	check(main.status.text != "TEST_STATUS_BEFORE_INVALID_LOAD" and not main.status.text.is_empty(), "invalid-content load displays an error")


func _test_boundary_save_hud() -> void:
	main._transition_to("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN")
	await _settle_transition("boundary save regression setup")
	if not _check_region("SCENE_HOME_COURTYARD", "boundary save regression setup"):
		return
	await _place(Vector2(224, 600), "down")
	_key(KEY_S, true)
	_key(KEY_SHIFT, true)
	await _step(12)
	_key(KEY_S, false)
	_key(KEY_SHIFT, false)
	await _step(2)
	var saved: Vector2 = _region().player_position
	check(saved.x == 224 and saved.y > 600 and saved.y <= 618.0, "sprinting into bottom wall stops at content's 16px inset plus six-pixel feet extent")
	check(content.is_safe_player_position("SCENE_HOME_COURTYARD", saved), "physically reachable bottom-wall position is accepted by save restoration validator")
	_check_bottom_hud("before boundary save")
	await _tap(KEY_F5)
	var saved_result: Dictionary = saves.load_game("quick")
	check(saved_result.get("error", FAILED) == OK, "bottom-wall F5 creates a valid save")
	if saved_result.get("error", FAILED) != OK:
		return
	check(Vector2(saved_result["state"].player_state.position.x, saved_result["state"].player_state.position.y) == saved, "bottom-wall save contains the exact collision-resolved position")
	main._load_game()
	await _step(3)
	check(_region().player_position == saved, "bottom-wall load restores exact position without teleporting to spawn")
	check(main.status.text.contains("primary"), "bottom-wall load succeeds normally without recovery fallback")
	_check_bottom_hud("after boundary reload")


func _check_bottom_hud(label: String) -> void:
	var screen_foot: Vector2 = _region().player.get_global_transform_with_canvas().origin
	var avatar := Rect2(screen_foot - Vector2(16, 44), Vector2(32, 48))
	check(screen_foot.y > 278, label + " exercises the lower camera edge")
	check(main.controls_backdrop.position.y == 48 and main.status.position.y == 53, label + " relocates controls backdrop and status above the player")
	check(not main.controls_backdrop.get_global_rect().intersects(avatar) and not main.status.get_global_rect().intersects(avatar), label + " controls never cover the full 32x48 avatar canvas")


func _check_snapshot(expected: Dictionary, label: String) -> void:
	if not _check_region(str(expected.scene_id), label):
		return
	check(session.state.route_id == expected.route_id and session.state.spawn_id == expected.spawn_id, label + " restores route and spawn IDs")
	check(session.state.world_flags == expected.world_flags, label + " restores all inspected flags")
	check(_same_json_data(session.state.time_state, expected.time_state), label + " restores world time")
	var position := Vector2(expected.player_state.position.x, expected.player_state.position.y)
	check(_region().player_position.is_equal_approx(position), label + " restores physical player position")
	check(_region().player.facing == expected.player_state.facing, label + " restores facing")
	check(_same_json_data(session.state.to_dict(), expected), label + " restores the complete state without route contamination")


func _test_process_restart() -> void:
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", SELF_SCRIPT, "--", "--reload-fixture=" + fixture])
	var pid: int = OS.create_process(OS.get_executable_path(), arguments)
	restart_pid = pid
	check(pid > 0, "fresh Godot process starts for persistence verification")
	if pid <= 0:
		return
	var deadline: int = Time.get_ticks_msec() + 12000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await _step()
	var timed_out: bool = OS.is_process_running(pid)
	check(not timed_out, "fresh Godot process finishes within twelve seconds")
	if timed_out:
		OS.kill(pid)
		restart_pid = -1
		return
	restart_pid = -1
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join(RECEIPT_FILE)))
	check(receipt is Dictionary, "fresh process leaves its isolated completion receipt")
	if receipt is Dictionary:
		check(receipt.get("pid", 0) == pid and pid != OS.get_process_id(), "reload evidence belongs to a distinct OS process")
		check(receipt.get("failures", ["missing"]).is_empty() and int(receipt.get("checks", 0)) >= 12, "fresh process verifies complete saved state and resumed movement")


func _run_restart_child() -> void:
	# Refuse arbitrary paths even though the caller is this same integration test.
	if not fixture.begins_with(FIXTURE_PREFIX) or "/" in fixture.trim_prefix(FIXTURE_PREFIX) or ".." in fixture:
		printerr("EXPLORATION_FLOW_FAIL invalid child fixture")
		quit(1)
		return
	saves.test_root = fixture
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join(EXPECTED_FILE)))
	check(expected is Dictionary, "restart child reads parent snapshot expectation")
	if expected is Dictionary:
		main = load(MAIN_SCENE).instantiate()
		root.add_child(main)
		await _step(2)
		check(main.get_node("SceneHost").get_child_count() == 0, "fresh process begins on title without a retained region")
		main._load_game()
		await _settle_transition("process restart")
		_check_snapshot(expected, "process restart")
		var region: Node2D = _region()
		if region != null:
			var before: Vector2 = region.player_position
			_key(KEY_D, true)
			await _step(4)
			_key(KEY_D, false)
			check(region.player_position.x > before.x, "restarted route accepts fresh keyboard movement")
	await _dispose_main()
	var receipt := FileAccess.open(fixture.path_join(RECEIPT_FILE), FileAccess.WRITE)
	if receipt != null:
		receipt.store_string(JSON.stringify({"pid": OS.get_process_id(), "checks": checks, "failures": failures}))
		receipt.close()
	else:
		check(false, "restart child writes its completion receipt")
	saves.test_root = ""
	if failures.is_empty():
		print("EXPLORATION_RESTART_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _test_runtime_fallback() -> void:
	session.state.scene_id = "SCENE_UNKNOWN_RUNTIME"
	session.state.spawn_id = "SPAWN_UNKNOWN_RUNTIME"
	session.state.player_state["position"] = {"x": -999, "y": -999}
	main._enter_yard()
	await _step(2)
	_check_region(content.start_scene_id, "invalid runtime state fallback")
	check(content.has_spawn(session.state.scene_id, session.state.spawn_id), "fallback chooses a registered spawn")
	check(not main.status.text.is_empty(), "runtime fallback gives visible feedback")


func _dispose_main() -> void:
	_release_keys()
	if is_instance_valid(main):
		root.remove_child(main)
		main.queue_free()
	await process_frame
	await process_frame


func _finish() -> void:
	await _dispose_main()
	saves.test_root = ""
	_cleanup(fixture)
	if failures.is_empty():
		print("EXPLORATION_FLOW_PASS checks=", checks, " (injected keyboard, real physics, 5x round trips each route, isolated actual process restart)")
	quit(0 if failures.is_empty() else 1)


func _cleanup(path: String) -> void:
	if fixture.is_empty() or not fixture.begins_with(FIXTURE_PREFIX):
		return
	if path != fixture and not path.begins_with(fixture + "/"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_cleanup(path.path_join(child))
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
