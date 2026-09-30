extends RefCounted
## Read-only projection. Evidence knowledge is independent of original ownership.
static func evidence_entries(state: GameState, definitions: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for evidence: Dictionary in definitions.get("evidence", []):
		if not state.evidence_states.has(evidence["id"]):
			continue
		var record: Dictionary = state.evidence_states[evidence["id"]]
		var detail: String = _t(evidence["description_key"]) + "\n" + _t("INV_EVIDENCE_META") % [
			_t("INV_KNOW_" + record["knowledge_state"]),
			_t("INV_HOLDER_" + record["holder_id"]),
			_t("INV_HOLDER_" + evidence["source_id"])]
		entries.append({"id": evidence["id"], "title": _t(evidence["title_key"]), "detail": detail})
	return entries

static func quest_entries(state: GameState, definitions: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var names: Dictionary = {}
	for quest: Dictionary in definitions.get("quests", []):
		names[quest["id"]] = _t(quest["title_key"])
	for quest: Dictionary in definitions.get("quests", []):
		var record: Dictionary = state.quest_states.get(quest["id"], {"status":"locked"})
		var detail: String = _t("INV_STATUS_" + record["status"])
		if quest["id"] == "QUEST_FIND_GRAVEKEEPER":
			var next_key := "INV_OBJECTIVE_SEARCH"
			if record["status"] == "locked": next_key = "INV_OBJECTIVE_START"
			elif record["status"] == "available": next_key = "INV_OBJECTIVE_ACCEPT"
			elif state.world_flags.get("FACT_WEST_GRAVES", false): next_key = "INV_OBJECTIVE_GRAVES"
			if record["status"] not in ["resolved", "changed"]:
				detail += "\n" + _t(next_key)
		if record["status"] == "changed":
			detail += "\n" + _t(record["reason_key"]) + "\n→ " + names.get(record["next_quest"], record["next_quest"])
		if quest["id"] == "QUEST_TRACE_LEDGER" and record["status"] == "available":
			detail += "\n" + _t("INV_OBJECTIVE_LEDGER")
		for fact: String in ["FACT_YAMEN_FORMATION", "FACT_FERRY_ROUTE"]:
			if quest["id"] == "QUEST_FIND_GRAVEKEEPER" and state.world_flags.get(fact, false):
				detail += "\n" + _t("INV_REWARD_FORMATION" if fact == "FACT_YAMEN_FORMATION" else "INV_REWARD_FERRY")
		entries.append({"id":quest["id"], "title":names[quest["id"]] + " · " + _t("INV_STATUS_" + record["status"]), "detail":detail})
	return entries

static func _t(key: String) -> String:
	return TranslationServer.translate(key)
