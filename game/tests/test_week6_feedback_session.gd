extends SceneTree
## Production ContentDB + real Main M keyboard + owned story adapter.
## Public investigation commands unlock the real route; no fake combat data,
## Combat.configure(), battle-unit mutation or injected combat result is used.
const MAIN := "res://game/presentation/main.tscn"
const IO = preload("res://game/persistence/save_file_io.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
const A := "CHAR_PROTAGONIST"
var checks := 0
var failures: Array[String] = []
var main: Node
var session: Node
var content: Node
var saves: Node
var app: Node
var fixture := ""
var phase := ""
var packed := false


func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: printerr("WEEK6_FEEDBACK_SESSION_FAIL watchdog"); quit(124))
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK6_FEEDBACK_SESSION_FAIL ",label)
	return ok


static func same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func step(frames := 2) -> void:
	for _index in range(frames):
		await physics_frame
		await process_frame


func key_state(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func tap(code: Key) -> void:
	key_state(code,true)
	await step(1)
	key_state(code,false)
	await step(1)


func region() -> Node:
	return main.get_node("SceneHost").get_child(0)


func walk_axis(axis: int, destination: float) -> bool:
	var code: Key = (KEY_D if destination > region().player_position[axis] else KEY_A) if axis == 0 else (KEY_S if destination > region().player_position[axis] else KEY_W)
	var previous_distance := INF
	var stalled := 0
	for _index in range(300):
		var distance: float = absf(destination-region().player_position[axis])
		if distance <= 2.0:
			key_state(code,false)
			await step()
			return true
		var desired: Key = (KEY_D if destination > region().player_position[axis] else KEY_A) if axis == 0 else (KEY_S if destination > region().player_position[axis] else KEY_W)
		if desired != code: key_state(code,false); code = desired
		key_state(code,true)
		await step(1)
		stalled = stalled+1 if distance == previous_distance else 0
		previous_distance = distance
		if stalled > 20: break
	key_state(code,false)
	return check(false,"bounded physical dock approach stalled")


func approach_boatman() -> void:
	if region().choose_target().get("id","") == "NPC_DOCK_WORKER": return
	# The real dock's crates occupy the northern edge. Use the clear southern
	# lane, then a real short facing pulse; never teleport the player.
	if not await walk_axis(1,384): return
	if not await walk_axis(0,704): return
	await tap(KEY_W)
	check(region().choose_target().get("id","") == "NPC_DOCK_WORKER","physical movement/facing selects the actual registered boatman")


func choose(identifier: String) -> bool:
	for _index in range(5):
		if main.reading_panel.view["choices"][main.reading_panel.cursor]["id"] == identifier:
			await tap(KEY_E)
			return true
		await tap(KEY_DOWN)
	return check(false,"real dialogue keyboard can select "+identifier)


func start_normal_story() -> Dictionary:
	await approach_boatman()
	check(main._save_game("manual_04") == OK,"sync legitimate current exploration position before story")
	var before: Dictionary = session.state.to_dict()
	await tap(KEY_E)
	if not check(app.current_context() == &"dialogue" and is_instance_valid(main.reading_panel),"actual E opens boatman dialogue"): return {}
	if not await choose("journey"): return {}
	if not check(main.reading_panel.node_id == "D_JOURNEY","real dialogue reaches registered departure node"): return {}
	if not await choose("depart"): return {}
	if not check(is_instance_valid(main.story_battle_screen) and session.story_encounter_active() and app.current_context() == &"battle","actual dialogue opens the owned production story battle"): return {}
	return before


func check_story_rules(battle: CombatEncounter, prepared: bool) -> void:
	check(battle.unit_ids().size() == 4 and battle.objective == {"kind":"eliminate"},"original story retains two enemies and strict clear objective")
	check(battle.skill("SK_YUE_THRUST")["qi_cost"] == (2 if prepared else 1),"actual story selects correct variant thrust cost")
	check(battle.skill("SK_YUE_THRUST")["distance_bonus"] == (3 if prepared else 1),"actual story selects correct variant distance incentive")
	check(battle.skill("SK_YUE_CROSSCUT")["area_pattern"] == ("front_arc" if prepared else "single"),"actual story selects true area sweep only after confirmed preparation")
	check(battle.skill("ACT_BREATH")["effects"] == ([] if prepared else ["guard"]),"actual story recovery/protection distinction follows selected table")
	check(battle.skill("SK_TRIP_WRIST").get("broken_mode","") == ("next_hit" if prepared else ""),"actual story break window is tactical only when explicitly prepared")
	check(battle.unit(A).has("loadout") == prepared and not battle.unit("CHAR_COMPANION").has("loadout"),"only explicitly prepared hero receives loadout, companion remains fixed")
	if prepared:
		check(battle.unit(A)["loadout"] == session.state.martial_states["loadout"],"persistent M choice is the actual story hero kit")
		check(battle.unit(A)["max_qi"] == 3 and battle.action_restore_qi(A,"SK_FIST_BASIC") == 0 and battle.action_restore_qi(A,"ACT_BREATH") == 1,"actual no-inner story uses 3/0/1 cycle, not legacy flat values")
	var forecast := battle.forecast_turn(A)
	check(forecast != null,"actual story provides disposable hero forecast")
	if forecast == null: return
	var before := battle.snapshot()
	check(Text.resource_help(forecast,A).contains("不减伤") == prepared,"production resource help accurately distinguishes tactical recovery")
	check(Text.skill_type(forecast.skill("ACT_BREATH")) == ("恢复" if prepared else "恢复／防御"),"production hover category is not falsely defensive")
	check(Text.status_help(forecast).contains("下一击") == prepared,"production rules text matches chosen break lifetime")
	check(Text.skill_detail(forecast,A,"SK_YUE_CROSSCUT").contains("前排3格") == prepared,"production skill shape text matches actual story variant")
	check(battle.snapshot() == before,"all actual story UI queries remain read-only")


func abort_and_close(before: Dictionary) -> void:
	main._abort_story_battle()
	await step()
	check(not session.story_encounter_active() and same(session.state.to_dict(),before),"owned abort restores exact prepared/legacy route state")
	await tap(KEY_ESCAPE)
	check(app.current_context() == &"exploration","return from story preserves exploration context")


func write_flow() -> Dictionary:
	session.start_new_game()
	for identifier: String in ["STEP_RECEIVE_INDEX","STEP_ACCEPT_SEARCH","STEP_INSPECT_BLANK"]:
		check(session.apply_investigation_step(identifier)["error"] == OK,"public production investigation command "+identifier)
	check(session.resolve_inquiry("INQ_INDEX",["EV_INDEX_01","EV_BLANK_DEATH_01"])["error"] == OK,"real inquiry unlocks accepted route")
	check(session.enter_region("SCENE_RIVER_DOCK","SPAWN_FROM_TOWN") == OK and session.mark_inspected("NPC_DOCK_WORKER") == OK,"registered production dock/boatman are legal")
	check(main._enter_yard() == OK,"normal Main enters real current exploration scene")
	await step()
	await approach_boatman()
	check(main._save_game("manual_01") == OK,"actual Main saves untouched schema1 martial slot")
	var legacy: Dictionary = session.state.to_dict()
	var legacy_sha := FileAccess.get_sha256(saves.slot_path("manual_01"))
	check(legacy["martial_states"] == {"mastery":{},"loadout":{}},"legacy persistent martial state is still raw empty")
	await tap(KEY_M)
	check(main.martial_panel.visible and main.martial_panel.skills["SK_YUE_THRUST"]["qi_cost"] == 2 and main.martial_panel.skills["SK_YUE_CROSSCUT"]["area_pattern"] == "front_arc","actual M uses production tactical definitions, not a special test seed")
	await tap(KEY_LEFT)
	await tap(KEY_ESCAPE)
	check(same(session.state.to_dict(),legacy) and FileAccess.get_sha256(saves.slot_path("manual_01")) == legacy_sha,"merely viewing/cancelling M neither upgrades old state nor rewrites disk")
	var before := await start_normal_story()
	if before.is_empty(): return {}
	check_story_rules(main.story_battle_screen.battle,false)
	await abort_and_close(before)
	await tap(KEY_M)
	await tap(KEY_LEFT)
	await tap(KEY_DOWN)
	await tap(KEY_LEFT)
	for _index in range(3): await tap(KEY_DOWN)
	await tap(KEY_RIGHT)
	check(main.martial_panel.selected_id().is_empty(),"keyboard deliberately removes internal without auto-fill")
	await tap(KEY_E)
	var custom: Dictionary = session.state.to_dict()
	var without_change: Dictionary = legacy.duplicate(true)
	without_change["martial_states"] = custom["martial_states"].duplicate(true)
	check(same(custom,without_change),"actual M confirmation changes only martial state")
	check(custom["martial_states"]["loadout"] == {"external":["SK_TRIP_WRIST","SK_YUE_THRUST","SK_YUE_CROSSCUT"],"movement":"SK_WATER_STEP","internal":""},"normal keyboard applies an intentionally alternate three-slot kit")
	await tap(KEY_ESCAPE)
	await tap(KEY_F5)
	var stored: Dictionary = saves.load_game("quick",false)
	check(stored["error"] == OK and same(stored["state"].to_dict(),custom),"normal F5 really persists all state of chosen tactical kit")
	var custom_sha := FileAccess.get_sha256(saves.slot_path("quick"))
	before = await start_normal_story()
	if before.is_empty(): return {}
	var battle: CombatEncounter = main.story_battle_screen.battle
	check_story_rules(battle,true)
	var initial := battle.snapshot()
	var staged: Dictionary = session.state.to_dict()
	check(saves.save_game("quick",session.state) == ERR_BUSY and FileAccess.get_sha256(saves.slot_path("quick")) == custom_sha,"active tactical story cannot replace actual saved slot")
	check(session.set_martial_loadout(custom["martial_states"]["loadout"]) == ERR_BUSY and session.state.to_dict() == staged,"story lock blocks real preparation confirmation")
	var actor := battle.current_actor_id()
	check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"],"actual story action uses its own tactical table")
	check(not battle.unit(actor)["statuses"].has("guard"),"tactical breathing does not silently apply old guard during real story")
	main._retry_story_battle()
	var retried := battle.snapshot()
	retried["revision"] = initial["revision"]
	check(retried == initial and session.state.to_dict() == staged,"normal owned retry restores chosen table/resources without world mutation")
	await abort_and_close(before)
	check(same(session.state.to_dict(),custom) and FileAccess.get_sha256(saves.slot_path("quick")) == custom_sha and FileAccess.get_sha256(saves.slot_path("manual_01")) == legacy_sha,"real tactical story attempt does not contaminate either persisted route")
	var expected := {"legacy":legacy,"legacy_sha":legacy_sha,"custom":custom,"custom_sha":custom_sha,"writer_pid":OS.get_process_id()}
	check(IO.write_text(fixture.path_join("expected.json"),JSON.stringify(expected)) == OK,"isolated expected snapshots emitted for optional independent cold reader")
	return expected


func read_flow(expected: Dictionary, cold: bool) -> void:
	if cold:
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("write_receipt.json")))
		check(receipt is Dictionary and receipt.get("failures",["missing"]).is_empty() and int(receipt.get("pid",0)) == int(expected["writer_pid"]) and int(expected["writer_pid"]) != OS.get_process_id(),"successful writer and cold reader have distinct actual process identities")
	check(not session.combat_active(),"transient ownership is absent before reload")
	main._load_game("manual_01")
	await step()
	check(same(session.state.to_dict(),expected["legacy"]) and session.state.martial_states == {"mastery":{},"loadout":{}},"actual Main restores entire legacy route without silent new preparation")
	await tap(KEY_M)
	await tap(KEY_ESCAPE)
	check(same(session.state.to_dict(),expected["legacy"]),"loaded legacy M view still does not persist seeded configuration")
	var before := await start_normal_story()
	if before.is_empty(): return
	check_story_rules(main.story_battle_screen.battle,false)
	await abort_and_close(before)
	main._load_game("quick")
	await step()
	check(same(session.state.to_dict(),expected["custom"]),"actual Main restores complete selected tactical route from disk")
	before = await start_normal_story()
	if before.is_empty(): return
	check_story_rules(main.story_battle_screen.battle,true)
	await abort_and_close(before)
	check(same(session.state.to_dict(),expected["custom"]) and FileAccess.get_sha256(saves.slot_path("quick")) == expected["custom_sha"] and FileAccess.get_sha256(saves.slot_path("manual_01")) == expected["legacy_sha"],"cold or warm actual story probes preserve both saved bytes and every route field")


func _run() -> void:
	await process_frame
	TranslationServer.set_locale("zh_CN")
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args():
		check(packed,"exported PCK only; no source overlay")
		if not packed: quit(1); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
	if fixture.is_empty() and phase.is_empty(): fixture = "user://tests/feedback_session_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	if not fixture.begins_with("user://tests/feedback_session_") or not fixture.trim_prefix("user://tests/").is_valid_identifier() or fixture.length() > 120 or not phase in ["","write","read"]:
		printerr("WEEK6_FEEDBACK_SESSION_FAIL invalid isolated fixture/phase")
		quit(1); return
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	saves = root.get_node("SaveService")
	app = root.get_node("App")
	saves.test_root = fixture
	check(content.last_error.is_empty(),"default production ContentDB loads without a test registry replacement")
	main = load(MAIN).instantiate()
	root.add_child(main)
	await step()
	if phase == "read":
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("expected.json")))
		if check(expected is Dictionary,"cold reader finds previous successful writer snapshots"): await read_flow(expected,true)
	else:
		var expected := await write_flow()
		if phase.is_empty() and not expected.is_empty(): await read_flow(expected,false)
	if not phase.is_empty():
		check(IO.write_text(fixture.path_join(phase+"_receipt.json"),JSON.stringify({"pid":OS.get_process_id(),"checks":checks,"failures":failures,"phase":phase,"packed":packed})) == OK,"isolated phase receipt records actual process result")
	root.remove_child(main)
	main.queue_free()
	await process_frame
	saves.test_root = ""
	print("WEEK6_FEEDBACK_SESSION: %d checks, %d failures; production keyboard/service flow, not human approval" % [checks,failures.size()])
	if failures.is_empty():
		if phase.is_empty(): print("WEEK6_FEEDBACK_SESSION_PASS checks=%d packed=%s" % [checks,str(packed)])
		else: print("WEEK6_FEEDBACK_SESSION_PHASE_PASS phase=%s pid=%d checks=%d packed=%s fixture=%s" % [phase,OS.get_process_id(),checks,str(packed),fixture])
	quit(0 if failures.is_empty() else 1)
