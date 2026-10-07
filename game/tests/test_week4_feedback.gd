extends SceneTree
var main: Node
var session: Node
var checks := 0
var failures: Array[String] = []
var captures := false

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FEEDBACK_FAIL ", label)

func _tap(code: Key, echo := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.echo = echo and pressed
		Input.parse_input_event(event)
		await process_frame
		await physics_frame

func _capture(label: String) -> void:
	if not captures: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	check(root.get_texture().get_image().save_png("res://builds/qa/feedback_" + label + ".png") == OK, "capture " + label)

func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	captures = "--capture-feedback" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported resources without source overlay")
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for fast: bool in [false, true]:
			main._start_game()
			await process_frame
			if fast:
				for _index: int in 8: await _tap(KEY_SPACE, true)
				check(main.reading_panel.page == 5, "held fast read stops at journal decision")
			var before: Dictionary = session.state.to_dict()
			var prior_page: int = main.reading_panel.page
			await _tap(KEY_TAB)
			check(main.reading_panel.skip_pending and main.reading_panel.cursor == 1, "skip requires confirmation with safe default")
			await _capture(locale + "_skip")
			await _tap(KEY_SPACE, true)
			check(session.state.to_dict() == before, "fast read cannot confirm skip")
			await _tap(KEY_E)
			check(not main.reading_panel.skip_pending and main.reading_panel.page == prior_page, "default keeps current passage")
			await _tap(KEY_TAB)
			await _tap(KEY_ESCAPE)
			check(session.state.to_dict() == before, "cancel skip changes nothing")
			await _tap(KEY_TAB)
			await _tap(KEY_UP)
			await _tap(KEY_E)
			check(main.reading_panel.page == 6, "confirmed skip stops at route selection")
			check(session.state.evidence_states.size() == 1 and session.state.evidence_states.has("EV_INDEX_01"), "skip only acquires index once")
			check(session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "available", "skip does not choose route or accept search")
			before = session.state.to_dict()
			await _tap(KEY_SPACE, true)
			check(session.state.to_dict() == before and main.reading_panel.page == 6, "holding Space never chooses a route")
			await _tap(KEY_E)
			check(root.get_node("App").current_context() == &"exploration", "explicit first-lead choice still works after skip")
			main._return_to_title()
		for home: bool in [false, true]:
			for dock: bool in [false, true]:
				session.start_new_game()
				for step: String in ["STEP_RECEIVE_INDEX", "STEP_ACCEPT_SEARCH"]: session.apply_investigation_step(step)
				if home:
					session.apply_investigation_step("STEP_INSPECT_BLANK")
					session.resolve_inquiry("INQ_INDEX", ["EV_INDEX_01", "EV_BLANK_DEATH_01"])
				if dock:
					session.apply_investigation_step("STEP_RECORD_BOATMAN")
					session.apply_investigation_step("STEP_TAKE_FERRY_TOKEN")
					session.resolve_inquiry("INQ_BOATMAN", ["EV_FERRY_TOKEN_01"])
				session.enter_region("SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN")
				main._enter_yard()
				var region: Node = main.get_node("SceneHost").get_child(0)
				region.player.position = Vector2(704, 396)
				region.player.facing = "up"
				await physics_frame
				await _tap(KEY_E)
				var before: Dictionary = session.state.to_dict()
				var node_before: String = main.reading_panel.node_id
				await _tap(KEY_SPACE, true)
				check(session.state.to_dict() == before and main.reading_panel.node_id == node_before, "dialogue fast read does not select or grant intel")
				await _tap(KEY_TAB)
				check(session.state.to_dict() == before and not main.reading_panel.visible, "dialogue skip closes without issuing commands")
				await _tap(KEY_E)
				for _index: int in (1 if dock else 3): await _tap(KEY_DOWN)
				await _tap(KEY_E)
				check(main.reading_panel.node_id == "D_JOURNEY", "actual dialogue reaches departure")
				await _tap(KEY_SPACE, true)
				check(not session.story_encounter_active(), "fast read cannot start battle")
				await _tap(KEY_E)
				var screen: Node = main.story_battle_screen
				check(screen.briefing.visible, "arrival requires acknowledgment")
				check(screen.briefing_body.text.contains(TranslationServer.translate("BATTLE_INTEL_HOME" if home else "BATTLE_NO_HOME")), "briefing matches actual home flag")
				check(screen.briefing_body.text.contains(TranslationServer.translate("BATTLE_INTEL_DOCK" if dock else "BATTLE_NO_DOCK")), "briefing matches actual dock flag")
				check(session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "changed" and session.state.quest_states["QUEST_RESCUE_GRAVEKEEPER"]["status"] == "active", "displayed quest transition actually occurred")
				var snap: Dictionary = screen.battle.snapshot()
				await _tap(KEY_F)
				await _tap(KEY_R)
				await _tap(KEY_SPACE, true)
				check(screen.battle.snapshot() == snap and screen.mode == "command", "briefing consumes combat shortcuts")
				await _capture(locale + "_arrival_%s_%s" % [home, dock])
				await _tap(KEY_E)
				check(not screen.briefing.visible and screen.battle.snapshot() == snap, "closing briefing spends no action")
				await _tap(KEY_F)
				check(screen.menu.text.contains("住所校勘情报") == home, "earned forecast shown immediately by F")
				await _capture(locale + "_forecast_%s_%s" % [home, dock])
				var cursor_before: Vector2i = screen.cursor
				await _tap(KEY_F1)
				check(screen.briefing.visible, "F1 reopens cause and intel from inspector")
				check(screen.briefing_body.text.contains("守势：减伤2") and screen.briefing_body.text.contains("普攻回内力1"), "existing F1 combat rules retained below intel")
				await _tap(KEY_TAB)
				check(screen.mode == "inspect" and screen.cursor == cursor_before and screen.battle.snapshot() == snap, "review preserves cursor mode and combat")
				await _tap(KEY_ESCAPE)
				# Real legal ally actions reach an enemy turn; briefing must pause AI.
				screen.auto_ai = false
				for _turn: int in 2:
					var actor: String = screen.battle.current_actor_id()
					var unit: Dictionary = screen.battle.unit(actor)
					check(screen.battle.perform_action(actor, "ACT_BREATH", BattleGrid.cell_of(unit), screen.battle.revision)["ok"], "legal ally action reaches enemy")
				screen.actor_changed()
				check(screen.battle.unit(screen.battle.current_actor_id())["team"] == "enemy", "enemy genuinely pending")
				await _tap(KEY_F1)
				snap = screen.battle.snapshot()
				screen.auto_ai = true
				screen._process(2.0)
				check(screen.battle.snapshot() == snap, "AI remains paused while reading briefing")
				await _tap(KEY_E)
				screen._process(2.0)
				check(screen.battle.snapshot() != snap, "AI resumes after briefing closes")
				main._abort_story_battle()
				check(not session.story_encounter_active(), "abort still restores prebattle state")
				main._return_to_title()
	root.remove_child(main)
	main.queue_free()
	await process_frame
	print("WEEK4_FEEDBACK: %d checks, %d failures (simulated input; not human acceptance)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
