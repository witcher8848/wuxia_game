class_name InvestigationRules
extends RefCounted
## Content-backed commands. Returns a candidate GameState; never mutates a live
## session, scene or save file. Day 22 foundation, not a dialogue/solver UI.

const KNOWLEDGE := ["clue", "doubt", "fact"]
const QUEST_STATES := ["locked", "available", "active", "resolved", "changed"]
const QUEST_TRANSITIONS := {
	"locked": ["available"], "available": ["active"],
	"active": ["resolved", "changed"], "changed": ["active", "resolved"], "resolved": [],
}
var _data: Dictionary = {}
var _evidence: Dictionary = {}
var _facts: Dictionary = {}
var _quests: Dictionary = {}
var _holders: Dictionary = {}
var _steps: Dictionary = {}


func configure(data: Dictionary) -> String:
	if not GameState.is_json_value(data):
		return "Investigation content must be finite JSON."
	# Validate in a separate registry. Failed reload leaves this instance intact.
	var candidate := InvestigationRules.new()
	var error: String = candidate._build(data)
	if not error.is_empty():
		return error
	_data = data.duplicate(true)
	_evidence = candidate._evidence
	_facts = candidate._facts
	_quests = candidate._quests
	_holders = candidate._holders
	_steps = candidate._steps
	return ""


func definitions() -> Dictionary:
	return _data.duplicate(true)


func _build(data: Dictionary) -> String:
	for name: String in ["evidence", "facts", "quests", "holders", "steps"]:
		if not data.get(name) is Array:
			return "Missing investigation array: " + name
	for identifier: Variant in data["holders"]:
		if not _id(identifier) or _holders.has(identifier):
			return "Duplicate or invalid holder."
		_holders[identifier] = true
	if not _holders.has("PLAYER"):
		return "PLAYER holder required."
	for identifier: Variant in data["facts"]:
		if not _id(identifier) or not identifier.begins_with("FACT_") or _facts.has(identifier):
			return "Duplicate or invalid fact."
		_facts[identifier] = true
	for entry: Variant in data["evidence"]:
		if not entry is Dictionary or not _id(entry.get("id")) or _evidence.has(entry["id"]):
			return "Duplicate or invalid evidence."
		for field: String in ["title_key", "description_key", "source_id"]:
			if not _id(entry.get(field)):
				return "Missing evidence field: " + field
		if not entry.get("kind") in ["document", "object", "testimony", "observation", "martial"]:
			return "Invalid evidence kind."
		if not entry["source_id"] in _holders or not _id(entry.get("initial_holder")) or not entry["initial_holder"] in _holders:
			return "Unknown evidence source or holder."
		_evidence[entry["id"]] = entry.duplicate(true)
	for entry: Variant in data["quests"]:
		if not entry is Dictionary or not _id(entry.get("id")) or _quests.has(entry["id"]) or not _id(entry.get("title_key")):
			return "Duplicate or invalid quest."
		_quests[entry["id"]] = entry.duplicate(true)
	for entry: Variant in data["steps"]:
		if not entry is Dictionary or not _id(entry.get("id")) or not entry["id"].begins_with("STEP_") or _steps.has(entry["id"]):
			return "Duplicate or invalid step."
		if not _id(entry.get("feedback_key")) or not entry.get("requires") is Array or not entry.get("effects") is Array or entry["effects"].is_empty():
			return "Step requires conditions, feedback key and effects."
		for condition: Variant in entry["requires"]:
			if not _valid_operation(condition, false):
				return "Invalid condition or reference in " + entry["id"]
		for effect: Variant in entry["effects"]:
			if not _valid_operation(effect, true):
				return "Invalid effect or reference in " + entry["id"]
		_steps[entry["id"]] = entry.duplicate(true)
	return ""


func _valid_operation(value: Variant, effect: bool) -> bool:
	if not value is Dictionary or not _id(value.get("op")) or not _id(value.get("id")):
		return false
	var identifier: String = value["id"]
	var op: String = value["op"]
	if effect:
		match op:
			"discover":
				return _fields(value, ["op", "id"]) and _evidence.has(identifier)
			"knowledge":
				return _fields(value, ["op", "id", "value"]) and _evidence.has(identifier) and value["value"] in KNOWLEDGE
			"transfer":
				return _fields(value, ["op", "id", "from", "to"]) and _evidence.has(identifier) and _id(value["from"]) and _id(value["to"]) and _holders.has(value["from"]) and _holders.has(value["to"]) and value["from"] != value["to"]
			"set_fact":
				return _fields(value, ["op", "id"]) and _facts.has(identifier)
			"set_quest":
				if not _fields(value, ["op", "id", "value", "reason_key", "next_quest"]) or not _quests.has(identifier) or not value["value"] in QUEST_STATES:
					return false
				if value["value"] == "changed":
					return _id(value["reason_key"]) and _id(value["next_quest"]) and _quests.has(value["next_quest"]) and value["next_quest"] != identifier
				return value["reason_key"] is String and value["next_quest"] is String and value["reason_key"].is_empty() and value["next_quest"].is_empty()
	else:
		match op:
			"evidence_at_least":
				return _fields(value, ["op", "id", "value"]) and _evidence.has(identifier) and value["value"] in KNOWLEDGE
			"holder_is":
				return _fields(value, ["op", "id", "value"]) and _evidence.has(identifier) and _id(value["value"]) and _holders.has(value["value"])
			"fact_is":
				return _fields(value, ["op", "id", "value"]) and _facts.has(identifier) and value["value"] is bool
			"quest_is":
				return _fields(value, ["op", "id", "value"]) and _quests.has(identifier) and value["value"] in QUEST_STATES
	return false


func validate_state(state: GameState) -> String:
	if state == null or not state.validate().is_empty():
		return "Invalid game state."
	for identifier: String in _evidence:
		if not state.evidence_states.has(identifier):
			continue # Empty containers from old saves are valid initial state.
		var record: Variant = state.evidence_states[identifier]
		if not record is Dictionary or not record.get("knowledge_state") in KNOWLEDGE:
			return "Invalid evidence knowledge."
		if not _id(record.get("holder_id")) or not _holders.has(record["holder_id"]):
			return "Invalid evidence holder."
		if not record.get("validity") in ["unverified", "verified"]:
			return "Invalid evidence validity."
		var discovered: Variant = record.get("discovered_at")
		if not discovered is Dictionary or not GameState.is_whole_number(discovered.get("day")) or discovered["day"] < 1 or not GameState.is_whole_number(discovered.get("slot")) or discovered["slot"] < 0 or discovered["slot"] > 7:
			return "Invalid discovery time."
	for identifier: String in _facts:
		if state.world_flags.has(identifier) and not state.world_flags[identifier] is bool:
			return "Invalid fact value."
	for identifier: String in _steps:
		var applied: String = "APPLIED_" + identifier
		if state.world_flags.has(applied) and not state.world_flags[applied] is bool:
			return "Invalid applied-step marker."
	for identifier: String in _quests:
		if not state.quest_states.has(identifier):
			continue
		var record: Variant = state.quest_states[identifier]
		if not record is Dictionary or not record.get("status") in QUEST_STATES:
			return "Invalid quest state."
		if record["status"] == "changed":
			if not _id(record.get("reason_key")) or not _id(record.get("next_quest")) or not _quests.has(record["next_quest"]) or record["next_quest"] == identifier:
				return "Changed quest needs reason and another valid target."
	return ""


func condition_matches(state: GameState, condition: Dictionary) -> bool:
	if not validate_state(state).is_empty() or not _valid_operation(condition, false):
		return false
	var identifier: String = condition["id"]
	match condition["op"]:
		"evidence_at_least":
			var record: Dictionary = state.evidence_states.get(identifier, {})
			return KNOWLEDGE.find(record.get("knowledge_state", "")) >= KNOWLEDGE.find(condition["value"])
		"holder_is":
			var record: Dictionary = state.evidence_states.get(identifier, {})
			return not record.is_empty() and record["holder_id"] == condition["value"]
		"fact_is":
			return state.world_flags.get(identifier, false) == condition["value"]
		"quest_is":
			return state.quest_states.get(identifier, {}).get("status", "locked") == condition["value"]
	return false


func prepare_step(state: GameState, step_id: String) -> Dictionary:
	var error: String = validate_state(state)
	if not error.is_empty():
		return _failure(ERR_INVALID_DATA, error)
	if not _steps.has(step_id):
		return _failure(ERR_INVALID_PARAMETER, "Unknown step.")
	if state.world_flags.get("APPLIED_" + step_id, false):
		return _failure(ERR_ALREADY_EXISTS, "Step already applied.")
	var step: Dictionary = _steps[step_id]
	for condition: Dictionary in step["requires"]:
		if not condition_matches(state, condition):
			return _failure(ERR_UNAVAILABLE, "Step requirements not satisfied.")
	var candidate: GameState = GameState.from_dict(state.to_dict())
	for effect: Dictionary in step["effects"]:
		var identifier: String = effect["id"]
		match effect["op"]:
			"discover":
				if not candidate.evidence_states.has(identifier):
					candidate.evidence_states[identifier] = {"knowledge_state": "clue", "holder_id": _evidence[identifier]["initial_holder"], "validity": "unverified", "discovered_at": state.time_state.duplicate(true)}
			"knowledge":
				var record: Dictionary = candidate.evidence_states.get(identifier, {})
				if record.is_empty() or KNOWLEDGE.find(effect["value"]) < KNOWLEDGE.find(record["knowledge_state"]):
					return _failure(ERR_UNAVAILABLE, "Cannot upgrade unknown evidence or forget known information.")
				record["knowledge_state"] = effect["value"]
				if effect["value"] == "fact":
					record["validity"] = "verified"
			"transfer":
				var record: Dictionary = candidate.evidence_states.get(identifier, {})
				if record.is_empty() or record["holder_id"] != effect["from"]:
					return _failure(ERR_UNAVAILABLE, "Original is not held by expected source.")
				record["holder_id"] = effect["to"]
			"set_fact":
				candidate.world_flags[identifier] = true
			"set_quest":
				var prior: String = candidate.quest_states.get(identifier, {}).get("status", "locked")
				if effect["value"] != prior and not effect["value"] in QUEST_TRANSITIONS[prior]:
					return _failure(ERR_UNAVAILABLE, "Illegal quest transition.")
				candidate.quest_states[identifier] = {"status": effect["value"], "reason_key": effect["reason_key"], "next_quest": effect["next_quest"]}
	candidate.world_flags["APPLIED_" + step_id] = true
	error = validate_state(candidate)
	if not error.is_empty():
		return _failure(ERR_INVALID_DATA, error)
	return {"error": OK, "state": candidate, "message": "", "feedback_key": step["feedback_key"]}


static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.is_valid_identifier()


static func _fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _failure(code: Error, message: String) -> Dictionary:
	return {"error": code, "state": null, "message": message, "feedback_key": ""}
