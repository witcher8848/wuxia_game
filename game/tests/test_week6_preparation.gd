extends SceneTree
## Normal-game keyboard entry, detached drafts, layout and real save/readback.
const MAIN := "res://game/presentation/main.tscn"
var checks := 0
var failures: Array[String] = []
var main: Node
var session: Node
var app: Node
var saves: Node
var capture_folder := ""
var captures := false
var packed := false
var captured: Array[String] = []

func _initialize() -> void:
	create_timer(75).timeout.connect(func() -> void: printerr("WEEK6_PREPARATION_FAIL watchdog"); quit(124))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("WEEK6_PREPARATION_FAIL ",message)

func step(frames := 2) -> void:
	for _index in range(frames):
		await physics_frame
		await process_frame

func tap(code: Key) -> void:
	for pressed: bool in [true,false]:
		key_state(code,pressed)
		await step(1)

func key_state(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func layout(node: Node, label: String) -> void:
	await step()
	var bounds := Rect2(0,0,640,360)
	if node is Control: check(bounds.encloses(node.get_global_rect()),label + " fits viewport")
	for child: Node in node.get_children():
		if child is Control and child.is_visible_in_tree():
			check(bounds.encloses(child.get_global_rect()),label + " control in viewport " + str(child.name))
			if child is Label:
				for line: String in child.text.split("\n"):
					var width: float = child.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
					check(width <= child.size.x + 0.1,label + " full line fits " + line)
				check(child.get_minimum_size().y <= child.size.y + 0.1,label + " glyph height fits")
		await layout(child,label)

func capture(name: String) -> void:
	if not captures: return
	await step(3)
	await RenderingServer.frame_post_draw
	var texture := root.get_texture().get_image()
	check(texture.get_size() == Vector2i(640,360),"real 640x360 " + name)
	check(texture.save_png(capture_folder.path_join(name + ".png")) == OK,"capture " + name)
	captured.append(name)

func panel() -> PanelContainer:
	return main.martial_panel

func _run() -> void:
	await process_frame
	TranslationServer.set_locale("zh_CN")
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	captures = "--capture-week6-preparation" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed,"real PCK only, no source overlay")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_folder = argument.trim_prefix("--capture-dir=")
	if captures:
		check(DisplayServer.get_name() != "headless","real rendering required")
		if capture_folder.is_empty(): capture_folder = ProjectSettings.globalize_path("res://builds/qa/week6_preparation")
		check(DirAccess.make_dir_recursive_absolute(capture_folder) == OK,"isolated capture directory")
	session = root.get_node("GameSession")
	app = root.get_node("App")
	saves = root.get_node("SaveService")
	saves.test_root = "user://tests/martial_ui_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	main = load(MAIN).instantiate()
	root.add_child(main)
	await step()
	session.start_new_game()
	check(main._enter_yard() == OK,"normal main exploration entry")
	await step()
	var before: Dictionary = session.state.to_dict()
	var region: Node = main.get_node("SceneHost").get_child(0)
	var position: Vector2 = region.player_position
	await tap(KEY_M)
	check(app.current_context() == &"codex" and panel().visible,"M opens normal-game martial overlay")
	check(session.state.to_dict() == before,"viewing legacy empty martial state does not migrate live state")
	check(panel().rows.size() == 6 and panel().draft["external"].size() == 3,"3 external plus movement plus internal and apply rows")
	await layout(panel(),"default preparation")
	await capture("prep_default")
	await tap(KEY_LEFT)
	check(panel().draft["external"][0] == "SK_TRIP_WRIST","keyboard cycles first slot to wrist art")
	await tap(KEY_DOWN)
	await tap(KEY_LEFT)
	check(panel().draft["external"][1] == "SK_YUE_THRUST","keyboard makes changed second slot")
	await tap(KEY_RIGHT)
	await tap(KEY_RIGHT)
	check(panel().notice.text.contains("尚未应用"),"draft is clearly not saved or applied")
	check(region.player_position == position,"overlay directional keys cannot move exploration player")
	check(session.state.to_dict() == before,"changing choices is read-only")
	await tap(KEY_ESCAPE)
	check(not panel().visible and app.current_context() == &"exploration","cancel restores exploration")
	check(session.state.to_dict() == before,"cancel leaves entire state unchanged")
	await tap(KEY_M)
	await tap(KEY_RIGHT)
	check(panel().draft["external"][0] == "SK_YUE_GUARD","create duplicate via actual cycling")
	await tap(KEY_E)
	check(session.state.to_dict() == before and panel().notice.text.contains("重复"),"duplicate cannot apply and explanation shown")
	await tap(KEY_LEFT)
	await tap(KEY_LEFT)
	check(panel().draft["external"][0] == "SK_TRIP_WRIST","correct duplicate without resetting focus")
	await capture("prep_changed")
	await tap(KEY_E)
	check(panel().notice.text.contains("已应用") and panel().notice.text.contains("F5"),"application is distinguished from disk save")
	var configured: Dictionary = session.state.to_dict()
	var expected: Dictionary = before.duplicate(true)
	expected["martial_states"] = configured["martial_states"].duplicate(true)
	check(configured == expected,"confirmed configuration changes only martial state")
	check(configured["martial_states"]["loadout"]["external"][0] == "SK_TRIP_WRIST","session owns real submitted choice")
	var draft_alias: Dictionary = panel().draft
	draft_alias["external"][0] = ""
	check(session.state.to_dict() == configured,"UI draft cannot alias authoritative session")
	await tap(KEY_ESCAPE)
	await tap(KEY_M)
	for _index in range(4): await tap(KEY_DOWN)
	check(panel().selection == 4 and panel().detail.text.contains("内力上限5"),"equipped internal passive explained")
	await tap(KEY_RIGHT)
	check(panel().draft["internal"].is_empty() and panel().detail.text.contains("内力上限3"),"no internal changes actual advertised baseline")
	await layout(panel(),"no internal preparation")
	await capture("prep_no_internal")
	await tap(KEY_E)
	check(session.state.martial_states["loadout"]["internal"].is_empty(),"internal unequip applied")
	await tap(KEY_M)
	check(app.current_context() == &"exploration","M closes overlay without opening codex")
	await tap(KEY_F5)
	var loaded: Dictionary = saves.load_game("quick",false)
	check(loaded["error"] == OK and loaded["state"].martial_states == session.state.martial_states,"normal F5 persists actual martial configuration")
	await tap(KEY_M)
	for _index in range(4): await tap(KEY_DOWN)
	await tap(KEY_RIGHT)
	await tap(KEY_E)
	check(session.state.martial_states["loadout"]["internal"] == "IN_BREATH_BASIC","internal can be re-equipped")
	await tap(KEY_ESCAPE)
	var seen: GameState = GameState.from_dict(session.state.to_dict())
	seen.martial_states["mastery"]["SK_YUE_CROSSCUT"] = "识招"
	seen.martial_states["loadout"]["external"] = ["SK_YUE_THRUST","SK_YUE_GUARD"]
	check(session.replace_state(seen) == OK,"legal observed-only martial state fixture")
	var observed_before: Dictionary = session.state.to_dict()
	await tap(KEY_M)
	await tap(KEY_DOWN)
	await tap(KEY_DOWN)
	await tap(KEY_LEFT)
	check(panel().selected_id() == "SK_YUE_CROSSCUT" and panel().detail.text.contains("识招"),"untrained art remains inspectable with condition")
	await tap(KEY_E)
	check(session.state.to_dict() == observed_before and panel().notice.text.contains("熟练"),"observed-only equipment blocked atomically")
	await tap(KEY_ESCAPE)
	check(InputMap.has_action("open_martial") and InputMap.action_get_events("open_martial").size() >= 2,"new action preserves pad mapping interface")
	await tap(KEY_M)
	position = region.player_position
	key_state(KEY_D,true)
	await step(3)
	await tap(KEY_ESCAPE)
	await step(3)
	check(region.player_position == position and region.player.velocity == Vector2.ZERO,"held direction cannot leak across overlay close")
	key_state(KEY_D,false)
	await step(3)
	key_state(KEY_D,true)
	await step(3)
	check(region.player.velocity.x > 0,"release and new press restores normal exploration movement")
	key_state(KEY_D,false)
	await step(2)
	main._return_to_title()
	await step(3)
	for _index in range(3): await tap(KEY_DOWN)
	check(root.gui_get_focus_owner() is Button and root.gui_get_focus_owner().text.contains("演武"),"real title keyboard reaches fourth trial entry")
	await tap(KEY_E)
	check(is_instance_valid(main._combat_v1_screen) and main._combat_v1_screen.phase == "selection","actual main title instantiates production trial")
	await tap(KEY_ESCAPE)
	await tap(KEY_E)
	await step(4)
	check(app.current_context() == &"system_menu" and main._menu_kind == &"title","trial detached before title contexts rebuild, no late pop")
	check(not session.combat_active(),"main trial exit releases combat authority")
	await tap(KEY_E)
	check(app.current_context() == &"dialogue" and main.get_node("SceneHost").get_child_count() == 1,"new game works after returning from main trial")
	if captures: check(captured == ["prep_default","prep_changed","prep_no_internal"],"complete 3 screenshot set")
	main.queue_free()
	await step()
	if failures.is_empty(): print("WEEK6_PREPARATION_PASS checks=",checks," packed=",packed," captures=",captured.size())
	else: printerr("WEEK6_PREPARATION_FAIL checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
