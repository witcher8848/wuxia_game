extends SceneTree
## SCRIPTED keyboard navigation, not a human/no-hint usability test.
## BFS supplies a route only; production physics moves the player using key events.

const MAIN_SCENE := "res://game/presentation/main.tscn"
const GRID: int = 32
const TOLERANCE: float = 1.3
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const MOVEMENT_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]

var checks: int = 0
var failures: Array[String] = []
var main: Node
var content: Node
var session: Node
var app: Node
var initial_time: Dictionary
var initial_route: String
var walked_distance: float = 0.0
var visited_waypoints: int = 0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(_watchdog_timeout)
	_run.call_deferred()


func _watchdog_timeout() -> void:
	_release_keys()
	printerr("EXPLORATION_WALK_FAIL SCRIPTED keyboard walkthrough exceeded 90 seconds")
	quit(124)


func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("EXPLORATION_WALK_FAIL ", message)
	return condition


func _step(frames: int = 1) -> void:
	for _frame in range(frames):
		await physics_frame
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	await _step()
	_key(code, false)
	await _step()


func _release_keys() -> void:
	for code: Key in MOVEMENT_KEYS:
		_key(code, false)
	_key(KEY_E, false)
	_key(KEY_ESCAPE, false)


func _region() -> Node2D:
	if not is_instance_valid(main):
		return null
	var host: Node = main.get_node("SceneHost")
	return host.get_child(0) as Node2D if host.get_child_count() == 1 else null


func _players_in(node: Node) -> int:
	var total: int = 1 if node is CharacterBody2D else 0
	for child: Node in node.get_children():
		total += _players_in(child)
	return total


func _target(identifier: String) -> Dictionary:
	for target: Dictionary in _region().definition.get("interactions", []):
		if target.get("id", "") == identifier:
			return target.duplicate(true)
	check(false, "current content defines " + identifier)
	return {}


func _bfs_path(destination: Vector2) -> Array[Vector2]:
	var start: Vector2 = (_region().player_position / GRID).round() * GRID
	var scene_id: String = session.state.scene_id
	if not content.is_safe_player_position(scene_id, start) or not content.is_safe_player_position(scene_id, destination):
		return []
	var start_cell := Vector2i(start / GRID)
	var end_cell := Vector2i(destination / GRID)
	var queue: Array[Vector2i] = [start_cell]
	var previous: Dictionary = {start_cell: start_cell}
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		if cell == end_cell:
			var result: Array[Vector2] = [Vector2(cell) * GRID]
			while cell != start_cell:
				cell = previous[cell]
				result.push_front(Vector2(cell) * GRID)
			return result
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = cell + direction
			if previous.has(next) or not content.is_safe_player_position(scene_id, Vector2(next) * GRID):
				continue
			previous[next] = cell
			queue.append(next)
	return []


func _move_axis(axis: int, destination: float) -> bool:
	var region: Node2D = _region()
	var difference: float = destination - region.player_position[axis]
	if absf(difference) <= TOLERANCE:
		return true
	var positive: bool = difference > 0.0
	var code: Key = (KEY_D if positive else KEY_A) if axis == 0 else (KEY_S if positive else KEY_W)
	var deadline: int = Time.get_ticks_msec() + 2000
	var stalled_frames: int = 0
	_key(KEY_SHIFT, true)
	_key(code, true)
	while absf(destination - region.player_position[axis]) > TOLERANCE:
		# A delayed rendered frame may contain multiple physics steps and overshoot
		# the waypoint. Re-steer from the actual position instead of holding the
		# initial direction until hitting a wall. No teleport or relaxed tolerance.
		positive = destination > region.player_position[axis]
		var next_code: Key = (KEY_D if positive else KEY_A) if axis == 0 else (KEY_S if positive else KEY_W)
		if next_code != code:
			_key(code, false)
			code = next_code
			_key(code, true)
		# Walk the final few pixels so navigation remains precise at faster sprint
		# speeds; do not change the real player's position or widen the tolerance.
		_key(KEY_SHIFT, absf(destination - region.player_position[axis]) > 8.0)
		var before: Vector2 = region.player_position
		await _step()
		var after: Vector2 = region.player_position
		walked_distance += before.distance_to(after)
		stalled_frames = stalled_frames + 1 if before.distance_to(after) < 0.01 else 0
		if Time.get_ticks_msec() >= deadline or stalled_frames >= 12:
			_release_keys()
			return check(false, "bounded keyboard movement stuck in %s at %s toward axis %d = %s" % [session.state.scene_id, str(after), axis, str(destination)])
		if not content.is_safe_player_position(session.state.scene_id, after):
			_release_keys()
			return check(false, "physical keyboard movement escaped safe geometry at " + str(after))
	_key(code, false)
	_key(KEY_SHIFT, false)
	await _step()
	return true


func _walk_to_target(identifier: String) -> bool:
	_release_keys()
	await _step(2)
	var target: Dictionary = _target(identifier)
	if target.is_empty():
		return false
	var target_point := Vector2(target.position[0], target.position[1])
	var path: Array[Vector2] = []
	var approach: Vector2
	# Prefer the visually clear southern approach; fall back to other safe sides.
	for side: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		approach = target_point + Vector2(side) * GRID
		path = _bfs_path(approach)
		if not path.is_empty():
			break
	if not check(not path.is_empty(), "safe 32px keyboard route exists to " + identifier):
		return false
	for waypoint: Vector2 in path:
		if not await _move_axis(0, waypoint.x) or not await _move_axis(1, waypoint.y):
			return false
		visited_waypoints += 1
		if not check(_region().player_position.distance_to(waypoint) <= TOLERANCE * sqrt(2.0), "actual controller reaches grid waypoint for " + identifier):
			return false
	# Face the interaction with an actual short movement, never a facing setter.
	_release_keys()
	await _step(2)
	var toward: Vector2 = target_point - approach
	var face_key: Key = (KEY_D if toward.x > 0 else KEY_A) if toward.x != 0 else (KEY_S if toward.y > 0 else KEY_W)
	_key(face_key, true)
	await _step(2)
	_key(face_key, false)
	await _step(2)
	return check(_region().choose_target().get("id", "") == identifier, "walking and real facing pulse select " + identifier)


func _check_route_invariants(label: String) -> void:
	check(session.state.time_state == initial_time, label + " spends no quest time")
	check(session.state.route_id == initial_route, label + " retains the same route")
	check(main.get_node("SceneHost").get_child_count() == 1 and _players_in(main.get_node("SceneHost")) == 1, label + " retains exactly one region and player")
	check(app.current_context() == &"exploration", label + " has exploration input")


func _read(identifier: String) -> bool:
	if not await _walk_to_target(identifier):
		return false
	await _tap(KEY_E)
	if not check(is_instance_valid(main.reading_panel) and main.reading_panel.visible, "E opens " + identifier + " after walking from previous objective"):
		return false
	check(session.is_inspected(identifier), identifier + " records its stable inspected fact")
	await _tap(KEY_ESCAPE)
	_release_keys()
	await _step(2)
	check(not main.reading_panel.visible and not main.menu.visible, "Escape closes " + identifier + " without pausing")
	_check_route_invariants(identifier)
	return true


func _exit(identifier: String, expected_scene: String, expected_spawn: String) -> bool:
	if not await _walk_to_target(identifier):
		return false
	var old_region_id: int = _region().get_instance_id()
	await _tap(KEY_E)
	var deadline: int = Time.get_ticks_msec() + 5000
	while main.transitioning and Time.get_ticks_msec() < deadline:
		await _step()
	_release_keys()
	await _step(2)
	if not check(not main.transitioning and _region() != null, identifier + " keyboard transition completes within five seconds"):
		return false
	check(_region().get_instance_id() != old_region_id, identifier + " replaces the old region")
	check(session.state.scene_id == expected_scene and session.state.spawn_id == expected_spawn, identifier + " reaches the exact configured destination")
	check(_region().scene_id == expected_scene and _region().player_position == content.get_spawn_position(expected_scene, expected_spawn), identifier + " arrives at actual authored spawn without test teleportation")
	_check_route_invariants(identifier)
	return true


func _run() -> void:
	await process_frame
	content = root.get_node("ContentDB")
	session = root.get_node("GameSession")
	app = root.get_node("App")
	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	await _step(2)
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	await _step(2)
	if not check(_region() != null and session.state.scene_id == "SCENE_TOWN_STREET", "normal new game enters authored street"):
		await _finish()
		return
	check(_region().player_position == content.get_spawn_position(content.start_scene_id, content.start_spawn_id), "walkthrough starts at real new-game spawn")
	initial_time = session.state.time_state.duplicate(true)
	initial_route = session.state.route_id
	var completed: bool = await _read("NPC_STREET_VENDOR")
	if completed:
		completed = await _read("DOC_STREET_NOTICE")
	if completed:
		completed = await _exit("EXIT_STREET_HOME", "SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN")
	if completed:
		completed = await _read("DOC_HOME_NOTE")
	if completed:
		completed = await _exit("EXIT_HOME_STREET", "SCENE_TOWN_STREET", "SPAWN_FROM_HOME")
	if completed:
		completed = await _exit("EXIT_STREET_DOCK", "SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN")
	if completed:
		completed = await _read("NPC_DOCK_WORKER")
	if completed:
		completed = await _exit("EXIT_DOCK_STREET", "SCENE_TOWN_STREET", "SPAWN_FROM_DOCK")
	check(completed, "SCRIPTED keyboard route completes street, home, dock and return")
	if completed:
		var inspected: Array[String] = ["NPC_STREET_VENDOR", "DOC_STREET_NOTICE", "DOC_HOME_NOTE", "NPC_DOCK_WORKER"]
		for identifier: String in inspected:
			check(session.is_inspected(identifier), "completed route retains " + identifier)
		check(session.state.world_flags.size() == inspected.size(), "complete route has exactly the four authored inspected facts")
		check(walked_distance > 1600.0, "route physically traverses substantial world distance through production controller")
		_check_route_invariants("completed keyboard route")
	await _finish()


func _finish() -> void:
	_release_keys()
	if is_instance_valid(main):
		root.remove_child(main)
		main.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("EXPLORATION_WALK_PASS checks=", checks, " waypoints=", visited_waypoints, " physical_distance=", snappedf(walked_distance, 0.1), " (SCRIPTED keyboard navigation; no player teleport/facing assignment; not human usability evidence)")
	quit(0 if failures.is_empty() else 1)
