extends RefCounted
## Read-only guidance: destinations, never a highlighted correct evidence item.
static func project(state: GameState) -> Dictionary:
	var flags := state.world_flags
	if flags.get("FACT_W8_ACTIVE", false):
		return _week8_project(state)
	if flags.get("FACT_GRAVES_SAFE", false):
		return {"key":"GUIDE_COMPLETE", "target":""}
	var dock: bool = flags.get("FACT_FIRST_DOCK", false)
	if state.scene_id == "SCENE_HOME_COURTYARD": dock = false
	if state.scene_id == "SCENE_RIVER_DOCK": dock = true
	var known: bool = flags.get("FACT_WEST_GRAVES", false)
	if known: dock = true
	var target := ""
	var key := "GUIDE_DOCK" if dock else "GUIDE_HOME"
	if state.scene_id == "SCENE_TOWN_STREET":
		target = "EXIT_STREET_DOCK" if dock else "EXIT_STREET_HOME"
	elif state.scene_id == "SCENE_HOME_COURTYARD":
		target = "EXIT_HOME_STREET" if known else "DOC_HOME_NOTE"
		key = "GUIDE_LEAVE_HOME" if known else "GUIDE_COMPARE" if state.evidence_states.has("EV_BLANK_DEATH_01") else "GUIDE_DOCUMENT"
	elif state.scene_id == "SCENE_RIVER_DOCK":
		target = "NPC_DOCK_WORKER"
		key = "GUIDE_DEPART" if known else "GUIDE_CHALLENGE" if state.evidence_states.has("CL_BOATMAN_01") else "GUIDE_BOATMAN"
	return {"key":key, "target":target}

static func _week8_project(state: GameState) -> Dictionary:
	var flags := state.world_flags
	var target := "NPC_DOCK_WORKER" if state.scene_id == "SCENE_RIVER_DOCK" else "EXIT_HOME_STREET" if state.scene_id == "SCENE_HOME_COURTYARD" else "EXIT_STREET_DOCK"
	if flags.get("FACT_GRAVES_SAFE", false):
		var after_key := "W8_OBJECTIVE_AFTERMATH"
		if flags.get("FACT_W8_REVIEWED", false): after_key = "W8_OBJECTIVE_END"
		elif flags.get("FACT_BURIAL_MISMATCH", false): after_key = "W8_OBJECTIVE_REVIEW"
		elif state.evidence_states.has("EV_GRAVE_TAG_03") and state.evidence_states.has("EV_BURIAL_PAGE_01"): after_key = "W8_OBJECTIVE_COMPARE"
		return {"key":after_key, "target":target}
	var receipt: Variant = flags.get("CHOICE_CH01_FIRST_LEAD", {})
	if receipt is Dictionary and receipt.get("choice", "") in ["home", "dock"]:
		if flags.get("FACT_WEST_GRAVES", false):
			return {"key":"GUIDE_DEPART", "target":target}
		var home: bool = receipt["choice"] == "home"
		if home:
			target = "DOC_HOME_NOTE" if state.scene_id == "SCENE_HOME_COURTYARD" else "EXIT_DOCK_STREET" if state.scene_id == "SCENE_RIVER_DOCK" else "EXIT_STREET_HOME"
		return {"key":"W8_OBJECTIVE_HOME" if home else "W8_OBJECTIVE_DOCK", "target":target}
	# The prologue's lead is navigation only. It may guide the player to either
	# shared confirmation entry without silently choosing an irreversible route.
	var dock: bool = flags.get("FACT_FIRST_DOCK", false)
	if state.scene_id == "SCENE_HOME_COURTYARD": target = "DOC_HOME_NOTE"
	elif state.scene_id == "SCENE_TOWN_STREET": target = "EXIT_STREET_DOCK" if dock else "EXIT_STREET_HOME"
	return {"key":"W8_OBJECTIVE_CHOOSE", "target":target}
