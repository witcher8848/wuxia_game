extends Node
## The one authoritative state for the active route; persistence is a separate service.

signal state_replaced

var state: GameState = GameState.new()
var _handover: Dictionary = {}
var _handover_sequence := 0
var _story: Dictionary = {}
var _story_sequence := 0
var _trial_token := ""
var _world_preview: Dictionary = {}
var _world_sequence := 0
var _branch_preview: Dictionary = {}
var _branch_sequence := 0
const BRANCH_NODE := "CH01_FIRST_LEAD"
var _branch_save_pending := false


func start_new_game(enable_week8: bool = false) -> GameState:
	if combat_active(): return state
	_trial_token = ""
	_handover.clear()
	_story.clear()
	_world_preview.clear()
	_branch_preview.clear()
	_branch_save_pending = false
	var next_state: GameState = GameState.new()
	if enable_week8: next_state.world_flags["FACT_W8_ACTIVE"] = true
	next_state.route_id = "ROUTE_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var content: Node = _content_db()
	if content != null and not content.start_scene_id.is_empty():
		var position: Vector2 = content.get_spawn_position(content.start_scene_id, content.start_spawn_id)
		if is_finite(position.x) and is_finite(position.y):
			next_state.scene_id = content.start_scene_id
			next_state.spawn_id = content.start_spawn_id
			next_state.player_state["position"] = {"x": position.x, "y": position.y}
	state = next_state
	state_replaced.emit()
	return state


func replace_state(next_state: GameState) -> Error:
	if not _trial_token.is_empty(): return ERR_BUSY
	if next_state == null or not next_state.validate().is_empty():
		return ERR_INVALID_DATA
	var content: Node = _content_db()
	if content != null and not content.validate_investigation_state(next_state).is_empty():
		return ERR_INVALID_DATA
	if content != null and not content.martial_configuration(next_state).get("error","").is_empty():
		return ERR_INVALID_DATA
	if content != null and not content.validate_world_state(next_state).is_empty():
		return ERR_INVALID_DATA
	if content != null and not content.validate_branch_choice_state(next_state).is_empty():
		return ERR_INVALID_DATA
	# Own a copy: a UI preview or loaded snapshot cannot mutate the live route later.
	state = GameState.from_dict(next_state.to_dict())
	_handover.clear()
	_story.clear()
	_trial_token = ""
	_world_preview.clear()
	_branch_preview.clear()
	_branch_save_pending = false
	state_replaced.emit()
	return OK


func branch_required() -> bool:
	var content := _content_db()
	return content != null and content.branch_required(state)


func pending_branch_save() -> bool:
	return _branch_save_pending


func retry_branch_save() -> Dictionary:
	if combat_active(): return {"error":ERR_BUSY,"saved":false,"save_error":ERR_BUSY}
	if not _branch_save_pending: return {"error":ERR_UNAVAILABLE,"saved":false,"save_error":ERR_UNAVAILABLE}
	return _save_week8_result()


func _save_week8_result() -> Dictionary:
	var saves := _save_service()
	if saves == null:
		_branch_save_pending = true
		return {"error":OK,"saved":false,"save_error":ERR_UNAVAILABLE,"requires_save":true,"slot":""}
	var result: Dictionary = saves.save_automatic(state)
	_branch_save_pending = result.get("error",ERR_INVALID_DATA) != OK
	return {"error":OK,"saved":not _branch_save_pending,"save_error":result.get("error",ERR_INVALID_DATA),"requires_save":_branch_save_pending,"slot":result.get("slot","")}


func _save_service() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	return main_loop.root.get_node_or_null("SaveService") if main_loop is SceneTree else null


## Preview may create the first immutable anchor; it never changes live state.
func preview_branch_choice(choice: String) -> Dictionary:
	_branch_preview.clear()
	if combat_active() or _branch_save_pending: return {"error":ERR_BUSY}
	var content := _content_db()
	var saves := _save_service()
	if content == null or saves == null: return {"error":ERR_UNAVAILABLE}
	var proposal: Dictionary = content.prepare_branch_choice(state, choice)
	if proposal.get("error", ERR_INVALID_DATA) != OK: return {"error":proposal.get("error", ERR_INVALID_DATA)}
	var written: Dictionary = saves.save_choice_anchor(BRANCH_NODE, state)
	if written.get("error", ERR_INVALID_DATA) not in [OK, ERR_ALREADY_EXISTS]:
		return {"error":written.get("error", ERR_INVALID_DATA)}
	var anchor: Dictionary = saves.load_choice_anchor(state.route_id, BRANCH_NODE)
	if anchor.get("error", ERR_INVALID_DATA) != OK: return {"error":anchor.get("error", ERR_INVALID_DATA)}
	# Cancel/reopen reuses the FIRST entry snapshot. Moving or reading since then
	# must not overwrite the anchor, or permanently block a legitimate choice.
	if content.prepare_branch_choice(anchor["state"], choice).get("error", ERR_INVALID_DATA) != OK:
		return {"error":ERR_INVALID_DATA}
	_branch_sequence += 1
	var token := "BRANCH_%d_%d" % [_branch_sequence, Time.get_ticks_usec()]
	_branch_preview = {"token":token,"choice":choice,"generation":content.content_generation(),
		"before":state.to_dict(),"after":proposal["state"].to_dict(),
		"summary":proposal["summary"].duplicate(true),"anchor":anchor["state"].to_dict()}
	return {"error":OK,"token":token,"anchor_id":anchor["anchor_id"],
		"summary":proposal["summary"].duplicate(true)}


func confirm_branch_choice(token: String) -> Dictionary:
	if token.is_empty() or token != _branch_preview.get("token", ""): return {"error":ERR_INVALID_PARAMETER}
	var pending := _branch_preview.duplicate(true)
	_branch_preview.clear()
	if combat_active() or state.to_dict() != pending["before"]: return {"error":ERR_BUSY}
	var content := _content_db()
	var saves := _save_service()
	if content == null or saves == null: return {"error":ERR_UNAVAILABLE}
	if content.content_generation() != pending["generation"]: return {"error":ERR_BUSY}
	var anchor: Dictionary = saves.load_choice_anchor(state.route_id, BRANCH_NODE)
	if anchor.get("error", ERR_INVALID_DATA) != OK: return {"error":anchor.get("error", ERR_INVALID_DATA)}
	# JSON readback may restore integral values as floats, so compare canonical
	# JSON values, not Variant numeric tags; no keys/items may be lost.
	if JSON.parse_string(JSON.stringify(anchor["state"].to_dict())) != JSON.parse_string(JSON.stringify(pending["anchor"])):
		return {"error":ERR_INVALID_DATA}
	var proposal: Dictionary = content.prepare_branch_choice(state, pending["choice"])
	if proposal.get("error", ERR_INVALID_DATA) != OK: return {"error":proposal.get("error", ERR_INVALID_DATA)}
	if proposal["state"].to_dict() != pending["after"] or proposal["summary"] != pending["summary"]:
		return {"error":ERR_BUSY}
	var error := replace_state(proposal["state"])
	var result := {"error":error,"saved":false,"requires_save":error == OK,"save_error":ERR_UNAVAILABLE,"slot":""}
	if error == OK and state.world_flags.get("FACT_W8_ACTIVE",false): result = _save_week8_result()
	result["summary"] = pending["summary"].duplicate(true) if error == OK else {}
	return result


func cancel_branch_choice(token: String) -> void:
	if not token.is_empty() and token == _branch_preview.get("token", ""): _branch_preview.clear()


func update_player_position(position: Vector2) -> Error:
	if combat_active() or _branch_save_pending: return ERR_BUSY
	if not is_finite(position.x) or not is_finite(position.y):
		return ERR_INVALID_PARAMETER
	state.player_state["position"] = {"x": position.x, "y": position.y}
	return OK


func enter_region(scene_id: String, spawn_id: String) -> Error:
	if combat_active() or _branch_save_pending: return ERR_BUSY
	var content: Node = _content_db()
	if content == null or not content.has_spawn(scene_id, spawn_id):
		return ERR_INVALID_PARAMETER
	var position: Vector2 = content.get_spawn_position(scene_id, spawn_id)
	if not content.is_safe_world_position(scene_id, position, state):
		return ERR_INVALID_PARAMETER
	# Commit all three fields together after validation. Walking and scene changes
	# are free exploration, not confirmed quest actions: time_state is untouched.
	state.scene_id = scene_id
	state.spawn_id = spawn_id
	state.player_state["position"] = {"x": position.x, "y": position.y}
	return OK


func mark_inspected(interaction_id: String) -> Error:
	if combat_active() or _branch_save_pending: return ERR_BUSY
	var content: Node = _content_db()
	if content == null or not content.has_inspectable(interaction_id):
		return ERR_INVALID_PARAMETER
	state.world_flags["INSPECTED_" + interaction_id] = true
	return OK


func is_inspected(interaction_id: String) -> bool:
	return state.world_flags.get("INSPECTED_" + interaction_id, false) == true


func preview_world_action(kind: String, npc_id: String = "") -> Dictionary:
	_world_preview.clear()
	if combat_active() or _branch_save_pending: return {"error":ERR_BUSY}
	var content := _content_db()
	if content == null: return {"error":ERR_UNAVAILABLE}
	if content.get_exploration_region(state.scene_id).is_empty(): return {"error":ERR_UNAVAILABLE}
	if kind == "help" and not content.can_reach_world_npc(state, npc_id): return {"error":ERR_UNAVAILABLE}
	var proposal: Dictionary = content.prepare_world_action(state, kind, npc_id)
	if proposal.get("error", ERR_INVALID_DATA) != OK: return {"error":proposal.get("error", ERR_INVALID_DATA)}
	_world_sequence += 1
	var token := "WORLD_%d_%d" % [_world_sequence, Time.get_ticks_usec()]
	_world_preview = {"token":token,"kind":kind,"npc_id":npc_id,"before":state.to_dict(),"after":proposal["state"].to_dict(),"summary":proposal["summary"].duplicate(true)}
	return {"error":OK,"token":token,"summary":proposal["summary"].duplicate(true)}


func confirm_world_action(token: String) -> Dictionary:
	if token.is_empty() or token != _world_preview.get("token", ""): return {"error":ERR_INVALID_PARAMETER}
	var pending := _world_preview.duplicate(true)
	_world_preview.clear()
	if combat_active() or state.to_dict() != pending["before"]: return {"error":ERR_BUSY}
	var content := _content_db()
	if content == null: return {"error":ERR_UNAVAILABLE}
	if pending["kind"] == "help" and not content.can_reach_world_npc(state, pending["npc_id"]): return {"error":ERR_UNAVAILABLE}
	var proposal: Dictionary = content.prepare_world_action(state, pending["kind"], pending["npc_id"])
	if proposal.get("error", ERR_INVALID_DATA) != OK: return {"error":proposal.get("error", ERR_INVALID_DATA)}
	if proposal["state"].to_dict() != pending["after"] or proposal["summary"] != pending["summary"]: return {"error":ERR_BUSY}
	var error := replace_state(proposal["state"])
	var result := {"error":error,"summary":pending["summary"].duplicate(true) if error == OK else {}}
	if error == OK and state.world_flags.get("FACT_W8_ACTIVE",false): result.merge(_save_week8_result(),true)
	return result


func cancel_world_action(token: String) -> void:
	if not token.is_empty() and token == _world_preview.get("token", ""): _world_preview.clear()


func apply_investigation_step(step_id: String) -> Dictionary:
	if _branch_save_pending: return {"error":ERR_BUSY,"feedback_key":"W8_SAVE_REQUIRED"}
	if combat_active() or step_id in ["STEP_PREPARE_RESCUE", "STEP_GRAVES_VICTORY"]:
		return {"error": ERR_BUSY, "feedback_key": "INV_COMMAND_FAILED"}
	var content: Node = _content_db()
	if content == null:
		return {"error": ERR_UNAVAILABLE, "message": "ContentDB unavailable.", "feedback_key": ""}
	if content.branch_command_requires_confirmation(state,step_id):
		return {"error":ERR_UNAVAILABLE,"activity":"@branch","feedback_key":"W8_CHOICE_NEEDED"}
	if not content.public_investigation_step_allowed(step_id):
		return {"error": ERR_UNAVAILABLE, "message": "This command requires its dedicated confirmation or encounter workflow.", "feedback_key": "INV_COMMAND_FAILED"}
	var prepared: Dictionary = content.prepare_investigation_step(state, step_id)
	if prepared["error"] != OK:
		return {"error": prepared["error"], "message": prepared["message"], "feedback_key": ""}
	var error: Error = replace_state(prepared["state"])
	var result := {"error": error, "message": "", "feedback_key": prepared["feedback_key"] if error == OK else ""}
	if error == OK and state.world_flags.get("FACT_W8_ACTIVE",false) and step_id.begins_with("STEP_W8_"): result.merge(_save_week8_result(),true)
	return result


func _content_db() -> Node:
	# Standalone service tests may construct a session before it enters the tree.
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop.root.get_node_or_null("ContentDB")
	return null


func choose_dialogue(node_id: String, choice_id: String) -> Dictionary:
	if combat_active(): return {"error": ERR_BUSY}
	var content: Node = _content_db()
	if content == null:
		return {"error": ERR_UNAVAILABLE}
	# Resolve the option again from current authoritative state, not UI snapshots.
	var view: Dictionary = content.dialogue_view(node_id, state)
	for choice: Dictionary in view.get("choices", []):
		if choice["id"] != choice_id:
			continue
		if not choice["enabled"]:
			return {"error": ERR_UNAVAILABLE, "feedback_key": choice["reason"]}
		if _branch_save_pending: return {"error":ERR_BUSY,"feedback_key":"W8_SAVE_REQUIRED"}
		if choice["next"] == "@battle" and branch_required(): return {"error":ERR_UNAVAILABLE,"activity":"@branch","feedback_key":"W8_CHOICE_NEEDED"}
		var feedback := ""
		var command_result: Dictionary = {}
		if not choice["command"].is_empty():
			var result: Dictionary = apply_investigation_step(choice["command"])
			if result["error"] != OK:
				return result
			feedback = result["feedback_key"]
			command_result = result
		var response := {"error": OK, "next": choice["next"], "feedback_key": feedback}
		for key: String in ["saved","save_error","requires_save","slot"]:
			if command_result.has(key): response[key] = command_result[key]
		return response
	return {"error": ERR_INVALID_PARAMETER}


func resolve_inquiry(identifier: String, selected: Array) -> Dictionary:
	if combat_active() or _branch_save_pending: return {"error": ERR_BUSY, "feedback_key": "W8_SAVE_REQUIRED" if _branch_save_pending else "INV_COMMAND_FAILED"}
	var content: Node = _content_db()
	if content == null:
		return {"error": ERR_UNAVAILABLE, "feedback_key": "INV_COMMAND_FAILED"}
	var proposal: Dictionary = content.prepare_inquiry(state, identifier, selected)
	if proposal["error"] != OK:
		return {"error": proposal["error"], "feedback_key": proposal["feedback_key"]}
	var error: Error = replace_state(proposal["state"])
	var result := {"error": error, "feedback_key": proposal["feedback_key"] if error == OK else "INV_COMMAND_FAILED"}
	if error == OK and state.world_flags.get("FACT_W8_ACTIVE",false) and identifier == "INQ_W8_GRAVES": result.merge(_save_week8_result(),true)
	return result


func preview_original_handover() -> Dictionary:
	if combat_active() or _branch_save_pending: return {"error": ERR_BUSY, "feedback_key": "INV_COMMAND_FAILED"}
	_handover.clear()
	var content: Node = _content_db()
	if content == null or state.scene_id != "SCENE_TOWN_STREET" or not is_inspected("DOC_STREET_NOTICE"):
		return {"error": ERR_UNAVAILABLE, "feedback_key": "INV_HANDOVER_LOCATION"}
	var proposal: Dictionary = _original_handover_proposal(content)
	if proposal["error"] != OK:
		return {"error": proposal["error"], "feedback_key": "INV_ALREADY_RECORDED" if proposal["error"] == ERR_ALREADY_EXISTS else "INV_REQUIREMENTS"}
	_handover_sequence += 1
	var token := "HANDOVER_%d_%d" % [_handover_sequence, Time.get_ticks_usec()]
	_handover = {"token": token, "before": state.to_dict(), "after":proposal["state"].to_dict()}
	return {"error": OK, "token": token, "evidence_id": "EV_BLANK_DEATH_01", "recipient_id": "FACTION_INSPECTOR", "effect_key": "INV_HANDOVER_EFFECT"}


func confirm_original_handover(token: String) -> Dictionary:
	if token.is_empty() or token != _handover.get("token", ""):
		return {"error": ERR_INVALID_PARAMETER, "feedback_key": "INV_HANDOVER_STALE"}
	var pending := _handover.duplicate(true)
	_handover.clear()
	if combat_active() or pending["before"] != state.to_dict():
		return {"error": ERR_BUSY, "feedback_key": "INV_HANDOVER_STALE"}
	var content := _content_db()
	if content == null: return {"error":ERR_UNAVAILABLE,"feedback_key":"INV_COMMAND_FAILED"}
	# Dedicated capability: ordinary investigation/dialogue/inquiry entry points
	# cannot commit PLAYER custody transfers. Recompute the exact preview effect.
	var proposal := _original_handover_proposal(content)
	if proposal["error"] != OK or proposal["state"].to_dict() != pending["after"]:
		return {"error":ERR_BUSY,"feedback_key":"INV_HANDOVER_STALE"}
	var error := replace_state(proposal["state"])
	return {"error":error,"feedback_key":proposal["feedback_key"] if error == OK else "INV_COMMAND_FAILED"}


func _original_handover_proposal(content: Node) -> Dictionary:
	var proposal: Dictionary = content.prepare_investigation_step(state, "STEP_HAND_OVER_BLANK")
	if proposal["error"] != OK: return proposal
	# The preview explicitly promises this original, recipient, and no other
	# consequences. Reject a content reload that silently changes that contract.
	var expected := state.to_dict()
	if not expected["evidence_states"].has("EV_BLANK_DEATH_01"):
		return {"error":ERR_INVALID_DATA}
	expected["evidence_states"]["EV_BLANK_DEATH_01"]["holder_id"] = "FACTION_INSPECTOR"
	expected["world_flags"]["APPLIED_STEP_HAND_OVER_BLANK"] = true
	if proposal["state"].to_dict() != expected: return {"error":ERR_INVALID_DATA}
	return proposal


func cancel_original_handover(token: String) -> void:
	if not token.is_empty() and token == _handover.get("token", ""):
		_handover.clear()


func begin_story_encounter() -> Dictionary:
	if _branch_save_pending: return {"error":ERR_BUSY,"feedback_key":"W8_SAVE_REQUIRED"}
	if branch_required(): return {"error":ERR_UNAVAILABLE,"activity":"@branch","feedback_key":"W8_CHOICE_NEEDED"}
	if combat_active() or state.scene_id != "SCENE_RIVER_DOCK" or not is_inspected("NPC_DOCK_WORKER"):
		return {"error": ERR_UNAVAILABLE}
	var content: Node = _content_db()
	if content == null: return {"error": ERR_UNAVAILABLE}
	var prepared: Dictionary = content.prepare_story_encounter(state)
	if prepared["error"] != OK: return {"error": prepared["error"]}
	var before := state.to_dict()
	if replace_state(prepared["state"]) != OK: return {"error": ERR_INVALID_DATA}
	_story_sequence += 1
	var token := "GRAVES_%d_%d" % [_story_sequence, Time.get_ticks_usec()]
	_story = {"token": token, "before": before, "expected": state.to_dict(), "battle": prepared["battle"]}
	# Only the transient combat authority is shared with presentation. No result
	# payload supplied by a screen is accepted by the settlement command.
	return {"error": OK, "token": token, "battle": prepared["battle"], "reveal": prepared["reveal"], "ferry": prepared["ferry"]}


func story_encounter_active() -> bool:
	return not _story.is_empty()

func combat_active() -> bool:
	return not _story.is_empty() or not _trial_token.is_empty()


func martial_configuration() -> Dictionary:
	var content: Node = _content_db()
	return content.martial_configuration(state) if content != null else {"error":"ContentDB unavailable.","state":{}}


func set_martial_loadout(loadout: Dictionary) -> Error:
	if not _story.is_empty() or not _trial_token.is_empty() or _branch_save_pending: return ERR_BUSY
	var content: Node = _content_db()
	if content == null: return ERR_UNAVAILABLE
	var normalized: Dictionary = content.martial_configuration(state)
	if not normalized["error"].is_empty(): return ERR_INVALID_DATA
	var proposed: Dictionary = normalized["state"].duplicate(true)
	proposed["loadout"] = loadout.duplicate(true)
	var checked: Dictionary = preload("res://game/domain/battle/martial_loadout.gd").normalize_state(proposed,content.martial_definitions())
	if not checked["error"].is_empty(): return ERR_INVALID_DATA
	var candidate: GameState = GameState.from_dict(state.to_dict())
	if candidate == null: return ERR_INVALID_DATA
	candidate.martial_states = checked["state"].duplicate(true)
	# Only a confirmed out-of-combat configuration changes persistent state.
	# It spends no story time and leaves HP, quests, relationships/evidence intact.
	return replace_state(candidate)


func lock_martial_trial() -> String:
	if not _story.is_empty() or not _trial_token.is_empty() or _branch_save_pending: return ""
	_world_preview.clear()
	_branch_preview.clear()
	_trial_token = "TRIAL_%d" % Time.get_ticks_usec()
	return _trial_token


func unlock_martial_trial(token: String) -> bool:
	if token.is_empty() or token != _trial_token: return false
	_trial_token = ""
	return true


func _owns_story(token: String) -> bool:
	return not token.is_empty() and token == _story.get("token", "") and state.to_dict() == _story.get("expected", {})


func finish_story_encounter(token: String) -> Dictionary:
	if not _owns_story(token): return {"error": ERR_INVALID_PARAMETER}
	var battle: CombatEncounter = _story["battle"]
	if battle.outcome != "victory": return {"error": ERR_UNAVAILABLE}
	var proposal: Dictionary = _content_db().finish_story_encounter(state, battle.result(), token)
	if proposal["error"] != OK: return {"error": proposal["error"]}
	var error := replace_state(proposal["state"])
	var result := {"error": error, "feedback_key": "INV_GRAVES_VICTORY"}
	if error == OK and state.world_flags.get("FACT_W8_ACTIVE",false): result.merge(_save_week8_result(),true)
	return result


func retry_story_encounter(token: String) -> Error:
	if not _owns_story(token): return ERR_INVALID_PARAMETER
	return OK if _story["battle"].retry() else ERR_INVALID_DATA


func abort_story_encounter(token: String) -> Error:
	if not _owns_story(token): return ERR_INVALID_PARAMETER
	# Return to the pre-encounter snapshot, not a partially changed quest.
	return replace_state(GameState.from_dict(_story["before"]))
