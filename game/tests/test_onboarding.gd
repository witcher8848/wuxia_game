extends SceneTree
const Guide = preload("res://game/presentation/investigation/objective_guide.gd")
var checks := 0
var failures: Array[String] = []
var main: Node
var session: Node
var app: Node
var captures := false

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ONBOARDING_FAIL ", label)

func _frames(count: int = 3) -> void:
	for _index: int in count: await process_frame

func _tap(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()

func _capture(label: String) -> void:
	if not captures: return
	print("ONBOARDING_CAPTURE_BEGIN ",label)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/onboarding_" + label + ".png") == OK, "capture " + label)
	print("ONBOARDING_CAPTURE_SAVED ",label)

func _run() -> void:
	create_timer(60).timeout.connect(func() -> void: printerr("ONBOARDING_FAIL watchdog"); quit(1))
	await _frames()
	captures = "--capture-onboarding" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "pack without source overlay")
	session = root.get_node("GameSession")
	app = root.get_node("App")
	var saves: Node = root.get_node("SaveService")
	saves.test_root = "user://tests/onboarding_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for lead: String in ["home", "dock"]:
			main = load("res://game/presentation/main.tscn").instantiate()
			# Preserve the complete legacy two-lead teaching regression explicitly;
			# Week 8's production mutual-exclusion flow has its own keyboard test.
			main.week8_enabled = false
			root.add_child(main)
			await _frames()
			await _tap(KEY_E) # Actual title button, not a fixture entry.
			check(app.current_context() == &"dialogue" and main.reading_panel.page == 0, "new game enters prologue")
			var position: Vector2 = main.get_node("SceneHost").get_child(0).player_position
			await _tap(KEY_D)
			await _tap(KEY_F5)
			check(main.get_node("SceneHost").get_child(0).player_position == position, "opening blocks movement")
			check(main._save_game() == ERR_UNAVAILABLE, "cannot save an incomplete prologue")
			await _tap(KEY_ESCAPE)
			check(main.reading_panel.page == 0, "escape does not silently drop player into town")
			for page: int in 6:
				check(main.reading_panel.page == page, "sequential opening page %d" % page)
				check(not main.reading_panel.body.text.begins_with("INTRO_"), "translated opening")
				check(not main.reading_panel.body.text.contains("\\n"), "rendered paragraph breaks")
				if lead == "home": await _capture(locale + "_page%d" % page)
				if page < 5: await _tap(KEY_E)
			check(session.state.evidence_states.has("EV_INDEX_01"), "index is acquired in the hall")
			check(session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "available", "search offered before leaving")
			var before: Dictionary = session.state.to_dict()
			await _tap(KEY_J)
			check(app.current_context() == &"codex" and main.activity_panel.onboarding, "J opens contextual journal introduction")
			check(main.activity_panel.entries.size() == 1, "only current task shown")
			if lead == "home": await _capture(locale + "_journal")
			await _tap(KEY_R)
			check(main.activity_panel.entries.size() == 1 and main.activity_panel.entries[0]["id"] == "EV_INDEX_01", "index visible in evidence page")
			await _tap(KEY_R)
			check(main.activity_panel.tab == 0, "cycle only usable tabs")
			await _tap(KEY_ESCAPE)
			check(app.current_context() == &"dialogue" and main.reading_panel.page == 5, "journal returns to exact opening passage")
			check(session.state.to_dict() == before, "reading journal changes no permanent state")
			await _tap(KEY_DOWN)
			await _tap(KEY_E)
			check(main.reading_panel.page == 6, "route choice follows journal lesson")
			if lead == "dock": await _tap(KEY_DOWN)
			await _tap(KEY_E)
			check(app.current_context() == &"exploration", "departure restores exploration")
			check(session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "active", "departure activates search")
			check(session.state.world_flags.get("FACT_FIRST_" + lead.to_upper(), false), "first lead persisted")
			check(Guide.project(session.state)["target"] == ("EXIT_STREET_HOME" if lead == "home" else "EXIT_STREET_DOCK"), "HUD guides chosen exit")
			check(main.objective_label.visible and not main.objective_label.text.is_empty(), "persistent objective visible")
			await _capture(locale + "_hud_" + lead)
			check(main._save_game() == OK, "save after introduction")
			var saved_route: String = session.state.route_id
			session.start_new_game()
			main._load_game("quick")
			check(session.state.route_id == saved_route, "real save restores original route")
			check(session.state.world_flags.get("FACT_FIRST_" + lead.to_upper(), false), "loaded choice retained")
			check(app.current_context() == &"exploration" and not main.reading_panel.visible, "load does not replay prologue")
			# Either lead remains reachable regardless of the original selection.
			session.enter_region("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN")
			check(Guide.project(session.state)["target"] == "DOC_HOME_NOTE", "home route not locked")
			session.apply_investigation_step("STEP_INSPECT_BLANK")
			check(Guide.project(session.state)["key"] == "GUIDE_COMPARE", "home clue updates objective")
			session.resolve_inquiry("INQ_INDEX", ["EV_INDEX_01", "EV_BLANK_DEATH_01"])
			check(Guide.project(session.state)["target"] == "EXIT_HOME_STREET", "home solution guides back to town")
			session.enter_region("SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN")
			main._enter_yard()
			await _frames()
			var region: Node = main.get_node("SceneHost").get_child(0)
			region.player_position = Vector2(704, 392)
			region.player.facing = "up"
			await physics_frame
			await _tap(KEY_E)
			check(main.reading_panel.node_id == "D_DOCK", "boatman starts with actionable dialogue after prologue")
			await _tap(KEY_E)
			check(main.reading_panel.node_id == "D_BOAT", "question records testimony")
			if lead == "dock": await _capture(locale + "_challenge_lesson")
			await _tap(KEY_DOWN) # challenge
			await _tap(KEY_E)
			check(main.activity_panel.mode == "challenge", "real dialogue opens evidence challenge")
			before = session.state.to_dict()
			await _tap(KEY_E) # Index cannot refute the claim.
			check(session.state.to_dict() == before, "wrong evidence has no cost or reward")
			await _tap(KEY_ESCAPE)
			check(main.reading_panel.node_id == "D_BOAT", "failed challenge returns to testimony")
			await _tap(KEY_DOWN) # token
			await _tap(KEY_E)
			check(main.reading_panel.node_id == "D_TOKEN", "can investigate instead of exhausting items")
			await _tap(KEY_DOWN)
			await _tap(KEY_E)
			var panel: Control = main.activity_panel
			for _attempt: int in panel.entries.size():
				if panel.entries[panel.cursor]["id"] == "EV_FERRY_TOKEN_01": break
				await _tap(KEY_DOWN)
			await _tap(KEY_E)
			check(session.state.world_flags.get("FACT_FERRY_ROUTE", false), "successful challenge grants actual tactical route")
			check(panel.message_key == "INV_BOATMAN_ADMITS", "success explains testimony location and tactical payoff")
			if lead == "dock": await _capture(locale + "_challenge_success")
			await _tap(KEY_ESCAPE)
			check(main.reading_panel.node_id == "D_DOCK_ADMITS", "success returns to updated testimony")
			await _tap(KEY_ESCAPE)
			check(Guide.project(session.state)["key"] == "GUIDE_DEPART", "next action is departure")
			main._return_to_title()
			root.remove_child(main)
			main.queue_free()
			await _frames()
	print("ONBOARDING: %d checks, %d failures (simulated keyboard; not human UX acceptance)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
