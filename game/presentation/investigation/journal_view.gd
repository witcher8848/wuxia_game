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
		var week8: bool = state.world_flags.get("FACT_W8_ACTIVE", false)
		if quest["id"] == "QUEST_FIND_GRAVEKEEPER":
			var next_key := "INV_OBJECTIVE_SEARCH"
			if record["status"] == "locked": next_key = "INV_OBJECTIVE_START"
			elif record["status"] == "available": next_key = "INV_OBJECTIVE_ACCEPT"
			elif state.world_flags.get("FACT_WEST_GRAVES", false): next_key = "INV_OBJECTIVE_GRAVES"
			if week8 and record["status"] == "active":
				var receipt: Dictionary = state.world_flags.get("CHOICE_CH01_FIRST_LEAD", {})
				next_key = "W8_OBJECTIVE_CHOOSE" if receipt.is_empty() else "W8_OBJECTIVE_HOME" if receipt.get("choice") == "home" else "W8_OBJECTIVE_DOCK"
				if state.world_flags.get("FACT_WEST_GRAVES", false): next_key = "GUIDE_DEPART"
			if record["status"] not in ["resolved", "changed"]:
				detail += "\n" + _t(next_key)
		if record["status"] == "changed":
			detail += "\n" + _t(record["reason_key"]) + "\n→ " + names.get(record["next_quest"], record["next_quest"])
		if quest["id"] == "QUEST_TRACE_LEDGER" and record["status"] in ["available", "active", "resolved"]:
			var next_key := "INV_OBJECTIVE_LEDGER"
			if week8:
				next_key = "W8_OBJECTIVE_AFTERMATH"
				if state.world_flags.get("FACT_W8_REVIEWED", false): next_key = "W8_OBJECTIVE_END"
				elif state.world_flags.get("FACT_BURIAL_MISMATCH", false): next_key = "W8_OBJECTIVE_REVIEW"
				elif state.evidence_states.has("EV_GRAVE_TAG_03") and state.evidence_states.has("EV_BURIAL_PAGE_01"): next_key = "W8_OBJECTIVE_COMPARE"
			detail += "\n" + _t(next_key)
		for fact: String in ["FACT_YAMEN_FORMATION", "FACT_FERRY_ROUTE"]:
			var prepared_fact: String = "FACT_W8_FERRY_ASSISTANCE" if week8 and fact == "FACT_FERRY_ROUTE" else fact
			# Later true evidence does not retroactively grant first-battle intel
			# or deployment. The Routes page records the opportunity afterwards.
			if week8 and state.world_flags.get("FACT_GRAVES_SAFE", false): continue
			if quest["id"] == "QUEST_FIND_GRAVEKEEPER" and state.world_flags.get(prepared_fact, false):
				detail += "\n" + _t("INV_REWARD_FORMATION" if fact == "FACT_YAMEN_FORMATION" else "INV_REWARD_FERRY")
		entries.append({"id":quest["id"], "title":names[quest["id"]] + " · " + _t("INV_STATUS_" + record["status"]), "detail":detail})
	return entries

static func people_entries(projected: Array) -> Array[Dictionary]:
	# ContentDB owns discovery/privacy and localized relationship stages. The UI
	# accepts only the published card fields, not hidden trust scores or live XY.
	var entries: Array[Dictionary] = []
	for item: Dictionary in projected:
		entries.append({"id":item["id"], "title":item["title"], "detail":item["detail"]})
	return entries

static func route_entries(state: GameState) -> Array[Dictionary]:
	# This is a read-only record of the player's own choice, not an ending menu,
	# alternate-history preview, or permission to restore the immutable anchor.
	var entries: Array[Dictionary] = []
	if not state.world_flags.get("FACT_W8_ACTIVE", false): return entries
	var receipt: Variant = state.world_flags.get("CHOICE_CH01_FIRST_LEAD", {})
	if not receipt is Dictionary or not receipt.get("choice", "") in ["home", "dock"]: return entries
	var home: bool = receipt["choice"] == "home"
	entries.append({"id":"CHOICE_CH01_FIRST_LEAD", "title":_t("W8_ROUTE_HOME" if home else "W8_ROUTE_DOCK"),
		"detail":_t("W8_ROUTE_PHASE") + "\n" + _t("W8_CHOICE_HOME_SUMMARY" if home else "W8_CHOICE_DOCK_SUMMARY") + "\n" + _t("W8_ROUTE_RECALL_LOCKED")})
	if state.world_flags.get("FACT_GRAVES_SAFE", false):
		entries.append({"id":"W8_RESCUE_REVIEW", "title":_t("W8_ROUTE_AFTER_HOME" if home else "W8_ROUTE_AFTER_DOCK"),
			"detail":_t("W8_ROUTE_AFTER_HOME_TEXT" if home else "W8_ROUTE_AFTER_DOCK_TEXT") + "\n" + _t("W8_ROUTE_RECALL_LOCKED")})
	return entries

static func _t(key: String) -> String:
	return TranslationServer.translate(key).replace("\\n", "\n")
