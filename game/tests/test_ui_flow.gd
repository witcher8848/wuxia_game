extends SceneTree

var failures: Array[String] = []
var checks := 0
var main: Node
var fixture: String

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("UI_FLOW_FAIL ", message)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	await process_frame
	var saves: Node = root.get_node("SaveService")
	var session: Node = root.get_node("GameSession")
	var app: Node = root.get_node("App")
	fixture = "user://tests/ui_flow_%d" % OS.get_process_id()
	saves.test_root = fixture
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	check(app.current_context() == &"system_menu", "title owns menu input")
	check(root.gui_get_focus_owner() is Button, "title focuses enter button")
	_key(KEY_E, true)
	await process_frame
	_key(KEY_E, false)
	await process_frame
	check(main.get_node("SceneHost").get_child_count() == 1, "E activates entry button")
	if main.get_node("SceneHost").get_child_count() != 1:
		quit(1)
		return
	var yard: Node2D = main.get_node("SceneHost").get_child(0)
	var before: Vector2 = yard.player_position
	_key(KEY_D, true)
	for _frame in range(8):
		await physics_frame
	_key(KEY_D, false)
	await physics_frame
	check(yard.player_position.x > before.x, "keyboard event moves player")
	var saved: Vector2 = yard.player_position
	_key(KEY_F5, true)
	await process_frame
	await process_frame
	_key(KEY_F5, false)
	print("UI_SAVE_PROBE ", main.status.text, " context=", app.current_context(), " path=", saves.slot_path("quick"))
	check(FileAccess.file_exists(saves.slot_path("quick")), "F5 writes actual save")
	check(saves.load_game("quick")["error"] == OK, "saved envelope valid")
	main._show_pause()
	var stopped: Vector2 = yard.player_position
	_key(KEY_D, true)
	for _frame in range(4):
		await physics_frame
	_key(KEY_D, false)
	check(yard.player_position == stopped, "pause blocks exploration input")
	main._resume()
	await process_frame
	check(app.current_context() == &"exploration", "resume restores exploration context")
	main._on_joy_connection_changed(0, false)
	check(app.current_context() == &"system_menu", "simulated disconnect pauses")
	main._resume()
	await process_frame
	# Dispose the scene and replace state before loading: exercise the actual UI restore.
	root.remove_child(main)
	main.queue_free()
	session.start_new_game()
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._load_game()
	await process_frame
	check(main.get_node("SceneHost").get_child_count() == 1, "loaded map exists")
	if main.get_node("SceneHost").get_child_count() != 1:
		_cleanup(fixture)
		quit(1)
		return
	yard = main.get_node("SceneHost").get_child(0)
	check(yard.player_position.is_equal_approx(saved), "new main scene restores saved position")
	check(is_equal_approx(float(session.state.player_state["position"]["x"]), saved.x), "loaded position belongs to authoritative state")
	check(main.status.text.contains("primary"), "load UI explains recovery source")
	main._return_to_title()
	await process_frame
	check(main.get_node("SceneHost").get_child_count() == 0, "return to title unloads map")
	check(app.current_context() == &"system_menu", "title restores menu context")
	root.remove_child(main)
	main.queue_free()
	await process_frame
	saves.test_root = ""
	_cleanup(fixture)
	if failures.is_empty():
		print("UI_FLOW_PASS checks=", checks, " (injected keyboard/controller events)")
	quit(0 if failures.is_empty() else 1)

func _cleanup(path: String) -> void:
	if path != fixture and not path.begins_with(fixture + "/"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child in directory.get_directories():
		_cleanup(path.path_join(child))
	for child in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
