class_name StoryEncounterRules
extends RefCounted
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
var _data: Dictionary = {}
var _rules: InvestigationRules
var _prepared_skills: Array = []

func configure(data: Dictionary, skills: Array, rules: InvestigationRules, prepared_skills: Array = []) -> String:
	if not prepared_skills.is_empty():
		var prepared_error: String = preload("res://game/domain/battle/battle_skills.gd").validate(prepared_skills)
		if not prepared_error.is_empty(): return prepared_error
	if not GameState.is_json_value(data) or data.size() != 10 or data.get("id") != "BATTLE_GRAVES_01":
		return "Invalid story encounter definition."
	if data.get("prepare_step") != "STEP_PREPARE_RESCUE" or data.get("victory_step") != "STEP_GRAVES_VICTORY" or data.get("formation_fact") != "FACT_YAMEN_FORMATION" or data.get("ferry_fact") != "FACT_FERRY_ROUTE":
		return "Invalid story-to-battle binding."
	var steps: Array[String] = []
	for step: Dictionary in rules.definitions().get("steps", []): steps.append(step["id"])
	for key: String in ["prepare_step", "victory_step"]:
		if not data.get(key) is String or not data[key] in steps: return "Unknown encounter command."
	for key: String in ["formation_fact", "ferry_fact"]:
		if not data.get(key) is String or not data[key] in rules.definitions().get("facts", []): return "Unknown encounter fact."
	if not GameState.is_whole_number(data.get("time_cost")) or not GameState.is_whole_number(data.get("trust_delta")) or data.get("time_cost") != 1 or data.get("trust_delta") != 1 or data.get("trust_character") != "CHAR_PRISONER":
		return "Invalid prototype outcome parameters."
	if not data.get("battle") is Dictionary or not data.get("ferry_deployment") is Dictionary:
		return "Missing battle or deployment."
	if data["ferry_deployment"].size() != 2 or not data["ferry_deployment"].has("CHAR_PROTAGONIST") or not data["ferry_deployment"].has("CHAR_COMPANION"):
		return "Both party members require a ferry deployment."
	var candidate: Dictionary = data.duplicate(true)
	candidate["battle"]["skill_definitions"] = skills.duplicate(true)
	var battle := Combat.new()
	var error: String = battle.configure(candidate["battle"])
	if not error.is_empty(): return error
	if battle.objective["kind"] != "eliminate": return "This story encounter requires repelling both pursuers."
	for actor: Variant in candidate["ferry_deployment"]:
		if not actor is String or battle.unit(actor).get("team") != "ally" or not BattleState._pair(candidate["ferry_deployment"][actor]):
			return "Invalid ferry deployment actor/cell."
	var nearer: Dictionary = _with_deployment(candidate)
	error = battle.configure(nearer)
	if not error.is_empty(): return error
	_data = candidate
	_rules = rules
	_prepared_skills = prepared_skills.duplicate(true)
	return ""

func prepare(state: GameState) -> Dictionary:
	if _data.is_empty(): return _failure(ERR_UNAVAILABLE)
	var proposal: Dictionary = _rules.prepare_step(state, _data["prepare_step"])
	if proposal["error"] != OK: return proposal
	if not _valid_relationship(state): return _failure(ERR_INVALID_DATA)
	var ferry: bool = state.world_flags.get(_data["ferry_fact"], false)
	if state.world_flags.get("FACT_W8_ACTIVE",false): ferry = state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false)
	var definition: Dictionary = _with_deployment(_data) if ferry else _data["battle"].duplicate(true)
	# Empty schema-1 records preserve the original story seed. An explicitly
	# confirmed preparation is applied to the protagonist, not the companion.
	if not state.martial_states.get("loadout",{}).is_empty():
		if not _prepared_skills.is_empty(): definition["skill_definitions"] = _prepared_skills.duplicate(true)
		var prepared: Dictionary = preload("res://game/domain/battle/martial_loadout.gd").normalize_state(state.martial_states,definition["skill_definitions"])
		if not prepared["error"].is_empty(): return _failure(ERR_INVALID_DATA)
		for unit: Dictionary in definition["units"]:
			if unit["id"] != "CHAR_PROTAGONIST": continue
			unit["loadout"] = prepared["state"]["loadout"].duplicate(true)
			unit["mastery"] = prepared["state"]["mastery"].duplicate(true)
	var battle := Combat.new()
	if not battle.configure(definition).is_empty(): return _failure(ERR_INVALID_DATA)
	return {"error": OK, "state": proposal["state"], "battle": battle, "id": _data["id"], "reveal": state.world_flags.get(_data["formation_fact"], false), "ferry": ferry}

func finish(state: GameState, result: Dictionary, instance_id: String) -> Dictionary:
	if instance_id.is_empty() or not instance_id.is_valid_identifier(): return _failure(ERR_INVALID_PARAMETER)
	if _data.is_empty() or result.get("outcome") != "victory" or not result.get("units") is Dictionary or not GameState.is_json_value(result) or not _valid_relationship(state):
		return _failure(ERR_INVALID_DATA)
	if result.get("objective") != _data["battle"]["objective"] or not GameState.is_whole_number(result.get("rounds")) or result["rounds"] < 1:
		return _failure(ERR_INVALID_DATA)
	if result["units"].size() != _data["battle"]["units"].size(): return _failure(ERR_INVALID_DATA)
	var survivors: Array[String] = []
	for expected: Dictionary in _data["battle"]["units"]:
		var unit: Variant = result["units"].get(expected["id"])
		if not unit is Dictionary or unit.get("team") != expected["team"] or not GameState.is_whole_number(unit.get("hp")) or unit["hp"] < 0 or unit["hp"] > expected["max_hp"]:
			return _failure(ERR_INVALID_DATA)
		if unit["team"] == "enemy" and unit["hp"] != 0: return _failure(ERR_INVALID_DATA)
		if unit["team"] == "ally" and unit["hp"] > 0: survivors.append(expected["id"])
	if survivors.is_empty(): return _failure(ERR_INVALID_DATA)
	var proposal: Dictionary = _rules.prepare_step(state, _data["victory_step"])
	if proposal["error"] != OK: return proposal
	var candidate: GameState = proposal["state"]
	var slot: int = int(candidate.time_state["slot"]) + int(_data["time_cost"])
	candidate.time_state = {"day": int(candidate.time_state["day"]) + int(slot / 8), "slot": slot % 8}
	var relationship: Dictionary = candidate.relationships.get(_data["trust_character"], {}).duplicate(true)
	relationship["trust"] = mini(100, int(relationship.get("trust", 0)) + int(_data["trust_delta"]))
	candidate.relationships[_data["trust_character"]] = relationship
	candidate.quest_states["QUEST_RESCUE_GRAVEKEEPER"]["resolution"] = {"battle_id":_data["id"], "instance_id":instance_id, "outcome":"victory", "rounds":int(result["rounds"]), "survivors":survivors}
	if not _rules.validate_state(candidate).is_empty(): return _failure(ERR_INVALID_DATA)
	if not validate_persistent_state(candidate).is_empty(): return _failure(ERR_INVALID_DATA)
	return {"error": OK, "state": candidate, "feedback_key": "INV_GRAVES_VICTORY"}

func _valid_relationship(state: GameState) -> bool:
	if state == null: return false
	var record: Variant = state.relationships.get(_data.get("trust_character", "CHAR_PRISONER"), {})
	return record is Dictionary and GameState.is_whole_number(record.get("trust", 0)) and record.get("trust", 0) >= -100 and record.get("trust", 0) <= 100

func validate_persistent_state(state: GameState) -> String:
	# Empty schema-1 saves remain valid; no transient encounter can be resumed.
	if _data.is_empty(): return ""
	if not _valid_relationship(state): return "Invalid prisoner relationship."
	var rescue: Dictionary = state.quest_states.get("QUEST_RESCUE_GRAVEKEEPER", {})
	var started: bool = state.world_flags.get("APPLIED_STEP_PREPARE_RESCUE", false)
	var finished: bool = state.world_flags.get("APPLIED_STEP_GRAVES_VICTORY", false)
	var safe: bool = state.world_flags.get("FACT_GRAVES_SAFE", false)
	if not started and not finished and not safe and rescue.is_empty(): return ""
	if not started or not finished or not safe or rescue.get("status") != "resolved":
		return "Unsettled story battles cannot be stored or loaded."
	var find: Dictionary = state.quest_states.get("QUEST_FIND_GRAVEKEEPER", {})
	if find.get("status") != "changed" or find.get("next_quest") != "QUEST_RESCUE_GRAVEKEEPER" or find.get("reason_key") != "INV_RESCUE_REASON":
		return "Missing story quest transition."
	var raw_follow: Variant = state.quest_states.get("QUEST_TRACE_LEDGER", {}).get("status", "")
	if not raw_follow is String: return "Invalid follow-up objective status."
	var follow_status: String = raw_follow
	var new_flow: bool = state.world_flags.get("FACT_W8_ACTIVE",false)
	if follow_status != "available" and not (new_flow and follow_status in ["active","resolved"]):
		return "Missing follow-up objective."
	if new_flow and follow_status in ["active","resolved"]:
		if not state.world_flags.get("APPLIED_STEP_W8_COLLECT_GRAVES",false) or not state.evidence_states.has("EV_GRAVE_TAG_03") or not state.evidence_states.has("EV_BURIAL_PAGE_01"):
			return "Missing follow-up evidence receipt."
		if follow_status == "resolved" and (not state.world_flags.get("APPLIED_STEP_W8_REVIEW",false) or not state.world_flags.get("FACT_W8_REVIEWED",false) or not state.world_flags.get("FACT_BURIAL_MISMATCH",false)):
			return "Missing follow-up review receipt."
	var resolution: Variant = rescue.get("resolution")
	if not resolution is Dictionary or resolution.get("battle_id") != _data["id"] or resolution.get("outcome") != "victory":
		return "Invalid settlement receipt."
	if not resolution.get("instance_id") is String or not resolution["instance_id"].begins_with("GRAVES_") or not resolution["instance_id"].is_valid_identifier():
		return "Invalid settlement instance."
	if not GameState.is_whole_number(resolution.get("rounds")) or resolution["rounds"] < 1 or not resolution.get("survivors") is Array or resolution["survivors"].is_empty():
		return "Invalid settlement rounds or survivors."
	var seen: Dictionary = {}
	for survivor: Variant in resolution["survivors"]:
		if not survivor is String or not survivor in ["CHAR_PROTAGONIST", "CHAR_COMPANION"] or seen.has(survivor): return "Invalid survivor reference."
		seen[survivor] = true
	return ""

static func _with_deployment(data: Dictionary) -> Dictionary:
	var definition: Dictionary = data["battle"].duplicate(true)
	for unit: Dictionary in definition["units"]:
		if data["ferry_deployment"].has(unit["id"]): unit["cell"] = data["ferry_deployment"][unit["id"]].duplicate()
	return definition

static func _failure(error: Error) -> Dictionary:
	return {"error": error, "state": null, "feedback_key": "INV_COMMAND_FAILED"}
