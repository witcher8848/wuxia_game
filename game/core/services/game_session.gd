extends Node
## The one authoritative state for the active route; persistence is a separate service.

signal state_replaced

var state: GameState = GameState.new()
var _handover: Dictionary = {}
var _handover_sequence := 0


func start_new_game() -> GameState:
	_handover.clear()
	var next_state: GameState = GameState.new()
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
	if next_state == null or not next_state.validate().is_empty():
		return ERR_INVALID_DATA
	# Own a copy: a UI preview or loaded snapshot cannot mutate the live route later.
	state = GameState.from_dict(next_state.to_dict())
	_handover.clear()
	state_replaced.emit()
	return OK


func update_player_position(position: Vector2) -> Error:
	if not is_finite(position.x) or not is_finite(position.y):
		return ERR_INVALID_PARAMETER
	state.player_state["position"] = {"x": position.x, "y": position.y}
	return OK


func enter_region(scene_id: String, spawn_id: String) -> Error:
	var content: Node = _content_db()
	if content == null or not content.has_spawn(scene_id, spawn_id):
		return ERR_INVALID_PARAMETER
	var position: Vector2 = content.get_spawn_position(scene_id, spawn_id)
	if not content.is_safe_player_position(scene_id, position):
		return ERR_INVALID_PARAMETER
	# Commit all three fields together after validation. Walking and scene changes
	# are free exploration, not confirmed quest actions: time_state is untouched.
	state.scene_id = scene_id
	state.spawn_id = spawn_id
	state.player_state["position"] = {"x": position.x, "y": position.y}
	return OK


func mark_inspected(interaction_id: String) -> Error:
	var content: Node = _content_db()
	if content == null or not content.has_inspectable(interaction_id):
		return ERR_INVALID_PARAMETER
	state.world_flags["INSPECTED_" + interaction_id] = true
	return OK


func is_inspected(interaction_id: String) -> bool:
	return state.world_flags.get("INSPECTED_" + interaction_id, false) == true


func apply_investigation_step(step_id: String) -> Dictionary:
	var content: Node = _content_db()
	if content == null:
		return {"error": ERR_UNAVAILABLE, "message": "ContentDB unavailable.", "feedback_key": ""}
	var prepared: Dictionary = content.prepare_investigation_step(state, step_id)
	if prepared["error"] != OK:
		return {"error": prepared["error"], "message": prepared["message"], "feedback_key": ""}
	var error: Error = replace_state(prepared["state"])
	return {"error": error, "message": "", "feedback_key": prepared["feedback_key"] if error == OK else ""}


func _content_db() -> Node:
	# Standalone service tests may construct a session before it enters the tree.
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop.root.get_node_or_null("ContentDB")
	return null


func choose_dialogue(node_id: String, choice_id: String) -> Dictionary:
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
		var feedback := ""
		if not choice["command"].is_empty():
			var result: Dictionary = apply_investigation_step(choice["command"])
			if result["error"] != OK:
				return result
			feedback = result["feedback_key"]
		return {"error": OK, "next": choice["next"], "feedback_key": feedback}
	return {"error": ERR_INVALID_PARAMETER}


func resolve_inquiry(identifier: String, selected: Array) -> Dictionary:
	var content: Node = _content_db()
	if content == null:
		return {"error": ERR_UNAVAILABLE, "feedback_key": "INV_COMMAND_FAILED"}
	var proposal: Dictionary = content.prepare_inquiry(state, identifier, selected)
	if proposal["error"] != OK:
		return {"error": proposal["error"], "feedback_key": proposal["feedback_key"]}
	var error: Error = replace_state(proposal["state"])
	return {"error": error, "feedback_key": proposal["feedback_key"] if error == OK else "INV_COMMAND_FAILED"}


func preview_original_handover() -> Dictionary:
	_handover.clear()
	var content: Node = _content_db()
	if content == null or state.scene_id != "SCENE_TOWN_STREET" or not is_inspected("DOC_STREET_NOTICE"):
		return {"error": ERR_UNAVAILABLE, "feedback_key": "INV_HANDOVER_LOCATION"}
	var proposal: Dictionary = content.prepare_investigation_step(state, "STEP_HAND_OVER_BLANK")
	if proposal["error"] != OK:
		return {"error": proposal["error"], "feedback_key": "INV_ALREADY_RECORDED" if proposal["error"] == ERR_ALREADY_EXISTS else "INV_REQUIREMENTS"}
	_handover_sequence += 1
	var token := "HANDOVER_%d_%d" % [_handover_sequence, Time.get_ticks_usec()]
	_handover = {"token": token, "before": state.to_dict()}
	return {"error": OK, "token": token, "evidence_id": "EV_BLANK_DEATH_01", "recipient_id": "FACTION_INSPECTOR", "effect_key": "INV_HANDOVER_EFFECT"}


func confirm_original_handover(token: String) -> Dictionary:
	if token.is_empty() or token != _handover.get("token", ""):
		return {"error": ERR_INVALID_PARAMETER, "feedback_key": "INV_HANDOVER_STALE"}
	var before: Dictionary = _handover["before"]
	_handover.clear()
	if before != state.to_dict():
		return {"error": ERR_BUSY, "feedback_key": "INV_HANDOVER_STALE"}
	return apply_investigation_step("STEP_HAND_OVER_BLANK")


func cancel_original_handover(token: String) -> void:
	if not token.is_empty() and token == _handover.get("token", ""):
		_handover.clear()
