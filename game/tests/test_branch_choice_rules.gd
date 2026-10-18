extends SceneTree
## Week 8 first-choice proposal contract, not a playable branch completion claim.
const Rules = preload("res://game/domain/investigation/branch_choice_rules.gd")
const Investigation = preload("res://game/domain/investigation/investigation_rules.gd")
var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_candidates()
	_test_requirements()
	_test_legacy()
	_test_bad_states()
	_test_step_guard()
	for failure: String in _failures:
		printerr("BRANCH_CHOICE_FAIL ", failure)
	print("BRANCH_CHOICE_RULES: %d checks, %d failures (pure first-choice foundation only)" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_candidates() -> void:
	var rules := Rules.new()
	for choice: String in ["home", "dock"]:
		var state := _ready()
		state.time_state = {"day": 4, "slot": 7}
		state.world_flags["UNRELATED_LEGACY_PAYLOAD"] = {"nested": ["kept"]}
		state.inventory["unchanged"] = {"amount": 3}
		state.relationships["CHAR_FATHER"] = {"trust": 4}
		var before: Dictionary = state.to_dict()
		var prepared: Dictionary = rules.prepare(state, choice)
		_check(prepared.size() == 3 and prepared["error"] == OK and prepared["state"] is GameState, "proposal has exact result shape " + choice)
		_check(state.to_dict() == before, "proposal leaves input unchanged " + choice)
		var candidate: GameState = prepared["state"]
		var receipt := {"id": Rules.RECORD_KEY, "choice": choice, "phase_id": Rules.PHASE_ID, "route_id": state.route_id}
		_check(rules.record(candidate) == receipt and rules.validate_state(candidate).is_empty(), "receipt fixed identity " + choice)
		var expected: Dictionary = before.duplicate(true)
		expected["world_flags"][Rules.RECORD_KEY] = receipt.duplicate(true)
		_check(candidate.to_dict() == expected, "only receipt added; no clock/evidence/reward changes " + choice)
		var summary: Dictionary = prepared["summary"]
		_check(summary["id"] == receipt["id"] and summary["choice"] == choice and summary["phase_id"] == receipt["phase_id"] and summary["route_id"] == receipt["route_id"], "summary has receipt identity " + choice)
		_check(summary["impact_ids"] == Rules.IMPACT_IDS and summary["opportunity_id"] == ("OPP_CH01_BOATMAN_QUESTIONED" if choice == "home" else "OPP_CH01_HOME_CONFISCATED"), "stable impact identifiers " + choice)
		for replacement: String in ["home", "dock"]:
			_refused(rules, candidate, replacement, ERR_ALREADY_EXISTS)
		_check(not rules.is_legacy(candidate), "new receipt is not reinterpreted as legacy " + choice)
		var queried: Dictionary = rules.record(candidate)
		queried["choice"] = "changed"
		summary["choice"] = "changed"
		summary["impact_ids"].clear()
		_check(rules.record(candidate) == receipt, "record and summary do not alias receipt " + choice)
		candidate.world_flags["UNRELATED_LEGACY_PAYLOAD"]["nested"].append("candidate_only")
		candidate.inventory["unchanged"]["amount"] = 10
		_check(state.to_dict() == before, "candidate owns deep nested state " + choice)
		_check(Rules.IMPACT_IDS.size() == 3, "summary does not alias static impact list " + choice)
		var loaded: GameState = GameState.from_dict(candidate.to_dict())
		_check(loaded != null and rules.validate_state(loaded).is_empty() and rules.record(loaded) == receipt, "receipt survives GameState round trip " + choice)
		_check(rules.prepare(_ready(), choice)["summary"]["impact_ids"].size() == 3, "later proposal independent of earlier summary " + choice)
		candidate.time_state = {"day": 7, "slot": 2}
		candidate.quest_states["QUEST_FIND_GRAVEKEEPER"] = {"status":"changed", "reason_key":"INV_RESCUE_REASON", "next_quest":"QUEST_RESCUE_GRAVEKEEPER"}
		candidate.quest_states["QUEST_RESCUE_GRAVEKEEPER"] = {"status":"resolved", "reason_key":"", "next_quest":""}
		candidate.quest_states["QUEST_TRACE_LEDGER"] = {"status":"available", "reason_key":"", "next_quest":""}
		candidate.world_flags["APPLIED_STEP_PREPARE_RESCUE"] = true
		candidate.world_flags["APPLIED_STEP_GRAVES_VICTORY"] = true
		candidate.world_flags["FACT_GRAVES_SAFE"] = true
		candidate.evidence_states["EV_INDEX_01"]["holder_id"] = "FACTION_INSPECTOR"
		var advanced: Dictionary = candidate.to_dict()
		_check(rules.validate_state(candidate).is_empty() and rules.record(candidate) == receipt and not rules.is_legacy(candidate), "past receipt remains valid after clock, ownership and quest advance; Story owns settlement validation " + choice)
		_check(candidate.to_dict() == advanced, "advanced-state queries are read-only " + choice)
		_refused(rules, candidate, choice, ERR_ALREADY_EXISTS)
		candidate.quest_states["QUEST_FIND_GRAVEKEEPER"] = {"status":"resolved", "reason_key":"", "next_quest":""}
		_check(rules.validate_state(candidate).is_empty() and rules.record(candidate) == receipt, "resolved search still retains historical origin " + choice)
	var absent := GameState.new()
	var snapshot: Dictionary = absent.to_dict()
	_check(rules.record(absent).is_empty() and not rules.is_legacy(absent) and rules.validate_state(absent).is_empty(), "empty old state is valid and uncommitted")
	_check(absent.to_dict() == snapshot, "queries never normalize empty old state")


func _test_requirements() -> void:
	var rules := Rules.new()
	for choice: String in ["", "HOME", "Dock", "both", "home ", "PHASE_DAY1_AFTERNOON"]:
		_refused(rules, _ready(), choice, ERR_INVALID_PARAMETER)
	_refused(rules, GameState.new(), "home", ERR_UNAVAILABLE)
	for status: String in ["locked", "available"]:
		var state := _ready()
		state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] = status
		_refused(rules, state, "home", ERR_UNAVAILABLE)
	var no_index := _ready()
	no_index.evidence_states.erase("EV_INDEX_01")
	_refused(rules, no_index, "dock", ERR_UNAVAILABLE)
	for holder: String in ["CHAR_PRISONER", "CHAR_FATHER", "FACTION_INSPECTOR", "CHAR_BOATMAN"]:
		var state := _ready()
		state.evidence_states["EV_INDEX_01"]["holder_id"] = holder
		_refused(rules, state, "home", ERR_UNAVAILABLE)
	var false_markers := _ready()
	for flag: String in Rules.PROGRESS_FLAGS:
		false_markers.world_flags[flag] = false
	_check(not rules.is_legacy(false_markers) and rules.prepare(false_markers, "home")["error"] == OK, "explicit false markers are not invented progress")
	for flag: String in Rules.NAVIGATION_FLAGS:
		var navigated := _ready()
		navigated.world_flags[flag] = true
		for choice: String in ["home", "dock"]:
			var prepared: Dictionary = rules.prepare(navigated, choice)
			_check(not rules.is_legacy(navigated) and prepared["error"] == OK, "navigation preference alone does not commit or prohibit changing direction " + flag + choice)
			if prepared["error"] == OK:
				_check(prepared["state"].world_flags[flag] == true, "navigation history preserved " + flag + choice)
	var both_navigation := _ready()
	for flag: String in Rules.NAVIGATION_FLAGS:
		both_navigation.world_flags[flag] = true
	_check(not rules.is_legacy(both_navigation), "even ambiguous old navigation is not converted to a choice")
	for choice: String in ["home", "dock"]:
		_check(rules.prepare(both_navigation, choice)["error"] == OK, "new commitment does not silently reinterpret old navigation " + choice)


func _test_legacy() -> void:
	var rules := Rules.new()
	for identifier: String in Rules.EVIDENCE_IDS:
		if identifier == "EV_INDEX_01":
			continue
		var state := _ready()
		state.evidence_states[identifier] = _evidence()
		_legacy_refused(rules, state, "line evidence is not retroactively rewritten " + identifier)
	for knowledge: String in ["doubt", "fact"]:
		var state := _ready()
		state.evidence_states["EV_INDEX_01"]["knowledge_state"] = knowledge
		_legacy_refused(rules, state, "index progress retained " + knowledge)
	for flag: String in Rules.PROGRESS_FLAGS:
		var state := _ready()
		state.world_flags[flag] = true
		_legacy_refused(rules, state, "legacy marker retained " + flag)
	for status: String in ["changed", "resolved"]:
		var state := _ready()
		state.quest_states["QUEST_FIND_GRAVEKEEPER"] = {"status": status, "reason_key": "INV_RESCUE_REASON" if status == "changed" else "", "next_quest": "QUEST_RESCUE_GRAVEKEEPER" if status == "changed" else ""}
		_legacy_refused(rules, state, "old find progress retained " + status)
	for quest: String in ["QUEST_RESCUE_GRAVEKEEPER", "QUEST_TRACE_LEDGER"]:
		for status: String in ["available", "active", "resolved"]:
			var state := _ready()
			state.quest_states[quest] = {"status": status, "reason_key": "", "next_quest": ""}
			_legacy_refused(rules, state, "old follow-up progress retained " + quest + status)
	var double_reward := _ready()
	double_reward.evidence_states["EV_BLANK_DEATH_01"] = _evidence("fact")
	double_reward.evidence_states["EV_FERRY_TOKEN_01"] = _evidence("fact")
	double_reward.world_flags["FACT_YAMEN_FORMATION"] = true
	double_reward.world_flags["FACT_FERRY_ROUTE"] = true
	_legacy_refused(rules, double_reward, "double reward save remains legacy with all rewards")


func _test_bad_states() -> void:
	var rules := Rules.new()
	var invalid: Array[GameState] = [null]
	var broken_clock := _ready()
	broken_clock.time_state["slot"] = 8
	invalid.append(broken_clock)
	for value: Variant in [null, true, "home", [], {}, {"id": Rules.RECORD_KEY}, {"id": Rules.RECORD_KEY, "choice": "home", "phase_id": Rules.PHASE_ID, "route_id": "ROUTE_WRONG"}]:
		var state := _ready()
		state.world_flags[Rules.RECORD_KEY] = value
		invalid.append(state)
	var valid: Dictionary = rules.prepare(_ready(), "home")["state"].world_flags[Rules.RECORD_KEY]
	for field: String in ["id", "choice", "phase_id", "route_id"]:
		for value: Variant in [null, 3, [], true, "bad"]:
			var state := _ready()
			state.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
			state.world_flags[Rules.RECORD_KEY][field] = value
			invalid.append(state)
		var missing := _ready()
		missing.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
		missing.world_flags[Rules.RECORD_KEY].erase(field)
		invalid.append(missing)
	var extra := _ready()
	extra.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
	extra.world_flags[Rules.RECORD_KEY]["settled"] = true
	invalid.append(extra)
	var missing_index := _ready()
	missing_index.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
	missing_index.evidence_states.erase("EV_INDEX_01")
	invalid.append(missing_index)
	var missing_search := _ready()
	missing_search.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
	missing_search.quest_states.erase("QUEST_FIND_GRAVEKEEPER")
	invalid.append(missing_search)
	for status: String in ["locked", "available"]:
		var unaccepted_search := _ready()
		unaccepted_search.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
		unaccepted_search.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] = status
		invalid.append(unaccepted_search)
	var fabricated := GameState.new()
	fabricated.route_id = "ROUTE_BRANCH_TEST"
	fabricated.world_flags[Rules.RECORD_KEY] = valid.duplicate(true)
	invalid.append(fabricated)
	for field: String in ["knowledge_state", "holder_id", "validity", "discovered_at"]:
		for value: Variant in [null, "bad", 2, []]:
			var state := _ready()
			state.evidence_states["EV_INDEX_01"][field] = value
			invalid.append(state)
	for flag: String in Rules.PROGRESS_FLAGS + Rules.NAVIGATION_FLAGS:
		var state := _ready()
		state.world_flags[flag] = "true"
		invalid.append(state)
	for identifier: String in Rules.QUEST_IDS:
		for value: Variant in [null, 3, {}, {"status":"failed"}, {"status":"changed"}]:
			var state := _ready()
			state.quest_states[identifier] = value
			invalid.append(state)
	for state: GameState in invalid:
		_check(not rules.validate_state(state).is_empty(), "bad relevant state rejected")
		_refused(rules, state, "home", ERR_INVALID_DATA)
		_check(rules.record(state).is_empty() and not rules.is_legacy(state) and not rules.allows_step(state, "STEP_RECEIVE_INDEX"), "bad state queries safely fail closed")


func _test_step_guard() -> void:
	var rules := Rules.new()
	var steps: Array[String] = ["STEP_FIRST_HOME", "STEP_FIRST_DOCK", "STEP_RECORD_BOATMAN", "STEP_TAKE_FERRY_TOKEN", "STEP_CHALLENGE_BOATMAN", "STEP_INSPECT_BLANK", "STEP_COMPARE_INDEX_BLANK", "STEP_PREPARE_RESCUE", "STEP_GRAVES_VICTORY", "STEP_HAND_OVER_BLANK"]
	var old := _ready()
	old.evidence_states["EV_BLANK_DEATH_01"] = _evidence()
	var old_before: Dictionary = old.to_dict()
	for step: String in steps:
		_check(rules.allows_step(old, step), "guard preserves no-receipt legacy flow " + step)
	_check(old.to_dict() == old_before, "legacy queries preserve state")
	for choice: String in ["home", "dock"]:
		var state: GameState = rules.prepare(_ready(), choice)["state"]
		var before: Dictionary = state.to_dict()
		for step: String in steps:
			var blocked: bool = step in (["STEP_FIRST_DOCK", "STEP_RECORD_BOATMAN", "STEP_TAKE_FERRY_TOKEN", "STEP_CHALLENGE_BOATMAN"] if choice == "home" else ["STEP_FIRST_HOME", "STEP_INSPECT_BLANK", "STEP_COMPARE_INDEX_BLANK"])
			_check(rules.allows_step(state, step) != blocked, "receipt guards opposite opportunity " + choice + step)
		_check(state.to_dict() == before, "step guard is read-only " + choice)
		_check(not rules.allows_step(state, "") and not rules.allows_step(state, "not a step"), "guard rejects invalid identifiers " + choice)
	var home: GameState = rules.prepare(_ready(), "home")["state"]
	home.evidence_states["EV_FERRY_TOKEN_01"] = _evidence()
	_check(not rules.allows_step(home, "STEP_CHALLENGE_BOATMAN"), "one proof alone does not bypass opportunity")
	home.evidence_states["CL_BOATMAN_01"] = _evidence()
	_check(rules.allows_step(home, "STEP_CHALLENGE_BOATMAN"), "same existing testimony and proof can establish truth regardless choice")
	var dock: GameState = rules.prepare(_ready(), "dock")["state"]
	dock.evidence_states["EV_BLANK_DEATH_01"] = _evidence()
	_check(rules.allows_step(dock, "STEP_INSPECT_BLANK") and rules.allows_step(dock, "STEP_COMPARE_INDEX_BLANK"), "existing original can be inspected and compared regardless choice")
	# A real domain command still checks the evidence and knowledge rules; this
	# opportunity guard is deliberately not an alternative command executor.
	var investigation := Investigation.new()
	_check(investigation.configure(JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/investigation.json"))).is_empty(), "canonical investigation config")
	_check(investigation.prepare_step(dock, "STEP_COMPARE_INDEX_BLANK")["error"] == OK, "truth-preserving exception uses canonical comparison")
	_check(investigation.prepare_step(home, "STEP_CHALLENGE_BOATMAN")["error"] == OK, "truth-preserving exception uses canonical challenge")


func _ready() -> GameState:
	var state := GameState.new()
	state.route_id = "ROUTE_BRANCH_TEST"
	state.quest_states["QUEST_FIND_GRAVEKEEPER"] = {"status": "active", "reason_key": "", "next_quest": ""}
	state.evidence_states["EV_INDEX_01"] = _evidence()
	return state


func _evidence(knowledge: String = "clue") -> Dictionary:
	return {"knowledge_state": knowledge, "holder_id": "PLAYER", "validity": "verified" if knowledge == "fact" else "unverified", "discovered_at": {"day":1, "slot":0}}


func _legacy_refused(rules: RefCounted, state: GameState, label: String) -> void:
	var before: Dictionary = state.to_dict()
	_check(rules.is_legacy(state), label)
	for choice: String in ["home", "dock"]:
		_refused(rules, state, choice, ERR_UNAVAILABLE)
	_check(state.to_dict() == before and not state.world_flags.has(Rules.RECORD_KEY), "legacy data untouched " + label)


func _refused(rules: RefCounted, state: GameState, choice: String, expected_error: Error) -> void:
	var before: Dictionary = state.to_dict() if state != null else {}
	var result: Dictionary = rules.prepare(state, choice)
	_check(result.size() == 3 and result["error"] == expected_error and result["state"] == null and result["summary"].is_empty(), "refusal returns no candidate or misleading summary")
	_check(state == null or state.to_dict() == before, "refused prepare never mutates input")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
