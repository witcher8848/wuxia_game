extends SceneTree

const PLAYER = preload("res://game/presentation/exploration/player_controller.gd")
const CAMERA = preload("res://game/presentation/exploration/exploration_camera.gd")
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "sprint"]
var failures: Array[String] = []
var checks := 0
var player: PLAYER
var world: Node2D
var app: Node

func _initialize() -> void:
	# A coroutine aborted by a runtime error must not leave a headless CI hanging.
	create_timer(45.0, true).timeout.connect(func() -> void:
		printerr("EXPLORATION_CONTROLLER_FAIL watchdog timeout")
		quit(1)
	)
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("EXPLORATION_CONTROLLER_FAIL ", message)

func _advance(frames: int = 1) -> void:
	for _frame in range(frames):
		await physics_frame
		await process_frame

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _reset_at(point: Vector2) -> void:
	_release()
	player.position = point
	player.reset_input()
	await _advance(2)

func _wall(rectangle: Rect2) -> void:
	var wall := StaticBody2D.new()
	wall.position = rectangle.get_center()
	wall.collision_layer = 1
	wall.collision_mask = 2
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rectangle.size
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)

func _run() -> void:
	await process_frame
	app = root.get_node("App")
	app.reset_contexts()
	var session := root.get_node("GameSession")
	var initial_state: Dictionary = session.state.to_dict().duplicate(true)
	world = Node2D.new()
	root.add_child(world)
	player = PLAYER.new()
	world.add_child(player)
	await _advance(2)
	var collider: CollisionShape2D = player.get_node("FeetCollision")
	check(collider.shape.size == Vector2(20, 12) and collider.position == Vector2.ZERO, "20x12 feet collision centered on player anchor")
	check(player.collision_layer == 2 and player.collision_mask == 1, "player collides with static world layer")
	var directions := {"move_left": Vector2.LEFT, "move_right": Vector2.RIGHT, "move_up": Vector2.UP, "move_down": Vector2.DOWN}
	var names := {"move_left": "left", "move_right": "right", "move_up": "up", "move_down": "down"}
	for action in directions:
		await _reset_at(Vector2(100, 100))
		Input.action_press(action)
		await _advance(12)
		var displacement: Vector2 = player.position - Vector2(100, 100)
		check(displacement.dot(directions[action]) > 12.0, action + " advances in expected direction")
		check(absf(displacement.cross(directions[action])) < 0.001, action + " stays on one axis")
		check(player.velocity.is_equal_approx(directions[action] * 180.0), action + " walk speed matches former sprint at180")
		check(player.facing == names[action] and player.facing_vector() == directions[action], action + " updates facing")
		_release()
		await _advance()
		check(player.velocity == Vector2.ZERO and player.facing == names[action], action + " release stops while retaining facing")
	# Exercise the actual bindings as well as synthetic action strengths. These
	# injected key events still do not stand in for a person's hardware playtest.
	for binding in [[KEY_A, Vector2.LEFT], [KEY_LEFT, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_RIGHT, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_UP, Vector2.UP], [KEY_S, Vector2.DOWN], [KEY_DOWN, Vector2.DOWN]]:
		await _reset_at(Vector2(100, 100))
		_key(binding[0], true)
		await _advance(3)
		check(player.velocity.is_equal_approx(binding[1] * 180.0), "physical key binding %s drives cardinal walk" % binding[0])
		_key(binding[0], false)
		await _advance(2)
		check(player.velocity == Vector2.ZERO, "physical key binding %s releases movement" % binding[0])
	await _reset_at(Vector2(100, 100))
	_key(KEY_D, true)
	_key(KEY_SHIFT, true)
	await _advance(3)
	check(player.velocity == Vector2(300, 0), "Shift keyboard binding drives sprint at300")
	check(player.sprinting and player.get_node("Visual").sprinting, "actual sprint movement enables dust and fast gait")
	check(is_equal_approx(PLAYER.SPRINT_SPEED / PLAYER.WALK_SPEED, 5.0 / 3.0), "sprint stays visibly faster than walking at five thirds speed")
	var running_phase: float = player.get_node("Visual").step_time
	await _advance(6)
	check(player.get_node("Visual").step_time - running_phase > 0.15, "sprint gait animation advances faster than walking")
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	await _advance(2)
	check(not player.sprinting and not player.get_node("Visual").sprinting, "releasing movement clears sprint feedback")
	await _reset_at(Vector2(100, 100))
	Input.action_press("move_up")
	Input.action_press("move_right")
	await _advance(12)
	check(is_equal_approx(player.velocity.length(), 180.0), "digital diagonal keeps full walk speed without normalization slowdown")
	check(player.position.y == 100 and player.position.x > 112, "diagonal selects deterministic horizontal axis without double movement")
	Input.action_press("sprint")
	await _advance(8)
	check(player.velocity == Vector2(300, 0), "sprint stays cardinal at300")
	# 180 px/s is exactly 3 px per 60 Hz tick. Seed a fractional origin to
	# detect unwanted physics snapping independently of the chosen speed.
	await _reset_at(Vector2(100.25, 100.25))
	Input.action_press("move_right")
	await _advance(4)
	check(not player.position.is_equal_approx(player.position.round()), "fractional physics position accumulates without pixel snapping")
	check(player.get_node("Visual").global_position == player.global_position.round(), "visual alone is snapped to integer world pixels")
	await _reset_at(Vector2(100, 100))
	Input.action_press("move_right")
	Input.action_press("move_left")
	await _advance(3)
	check(player.position == Vector2(100, 100), "opposite held directions cancel")
	await _reset_at(Vector2(100, 100))
	Input.action_press("move_up", 0.8)
	Input.action_press("move_right", 0.4)
	await _advance(3)
	check(player.velocity == Vector2(0, -180), "stronger analogue axis wins at full cardinal walk speed")
	await _reset_at(Vector2(100, 100))
	Input.action_press("move_up")
	Input.action_press("move_down")
	await _advance(3)
	check(player.position == Vector2(100, 100), "opposite vertical directions cancel")
	await _reset_at(Vector2(100, 100))
	Input.action_press("sprint")
	await _advance(3)
	check(not player.sprinting and not player.get_node("Visual").sprinting, "Shift while stationary shows no fake running feedback")
	await _reset_at(Vector2(100, 100))
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _advance(3)
	app.push_context(&"system_menu")
	var stopped := player.position
	await _advance(4)
	check(player.position == stopped and player.velocity == Vector2.ZERO, "pause context immediately stops held movement")
	check(not player.sprinting and not player.get_node("Visual").sprinting, "pause removes sprint feedback")
	app.pop_context()
	await _advance(4)
	check(player.position == stopped, "resume ignores stale held direction until release")
	_release()
	await _advance(2)
	Input.action_press("move_right")
	await _advance(3)
	check(player.position.x > stopped.x, "fresh press after pause release moves normally")
	player.movement_enabled = false
	stopped = player.position
	await _advance(3)
	check(player.position == stopped, "dialogue interaction disables movement")
	player.movement_enabled = true
	await _advance(3)
	check(player.position == stopped, "closing dialogue does not reuse held movement")
	await _reset_at(Vector2(100, 100))
	Input.action_press("move_right")
	await _advance(2)
	player.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	stopped = player.position
	await _advance(3)
	check(player.position == stopped, "focus loss stops held movement")
	player.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await _advance(3)
	check(player.position == stopped, "focus return rejects stale held key")
	_release()
	await _advance(2)
	Input.action_press("move_down")
	await _advance(3)
	check(player.position.y > stopped.y, "fresh press after focus restore works")
	paused = true
	stopped = player.position
	await process_frame
	paused = false
	await _advance(3)
	check(player.position == stopped, "actual SceneTree pause/resume also clears held intent")
	await _reset_at(Vector2(100, 160))
	_wall(Rect2(190, 0, 20, 400))
	_wall(Rect2(0, 210, 200, 20))
	await _advance(2)
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _advance(65)
	check(player.position.x <= 180.02 and player.position.x > 178.0, "sprinting cannot penetrate vertical wall")
	check(player.get_slide_collision_count() > 0, "wall check exercises physics collision")
	check(not player.sprinting and not player.get_node("Visual").sprinting, "holding sprint into a wall does not emit moving dust")
	_release()
	Input.action_press("move_down")
	await _advance(65)
	check(player.position.y <= 204.02 and player.position.y > 202.0, "turn into corner stops feet at horizontal wall")
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _advance(30)
	check(player.position.x <= 180.02 and player.position.y <= 204.02, "held diagonal+sprint cannot cut wall corner")
	check(session.state.to_dict() == initial_state, "controller never writes permanent session state")
	_release()
	var camera := CAMERA.new()
	world.add_child(camera)
	var bounds := Rect2(0, 0, 1280, 768)
	camera.configure_bounds(bounds)
	for target in [Vector2(-800, -800), Vector2(500.4, 350.6), Vector2(2000, 2000)]:
		camera.follow(target)
		check(camera.global_position == camera.global_position.round(), "camera center integer for target " + str(target))
		check(bounds.encloses(Rect2(camera.global_position - Vector2(320, 180), Vector2(640, 360))), "viewport remains inside bounds for " + str(target))
		check(camera.get_screen_center_position().is_equal_approx(camera.global_position), "actual camera scroll matches integer center for " + str(target))
		check(root.canvas_transform.origin == root.canvas_transform.origin.round(), "actual viewport translation uses integer logical pixels for " + str(target))
	check(camera.global_position == Vector2(960, 588), "bottom right edge clamps using logical viewport")
	camera.follow(Vector2.ZERO)
	check(camera.global_position == Vector2(320, 180), "top left edge clamps using logical viewport")
	check(not camera.position_smoothing_enabled and camera.zoom == Vector2.ONE and camera.offset == Vector2.ZERO, "camera disables smoothing and scaling")
	camera.configure_bounds(Rect2(-320, -180, 960, 540))
	camera.follow(Vector2(-1000, -1000))
	check(camera.global_position == Vector2.ZERO, "nonzero region origin honored")
	camera.configure_bounds(Rect2(0, 0, 640, 360))
	camera.follow(Vector2(500, 300))
	check(camera.global_position == Vector2(320, 180), "one-screen region does not scroll")
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("EXPLORATION_CONTROLLER_PASS checks=", checks, " (injected actions/focus; real collision and camera code)")
	quit(0 if failures.is_empty() else 1)
