class_name InquiryRules
extends RefCounted
## Evidence selection is a finite content rule, not arbitrary combinations/scripts.
var _entries: Dictionary = {}
var _rules: InvestigationRules

func configure(data: Variant, rules: InvestigationRules, keys: Dictionary) -> String:
	if not data is Array or not GameState.is_json_value(data):
		return "Inquiries must be a finite array."
	var evidence: Dictionary = {}
	var steps: Dictionary = {}
	for entry: Dictionary in rules.definitions().get("evidence", []):
		evidence[entry["id"]] = true
	for step: Dictionary in rules.definitions().get("steps", []):
		steps[step["id"]] = true
	var entries: Dictionary = {}
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry["id"].is_valid_identifier() or entries.has(entry["id"]):
			return "Duplicate or invalid inquiry ID."
		if not entry.get("kind") in ["challenge", "compare"] or not entry.get("candidates") is Array or entry["candidates"].size() < 2 or entry["candidates"].size() > 4:
			return "Inquiry needs two to four relevant candidates."
		var seen: Dictionary = {}
		for identifier: Variant in entry["candidates"]:
			if not identifier is String or not evidence.has(identifier) or seen.has(identifier):
				return "Invalid or repeated inquiry candidate."
			seen[identifier] = true
		for field: String in ["title_key", "prompt_key", "wrong_key"]:
			if not entry.get(field) is String or not keys.has(entry[field]):
				return "Missing inquiry translation."
		if not entry.get("step_id") is String or not steps.has(entry["step_id"]):
			return "Unknown inquiry command."
		if entry["kind"] == "challenge":
			if entry.size() != 9 or not entry.get("claim_id") is String or not evidence.has(entry["claim_id"]) or not entry.get("proof_id") is String or not seen.has(entry["proof_id"]) or entry["proof_id"] == entry["claim_id"]:
				return "Invalid challenge claim/proof."
		else:
			if entry.size() != 8 or not entry.get("pair") is Array or entry["pair"].size() != 2:
				return "Comparison needs a pair."
			if not entry["pair"][0] is String or not entry["pair"][1] is String or entry["pair"][0] == entry["pair"][1] or not seen.has(entry["pair"][0]) or not seen.has(entry["pair"][1]):
				return "Invalid comparison pair."
		entries[entry["id"]] = entry.duplicate(true)
	_entries = entries
	_rules = rules
	return ""

func view(identifier: String, state: GameState, first := "") -> Dictionary:
	if not _entries.has(identifier) or not _rules.validate_state(state).is_empty():
		return {}
	var entry: Dictionary = _entries[identifier]
	var known: Array[String] = []
	for candidate: String in entry["candidates"]:
		if candidate != first and state.evidence_states.has(candidate):
			known.append(candidate)
	return {"id": identifier, "kind": entry["kind"], "title_key": entry["title_key"], "prompt_key": entry["prompt_key"], "candidates": known, "claim_id": entry.get("claim_id", "")}

func prepare(state: GameState, identifier: String, selected: Array) -> Dictionary:
	if not _entries.has(identifier) or not _rules.validate_state(state).is_empty():
		return _failure(ERR_INVALID_DATA, "INV_COMMAND_FAILED")
	var entry: Dictionary = _entries[identifier]
	var count: int = 1 if entry["kind"] == "challenge" else 2
	if selected.size() != count or (count == 2 and selected[0] == selected[1]):
		return _failure(ERR_INVALID_PARAMETER, "INV_PAIR_DISTINCT")
	for candidate: Variant in selected:
		if not candidate is String or not candidate in entry["candidates"] or not state.evidence_states.has(candidate):
			return _failure(ERR_UNAVAILABLE, "INV_REQUIREMENTS")
	if entry["kind"] == "challenge" and not state.evidence_states.has(entry["claim_id"]):
		return _failure(ERR_UNAVAILABLE, "INV_REQUIREMENTS")
	var matches: bool = selected[0] == entry["proof_id"] if count == 1 else selected[0] in entry["pair"] and selected[1] in entry["pair"]
	if not matches:
		return _failure(ERR_INVALID_PARAMETER, entry["wrong_key"])
	var proposal: Dictionary = _rules.prepare_step(state, entry["step_id"])
	if proposal["error"] != OK:
		proposal["feedback_key"] = "INV_ALREADY_RECORDED" if proposal["error"] == ERR_ALREADY_EXISTS else "INV_REQUIREMENTS"
	return proposal

static func _failure(error: Error, feedback: String) -> Dictionary:
	return {"error": error, "state": null, "feedback_key": feedback}
