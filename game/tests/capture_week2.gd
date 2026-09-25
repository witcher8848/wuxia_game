extends SceneTree
## Actual-render QA, separate from headless input checks and human usability.
const OUTPUT := "res://builds/qa/week2_visual"
var main: Node
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _step(frames: int = 3) -> void:
	for _frame in range(frames):
		await physics_frame
		await process_frame

func _capture(label: String) -> void:
	await _step()
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))
	if result != OK:
		failures.append("Capture failed: " + label)
	print("VISUAL_CAPTURE ", label, " window=", DisplayServer.window_get_size(), " logical=", root.get_visible_rect().size, " transform=", root.get_final_transform())

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("VISUAL_FAIL ", message)

func _change_region(identifier: String, spawn: String) -> void:
	main._transition_to(identifier, spawn)
	while main.transitioning:
		await _step(1)
	await _step()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("VISUAL_FAIL graphical renderer required")
		quit(1)
		return
	create_timer(60).timeout.connect(func() -> void:
		printerr("VISUAL_FAIL watchdog")
		quit(1))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_node("SaveService").test_root = "user://tests/week2_visual_" + str(OS.get_process_id())
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _capture("title_1280")
	main._start_game()
	await _capture("town_1280")
	DisplayServer.window_move_to_foreground()
	await _step(8)
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _step(4)
	_check(main.get_node("SceneHost").get_child(0).player.sprinting, "new sprint feedback is active while moving")
	await _capture("feedback_sprint_1280")
	Input.action_release("sprint")
	Input.action_release("move_right")
	await _step(3)
	var region: Node = main.get_node("SceneHost").get_child(0)
	region.player_position = Vector2(608, 396)
	region.player.facing = "up"
	await _step()
	main._on_interaction(region.choose_target())
	await _capture("npc_reading_1280")
	_check(is_instance_valid(main.reading_panel) and main.reading_panel.visible, "NPC reading visible")
	_check(main.reading_panel.position.y + main.reading_panel.size.y <= 360, "reading panel inside logical screen")
	main._close_reading()
	await _change_region("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN")
	await _capture("home_1280")
	region = main.get_node("SceneHost").get_child(0)
	region.player_position = Vector2(224, 600)
	await _step()
	await _capture("home_lower_boundary_1280")
	_check(main.controls_backdrop.position.y == 48, "HUD vacates lower edge for player")
	await _change_region("SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN")
	await _capture("dock_1280")
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await _step(5)
	await _capture("dock_1366")
	_check(DisplayServer.window_get_size() == Vector2i(1366, 768), "1366x768 window applied")
	_check(root.get_visible_rect().size == Vector2(640, 360), "logical viewport unchanged at1366x768")
	var transform := root.get_final_transform()
	_check(is_equal_approx(transform.x.length(), transform.y.length()) and is_equal_approx(transform.x.length(), roundf(transform.x.length())), "display scaling uniform integer")
	main._show_pause()
	await _capture("pause_1366")
	main._toggle_fullscreen()
	await _step(8)
	await _capture("pause_fullscreen")
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen applied")
	main._toggle_fullscreen()
	main._resume()
	await _step(5)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "returned to windowed mode")
	Input.action_press("move_right")
	var before: Vector2 = main.get_node("SceneHost").get_child(0).player_position
	await _step(6)
	Input.action_release("move_right")
	_check(main.get_node("SceneHost").get_child(0).player_position.x > before.x, "movement restored after fullscreen")
	Input.action_release("move_right")
	await _capture_save_slots()
	if failures.is_empty():
		print("WEEK2_VISUAL_PASS renderer=", RenderingServer.get_video_adapter_name(), " input=simulated; human usability not covered")
	quit(0 if failures.is_empty() else 1)

func _capture_save_slots() -> void:
	# Only this process's isolated test directory is touched. These images show
	# deterministic fixture saves, not the user's progress or human acceptance.
	var saves: Node = root.get_node("SaveService")
	var session: Node = root.get_node("GameSession")
	var fixture: String = saves.test_root
	_check(fixture == "user://tests/week2_visual_" + str(OS.get_process_id()), "save screenshots use isolated test root")
	if not fixture.begins_with("user://tests/week2_visual_"):
		return
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await _step(5)
	for slot: String in ["quick", "manual_01", "manual_02", "manual_03", "manual_04", "manual_05", "auto_01", "auto_02", "auto_03"]:
		_check(saves.save_game(slot, session.state) == OK, "fixture save written: " + slot)
	# A bad primary with a valid backup tests long, localized recovery labels.
	_check(saves.save_game("manual_01", session.state) == OK, "fixture backup exists")
	var damaged := FileAccess.open(saves.slot_path("manual_01"), FileAccess.WRITE)
	damaged.store_string("damaged isolated screenshot fixture")
	damaged.close()
	main._show_pause()
	await _step()
	main._show_save_slots()
	await _capture("feedback_manual_slots_1366")
	_check_menu_bounds("manual slots first page")
	main._show_slot_list(&"save_slots", 1)
	await _capture("feedback_manual_slots_page2_1366")
	_check_menu_bounds("manual slots last page")
	main._show_slot_list(&"save_slots", 0)
	await _step()
	main._request_save_slot("manual_01")
	await _capture("feedback_overwrite_1366")
	_check_menu_bounds("overwrite confirmation")
	_check(root.gui_get_focus_owner().name == "OverwriteCancel", "overwrite defaults to cancel")
	main._menu_back()
	await _step()
	main._menu_back()
	await _step()
	main._show_load_slots()
	await _capture("feedback_load_slots_1366")
	_check_menu_bounds("load slots with backup summary")
	TranslationServer.set_locale("en")
	main._show_slot_list(&"load_slots", 0)
	await _capture("feedback_load_slots_en_1366")
	_check_menu_bounds("English long recovery summary")
	TranslationServer.set_locale("zh_CN")
	main._return_to_title()
	await _step()
	main._show_load_slots()
	await _step()
	main._show_slot_list(&"load_slots", 2)
	await _capture("feedback_title_auto_slots_1366")
	_check_menu_bounds("title last load page")
	_remove_fixture(fixture, fixture)
	saves.test_root = ""

func _check_menu_bounds(label: String) -> void:
	_check(Rect2(Vector2.ZERO, Vector2(640, 310)).encloses(main.menu.get_global_rect()), label + " fits above footer")
	for button in main.slot_buttons:
		if is_instance_valid(button) and button.is_visible_in_tree():
			_check(main.menu.get_global_rect().encloses(button.get_global_rect()), label + " contains " + button.name)

func _remove_fixture(path: String, fixture: String) -> void:
	if fixture != "user://tests/week2_visual_" + str(OS.get_process_id()) or (path != fixture and not path.begins_with(fixture + "/")):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_fixture(path.path_join(child), fixture)
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
