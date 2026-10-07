extends RefCounted
## Read-only guidance: destinations, never a highlighted correct evidence item.
static func project(state: GameState) -> Dictionary:
	var flags := state.world_flags
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
