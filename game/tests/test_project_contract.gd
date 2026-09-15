extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("CHECK_FAILED: ", description)

func _run() -> void:
	await process_frame
	for setting in {
		"display/window/size/viewport_width": 640,
		"display/window/size/viewport_height": 360,
		"display/window/stretch/mode": "viewport",
		"display/window/stretch/aspect": "keep",
		"display/window/stretch/scale_mode": "integer",
		"rendering/renderer/rendering_method": "gl_compatibility",
		"application/config/custom_user_dir_name": "ProjectWuming",
		"application/config/use_custom_user_dir": true,
	}:
		var expected: Dictionary = {
			"display/window/size/viewport_width": 640,
			"display/window/size/viewport_height": 360,
			"display/window/stretch/mode": "viewport",
			"display/window/stretch/aspect": "keep",
			"display/window/stretch/scale_mode": "integer",
			"rendering/renderer/rendering_method": "gl_compatibility",
			"application/config/custom_user_dir_name": "ProjectWuming",
			"application/config/use_custom_user_dir": true,
		}
		check(ProjectSettings.get_setting(setting) == expected[setting], setting)
	for singleton in ["App", "GameSession", "ContentDB", "SaveService", "PlatformService"]:
		check(root.has_node(singleton), "autoload " + singleton)
	var app: Node = root.get_node("App")
	check(not app.debug_enabled, "debug defaults off")
	check(app.current_context() == &"exploration", "base context")
	app.push_context(&"codex")
	app.push_context(&"system_menu")
	check(app.current_context() == &"system_menu", "top context owns input")
	app.pop_context()
	check(app.current_context() == &"codex", "restore previous context")
	app.reset_contexts()
	app.pop_context()
	check(app.current_context() == &"exploration", "cannot pop base context")
	for action in ["move_up", "move_down", "move_left", "move_right", "confirm", "cancel", "sprint", "inspect", "open_codex", "tab_previous", "tab_next", "pause", "quick_save", "toggle_threat"]:
		check(InputMap.has_action(action), "input exists " + action)
		check(not InputMap.action_get_events(action).is_empty(), "input bound " + action)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F5
	check(InputMap.event_is_action(key, "quick_save"), "F5 key code")
	key.physical_keycode = KEY_SHIFT
	check(InputMap.event_is_action(key, "sprint"), "Shift key code")
	key.physical_keycode = KEY_W
	check(InputMap.event_is_action(key, "move_up"), "W movement")
	check(InputMap.event_is_action(key, "ui_up"), "W menu navigation")
	key.physical_keycode = KEY_E
	check(InputMap.event_is_action(key, "ui_accept"), "E menu confirm")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	check(InputMap.event_is_action(pad, "confirm"), "A confirm configuration")
	check(InputMap.event_is_action(pad, "ui_accept"), "A menu configuration")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	check(InputMap.event_is_action(stick, "move_right"), "left stick configuration")
	check(is_equal_approx(InputMap.action_get_deadzone("move_right"), 0.25), "stick deadzone")
	var content: Node = root.get_node("ContentDB")
	check(content.last_error.is_empty(), "bootstrap loaded")
	check(content.get_scene_path("SCENE_TEST_YARD") == "res://game/presentation/exploration/test_yard.tscn", "scene ID resolves")
	var platform: Node = root.get_node("PlatformService")
	check(not platform.is_available(), "offline without Steam")
	var session: Node = root.get_node("GameSession")
	check(session.update_player_position(Vector2(120, 160)) == OK, "position command updates state")
	check(session.state.player_state["position"] == {"x": 120.0, "y": 160.0}, "position command owns persistent coordinates")
	check(session.update_player_position(Vector2(NAN, 0)) == ERR_INVALID_PARAMETER, "position command rejects invalid numbers")
	if failures.is_empty():
		print("PROJECT_CONTRACT_PASS checks=", checks, " (simulated input mapping; no physical hardware claim)")
	else:
		printerr("PROJECT_CONTRACT_FAILED ", failures)
	quit(0 if failures.is_empty() else 1)
