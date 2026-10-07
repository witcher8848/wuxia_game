extends SceneTree
## Writer and reader are separate, sequentially launched OS processes.
const IO = preload("res://game/persistence/save_file_io.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
var failures: Array[String] = []
var checks := 0
var session: Node
var saves: Node
var content: Node
var main: Node
var fixture := ""
var phase := ""

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("STORY_PERSISTENCE_FAIL ", label)

func _run() -> void:
	if "--require-pack" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported pack only; no source overlay")
		if not failures.is_empty():
			quit(1)
			return
	await process_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
	if not fixture.begins_with("user://tests/story_persistence_") or not fixture.trim_prefix("user://tests/").is_valid_identifier() or not phase in ["write","read"]:
		printerr("STORY_PERSISTENCE_FAIL invalid isolated fixture or phase")
		quit(1)
		return
	session = root.get_node("GameSession")
	saves = root.get_node("SaveService")
	content = root.get_node("ContentDB")
	saves.test_root = fixture
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	if phase == "write": await _write()
	else: await _read()
	check(IO.write_text(fixture.path_join(phase + "_receipt.json"), JSON.stringify({"pid":OS.get_process_id(),"checks":checks,"failures":failures})) == OK, "own process receipt")
	root.remove_child(main)
	main.queue_free()
	await _frames()
	saves.test_root = ""
	print("STORY_PERSISTENCE_%s: %d checks, %d failures fixture=%s pid=%d" % [phase.to_upper(),checks,failures.size(),fixture,OS.get_process_id()])
	quit(0 if failures.is_empty() else 1)

func _write() -> void:
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	for step: String in ["STEP_RECEIVE_INDEX","STEP_ACCEPT_SEARCH","STEP_INSPECT_BLANK"]:
		check(session.apply_investigation_step(step)["error"] == OK, "starting investigation " + step)
	check(session.resolve_inquiry("INQ_INDEX", ["EV_INDEX_01","EV_BLANK_DEATH_01"])["error"] == OK, "actual comparison before save")
	check(main._save_game("manual_01") == OK, "manual slot stores earlier home-only progress")
	var before: Dictionary = session.state.to_dict()
	check(session.mark_inspected("DOC_STREET_NOTICE") == OK, "actual registered handover location")
	var preview: Dictionary = session.preview_original_handover()
	check(preview["error"] == OK and session.confirm_original_handover(preview.get("token",""))["error"] == OK, "original custody transferred with confirmation")
	for step: String in ["STEP_RECORD_BOATMAN","STEP_TAKE_FERRY_TOKEN"]:
		check(session.apply_investigation_step(step)["error"] == OK, "dock investigation " + step)
	check(session.resolve_inquiry("INQ_BOATMAN", ["EV_FERRY_TOKEN_01"])["error"] == OK, "dock fact confirmed")
	check(session.enter_region("SCENE_RIVER_DOCK","SPAWN_FROM_TOWN") == OK and session.mark_inspected("NPC_DOCK_WORKER") == OK, "real encounter location")
	var start: Dictionary = session.begin_story_encounter()
	check(start["error"] == OK, "owned encounter begins")
	if start["error"] != OK: return
	var hash_before: String = FileAccess.get_sha256(saves.slot_path("manual_01"))
	check(saves.save_game("manual_01",session.state) == ERR_BUSY and FileAccess.get_sha256(saves.slot_path("manual_01")) == hash_before, "service blocks combat save without overwriting earlier slot")
	var battle: CombatEncounter = start["battle"]
	for turn: int in 180:
		if battle.outcome != "ongoing": break
		var actor := battle.current_actor_id()
		var plan := AI.plan(battle,actor)
		check(not plan.is_empty(), "real legal combat plan")
		if plan.is_empty(): break
		if plan["destination"] != Grid.cell_of(battle.unit(actor)):
			check(battle.move_actor(actor,plan["destination"],battle.revision)["ok"], "real legal combat move")
		check(battle.perform_action(actor,plan["skill_id"],plan["target"],battle.revision)["ok"], "real legal combat action")
	check(battle.outcome == "victory" and session.finish_story_encounter(start["token"])["error"] == OK, "genuine victory settles before save")
	check(main._enter_yard() == OK, "return to real dock region")
	await _frames()
	await _tap(KEY_F5)
	check(saves.slot_summary("quick")["can_load"], "actual F5 quick save")
	check(main._save_game("quick") == OK and main._save_game("manual_02") == OK, "same-slot backup and independent later manual slot")
	var after: Dictionary = session.state.to_dict()
	check(content.validate_persistent_state(session.state).is_empty(), "complete settled state validates")
	check(IO.write_text(fixture.path_join("expected.json"),JSON.stringify({"before":before,"after":after,"writer_pid":OS.get_process_id(),"old_token":start["token"]})) == OK, "write exact expected snapshots")
	_inject_bad_saves(after)
	var old := GameState.new()
	old.scene_id = "SCENE_TOWN_STREET"
	old.spawn_id = "SPAWN_START"
	check(saves.save_game("manual_04",old) == OK, "old empty schema-1 state writes")
	var legacy: Dictionary = saves.load_game("manual_04",false)
	check(legacy["error"] == OK and content.prepare_investigation_step(legacy["state"],"STEP_RECEIVE_INDEX")["error"] == OK, "empty old state can begin investigation")
	check(_same(saves.load_game("manual_01",false)["state"].to_dict(),before), "earlier manual slot remains unchanged after battle")
	# Both corruptions are confined to this test's unique directory.
	check(IO.write_text(saves.slot_path("quick"),"{broken") == OK, "corrupt quick primary in isolated fixture")
	check(saves.load_game("quick",false)["source"] == "backup", "same-slot backup recovers completed quest")
	check(saves.save_game("auto_01",session.state) == OK, "unrelated valid auto slot present")
	check(saves.load_game("manual_05",false)["error"] != OK, "missing exact manual slot never borrows auto progress")

func _inject_bad_saves(after: Dictionary) -> void:
	var bad_states: Array[Dictionary] = []
	for field: String in ["knowledge_state","holder_id","validity","discovered_at"]:
		var bad := after.duplicate(true)
		bad["evidence_states"]["EV_INDEX_01"][field] = "BAD_REFERENCE"
		bad_states.append(bad)
	for field: String in ["status","next_quest"]:
		var bad := after.duplicate(true)
		bad["quest_states"]["QUEST_FIND_GRAVEKEEPER"][field] = "UNKNOWN"
		bad_states.append(bad)
	for field: String in ["battle_id","instance_id","rounds","survivors","outcome"]:
		var bad := after.duplicate(true)
		bad["quest_states"]["QUEST_RESCUE_GRAVEKEEPER"]["resolution"][field] = "BAD"
		bad_states.append(bad)
	var partial := after.duplicate(true)
	partial["quest_states"]["QUEST_RESCUE_GRAVEKEEPER"]["status"] = "active"
	bad_states.append(partial)
	var invalid_trust := after.duplicate(true)
	invalid_trust["relationships"]["CHAR_PRISONER"]["trust"] = "one"
	bad_states.append(invalid_trust)
	var invalid_fact := after.duplicate(true)
	invalid_fact["world_flags"]["FACT_GRAVES_SAFE"] = "yes"
	bad_states.append(invalid_fact)
	for bad: Dictionary in bad_states:
		var state := GameState.from_dict(bad)
		check(state != null, "malformed content remains generic JSON; semantic validator required")
		check(saves.save_game("manual_03",state) == ERR_INVALID_DATA, "invalid registered state refused before write")
		var envelope: Dictionary = saves._make_envelope("manual_03",state)
		check(IO.write_text(saves.slot_path("manual_03"),JSON.stringify(envelope)) == OK, "inject semantic bad envelope")
		check(saves.load_game("manual_03",false)["error"] == ERR_INVALID_DATA, "semantic bad file cannot load")
		check(_same(session.state.to_dict(),after), "bad reads never mutate live state")
	# A semantically invalid primary must not poison a valid same-slot backup.
	var envelope: Dictionary = saves._make_envelope("quick",GameState.from_dict(bad_states[0]))
	var backup_hash: String = FileAccess.get_sha256(saves.backup_path("quick"))
	check(IO.write_text(saves.slot_path("quick"),JSON.stringify(envelope)) == OK, "inject invalid evidence into quick primary")
	check(saves.load_game("quick",false)["source"] == "backup", "semantic corruption recovers same-slot backup")
	check(saves.save_game("quick",session.state) == OK and FileAccess.get_sha256(saves.backup_path("quick")) == backup_hash, "saving over semantic corruption preserves valid backup")

func _read() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("expected.json")))
	# Unix Godot cannot poll a sibling PID. The Python harness waits for the
	# writer's clean exit before launching us; here verify separate identities.
	check(int(expected["writer_pid"]) != OS.get_process_id(), "reader is a distinct process from the writer")
	check(main.get_node("SceneHost").get_child_count() == 0, "fresh process starts at title")
	await _tap(KEY_S)
	await _tap(KEY_E)
	check(main._menu_kind == &"load_slots", "keyboard opens actual load menu")
	check(root.gui_get_focus_owner().get_meta("slot","") == "quick", "quick slot explicitly focused")
	await _tap(KEY_E)
	check(_same(session.state.to_dict(),expected["after"]), "selected backup restores every authoritative field")
	check(main.status.text.contains("备份"), "recovery source visible to player")
	for field: String in ["quest_states","evidence_states","world_flags","relationships","time_state","player_state","route_id"]:
		check(_same(session.state.to_dict()[field],expected["after"][field]), "restart exact " + field)
	check(session.state.evidence_states["EV_BLANK_DEATH_01"]["holder_id"] == "FACTION_INSPECTOR" and session.state.evidence_states["EV_BLANK_DEATH_01"]["knowledge_state"] == "fact", "knowledge retained while original stays transferred")
	check(not session.story_encounter_active() and session.finish_story_encounter(expected["old_token"])["error"] != OK, "transient battle ownership does not survive restart")
	check(session.begin_story_encounter()["error"] != OK, "loaded completed encounter cannot be farmed")
	await _tap(KEY_J)
	await _tap(KEY_S)
	await _tap(KEY_S)
	check(main.activity_panel.body.text.contains("迁坟旧账"), "loaded journal shows next objective")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)
	main._show_load_slots()
	await _frames()
	await _tap(KEY_S)
	check(root.gui_get_focus_owner().get_meta("slot","") == "manual_01", "explicitly select earlier manual slot")
	await _tap(KEY_E)
	check(_same(session.state.to_dict(),expected["before"]), "earlier slot retains home-only progress without ferry or settlement")
	check(session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "active" and not session.state.world_flags.get("FACT_GRAVES_SAFE",false), "earlier quest continues before battle")
	check(session.apply_investigation_step("STEP_RECORD_BOATMAN")["error"] == OK, "restored route accepts next valid investigation")
	check(_same(saves.load_game("manual_02",false)["state"].to_dict(),expected["after"]), "loading and continuing earlier slot does not alter later slot")

static func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _tap(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames()

func _frames() -> void:
	for index: int in 2:
		await physics_frame
		await process_frame
