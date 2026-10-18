class_name BranchChoiceRules
extends RefCounted
## The first lead's irreversible opportunity receipt. Pure proposals only: no
## disk access, clock mutation, evidence grants, ownership or battle rewards.

const RECORD_KEY := "CHOICE_CH01_FIRST_LEAD"
const ACTIVE_FLAG := "FACT_W8_ACTIVE"
const PHASE_ID := "PHASE_DAY1_AFTERNOON"
const CHOICES := ["home", "dock"]
const IMPACT_IDS := ["IMPACT_ORIGINAL_DOCUMENT", "IMPACT_FERRY_ASSISTANCE", "IMPACT_BATTLE_PREPARATION"]
const EVIDENCE_IDS := ["EV_INDEX_01", "EV_BLANK_DEATH_01", "EV_FERRY_TOKEN_01", "CL_BOATMAN_01", "EV_HOME_EXTRACT_01", "EV_GRAVE_TAG_03", "EV_BURIAL_PAGE_01"]
const HOLDERS := ["PLAYER", "CHAR_PRISONER", "CHAR_FATHER", "FACTION_INSPECTOR", "CHAR_BOATMAN"]
const QUEST_IDS := ["QUEST_FIND_GRAVEKEEPER", "QUEST_RESCUE_GRAVEKEEPER", "QUEST_TRACE_LEDGER"]
const QUEST_STATUSES := ["locked", "available", "active", "resolved", "changed"]
const NAVIGATION_FLAGS := ["FACT_FIRST_HOME", "FACT_FIRST_DOCK", "APPLIED_STEP_FIRST_HOME", "APPLIED_STEP_FIRST_DOCK"]
const PROGRESS_FLAGS := [
	"FACT_WEST_GRAVES", "FACT_YAMEN_FORMATION", "FACT_FERRY_ROUTE", "FACT_GRAVES_SAFE",
	"APPLIED_STEP_INSPECT_BLANK", "APPLIED_STEP_COMPARE_INDEX_BLANK",
	"APPLIED_STEP_RECORD_BOATMAN", "APPLIED_STEP_TAKE_FERRY_TOKEN", "APPLIED_STEP_CHALLENGE_BOATMAN",
	"APPLIED_STEP_PREPARE_RESCUE", "APPLIED_STEP_GRAVES_VICTORY", "APPLIED_STEP_HAND_OVER_BLANK",
]


func validate_state(state: GameState) -> String:
	if state == null or not state.validate().is_empty():
		return "Invalid game state."
	for flag: String in [ACTIVE_FLAG,"FACT_W8_FERRY_ASSISTANCE","FACT_BURIAL_MISMATCH","FACT_W8_REVIEWED"]:
		if state.world_flags.has(flag) and not state.world_flags[flag] is bool: return "Invalid branch progress flag."
	# Validate the fields inspected here, without reinterpreting unrelated legacy
	# payloads or duplicating the content registry's complete domain validation.
	for identifier: String in EVIDENCE_IDS:
		if not state.evidence_states.has(identifier):
			continue
		var evidence: Variant = state.evidence_states[identifier]
		if not evidence is Dictionary or not evidence.get("knowledge_state") in ["clue", "doubt", "fact"]:
			return "Invalid first-lead evidence knowledge."
		if not evidence.get("holder_id") in HOLDERS or not evidence.get("validity") in ["unverified", "verified"]:
			return "Invalid first-lead evidence provenance."
		var discovered: Variant = evidence.get("discovered_at")
		if not discovered is Dictionary or not GameState.is_whole_number(discovered.get("day")) or discovered["day"] < 1 or not GameState.is_whole_number(discovered.get("slot")) or discovered["slot"] < 0 or discovered["slot"] > 7:
			return "Invalid first-lead evidence discovery time."
	for identifier: String in PROGRESS_FLAGS + NAVIGATION_FLAGS + ["APPLIED_STEP_RECEIVE_INDEX", "APPLIED_STEP_ACCEPT_SEARCH"]:
		if state.world_flags.has(identifier) and not state.world_flags[identifier] is bool:
			return "Invalid first-lead progress flag."
	for identifier: String in QUEST_IDS:
		if not state.quest_states.has(identifier):
			continue
		var quest: Variant = state.quest_states[identifier]
		if not quest is Dictionary or not quest.get("status") in QUEST_STATUSES:
			return "Invalid first-lead quest."
		if quest["status"] == "changed" and (not _identifier(quest.get("reason_key")) or not quest.get("next_quest") in QUEST_IDS or quest["next_quest"] == identifier):
			return "Invalid changed first-lead quest."
	if not state.world_flags.has(RECORD_KEY):
		if state.world_flags.get(ACTIVE_FLAG,false) and is_progressed_without_choice(state):
			return "New branch progress requires its choice receipt."
		return ""
	var receipt: Variant = state.world_flags[RECORD_KEY]
	if not receipt is Dictionary or receipt.size() != 4:
		return "Invalid first-lead receipt shape."
	for field: String in ["id", "choice", "phase_id", "route_id"]:
		if not receipt.get(field) is String:
			return "Invalid first-lead receipt field."
	if receipt.get("id") != RECORD_KEY or not receipt.get("choice") in CHOICES or receipt.get("phase_id") != PHASE_ID or receipt.get("route_id") != state.route_id:
		return "Invalid first-lead receipt identity."
	# A historical choice proves the lead was received and the search accepted.
	# Later ownership, quest transitions and the technical clock remain free to
	# advance under their own rules; this is not a demand to replay the choice.
	if not state.evidence_states.has("EV_INDEX_01") or not state.quest_states.get("QUEST_FIND_GRAVEKEEPER", {}).get("status", "locked") in ["active", "changed", "resolved"]:
		return "First-lead receipt is missing its accepted-search origin."
	if state.world_flags.get(ACTIVE_FLAG,false):
		var safe: bool = state.world_flags.get("FACT_GRAVES_SAFE",false)
		if not safe:
			if receipt["choice"] == "dock" and state.evidence_states.has("EV_BLANK_DEATH_01"): return "Confiscated original cannot be acquired before the rescue."
			if receipt["choice"] == "home" and (state.evidence_states.has("CL_BOATMAN_01") or state.evidence_states.has("EV_FERRY_TOKEN_01")): return "Questioned witness cannot provide a complete opportunity before the rescue."
		if state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false) and (receipt["choice"] != "dock" or not state.world_flags.get("FACT_FERRY_ROUTE",false)):
			return "Ferry assistance requires the committed witness route and its verified testimony."
		if state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false) and (not state.world_flags.get("APPLIED_STEP_CHALLENGE_BOATMAN",false) or not state.evidence_states.has("EV_FERRY_TOKEN_01") or not state.evidence_states.has("CL_BOATMAN_01")):
			return "Missing witness assistance source."
		for identifier: String in ["EV_HOME_EXTRACT_01","EV_GRAVE_TAG_03","EV_BURIAL_PAGE_01"]:
			if state.evidence_states.has(identifier) and not safe: return "Follow-up evidence precedes the rescue."
		if state.evidence_states.has("EV_HOME_EXTRACT_01") and (receipt["choice"] != "dock" or not state.world_flags.get("APPLIED_STEP_W8_SUPPLEMENT",false)): return "Missing excerpt provenance."
		if state.world_flags.get("FACT_BURIAL_MISMATCH",false):
			if not safe or not state.world_flags.get("APPLIED_STEP_W8_COMPARE_GRAVES",false): return "Missing grave comparison receipt."
			for identifier: String in ["EV_GRAVE_TAG_03","EV_BURIAL_PAGE_01"]:
				if state.evidence_states.get(identifier,{}).get("knowledge_state") != "fact": return "Grave comparison needs both verified records."
		if state.world_flags.get("FACT_W8_REVIEWED",false) and (not state.world_flags.get("FACT_BURIAL_MISMATCH",false) or not state.world_flags.get("APPLIED_STEP_W8_REVIEW",false) or state.quest_states.get("QUEST_TRACE_LEDGER",{}).get("status") != "resolved"):
			return "Missing reviewed case settlement."
	return ""


func is_progressed_without_choice(state: GameState) -> bool:
	# Do not call validate_state here: that would recurse for active new routes.
	for identifier: String in EVIDENCE_IDS:
		if identifier != "EV_INDEX_01" and state.evidence_states.has(identifier): return true
	for identifier: String in PROGRESS_FLAGS:
		if state.world_flags.get(identifier,false): return true
	for identifier: String in ["FACT_W8_FERRY_ASSISTANCE","FACT_BURIAL_MISMATCH","FACT_W8_REVIEWED","APPLIED_STEP_W8_COLLECT_GRAVES","APPLIED_STEP_W8_COMPARE_GRAVES","APPLIED_STEP_W8_REVIEW","APPLIED_STEP_W8_SUPPLEMENT","APPLIED_STEP_W8_SUPPLEMENT_BOATMAN"]:
		if state.world_flags.get(identifier,false): return true
	for identifier: String in ["QUEST_RESCUE_GRAVEKEEPER","QUEST_TRACE_LEDGER"]:
		if state.quest_states.get(identifier,{}).get("status","locked") != "locked": return true
	if state.evidence_states.has("EV_INDEX_01") and state.evidence_states["EV_INDEX_01"]["knowledge_state"] != "clue": return true
	return false


func required(state: GameState) -> bool:
	return validate_state(state).is_empty() and state.world_flags.get(ACTIVE_FLAG,false) and not state.world_flags.has(RECORD_KEY)


func prepare(state: GameState, choice: String) -> Dictionary:
	if not validate_state(state).is_empty():
		return _failure(ERR_INVALID_DATA)
	if not choice in CHOICES:
		return _failure(ERR_INVALID_PARAMETER)
	if state.world_flags.has(RECORD_KEY):
		return _failure(ERR_ALREADY_EXISTS)
	if is_legacy(state):
		return _failure(ERR_UNAVAILABLE)
	if state.quest_states.get("QUEST_FIND_GRAVEKEEPER", {}).get("status") != "active" or not state.evidence_states.has("EV_INDEX_01"):
		return _failure(ERR_UNAVAILABLE)
	if state.evidence_states["EV_INDEX_01"]["holder_id"] != "PLAYER":
		return _failure(ERR_UNAVAILABLE)
	var candidate: GameState = GameState.from_dict(state.to_dict())
	var receipt: Dictionary = {"id": RECORD_KEY, "choice": choice, "phase_id": PHASE_ID, "route_id": state.route_id}
	candidate.world_flags[RECORD_KEY] = receipt
	# The opportunity consequence is a projection of this immutable receipt, not
	# a second mutable flag that could disagree with the selected route later.
	var summary: Dictionary = receipt.duplicate(true)
	summary["impact_ids"] = IMPACT_IDS.duplicate()
	summary["opportunity_id"] = "OPP_CH01_BOATMAN_QUESTIONED" if choice == "home" else "OPP_CH01_HOME_CONFISCATED"
	return {"error": OK, "state": candidate, "summary": summary}


func record(state: GameState) -> Dictionary:
	if not validate_state(state).is_empty() or not state.world_flags.has(RECORD_KEY):
		return {}
	return state.world_flags[RECORD_KEY].duplicate(true)


func is_legacy(state: GameState) -> bool:
	if not validate_state(state).is_empty() or state.world_flags.has(RECORD_KEY):
		return false
	for identifier: String in EVIDENCE_IDS:
		if identifier != "EV_INDEX_01" and state.evidence_states.has(identifier):
			return true
	if state.evidence_states.has("EV_INDEX_01") and state.evidence_states["EV_INDEX_01"]["knowledge_state"] != "clue":
		return true
	for identifier: String in PROGRESS_FLAGS:
		if state.world_flags.get(identifier, false):
			return true
	if state.quest_states.get("QUEST_FIND_GRAVEKEEPER", {}).get("status", "locked") in ["changed", "resolved"]:
		return true
	for identifier: String in ["QUEST_RESCUE_GRAVEKEEPER", "QUEST_TRACE_LEDGER"]:
		if state.quest_states.get(identifier, {}).get("status", "locked") != "locked":
			return true
	return false


func allows_step(state: GameState, step_id: String) -> bool:
	# This adds an opportunity guard, not a command registry or authorization.
	# Callers must still validate registered steps and dedicated Session owners.
	if not validate_state(state).is_empty() or not _identifier(step_id):
		return false
	var receipt: Dictionary = record(state)
	if receipt.is_empty():
		return true # Preserve uncommitted / progressed schema-1 flows verbatim.
	if state.world_flags.get(ACTIVE_FLAG,false) and state.world_flags.get("FACT_GRAVES_SAFE",false):
		# The opportunity is settled. Short later investigation may establish true
		# knowledge, but cannot replay the completed battle or grant its old entry.
		if receipt["choice"] == "dock" and step_id == "STEP_INSPECT_BLANK": return state.evidence_states.has("EV_BLANK_DEATH_01")
		return step_id not in ["STEP_FIRST_HOME","STEP_FIRST_DOCK"]
	if receipt["choice"] == "home":
		if step_id in ["STEP_FIRST_DOCK", "STEP_RECORD_BOATMAN", "STEP_TAKE_FERRY_TOKEN"]:
			return false
		if step_id == "STEP_CHALLENGE_BOATMAN":
			return state.evidence_states.has("CL_BOATMAN_01") and state.evidence_states.has("EV_FERRY_TOKEN_01")
	else:
		if step_id == "STEP_FIRST_HOME":
			return false
		if step_id == "STEP_INSPECT_BLANK":
			return state.evidence_states.has("EV_BLANK_DEATH_01")
		if step_id == "STEP_COMPARE_INDEX_BLANK":
			return state.evidence_states.has("EV_INDEX_01") and state.evidence_states.has("EV_BLANK_DEATH_01")
	return true


static func _identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.is_valid_identifier()


static func _failure(error: Error) -> Dictionary:
	return {"error": error, "state": null, "summary": {}}
