extends Node
## The one authoritative state for the active route; persistence is a separate service.

signal state_replaced

var state: GameState = GameState.new()


func start_new_game() -> GameState:
	var next_state: GameState = GameState.new()
	next_state.route_id = "ROUTE_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
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
