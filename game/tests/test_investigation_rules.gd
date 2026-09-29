extends SceneTree
## Day 22 domain/service tests; no playable dialogue or battle claim.
const Rules = preload("res://game/domain/investigation/investigation_rules.gd")
const Saves = preload("res://game/persistence/save_service.gd")
const CONTENT_PATH := "res://game/content/data/investigation.json"
const INDEX := "EV_INDEX_01"
const BLANK := "EV_BLANK_DEATH_01"
const FIND := "QUEST_FIND_GRAVEKEEPER"
const RESCUE := "QUEST_RESCUE_GRAVEKEEPER"
var _checks := 0
var _failures: Array[String] = []
var _signals := 0
var _data: Dictionary
var _root_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	_test_definitions()
	_test_rules()
	_test_invalid_states()
	_test_service_and_saves()
	for failure: String in _failures:
		printerr("INVESTIGATION_FAIL ", failure)
	print("INVESTIGATION_RULES: %d checks, %d failures (Day 22 only; no UI/combat/human-play claim)" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_definitions() -> void:
	var rules := Rules.new()
	_check(rules.configure(_data).is_empty(), "canonical definitions validate")
	var published: Dictionary = rules.definitions()
	published["evidence"].clear()
	_check(rules.definitions()["evidence"].size() == _data["evidence"].size(), "definitions are deep copies")
	var bad_cases: Array[Dictionary] = []
	for field: String in ["evidence", "facts", "quests", "holders", "steps"]:
		var bad := _data.duplicate(true)
		bad[field] = "not an array"
		bad_cases.append(bad)
		bad = _data.duplicate(true)
		bad[field].append(bad[field][0])
		bad_cases.append(bad)
	for effect: Variant in [
		{"op": "run_script", "id": INDEX},
		{"op": "discover", "id": "EV_UNKNOWN"},
		{"op": "discover", "id": INDEX, "property": "player_state.hp"},
		{"op": "knowledge", "id": INDEX, "value": "omniscient"},
		{"op": "transfer", "id": INDEX, "from": "PLAYER", "to": "MISSING"},
		_quest("changed", "", RESCUE), _quest("changed", "REASON_TEST", FIND),
		_quest("active", "REASON_TEST", ""), null, 2,
		{"op": "set_quest", "id": FIND, "value": "available", "reason_key": [], "next_quest": ""},
	]:
		var bad := _data.duplicate(true)
		bad["steps"][0]["effects"] = [effect]
		bad_cases.append(bad)
	for condition: Variant in [
		{"op": "fact_is", "id": "FACT_WEST_GRAVES", "value": "true"},
		{"op": "quest_is", "id": "QUEST_MISSING", "value": "active"},
		{"op": "eval", "id": INDEX}, null,
	]:
		var bad := _data.duplicate(true)
		bad["steps"][0]["requires"] = [condition]
		bad_cases.append(bad)
	var source_bad := _data.duplicate(true)
	source_bad["evidence"][0]["source_id"] = "UNKNOWN_SOURCE"
	bad_cases.append(source_bad)
	for bad: Dictionary in bad_cases:
		_check(not rules.configure(bad).is_empty(), "invalid definitions refused")
		_check(_same(rules.definitions(), _data), "failed configure preserves registry")
	var alias := _data.duplicate(true)
	_check(rules.configure(alias).is_empty(), "configurable from caller dictionary")
	alias["steps"].clear()
	_check(rules.definitions()["steps"].size() == _data["steps"].size(), "configure owns its definitions")


func _test_rules() -> void:
	var rules := Rules.new()
	_check(rules.configure(_data).is_empty(), "rules initialized")
	var state := GameState.new()
	_check(rules.validate_state(state).is_empty(), "old empty schema 1 is valid")
	_check(rules.condition_matches(state, {"op": "quest_is", "id": FIND, "value": "locked"}), "absent quest defaults locked")
	_check(rules.condition_matches(state, {"op": "fact_is", "id": "FACT_WEST_GRAVES", "value": false}), "absent fact defaults false")
	for step: String in ["STEP_COMPARE_INDEX_BLANK", "STEP_HAND_OVER_BLANK", "STEP_INSPECT_BLANK", "STEP_UNKNOWN"]:
		_refused(rules, state, step)
	var before := state.to_dict()
	var prepared: Dictionary = rules.prepare_step(state, "STEP_RECEIVE_INDEX")
	_check(prepared["error"] == OK and not prepared["feedback_key"].is_empty(), "prepare returns candidate and feedback")
	_check(_same(state.to_dict(), before), "prepare never mutates caller")
	state = prepared["state"]
	_check(state.evidence_states[INDEX]["holder_id"] == "PLAYER", "original transferred from prisoner")
	_refused(rules, state, "STEP_RECEIVE_INDEX")
	state = _apply(rules, state, "STEP_ACCEPT_SEARCH")
	state = _apply(rules, state, "STEP_INSPECT_BLANK")
	_check(state.evidence_states[BLANK]["knowledge_state"] == "clue", "new evidence starts clue")
	state = _apply(rules, state, "STEP_COMPARE_INDEX_BLANK")
	for identifier: String in [INDEX, BLANK]:
		_check(state.evidence_states[identifier]["knowledge_state"] == "fact", "comparison upgrades knowledge")
		_check(state.evidence_states[identifier]["validity"] == "verified", "comparison verifies evidence")
	_check(state.world_flags["FACT_WEST_GRAVES"] and state.world_flags["FACT_YAMEN_FORMATION"], "comparison yields location and future battle facts")
	state = _apply(rules, state, "STEP_HAND_OVER_BLANK")
	_check(state.evidence_states[BLANK]["holder_id"] == "FACTION_INSPECTOR", "original held elsewhere")
	_check(rules.condition_matches(state, {"op": "evidence_at_least", "id": BLANK, "value": "doubt"}), "knowledge survives transfer")
	_check(not rules.condition_matches(state, {"op": "holder_is", "id": BLANK, "value": "PLAYER"}), "knowledge is not physical ownership")
	var extra := _data.duplicate(true)
	extra["steps"].append(_step("STEP_REDISCOVER", [{"op": "discover", "id": BLANK}]))
	extra["steps"].append(_step("STEP_DOWNGRADE", [{"op": "knowledge", "id": BLANK, "value": "clue"}]))
	extra["steps"].append(_step("STEP_ATOMIC_FAIL", [_quest("resolved"), {"op": "transfer", "id": BLANK, "from": "PLAYER", "to": "CHAR_FATHER"}]))
	extra["steps"].append(_step("STEP_CHANGED", [_quest("changed", "REASON_GRAVEKEEPER_TAKEN", RESCUE), _quest("available", "", "", RESCUE)]))
	extra["steps"].append(_step("STEP_RESOLVED", [_quest("resolved")]))
	extra["steps"].append(_step("STEP_REOPEN", [_quest("active")]))
	_check(rules.configure(extra).is_empty(), "test-only transitions configure")
	state = _apply(rules, state, "STEP_REDISCOVER")
	_check(state.evidence_states[BLANK]["holder_id"] == "FACTION_INSPECTOR" and state.evidence_states[BLANK]["knowledge_state"] == "fact", "rediscovery cannot reclaim or forget original")
	_refused(rules, state, "STEP_DOWNGRADE")
	_refused(rules, state, "STEP_ATOMIC_FAIL")
	state = _apply(rules, state, "STEP_CHANGED")
	_check(state.quest_states[FIND]["status"] == "changed" and state.quest_states[FIND]["next_quest"] == RESCUE and not state.quest_states[FIND]["reason_key"].is_empty(), "changed quest retains reason and next goal")
	_check(state.quest_states[RESCUE]["status"] == "available", "replacement goal available in same transaction")
	state = _apply(rules, state, "STEP_RESOLVED")
	_refused(rules, state, "STEP_REOPEN")
	_check(state.time_state == {"day": 1, "slot": 0}, "all Day 22 steps leave clock unchanged")
	# Unregistered legacy keys are retained and cannot collide across partitions.
	var legacy := GameState.new()
	legacy.evidence_states[FIND] = 17
	legacy.evidence_states["FACT_WEST_GRAVES"] = "legacy payload"
	_check(rules.condition_matches(legacy, {"op": "quest_is", "id": FIND, "value": "locked"}), "conditions only access their own partition")
	legacy = _apply(rules, legacy, "STEP_RECEIVE_INDEX")
	_check(legacy.evidence_states[FIND] == 17, "effects preserve unrelated legacy data")


func _test_invalid_states() -> void:
	var rules := Rules.new()
	_check(rules.configure(_data).is_empty(), "state validator initialized")
	var known := _apply(rules, GameState.new(), "STEP_RECEIVE_INDEX")
	var bad_states: Array[GameState] = []
	for field: String in ["knowledge_state", "holder_id", "validity", "discovered_at"]:
		for value: Variant in [null, [], 2, "bad"]:
			var bad := GameState.from_dict(known.to_dict())
			bad.evidence_states[INDEX][field] = value
			bad_states.append(bad)
	for discovery: Dictionary in [{"day": 0, "slot": 0}, {"day": 1, "slot": 8}, {"day": 1.2, "slot": 0}]:
		var bad := GameState.from_dict(known.to_dict())
		bad.evidence_states[INDEX]["discovered_at"] = discovery
		bad_states.append(bad)
	for record: Variant in [null, 3, {}, {"status": "failed"}, {"status": "changed"}, {"status": "changed", "reason_key": "REASON_TEST", "next_quest": FIND}]:
		var bad := GameState.from_dict(known.to_dict())
		bad.quest_states[FIND] = record
		bad_states.append(bad)
	for flag: String in ["FACT_WEST_GRAVES", "APPLIED_STEP_ACCEPT_SEARCH"]:
		var bad := GameState.from_dict(known.to_dict())
		bad.world_flags[flag] = 1
		bad_states.append(bad)
	for bad: GameState in bad_states:
		_check(not rules.validate_state(bad).is_empty(), "malformed registered state rejected")
		_refused(rules, bad, "STEP_ACCEPT_SEARCH")
	_check(not rules.condition_matches(known, {"op": "fact_is", "id": "FACT_WEST_GRAVES", "value": "true"}), "invalid query is false")


func _test_service_and_saves() -> void:
	var content := root.get_node("ContentDB")
	var session := root.get_node("GameSession")
	var bootstrap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/bootstrap.json"))
	var original: Dictionary = content.get_investigation_definitions()
	var scene_path: String = content.get_scene_path("SCENE_TOWN_STREET")
	var bad := _data.duplicate(true)
	bad["steps"][0]["effects"][0]["id"] = "EV_MISSING"
	_check(content.load_definitions(bootstrap, null, bad) == ERR_INVALID_DATA, "ContentDB rejects bad investigation")
	_check(_same(content.get_investigation_definitions(), original) and content.get_scene_path("SCENE_TOWN_STREET") == scene_path, "failed reload preserves all registries")
	_check(content.reload_content() == OK, "ContentDB canonical reload succeeds")
	session.start_new_game()
	session.state.inventory["legacy_item"] = 3
	session.state.relationships["CHAR_FATHER"] = {"trust": 4}
	var untouched: Dictionary = session.state.to_dict()
	session.state_replaced.connect(func() -> void: _signals += 1)
	var failed: Dictionary = session.apply_investigation_step("STEP_COMPARE_INDEX_BLANK")
	_check(failed["error"] != OK and _signals == 0 and _same(session.state.to_dict(), untouched), "failed command emits nothing and preserves live state")
	for step: String in ["STEP_RECEIVE_INDEX", "STEP_ACCEPT_SEARCH", "STEP_INSPECT_BLANK", "STEP_COMPARE_INDEX_BLANK", "STEP_HAND_OVER_BLANK"]:
		_check(session.apply_investigation_step(step)["error"] == OK, "live command succeeds " + step)
		var snapshot: Dictionary = session.state.to_dict()
		_check(session.apply_investigation_step(step)["error"] == ERR_ALREADY_EXISTS, "duplicate command refused " + step)
		_check(_same(session.state.to_dict(), snapshot), "duplicate command has no effects")
	_check(_signals == 5, "exactly one notification per successful command")
	for field: String in ["time_state", "player_state", "inventory", "relationships", "route_id", "scene_id", "spawn_id"]:
		_check(_same(session.state.to_dict()[field], untouched[field]), "investigation leaves unrelated field intact " + field)
	var saves := Saves.new()
	_root_path = "user://tests/investigation_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	saves.test_root = _root_path
	_check(saves.save_game("manual_01", session.state) == OK, "new investigation state saves in isolated root")
	var loaded: Dictionary = saves.load_game("manual_01", false)
	_check(loaded["error"] == OK, "new state loads exact slot")
	if loaded["error"] == OK:
		_check(_same(loaded["state"].to_dict(), session.state.to_dict()), "all new and legacy fields survive save roundtrip")
		_check(session.replace_state(loaded["state"]) == OK, "loaded state installed")
		loaded["state"].evidence_states[BLANK]["holder_id"] = "PLAYER"
		_check(session.state.evidence_states[BLANK]["holder_id"] == "FACTION_INSPECTOR", "loaded snapshot cannot alias live ownership")
		_check(session.apply_investigation_step("STEP_HAND_OVER_BLANK")["error"] == ERR_ALREADY_EXISTS, "loaded applied marker prevents duplicate command")
		_check(content.investigation_condition(session.state, {"op": "fact_is", "id": "FACT_WEST_GRAVES", "value": true}), "loaded fact satisfies same conditions")
	var old := GameState.new()
	_check(saves.save_game("manual_02", old) == OK, "old empty schema 1 saves")
	loaded = saves.load_game("manual_02", false)
	_check(loaded["error"] == OK and _same(loaded["state"].to_dict(), old.to_dict()), "old empty schema 1 loads unchanged")
	if loaded["error"] == OK:
		_check(content.prepare_investigation_step(loaded["state"], "STEP_RECEIVE_INDEX")["error"] == OK, "old save can begin new investigation")
	saves.free()
	_remove_fixture(_root_path)
	_check(not DirAccess.dir_exists_absolute(_root_path), "only owned test fixture cleaned")


func _apply(rules: RefCounted, state: GameState, step: String) -> GameState:
	var result: Dictionary = rules.prepare_step(state, step)
	_check(result["error"] == OK, "step succeeds " + step)
	return result["state"] if result["error"] == OK else state


func _refused(rules: RefCounted, state: GameState, step: String) -> void:
	var before := state.to_dict()
	var result: Dictionary = rules.prepare_step(state, step)
	_check(result["error"] != OK and result["state"] == null, "step refused " + step)
	_check(_same(before, state.to_dict()), "refused step is atomic " + step)


func _quest(value: String, reason: String = "", next: String = "", identifier: String = FIND) -> Dictionary:
	return {"op": "set_quest", "id": identifier, "value": value, "reason_key": reason, "next_quest": next}


func _step(identifier: String, effects: Array) -> Dictionary:
	return {"id": identifier, "feedback_key": "TEST_FEEDBACK", "requires": [], "effects": effects}


func _same(a: Variant, b: Variant) -> bool:
	# Normalize JSON numbers, which load as floats even when written as integers.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _remove_fixture(path: String) -> void:
	if _root_path.is_empty() or not (path == _root_path or path.begins_with(_root_path + "/")):
		_check(false, "refuse unsafe cleanup")
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_fixture(path.path_join(child))
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
