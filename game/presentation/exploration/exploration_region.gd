extends Node2D
## Disposable presentation of content definitions. Persistent facts belong to GameSession.

signal interaction_requested(target: Dictionary)

const PlayerScript = preload("res://game/presentation/exploration/player_controller.gd")
const CameraScript = preload("res://game/presentation/exploration/exploration_camera.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const PLAYER_FEET := Vector2(20, 12)
const RECOVERY_MARGIN := 0.05
@export var scene_id: String = "SCENE_TOWN_STREET"
var definition: Dictionary = {}
var player: CharacterBody2D
var camera: Camera2D
var selected_target: Dictionary = {}
var observing: bool = false
var _target_bodies: Dictionary = {}
var player_position: Vector2:
	get:
		return player.position if is_instance_valid(player) else Vector2.ZERO
	set(value):
		if is_instance_valid(player):
			player.position = value

func _ready() -> void:
	process_physics_priority = 10
	var projected: Dictionary = ContentDB.exploration_view(scene_id, GameSession.state)
	if not projected.get("error", "").is_empty() or projected.get("region", {}).is_empty():
		push_error("Missing exploration projection: " + scene_id)
		return
	definition = projected["region"]
	var dimensions := Vector2(definition["size"][0], definition["size"][1])
	# Match the content validator's 16px inset, including the player's foot extents.
	for rect: Rect2 in [Rect2(-32, -32, dimensions.x + 64, 48), Rect2(-32, dimensions.y - 16, dimensions.x + 64, 48), Rect2(-32, 0, 48, dimensions.y), Rect2(dimensions.x - 16, 0, 48, dimensions.y)]:
		_add_obstacle(rect)
	for obstacle: Dictionary in definition["obstacles"]:
		_add_obstacle(_rect(obstacle["rect"]))
	_sync_target_bodies()
	player = PlayerScript.new()
	player.name = "Player"
	player.position = _saved_position()
	player.facing = GameSession.state.player_state.get("facing", "down")
	add_child(player)
	player.reset_input()
	camera = CameraScript.new()
	camera.name = "ExplorationCamera"
	add_child(camera)
	camera.configure_bounds(Rect2(Vector2.ZERO, dimensions))
	camera.follow(player.position)
	camera.make_current()
	camera.force_update_scroll()
	GameSession.state_replaced.connect(_on_state_replaced)
	queue_redraw()

func _saved_position() -> Vector2:
	var saved: Dictionary = GameSession.state.player_state["position"]
	var result := Vector2(saved["x"], saved["y"])
	if not is_safe_position(definition, result):
		result = nearest_safe_position(definition, result)
		if is_finite(result.x) and is_finite(result.y):
			GameSession.update_player_position(result)
	return result

func _on_state_replaced() -> void:
	# A transition/load can briefly leave the old region alive. It must not move
	# the new route's player or render another region's authoritative state.
	if not is_inside_tree() or GameSession.state.scene_id != scene_id:
		return
	refresh_world_view()

func refresh_world_view() -> bool:
	var projected: Dictionary = ContentDB.exploration_view(scene_id, GameSession.state)
	if not projected.get("error", "").is_empty() or projected.get("region", {}).is_empty():
		return false
	var next_definition: Dictionary = projected["region"]
	var saved: Dictionary = GameSession.state.player_state["position"]
	var restored := Vector2(saved["x"], saved["y"])
	if not is_safe_position(next_definition, restored):
		restored = nearest_safe_position(next_definition, restored)
		if not is_finite(restored.x) or not is_finite(restored.y):
			return false
		# Only old saves/legacy story ticks need this repair. The world command
		# normally chooses a persisted NPC anchor clear of the player's feet.
		if GameSession.update_player_position(restored) != OK:
			return false
	definition = next_definition
	_sync_target_bodies()
	selected_target.clear()
	if is_instance_valid(player):
		player.position = restored
		player.facing = GameSession.state.player_state.get("facing", "down")
		player.reset_input()
		player._sync_visual(0.0)
		camera.follow(player.position)
	queue_redraw()
	return true

func _sync_target_bodies() -> void:
	var retained: Dictionary = {}
	for target: Dictionary in definition["interactions"]:
		if target["kind"] == "exit":
			continue
		var identifier: String = target["id"]
		var point := _point(target["position"])
		var body: StaticBody2D = _target_bodies.get(identifier)
		if not is_instance_valid(body):
			body = _add_obstacle(Rect2(point - PLAYER_FEET / 2.0, PLAYER_FEET))
		else:
			body.position = point
		retained[identifier] = body
	for identifier: String in _target_bodies:
		if not retained.has(identifier):
			var body: StaticBody2D = _target_bodies[identifier]
			remove_child(body)
			body.queue_free()
	_target_bodies = retained

static func is_safe_position(region: Dictionary, point: Vector2) -> bool:
	if region.is_empty() or not is_finite(point.x) or not is_finite(point.y):
		return false
	var feet := Rect2(point - PLAYER_FEET / 2.0, PLAYER_FEET)
	var size_values: Array = region["size"]
	var bounds := Rect2(Vector2.ONE * 16, Vector2(size_values[0], size_values[1]) - Vector2.ONE * 32)
	if not bounds.encloses(feet):
		return false
	for rectangle: Rect2 in _solid_rectangles(region):
		if feet.intersects(rectangle):
			return false
	return true

static func _solid_rectangles(region: Dictionary) -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	for obstacle: Dictionary in region["obstacles"]:
		var values: Array = obstacle["rect"]
		rectangles.append(Rect2(values[0], values[1], values[2], values[3]))
	for target: Dictionary in region["interactions"]:
		if target["kind"] in ["npc", "document"]:
			var values: Array = target["position"]
			rectangles.append(Rect2(Vector2(values[0], values[1]) - PLAYER_FEET / 2.0, PLAYER_FEET))
	return rectangles

static func nearest_safe_position(region: Dictionary, origin: Vector2) -> Vector2:
	if is_safe_position(region, origin):
		return origin
	if region.is_empty() or not is_finite(origin.x) or not is_finite(origin.y):
		return Vector2.INF
	# Axis-aligned geometry: a closest free point lies at the original coordinate
	# or an expanded solid/bounds edge on each axis. Unlike grid BFS this keeps
	# legacy fractional positions and never teleports farther just to hit a tile.
	var size_values: Array = region["size"]
	var minimum := Vector2.ONE * 16 + PLAYER_FEET / 2.0 + Vector2.ONE * RECOVERY_MARGIN
	var maximum := Vector2(size_values[0], size_values[1]) - minimum
	var xs: Array[float] = [clampf(origin.x, minimum.x, maximum.x), minimum.x, maximum.x]
	var ys: Array[float] = [clampf(origin.y, minimum.y, maximum.y), minimum.y, maximum.y]
	for solid: Rect2 in _solid_rectangles(region):
		var expanded := Rect2(solid.position - PLAYER_FEET / 2.0, solid.size + PLAYER_FEET)
		xs.append(clampf(expanded.position.x - RECOVERY_MARGIN, minimum.x, maximum.x))
		xs.append(clampf(expanded.end.x + RECOVERY_MARGIN, minimum.x, maximum.x))
		ys.append(clampf(expanded.position.y - RECOVERY_MARGIN, minimum.y, maximum.y))
		ys.append(clampf(expanded.end.y + RECOVERY_MARGIN, minimum.y, maximum.y))
	var closest := Vector2.INF
	var distance := INF
	for x: float in xs:
		for y: float in ys:
			var candidate := Vector2(x, y)
			var next_distance := candidate.distance_squared_to(origin)
			if next_distance < distance and is_safe_position(region, candidate):
				closest = candidate
				distance = next_distance
	return closest

func _add_obstacle(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	camera.follow(player.position)
	GameSession.update_player_position(player.position)
	GameSession.state.player_state["facing"] = player.facing
	observing = App.current_context() == &"exploration" and Input.is_action_pressed("inspect")
	selected_target = choose_target() if App.current_context() == &"exploration" else {}
	queue_redraw()

func choose_target() -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	for target: Dictionary in definition.get("interactions", []):
		var offset := _point(target["position"]) - player.position
		var distance := offset.length()
		if distance > 58.0:
			continue
		var alignment: float = offset.normalized().dot(player.facing_vector()) if distance > 0.01 else 1.0
		if alignment < 0.1 and distance > 24.0:
			continue
		var query := PhysicsRayQueryParameters2D.create(player.global_position, _point(target["position"]), 1)
		var excluded: Array[RID] = [player.get_rid()]
		if _target_bodies.has(target["id"]):
			excluded.append(_target_bodies[target["id"]].get_rid())
		query.exclude = excluded
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var score := distance + (1.0 - alignment) * 16.0
		if score < best_score:
			best = target
			best_score = score
	return best.duplicate(true)

func _unhandled_input(event: InputEvent) -> void:
	if App.current_context() != &"exploration" or event.is_echo():
		return
	if event.is_action_pressed("confirm"):
		selected_target = choose_target()
		if not selected_target.is_empty():
			get_viewport().set_input_as_handled()
			player.reset_input()
			interaction_requested.emit(selected_target.duplicate(true))

func _draw() -> void:
	if definition.is_empty():
		return
	var bounds := Rect2(0, 0, definition["size"][0], definition["size"][1])
	draw_rect(bounds, Color(definition.get("ground", "#a9ada4")))
	# Readable 32px modular grid: graybox geometry, not generated concept art.
	for x in range(0, int(bounds.size.x), 32):
		draw_line(Vector2(x, 0), Vector2(x, bounds.size.y), Color(0.1, 0.14, 0.16, 0.12))
	for y in range(0, int(bounds.size.y), 32):
		draw_line(Vector2(0, y), Vector2(bounds.size.x, y), Color(0.1, 0.14, 0.16, 0.12))
	for obstacle: Dictionary in definition["obstacles"]:
		var rect := _rect(obstacle["rect"])
		var kind: String = obstacle["kind"]
		var color := Color("#4c5660") if kind == "building" else Color("#5b3a30")
		if kind == "water":
			color = Color("#335f79")
		draw_rect(rect, color)
		draw_rect(rect, Color("#242833"), false, 2.0)
		if kind == "building":
			draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, 12)), Color("#333b46"))
		if obstacle.has("label_key"):
			draw_string(FONT, rect.position + Vector2(8, minf(40, rect.size.y - 5)), tr(obstacle["label_key"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 14, Color("#f1e6cf"))
	for target: Dictionary in definition["interactions"]:
		_draw_target(target)
	draw_rect(bounds.grow(-8), Color("#4c5660"), false, 16.0)

func _draw_target(target: Dictionary) -> void:
	var point := _point(target["position"])
	var kind: String = target["kind"]
	var inspected: bool = GameSession.is_inspected(target["id"])
	var selected: bool = selected_target.get("id", "") == target["id"]
	if kind == "npc":
		draw_rect(Rect2(point - Vector2(9, 30), Vector2(18, 30)), Color("#a96a42") if scene_id == "SCENE_TOWN_STREET" else Color("#34594a"))
		draw_rect(Rect2(point - Vector2(6, 41), Vector2(12, 11)), Color("#e2aa78"))
		draw_rect(Rect2(point - Vector2(7, 44), Vector2(14, 5)), Color("#242833"))
	elif kind == "document":
		draw_rect(Rect2(point - Vector2(15, 28), Vector2(30, 28)), Color("#5b3a30"))
		draw_rect(Rect2(point - Vector2(11, 25), Vector2(22, 19)), Color("#d8d0be"))
		draw_rect(Rect2(point - Vector2(2, 15), Vector2(5, 5)), Color("#b84a3e"))
	else:
		draw_rect(Rect2(point - Vector2(20, 18), Vector2(40, 36)), Color("#34594a"), false, 3.0)
		draw_line(point - Vector2(10, 0), point + Vector2(10, 0), Color("#171820"), 2.0)
		draw_line(point + Vector2(4, -6), point + Vector2(10, 0), Color("#171820"), 2.0)
		draw_line(point + Vector2(4, 6), point + Vector2(10, 0), Color("#171820"), 2.0)
	if selected or observing:
		draw_rect(Rect2(point - Vector2(19, 47), Vector2(38, 51)), Color("#d19a5c") if selected else Color("#335f79"), false, 2.0 if selected else 1.0)
	if inspected:
		draw_line(point + Vector2(12, -35), point + Vector2(16, -31), Color("#203934"), 2.0)
		draw_line(point + Vector2(16, -31), point + Vector2(24, -41), Color("#203934"), 2.0)
	# Destinations are always legible; only one contextual action prompt lives in HUD.
	if kind == "exit" or selected or observing:
		var caption: String = tr(target["name_key"])
		var width := FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var baseline := point + Vector2(-width / 2, -54)
		draw_rect(Rect2(baseline + Vector2(-4, -16), Vector2(width + 8, 21)), Color("#171820"))
		draw_string(FONT, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#f1e6cf"))

func _point(values: Array) -> Vector2:
	return Vector2(values[0], values[1])

func _rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])
