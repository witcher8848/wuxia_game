extends SceneTree
## Real Main keyboard ownership from the title, both choices and investigation
## panels in both locales. Travel/nearby placements are explicit fixtures; the
## rescue uses legal deterministic combat commands, not human playtime evidence.
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Guide = preload("res://game/presentation/investigation/objective_guide.gd")
var checks := 0
var failures: Array[String] = []
var main: Node
var session: Node
var content: Node
var app: Node
var saves: Node
var capture_enabled := false
var captures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK8_BRANCH_UI_FAIL ", label)
	return ok

func frames(count: int = 2) -> void:
	for _index: int in count:
		await physics_frame
		await process_frame

func tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()

func capture(label: String) -> void:
	if not capture_enabled: return
	print("WEEK8_UI_TRACE capture_begin=",label)
	# Explicit native rendering avoids waiting indefinitely for a future draw
	# signal when the test window is occluded. This still reads the actual GPU
	# viewport; never substitute a mock or headless image for native evidence.
	await process_frame
	RenderingServer.force_draw(true)
	var folder := OS.get_environment("WUXIA_CAPTURE_DIR")
	if folder.is_empty(): folder = "res://builds/qa/week8"
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "capture directory")
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == Vector2i(640,360), "native logical viewport 640x360")
	check(image.save_png(folder.path_join("week8_"+label+".png")) == OK, "capture "+label)
	captures += 1
	print("WEEK8_UI_TRACE capture_done=",label)

func _start(lead: String, locale: String) -> void:
	saves.test_root = "user://tests/week8_ui_%s_%s_%d_%d" % [locale,lead,OS.get_process_id(),Time.get_ticks_usec()]
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	await tap(KEY_E)
	check(session.state.world_flags.get("FACT_W8_ACTIVE", false), "production title enables new opportunity")
	check(main.reading_panel.page == 0, "title enters original opening")
	for _page: int in 5: await tap(KEY_E)
	check(main.reading_panel.page == 5, "opening reaches index lesson")
	await tap(KEY_J)
	check(main.activity_panel.onboarding, "opening still teaches the journal")
	await tap(KEY_ESCAPE)
	await tap(KEY_DOWN)
	await tap(KEY_E)
	check(main.reading_panel.page == 6, "navigation choice follows original lesson")
	if lead == "dock": await tap(KEY_DOWN)
	await tap(KEY_E)
	check(app.current_context() == &"exploration", "opening restores exploration")
	check(not session.state.world_flags.has("CHOICE_CH01_FIRST_LEAD"), "navigation does not secretly commit")
	check(main.region_label.text.contains(TranslationServer.translate("W8_CLOCK_PROTOTYPE")), "technical daily clock is labelled a prototype")
	await capture(locale+"_"+lead+"_objective")

func _near(target: String) -> void:
	var region: Node = main.get_node("SceneHost").get_child(0)
	var point := Vector2(448,352)
	if target == "NPC_DOCK_WORKER":
		var npc: Dictionary = content.world_npc(session.state,target)["npc"]
		point = Vector2(npc["position"][0],npc["position"][1])
	region.player_position = point + Vector2(0,40)
	region.player.facing = "up"
	await frames()

func _travel(scene: String, target: String) -> void:
	if capture_enabled: print("WEEK8_UI_TRACE travel=",scene," target=",target)
	for _layer: int in 3:
		if app.current_context() != &"codex": break
		await tap(KEY_ESCAPE)
	if app.current_context() == &"dialogue": await tap(KEY_ESCAPE)
	check(session.enter_region(scene,"SPAWN_FROM_TOWN") == OK, "explicit travel fixture "+scene)
	check(main._enter_yard() == OK, "project actual region")
	await frames()
	await _near(target)
	await tap(KEY_E)
	check(app.current_context() == &"dialogue" and main.reading_panel.visible, "actual nearby E opens "+target)

func _dialogue_choice(identifier: String) -> bool:
	var panel: Node = main.reading_panel
	if capture_enabled: print("WEEK8_UI_TRACE dialogue=",panel.node_id," option=",identifier)
	for _attempt: int in panel.view["choices"].size():
		if panel.view["choices"][panel.cursor]["id"] == identifier:
			await tap(KEY_E)
			return true
		await tap(KEY_DOWN)
	check(false,"reachable keyboard dialogue choice "+panel.node_id+"/"+identifier)
	return false

func _entry(identifier: String) -> bool:
	var panel: Node = main.activity_panel
	if capture_enabled: print("WEEK8_UI_TRACE activity=",panel.mode," evidence=",identifier)
	for _attempt: int in panel.entries.size():
		if panel.entries[panel.cursor]["id"] == identifier:
			await tap(KEY_E)
			return true
		await tap(KEY_DOWN)
	check(false,"reachable keyboard evidence "+identifier)
	return false

func _branch_geometry() -> void:
	var panel: Node = main.activity_panel
	check(root.get_visible_rect().encloses(panel.get_global_rect()), "choice modal fits 640x360")
	check(panel.body.get_global_rect().end.y <= panel.choices[0].get_global_rect().position.y, "risk text scrolls without covering choices")
	check(panel.feedback.get_global_rect().end.y <= panel.hint.get_global_rect().position.y, "persistence feedback does not cover keyboard hints")
	check(panel.hint.get_theme_font("font").get_string_size(panel.hint.text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x <= 588, "complete localized choice controls fit")

func _commit(lead: String, locale: String, fail_save: bool) -> void:
	var old_node: String = main.reading_panel.node_id
	var old_cursor: int = main.reading_panel.cursor
	var before: Dictionary = session.state.to_dict()
	await tap(KEY_E)
	if not check(app.current_context() == &"codex" and main.activity_panel.mode == "branch", "first key evidence opens shared choice"): return
	_branch_geometry()
	check(not main.reading_panel.visible and session.state.to_dict() == before, "choice opening hides source without taking evidence")
	await capture(locale+"_"+lead+"_choice")
	if lead == "dock": await tap(KEY_DOWN)
	await tap(KEY_E)
	check(main.activity_panel.phase == "confirm" and main.activity_panel.cursor == 1, "irreversible confirmation defaults to cancel")
	_branch_geometry()
	check(session.state.to_dict() == before, "preview/anchor does not alter live route")
	check(not main.activity_panel.body.text.begins_with("W8_"), "translated known-risk summary")
	await capture(locale+"_"+lead+"_confirm")
	await tap(KEY_F5)
	await tap(KEY_D)
	check(session.state.to_dict() == before and not FileAccess.file_exists(saves.slot_path("quick")), "choice consumes movement and quicksave")
	await tap(KEY_E)
	check(main.activity_panel.phase == "choose", "second Enter safely backs out")
	await tap(KEY_ESCAPE)
	check(main.reading_panel.visible and main.reading_panel.node_id == old_node and main.reading_panel.cursor == old_cursor, "cancel restores exact source node and cursor")
	check(session.state.to_dict() == before, "cancel has no permanent effect")
	await tap(KEY_E)
	if lead == "dock": await tap(KEY_DOWN)
	await tap(KEY_E)
	if fail_save:
		# Real disk failure, confined to this test's empty automatic-slot paths.
		# Anchors remain readable, so confirmation itself can succeed first.
		for slot: String in ["auto_01","auto_02","auto_03"]:
			check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.slot_path(slot))) == OK, "block owned automatic destination "+slot)
	await tap(KEY_UP)
	await tap(KEY_E)
	check(session.state.world_flags.get("CHOICE_CH01_FIRST_LEAD",{}).get("choice") == lead, "one actual committed "+lead+" receipt")
	if fail_save:
		check(main.activity_panel.phase == "pending" and session.pending_branch_save(), "failed write reports actual committed pending result")
		var committed: Dictionary = session.state.to_dict()
		await tap(KEY_E)
		check(session.state.to_dict() == committed and main.activity_panel.phase == "pending", "failed retry never recommits or rolls back")
		await tap(KEY_ESCAPE)
		check(app.current_context() == &"codex" and main.activity_panel.visible, "Escape does not silently resume unsaved play")
		check(main.activity_panel.entries[1]["id"] == "title", "unsaved result has explicit safe title retreat")
		await capture(locale+"_"+lead+"_save_pending")
		for slot: String in ["auto_01","auto_02","auto_03"]:
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.slot_path(slot))) == OK, "remove only owned empty blocker "+slot)
		await tap(KEY_E)
	check(not session.pending_branch_save() and app.current_context() == &"dialogue" and main.reading_panel.visible, "successful save returns to updated entry")
	check(main.reading_panel.node_id == content.dialogue_entry(main.reading_panel.target_id,session.state), "success refreshes source entry")
	check(session.state.time_state == before["time_state"], "opportunity choice is not technical waiting")

func _investigate(lead: String) -> void:
	if lead == "home":
		await _dialogue_choice("inspect")
		check(session.state.evidence_states.has("EV_BLANK_DEATH_01"), "home receives the actual original")
		await _dialogue_choice("compare")
		await _entry("EV_INDEX_01")
		await _entry("EV_BLANK_DEATH_01")
		check(session.state.world_flags.get("FACT_YAMEN_FORMATION",false), "keyboard home comparison grants document intel")
		await tap(KEY_ESCAPE) # Clear first selection.
		await tap(KEY_ESCAPE)
		await _travel("SCENE_RIVER_DOCK","NPC_DOCK_WORKER")
		check(main.reading_panel.node_id == "D_W8_BOATMAN_QUESTIONED", "home route visibly loses immediate boatman cooperation")
		check(not session.state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false), "home knowledge is not personal ferry assistance")
	else:
		await _dialogue_choice("ask")
		await _dialogue_choice("token")
		await _dialogue_choice("challenge")
		await _entry("EV_FERRY_TOKEN_01")
		check(session.state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false), "keyboard challenge earns actual ferry commitment")
		await tap(KEY_ESCAPE)
		await _travel("SCENE_HOME_COURTYARD","DOC_HOME_NOTE")
		check(main.reading_panel.node_id == "D_W8_HOME_SEIZED", "dock route visibly finds confiscated home")
		check(not session.state.evidence_states.has("EV_BLANK_DEATH_01"), "confiscated original is not granted as a copy")
		await _travel("SCENE_RIVER_DOCK","NPC_DOCK_WORKER")

func _victory(lead: String, locale: String) -> void:
	await _dialogue_choice("journey")
	check(main.reading_panel.node_id == "D_JOURNEY", "same actual rescue briefing is reachable")
	await _dialogue_choice("depart")
	if not check(session.story_encounter_active() and app.current_context() == &"battle", "dialogue opens owned rescue encounter"): return
	var screen: Node = main.story_battle_screen
	screen.auto_ai = false
	check(screen.reveal_intent == (lead == "home") and screen.ferry_deployment == (lead == "dock"), "two branches have distinct actual tactical preparation")
	await capture(locale+"_"+lead+"_battle")
	await tap(KEY_E)
	for _turn: int in 180:
		if screen.battle.outcome != "ongoing": break
		var battle: CombatEncounter = screen.battle
		var actor: String = battle.current_actor_id()
		var plan: Dictionary = AI.plan(battle,actor)
		if not check(not plan.is_empty(), "legal rescue combat plan"): break
		if plan["destination"] != Grid.cell_of(battle.unit(actor)):
			check(battle.move_actor(actor,plan["destination"],battle.revision)["ok"], "legal rescue combat move")
		check(battle.perform_action(actor,plan["skill_id"],plan["target"],battle.revision)["ok"], "legal rescue combat action")
	check(screen.battle.outcome == "victory", "bounded legal combat reaches victory")
	screen.actor_changed()
	await frames()
	await tap(KEY_E)
	check(session.state.world_flags.get("FACT_GRAVES_SAFE",false), "actual keyboard settlement saves rescue")
	if app.current_context() == &"dialogue": await tap(KEY_ESCAPE)
	await _near("NPC_DOCK_WORKER")
	await tap(KEY_E)
	check(main.reading_panel.node_id == ("D_W8_AFTER_HOME" if lead == "home" else "D_W8_AFTER_DOCK"), "route-specific aftermath explains actual consequence")
	await capture(locale+"_"+lead+"_aftermath")
	var fail_followup_save: bool = lead == "home" and locale == "zh_CN"
	if fail_followup_save:
		for slot: String in ["auto_01","auto_02","auto_03"]:
			check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.slot_path(slot)+".tmp")) == OK, "owned post-action disk fixture "+slot)
	await _dialogue_choice("collect")
	check(main.reading_panel.node_id == "D_W8_GRAVES_FOUND", "grave records have an actual acquisition")
	if fail_followup_save:
		check(session.pending_branch_save() and main.reading_panel.feedback.text == TranslationServer.translate("W8_PROGRESS_SAVE_FAILED"), "committed collection failure is visible inside dialogue")
		var collected: Dictionary = session.state.to_dict()
		await tap(KEY_F5)
		check(session.pending_branch_save() and session.state.to_dict() == collected, "reading-panel F5 reaches a real failed save retry, not a new command")
		await capture(locale+"_"+lead+"_progress_pending")
		for slot: String in ["auto_01","auto_02","auto_03"]:
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.slot_path(slot)+".tmp")) == OK, "remove only owned post-action blocker "+slot)
		await tap(KEY_F5)
		check(not session.pending_branch_save() and session.state.to_dict() == collected, "dialogue F5 saves exactly the committed collection and clears pending")
		check(not FileAccess.file_exists(saves.slot_path("quick")), "pending retry uses actual automatic slot, not a fake quick-save acknowledgement")
	check(Guide.project(session.state)["key"] == "W8_OBJECTIVE_COMPARE", "acquisition updates next objective")
	# Evidence-page shortcuts must not send every record back to INQ_INDEX.
	await tap(KEY_ESCAPE)
	await tap(KEY_J)
	await tap(KEY_R)
	await _entry("EV_GRAVE_TAG_03")
	check(main.activity_panel.mode == "graves_compare" and main.activity_panel.first_selected == "EV_GRAVE_TAG_03", "journal record opens the matching grave comparison")
	await tap(KEY_ESCAPE) # First selection.
	await tap(KEY_ESCAPE) # Compare back to journal.
	await tap(KEY_ESCAPE) # Journal back to exploration.
	await _near("NPC_DOCK_WORKER")
	await tap(KEY_E)
	await _dialogue_choice("compare")
	check(main.activity_panel.mode == "graves_compare", "new compare activity uses grave inquiry")
	var before: Dictionary = session.state.to_dict()
	await _entry("EV_INDEX_01")
	await _entry("EV_GRAVE_TAG_03")
	check(session.state.to_dict() == before, "wrong grave comparison is free and honest")
	await tap(KEY_ESCAPE)
	await _entry("EV_GRAVE_TAG_03")
	await _entry("EV_BURIAL_PAGE_01")
	check(session.state.world_flags.get("FACT_BURIAL_MISMATCH",false), "actual grave comparison establishes mismatch")
	await capture(locale+"_"+lead+"_grave_compare")
	await tap(KEY_ESCAPE) # Clear first selection.
	await tap(KEY_ESCAPE)
	check(main.reading_panel.node_id == "D_W8_GRAVES_MATCHED", "compare returns to the new truthful entry")
	await _dialogue_choice("review")
	check(session.state.world_flags.get("FACT_W8_REVIEWED",false) and main.reading_panel.node_id == "D_W8_END", "review reaches next-case internal stop")
	check(not main.reading_panel.body.text.contains("\\n"), "actual aftermath paragraphs render line breaks")
	check(Guide.project(session.state)["key"] == "W8_OBJECTIVE_END", "end does not keep asking for finished action")
	await capture(locale+"_"+lead+"_end")
	await _late_supplement(lead)
	await tap(KEY_ESCAPE)
	await tap(KEY_J)
	for _page: int in 3: await tap(KEY_R)
	check(main.activity_panel.tab == 3 and main.activity_panel.entries.size() == 2, "route page contains own choice and rescue review")
	check(not main.activity_panel.heading.text.contains("未开放") and not main.activity_panel.heading.text.contains("unavailable"), "implemented route records are not titled unavailable")
	check(not main.activity_panel.body.text.contains("W8_"), "route record is localized")
	before = session.state.to_dict()
	await tap(KEY_E)
	check(session.state.to_dict() == before and main.activity_panel.mode == "journal", "route confirm does not open final recollection or replay reward")
	await capture(locale+"_"+lead+"_routes")
	await tap(KEY_ESCAPE)

func _late_supplement(lead: String) -> void:
	var before_time: Dictionary = session.state.time_state.duplicate(true)
	var before_relationships: Dictionary = session.state.relationships.duplicate(true)
	var before_resolution: Dictionary = session.state.quest_states["QUEST_RESCUE_GRAVEKEEPER"]["resolution"].duplicate(true)
	await _dialogue_choice("supplement")
	if lead == "home":
		check(main.reading_panel.node_id == "D_W8_SUPPLEMENT_HOME", "end still exposes real boatman follow-up")
		await _dialogue_choice("record")
		check(main.reading_panel.node_id == "D_W8_SUPPLEMENT_RECORDED", "actual late record button uses dedicated completed-quest command")
		check(session.state.evidence_states.get("CL_BOATMAN_01",{}).get("knowledge_state") == "doubt" and session.state.evidence_states.get("EV_FERRY_TOKEN_01",{}).get("knowledge_state") == "fact", "late testimony and token retain honest knowledge")
		check(session.state.world_flags.get("FACT_FERRY_ROUTE",false) and not session.state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false), "late true route cannot rewrite missed personal deployment")
		await _dialogue_choice("back")
		await _dialogue_choice("supplement")
		var before: Dictionary = session.state.to_dict()
		await _dialogue_choice("record")
		check(session.state.to_dict() == before, "repeated late record cannot farm a second settlement")
	else:
		check(main.reading_panel.node_id == "D_W8_HOME_FOLLOWUP_GUIDE", "end guides actual travel instead of granting a remote home reward")
		check(not main.reading_panel.view["choices"].any(func(option: Dictionary) -> bool: return option["command"] == "STEP_W8_SUPPLEMENT"), "dock guidance does not offer remote extract collection")
		# The source is the home desk, not a remote dock reward. Travel/placement
		# is an explicit fixture; retrieval itself remains a real keyboard command.
		await _travel("SCENE_HOME_COURTYARD","DOC_HOME_NOTE")
		await _dialogue_choice("supplement")
		check(main.reading_panel.node_id == "D_W8_HOME_EXTRACT" and session.state.evidence_states.has("EV_HOME_EXTRACT_01"), "actual home follow-up acquires sourced extract")
		check(not session.state.evidence_states.has("EV_BLANK_DEATH_01") and not session.state.world_flags.get("FACT_YAMEN_FORMATION",false), "extract neither replaces original nor retroactively adds formation intel")
		await _dialogue_choice("back")
		var before: Dictionary = session.state.to_dict()
		await _dialogue_choice("supplement")
		check(session.state.to_dict() == before, "repeated extract retrieval cannot farm another settlement")
	check(session.state.time_state == before_time and session.state.relationships == before_relationships, "follow-up does not charge time or duplicate rescue trust")
	check(session.state.quest_states["QUEST_RESCUE_GRAVEKEEPER"]["resolution"] == before_resolution, "follow-up never rewrites the completed battle receipt")

func _direct_departure_retreat() -> void:
	await _start("dock","zh_CN")
	await _travel("SCENE_RIVER_DOCK","NPC_DOCK_WORKER")
	await _dialogue_choice("journey")
	check(main.reading_panel.node_id == "D_JOURNEY" and session.branch_required(), "no-intel briefing remains reachable before taking a side")
	await _dialogue_choice("depart")
	check(app.current_context() == &"codex" and main.activity_panel.mode == "branch" and not session.story_encounter_active(), "direct departure cannot bypass shared commitment")
	await tap(KEY_E) # Preview home without taking home evidence.
	for slot: String in ["auto_01","auto_02","auto_03"]:
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.slot_path(slot))) == OK, "owned pending-retreat disk fixture "+slot)
	await tap(KEY_UP)
	await tap(KEY_E)
	check(main.activity_panel.phase == "pending" and session.pending_branch_save(), "retreat test really reaches unsaved confirmed result")
	var before: Dictionary = session.state.to_dict()
	await tap(KEY_DOWN)
	await capture("zh_CN_unsaved_title_retreat")
	await tap(KEY_E)
	check(main._menu_kind == &"title" and main.menu.visible and main.get_node("SceneHost").get_child_count() == 0, "pending result has a normal keyboard return to title")
	check(app.current_context() == &"system_menu" and not main.activity_panel.visible, "title retreat restores input ownership")
	check(session.state.to_dict() == before and not FileAccess.file_exists(saves.slot_path("quick")), "retreat does not rewrite live receipt or overwrite old quick slot")
	check(FileAccess.file_exists(saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")), "title retreat preserves immutable anchor")
	root.remove_child(main)
	main.free()
	app.reset_contexts()
	session.start_new_game()
	await frames()

func _world_save_retry() -> void:
	await tap(KEY_H)
	check(main.world_panel.visible, "new route still opens actual world panel")
	await tap(KEY_E)
	check(main.world_panel.confirmation and main.world_panel.body.text.contains(TranslationServer.translate("W8_WORLD_AUTOSAVE")), "W8 world confirmation explains real automatic-save semantics")
	for slot: String in ["auto_01","auto_02","auto_03"]:
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.slot_path(slot)+".tmp")) == OK, "owned world-action disk fixture "+slot)
	var before_clock: Dictionary = session.state.time_state.duplicate(true)
	await tap(KEY_DOWN)
	await tap(KEY_E)
	check(session.pending_branch_save() and session.state.time_state != before_clock, "world action is committed exactly once before failed write")
	check(main.world_panel.feedback.text == TranslationServer.translate("W8_PROGRESS_SAVE_FAILED"), "world failure is visibly unsaved, not successful persistence")
	var committed: Dictionary = session.state.to_dict()
	await tap(KEY_F5)
	check(session.pending_branch_save() and session.state.to_dict() == committed, "world panel F5 reaches failed persistence retry without advancing time")
	await capture("zh_CN_home_world_pending")
	for slot: String in ["auto_01","auto_02","auto_03"]:
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.slot_path(slot)+".tmp")) == OK, "remove only owned world-action blocker "+slot)
	await tap(KEY_F5)
	check(not session.pending_branch_save() and session.state.to_dict() == committed, "world-panel F5 retries the same result and clears pending")
	check(not main.world_panel.feedback.text.contains("尚未保存") and not main.world_panel.feedback.text.contains("not saved"), "world success no longer falsely claims no save")
	await tap(KEY_ESCAPE)
	check(app.current_context() == &"exploration", "world retry returns to ordinary exploration")

func _run() -> void:
	create_timer(150).timeout.connect(func() -> void: printerr("WEEK8_BRANCH_UI_FAIL watchdog"); quit(124))
	await frames()
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	app = root.get_node("App")
	saves = root.get_node("SaveService")
	if not check(content.last_error.is_empty(), "content preflight: "+content.last_error):
		quit(1)
		return
	for locale: String in ["zh_CN","en"]:
		TranslationServer.set_locale(locale)
		for key: String in ["W8_CHOICE_RESULT_SAVE_FAILED","W8_WORLD_AUTOSAVE"]:
			check(TranslationServer.translate(key) != key, "imported locale preflight "+locale+"/"+key)
	if not failures.is_empty():
		quit(1)
		return
	capture_enabled = "--capture-week8" in OS.get_cmdline_user_args()
	check(not capture_enabled or DisplayServer.get_name() != "headless", "captures require native renderer")
	var packed := "--require-pack" in OS.get_cmdline_user_args()
	check(not packed or FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "packed test has no source overlay")
	for locale: String in ["zh_CN","en"]:
		TranslationServer.set_locale(locale)
		for lead: String in ["home","dock"]:
			await _start(lead,locale)
			await _travel("SCENE_HOME_COURTYARD" if lead == "home" else "SCENE_RIVER_DOCK", "DOC_HOME_NOTE" if lead == "home" else "NPC_DOCK_WORKER")
			await _commit(lead,locale,locale == "zh_CN" and lead == "home")
			await _investigate(lead)
			await _victory(lead,locale)
			if locale == "zh_CN" and lead == "home": await _world_save_retry()
			main._return_to_title()
			root.remove_child(main)
			main.free()
			app.reset_contexts()
			await frames()
	TranslationServer.set_locale("zh_CN")
	await _direct_departure_retreat()
	saves.test_root = ""
	if failures.is_empty(): print("WEEK8_BRANCH_UI_PASS checks=%d packed=%s captures=%d (keyboard UI; fixture travel; legal scripted combat; not human UX/time)" % [checks,str(packed),captures])
	else: printerr("WEEK8_BRANCH_UI_FAILED ",failures)
	quit(0 if failures.is_empty() else 1)
