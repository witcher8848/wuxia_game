extends SceneTree
## Actual Main keyboard routing and two-step world actions, not direct UI callbacks.
var checks := 0
var failures: Array[String] = []
var captures := 0
var capture_enabled := false
var main: Node
var session: Node
var content: Node
var app: Node

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK7_WORLD_UI_FAIL ", label)

func frames(count: int = 3) -> void:
	for _index: int in count: await process_frame
	await physics_frame

func tap(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func capture(label: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("WUXIA_CAPTURE_DIR")
	if folder.is_empty(): folder = "res://builds/qa/week7"
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "capture folder")
	check(root.get_texture().get_image().save_png(folder.path_join("week7_"+label+".png")) == OK, "capture "+label)
	captures += 1

func near_npc(id: String) -> void:
	var npc: Dictionary = content.world_npc(session.state, id)["npc"]
	var region: Node = main.get_node("SceneHost").get_child(0)
	region.player_position = Vector2(npc["position"][0],npc["position"][1])+Vector2(0,40)
	region.player.facing = "up"
	await frames()

func _run() -> void:
	create_timer(90).timeout.connect(func() -> void: printerr("WEEK7_WORLD_UI_FAIL watchdog"); quit(1))
	await frames()
	var packed := "--require-pack" in OS.get_cmdline_user_args()
	check(not packed or FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "packed tests cannot use source overlay")
	capture_enabled = "--capture-week7" in OS.get_cmdline_user_args()
	check(not capture_enabled or DisplayServer.get_name() != "headless", "capture requires native renderer")
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	app = root.get_node("App")
	var saves: Node = root.get_node("SaveService")
	saves.test_root = "user://tests/week7_world_ui_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		session.start_new_game()
		main = load("res://game/presentation/main.tscn").instantiate()
		root.add_child(main)
		check(main._enter_yard() == OK, "enter normal exploration "+locale)
		await frames()
		var region: Node = main.get_node("SceneHost").get_child(0)
		var before: Dictionary = session.state.to_dict()
		var original_position: Array = content.world_npc(session.state,"NPC_STREET_VENDOR")["npc"]["position"]
		await tap(KEY_H)
		check(app.current_context() == &"codex" and main.world_panel.visible, "H opens world panel")
		check(not main.world_panel.heading.text.contains("WORLD_"), "translated clock")
		await capture(locale+"_clock")
		await tap(KEY_D)
		await tap(KEY_F5)
		check(session.state.to_dict() == before, "world view blocks movement and quicksave")
		check(not FileAccess.file_exists(saves.slot_path("quick")), "world view cannot create quick save")
		await tap(KEY_E)
		check(main.world_panel.confirmation and main.world_panel.cursor == 0, "wait preview defaults to cancel")
		check(session.state.to_dict() == before, "preview does not advance")
		await capture(locale+"_wait_confirm")
		await tap(KEY_E)
		check(not main.world_panel.confirmation and session.state.to_dict() == before, "second Enter cancels safely")
		await tap(KEY_E)
		await tap(KEY_DOWN)
		await tap(KEY_E)
		check(session.state.time_state == {"day":1,"slot":1}, "confirmed waiting advances exactly once")
		check(session.state.relationships.is_empty(), "waiting cannot farm trust")
		check(content.world_npc(session.state,"NPC_STREET_VENDOR")["npc"]["position"] != original_position, "NPC really relocates")
		await tap(KEY_ESCAPE)
		check(app.current_context() == &"exploration", "world panel restores exploration")
		await capture(locale+"_relocated")
		await near_npc("NPC_STREET_VENDOR")
		await tap(KEY_E)
		check(main.reading_panel.visible and app.current_context() == &"dialogue", "E opens actual vendor social dialogue")
		await capture(locale+"_vendor_before")
		await tap(KEY_H)
		check(main.world_panel.visible and main.world_panel.npc_id == "NPC_STREET_VENDOR", "H opens vendor social actions")
		check(session.is_inspected("NPC_STREET_VENDOR"), "speaking makes acquaintance known")
		var greeting: String = content.world_greeting(session.state,"NPC_STREET_VENDOR")
		before = session.state.to_dict()
		await tap(KEY_E)
		check(main.world_panel.confirmation, "help previews the cost and reward")
		await capture(locale+"_help_confirm")
		await tap(KEY_ESCAPE)
		check(not main.world_panel.confirmation and session.state.to_dict() == before, "cancel help changes nothing")
		await tap(KEY_E)
		await tap(KEY_DOWN)
		await tap(KEY_E)
		check(session.state.relationships.get("NPC_STREET_VENDOR",{}).get("trust",0) == 1, "actual help increases trust")
		check(session.state.world_flags.get("REP_TOWN",0) == 1, "actual help increases reputation")
		check(content.world_greeting(session.state,"NPC_STREET_VENDOR") != greeting, "help changes actual dialogue")
		check(not main.world_panel.body.text.contains(content.world_greeting(session.state,"NPC_STREET_VENDOR")), "relocated NPC cannot continue talking remotely")
		before = session.state.to_dict()
		await tap(KEY_E)
		check(not main.world_panel.confirmation and session.state.to_dict() == before, "help cannot be repeated today")
		await capture(locale+"_help_result")
		await tap(KEY_ESCAPE)
		if app.current_context() == &"dialogue": await tap(KEY_ESCAPE)
		check(app.current_context() == &"exploration", "vendor panel returns cleanly")
		await near_npc("NPC_STREET_VENDOR")
		before = session.state.to_dict()
		await tap(KEY_E)
		check(main.reading_panel.body.text == content.world_greeting(session.state,"NPC_STREET_VENDOR"), "nearby renewed conversation shows the actual changed greeting")
		check(session.state.to_dict() == before, "ordinary renewed conversation cannot farm time or social rewards")
		await capture(locale+"_vendor_after")
		await tap(KEY_ESCAPE)
		check(session.enter_region("SCENE_RIVER_DOCK","SPAWN_FROM_TOWN") == OK, "travel remains free")
		check(main._enter_yard() == OK, "load projected dock")
		await frames()
		await near_npc("NPC_DOCK_WORKER")
		await tap(KEY_E)
		check(app.current_context() == &"dialogue" and is_instance_valid(main.reading_panel) and main.reading_panel.has_method("go_to"), "old dock investigation still opens")
		var dock_greeting: String = content.world_greeting(session.state,"NPC_DOCK_WORKER")
		var entry_text: String = TranslationServer.translate(main.reading_panel.view["text_key"])
		check(main.reading_panel.body.text.begins_with(entry_text), "current quest entry is readable before ambient chatter")
		check(main.reading_panel.body.text.ends_with(dock_greeting), "entry still appends actual time and social greeting")
		check(main.reading_panel.body.text.contains(TranslationServer.translate("NPC_DOCK_WORKER_NAME")+": "+dock_greeting), "appended NPC chatter explicitly names its speaker")
		check(main.reading_panel.heading.text == TranslationServer.translate("INV_SELF"), "initial protagonist monologue retains its actual speaker")
		await capture(locale+"_boatman_topic")
		await tap(KEY_E)
		check(main.reading_panel.node_id == "D_ACCEPT", "actual entry command advances to quest acceptance")
		await tap(KEY_E)
		check(main.reading_panel.node_id == "D_DOCK", "actual acceptance reaches the dock investigation")
		check(main.reading_panel.heading.text == TranslationServer.translate("INV_BOATMAN"), "boatman entry retains its own speaker")
		await tap(KEY_E)
		check(main.reading_panel.node_id == "D_BOAT", "asking the boatman opens the actual testimony answer")
		check(main.reading_panel.body.text == TranslationServer.translate("D_BOAT_TEXT"), "testimony and challenge instructions are first without repeated chatter")
		check(not main.reading_panel.body.text.contains(dock_greeting), "non-entry answer does not repeat ambient greeting")
		await capture(locale+"_boatman_answer")
		await tap(KEY_H)
		check(app.current_context() == &"codex" and main.world_panel.npc_id == "NPC_DOCK_WORKER", "dock H opens social panel")
		check(main.world_panel.body.text.begins_with(dock_greeting), "H preserves the full actual time and relationship greeting")
		await tap(KEY_ESCAPE)
		check(app.current_context() == &"dialogue" and main.reading_panel.visible, "cancel social returns to dock dialogue")
		check(main.reading_panel.node_id == "D_BOAT" and main.reading_panel.body.text == TranslationServer.translate("D_BOAT_TEXT"), "returning from H preserves the readable testimony answer")
		await tap(KEY_ESCAPE)
		await tap(KEY_J)
		await tap(KEY_R)
		await tap(KEY_R)
		check(main.activity_panel.tab == 2 and main.activity_panel.entries.size() == 2, "people page contains both acquaintances")
		check(not main.activity_panel.heading.text.contains("未开放") and not main.activity_panel.heading.text.contains("unavailable"), "enabled people page is not labelled unavailable")
		await capture(locale+"_people")
		await tap(KEY_ESCAPE)
		check(app.current_context() == &"exploration", "journal restores exploration")
		check(main.region_label.text.contains("H ") and not main.region_label.text.contains("WORLD_"), "clock and H discoverable in HUD")
		# This test uses isolated directories only; a prior locale must not affect the next.
		saves.test_root = "user://tests/week7_world_ui_%s_%d" % [locale,Time.get_ticks_usec()]
		root.remove_child(main)
		main.free()
		app.reset_contexts()
	if failures.is_empty(): print("WEEK7_WORLD_UI_PASS checks=%d packed=%s captures=%d" % [checks,str(packed),captures])
	else: printerr("WEEK7_WORLD_UI_FAILED ", failures)
	quit(0 if failures.is_empty() else 1)
