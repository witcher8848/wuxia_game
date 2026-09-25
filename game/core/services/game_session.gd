extends Node
## The one authoritative state for the active route; persistence is a separate service.

signal state_replaced

var state: GameState = GameState.new()


func start_new_game() -> GameState:
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


func _content_db() -> Node:
	# Standalone service tests may construct a session before it enters the tree.
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop.root.get_node_or_null("ContentDB")
	return null
