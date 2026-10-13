extends SceneTree
## Actual autoload services and isolated SaveService slots, never user saves.
const IO = preload("res://game/persistence/save_file_io.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var saves: Node
var seed: Dictionary
var fixture := ""
var replacements := 0


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK6_MARTIAL_SESSION_FAIL ", label)


func _run() -> void:
	var packed := "--require-pack" in OS.get_cmdline_user_args()
	if packed:
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported pack only; no source overlay")
		if not failures.is_empty(): quit(1); return
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	saves = root.get_node("SaveService")
	session.state_replaced.connect(_on_state_replaced)
	fixture = "user://tests/martial_session_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	saves.test_root = fixture
	_test_legacy_and_confirm()
	_test_rejections_and_persistence()
	_test_stale_mastery()
	_test_story_and_trial_locks()
	saves.test_root = ""
	print("WEEK6_MARTIAL_SESSION: %d checks, %d failures; actual services, not human UX" % [checks, failures.size()])
	if failures.is_empty(): print("WEEK6_MARTIAL_SESSION_PASS checks=%d packed=%s" % [checks,str(packed)])
	quit(0 if failures.is_empty() else 1)


func _on_state_replaced() -> void:
	replacements += 1


static func without_martial(snapshot: Dictionary) -> Dictionary:
	var copy := snapshot.duplicate(true)
	copy.erase("martial_states")
	return copy


static func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _test_legacy_and_confirm() -> void:
	session.start_new_game()
	var before: Dictionary = session.state.to_dict()
	check(before["save_version"] == 1 and before["martial_states"] == {"mastery":{},"loadout":{}}, "new/old schema1 state stays empty until explicit confirmation")
	seed = session.martial_configuration()["state"]
	check(seed["mastery"].size() == 6 and seed["loadout"]["external"].size() == 3 and not seed["loadout"]["movement"].is_empty() and not seed["loadout"]["internal"].is_empty(), "read-only compatibility view has six seeds and 3/1/1 slots")
	check(session.state.to_dict() == before, "viewing preparation does not mutate old state")
	var view: Dictionary = session.martial_configuration()
	view["state"]["loadout"]["external"].clear()
	view["state"]["mastery"].clear()
	check(session.state.to_dict() == before and session.martial_configuration()["state"] == seed, "read-only view deeply detached")
	check(content.validate_persistent_state(session.state).is_empty() and session.state.to_dict() == before, "content validation does not rewrite empty legacy martial state")
	check(saves.save_game("manual_01",session.state) == OK, "actual legacy schema1 save")
	var saved_bytes := FileAccess.get_file_as_bytes(saves.slot_path("manual_01"))
	var hash_before := FileAccess.get_sha256(saves.slot_path("manual_01"))
	var restored: Dictionary = saves.load_game("manual_01",false)
	check(restored["error"] == OK and _same(restored["state"].to_dict(),before), "actual old load preserves exact state snapshot")
	check(session.replace_state(restored["state"]) == OK and _same(session.state.to_dict(),before), "replace old state does not silently seed persistence")
	check(FileAccess.get_file_as_bytes(saves.slot_path("manual_01")) == saved_bytes and FileAccess.get_sha256(saves.slot_path("manual_01")) == hash_before, "reading/validation/replacement do not rewrite old save bytes")
	var selected: Dictionary = seed["loadout"].duplicate(true)
	check(session.set_martial_loadout(selected) == OK, "explicit confirmed preparation accepted")
	check(session.state.martial_states == seed and _same(without_martial(session.state.to_dict()),without_martial(before)), "confirmation changes only martial state, not time/HP/evidence/quests/route")
	selected["external"].clear()
	check(session.state.martial_states == seed, "confirmed state owns copy, not UI selection array")
	check(saves.save_game("manual_02",session.state) == OK, "actual configured save")
	restored = saves.load_game("manual_02",false)
	check(restored["error"] == OK and restored["state"].to_dict() == session.state.to_dict(), "actual configured load exact all state")
	check(_same(saves.load_game("manual_01",false)["state"].to_dict(),before) and FileAccess.get_sha256(saves.slot_path("manual_01")) == hash_before, "later configuration does not contaminate earlier legacy slot")


func _test_rejections_and_persistence() -> void:
	var before: Dictionary = session.state.to_dict()
	var slot_hash := FileAccess.get_sha256(saves.slot_path("manual_02"))
	for patch: Dictionary in [{"external":["SK_YUE_THRUST","SK_YUE_GUARD","SK_YUE_CROSSCUT","SK_TRIP_WRIST"]}, {"external":["SK_YUE_THRUST","SK_YUE_THRUST"]}, {"external":["SK_WATER_STEP"]}, {"external":["IN_BREATH_BASIC"]}, {"external":["SK_FIST_BASIC"]}, {"external":["EN_CATCHER_LOCK"]}, {"external":["ULT_SWORD"]}, {"external":["MISSING"]}, {"external":"SK_YUE_THRUST"}, {"movement":[]}, {"movement":"SK_YUE_GUARD"}, {"internal":[]}, {"internal":"ACT_BREATH"}, {"unknown":1}]:
		var wrong: Dictionary = seed["loadout"].duplicate(true)
		wrong.merge(patch,true)
		check(session.set_martial_loadout(wrong) == ERR_INVALID_DATA, "bad slots rejected by session " + str(patch))
		check(session.state.to_dict() == before and FileAccess.get_sha256(saves.slot_path("manual_02")) == slot_hash, "bad selection cannot mutate authoritative state or saved slot")
	var corruptions: Array[Dictionary] = []
	for patch: Dictionary in [{"external":["MISSING"]}, {"external":["SK_YUE_THRUST","SK_YUE_THRUST"]}, {"movement":"SK_YUE_GUARD"}, {"internal":"ACT_BREATH"}]:
		var wrong := before.duplicate(true)
		wrong["martial_states"]["loadout"].merge(patch,true)
		corruptions.append(wrong)
	for bad_mastery: Dictionary in [{"MISSING":"熟练"}, {"SK_YUE_THRUST":"识招"}, {"SK_YUE_THRUST":"novice"}]:
		var wrong := before.duplicate(true)
		wrong["martial_states"]["mastery"].merge(bad_mastery,true)
		corruptions.append(wrong)
	for wrong: Dictionary in corruptions:
		var malformed := GameState.from_dict(wrong)
		check(malformed != null, "invalid martial references remain schema1 JSON, require semantic validator")
		check(not content.validate_persistent_state(malformed).is_empty(), "ContentDB rejects semantic martial corruption")
		check(session.replace_state(malformed) == ERR_INVALID_DATA and session.state.to_dict() == before, "bad replacement preserves entire live route")
		check(saves.save_game("manual_02",malformed) == ERR_INVALID_DATA and FileAccess.get_sha256(saves.slot_path("manual_02")) == slot_hash, "bad references cannot overwrite valid primary")
		check(IO.write_text(saves.slot_path("manual_03"),JSON.stringify(saves._make_envelope("manual_03",malformed))) == OK, "inject own isolated semantic-corruption envelope")
		check(saves.load_game("manual_03",false)["error"] == ERR_INVALID_DATA and session.state.to_dict() == before, "semantic-corrupt file cannot load or change session")
	var bad_qi: Dictionary = seed["loadout"].duplicate(true)
	bad_qi["internal"] = ""
	bad_qi["external"] = ["SK_TRIP_WRIST"]
	check(session.set_martial_loadout(bad_qi) == OK, "alternate legal loadout with one external and empty internal")
	check(without_martial(session.state.to_dict()) == without_martial(before), "removing internal does not pre-spend persistent HP/qi/time")
	check(saves.save_game("quick",session.state) == OK, "first alternate quick save")
	check(session.set_martial_loadout(seed["loadout"]) == OK and saves.save_game("quick",session.state) == OK, "same-slot second config creates real backup")
	var backup_hash := FileAccess.get_sha256(saves.backup_path("quick"))
	var corrupt := GameState.from_dict(corruptions[0])
	check(IO.write_text(saves.slot_path("quick"),JSON.stringify(saves._make_envelope("quick",corrupt))) == OK, "inject own bad primary")
	var recovered: Dictionary = saves.load_game("quick",false)
	check(recovered["error"] == OK and recovered["source"] == "backup" and recovered["state"].martial_states["loadout"] == bad_qi, "same-slot backup restores prior configuration, not current memory/defaults")
	check(saves.save_game("quick",session.state) == OK and FileAccess.get_sha256(saves.backup_path("quick")) == backup_hash, "semantic corruption cannot poison valid backup on next write")


func _test_stale_mastery() -> void:
	var source: Dictionary = session.state.to_dict()
	var stale_selection: Dictionary = seed["loadout"].duplicate(true)
	var newer := source.duplicate(true)
	newer["martial_states"]["mastery"]["SK_YUE_THRUST"] = "识招"
	newer["martial_states"]["loadout"]["external"] = ["SK_TRIP_WRIST","SK_YUE_GUARD","SK_YUE_CROSSCUT"]
	check(session.replace_state(GameState.from_dict(newer)) == OK, "valid newer authoritative mastery may identify unassigned art")
	var before: Dictionary = session.state.to_dict()
	check(session.set_martial_loadout(stale_selection) == ERR_INVALID_DATA and session.state.to_dict() == before, "confirmation revalidates current mastery, not stale preview")
	check(session.replace_state(GameState.from_dict(source)) == OK, "restore independent valid fixture")


func prepare_story() -> void:
	session.start_new_game()
	for step: String in ["STEP_RECEIVE_INDEX","STEP_ACCEPT_SEARCH","STEP_INSPECT_BLANK"]:
		check(session.apply_investigation_step(step)["error"] == OK, "actual story preparation " + step)
	check(session.resolve_inquiry("INQ_INDEX",["EV_INDEX_01","EV_BLANK_DEATH_01"])["error"] == OK, "actual fact unlocks story path")
	check(session.enter_region("SCENE_RIVER_DOCK","SPAWN_FROM_TOWN") == OK and session.mark_inspected("NPC_DOCK_WORKER") == OK, "actual departure location and known NPC")


func _test_story_and_trial_locks() -> void:
	prepare_story()
	var old_before: Dictionary = session.state.to_dict()
	var legacy: Dictionary = session.begin_story_encounter()
	check(legacy["error"] == OK, "empty legacy martial state still starts original story")
	if legacy["error"] != OK: return
	check(not legacy["battle"].unit("CHAR_PROTAGONIST").has("loadout") and not "SK_YUE_CROSSCUT" in legacy["battle"].abilities("CHAR_PROTAGONIST"), "legacy story retains old flat seed, not silent new default")
	check(session.abort_story_encounter(legacy["token"]) == OK and session.state.to_dict() == old_before, "legacy abort restores original exact empty state")
	check(session.set_martial_loadout(seed["loadout"]) == OK, "confirm real story preparation")
	var before: Dictionary = session.state.to_dict()
	var start: Dictionary = session.begin_story_encounter()
	check(start["error"] == OK, "explicit configured story starts")
	if start["error"] != OK: return
	var battle: CombatEncounter = start["battle"]
	check(battle.unit("CHAR_PROTAGONIST")["loadout"] == seed["loadout"] and battle.unit("CHAR_PROTAGONIST")["mastery"] == seed["mastery"], "actual story hero receives exact persistent loadout/mastery")
	check(battle.unit("CHAR_PROTAGONIST")["max_qi"] == 5 and "SK_YUE_CROSSCUT" in battle.abilities("CHAR_PROTAGONIST") and not "IN_BREATH_BASIC" in battle.abilities("CHAR_PROTAGONIST"), "injected internal runs passively and crosscut is executable ability")
	check(not battle.unit("CHAR_COMPANION").has("loadout") and "SK_TRIP_WRIST" in battle.abilities("CHAR_COMPANION"), "hero prep does not overwrite companion fixed kit")
	var staged: Dictionary = session.state.to_dict()
	var emitted_before := replacements
	check(session.set_martial_loadout(seed["loadout"]) == ERR_BUSY and session.state.to_dict() == staged, "in-combat preparation forbidden atomically")
	check(session.start_new_game().to_dict() == staged and replacements == emitted_before, "story combat cannot reset route or emit replacement through new game")
	check(session.lock_martial_trial().is_empty(), "story combat forbids simultaneous trial")
	check(saves.save_game("manual_04",session.state) == ERR_BUSY and not FileAccess.file_exists(saves.slot_path("manual_04")), "actual service cannot write unsettled story")
	var initial := battle.snapshot()
	var actor := battle.current_actor_id()
	check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"], "actual story action before retry")
	check(session.retry_story_encounter("WRONG") == ERR_INVALID_PARAMETER and session.abort_story_encounter("WRONG") == ERR_INVALID_PARAMETER, "wrong story tokens cannot reset or abort")
	check(session.retry_story_encounter(start["token"]) == OK, "owned retry succeeds")
	var after_retry := battle.snapshot()
	initial.erase("revision")
	after_retry.erase("revision")
	check(after_retry == initial and session.state.to_dict() == staged, "retry preserves exact equipped snapshot and all persistent fields")
	check(session.abort_story_encounter(start["token"]) == OK and session.state.to_dict() == before, "abort restores full pre-battle equipped route")
	var no_internal: Dictionary = seed["loadout"].duplicate(true)
	no_internal["internal"] = ""
	check(session.set_martial_loadout(no_internal) == OK, "confirm no-inner configuration after abort")
	start = session.begin_story_encounter()
	check(start["error"] == OK and start["battle"].unit("CHAR_PROTAGONIST")["max_qi"] == 3 and start["battle"].action_restore_qi("CHAR_PROTAGONIST","SK_FIST_BASIC") == 0 and start["battle"].action_restore_qi("CHAR_PROTAGONIST","ACT_BREATH") == 1, "actual story uses unequipped resource cycle, not flat legacy numbers")
	check(session.abort_story_encounter(start["token"]) == OK, "return from actual no-inner story")
	before = session.state.to_dict()
	var token: String = session.lock_martial_trial()
	check(not token.is_empty() and session.lock_martial_trial().is_empty(), "single owned trial lock, not nesting")
	check(not session.unlock_martial_trial("") and not session.unlock_martial_trial("WRONG"), "wrong trial tokens do not release lock")
	check(session.set_martial_loadout(seed["loadout"]) == ERR_BUSY and session.state.to_dict() == before, "trial locks preparation without state change")
	check(session.replace_state(GameState.from_dict(before)) == ERR_BUSY and session.state.to_dict() == before, "trial cannot bypass lock through loaded replacement")
	var slot_hash := FileAccess.get_sha256(saves.slot_path("manual_02"))
	check(saves.save_game("manual_02",session.state) == ERR_BUSY and FileAccess.get_sha256(saves.slot_path("manual_02")) == slot_hash, "actual SaveService blocks trial overwrite")
	check(session.update_player_position(Vector2.ZERO) == ERR_BUSY and session.enter_region("SCENE_TOWN_STREET","SPAWN_START") == ERR_BUSY and session.mark_inspected("DOC_HOME_NOTE") == ERR_BUSY and session.state.to_dict() == before, "trial forbids exploration mutations")
	check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] == ERR_BUSY and session.resolve_inquiry("INQ_INDEX",["EV_INDEX_01","EV_BLANK_DEATH_01"])["error"] == ERR_BUSY and session.preview_original_handover()["error"] == ERR_BUSY and session.state.to_dict() == before, "trial forbids investigation and handover commands")
	emitted_before = replacements
	check(session.start_new_game().to_dict() == before and session.state.to_dict() == before and replacements == emitted_before, "trial cannot clear its token or emit replacement by starting a new game")
	check(session.begin_story_encounter()["error"] != OK and session.state.to_dict() == before, "trial forbids concurrent story entry without clearing its token")
	check(session.unlock_martial_trial(token) and not session.unlock_martial_trial(token), "exact trial token releases once")
	var next_token: String = session.lock_martial_trial()
	check(not next_token.is_empty() and next_token != token and not session.unlock_martial_trial(token) and session.set_martial_loadout(seed["loadout"]) == ERR_BUSY, "old trial token cannot release a newer trial")
	check(session.unlock_martial_trial(next_token), "new trial owner releases its own token")
	check(session.set_martial_loadout(seed["loadout"]) == OK, "preparation unlocked after owned trial exit")
