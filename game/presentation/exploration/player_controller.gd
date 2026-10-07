class_name ExplorationPlayer
extends CharacterBody2D
## Scene-local movement only. The region owns persistence and interaction state.
## Origin is the feet anchor (16, 44) of the 32 × 48 placeholder canvas.

const WALK_SPEED := 180.0
const SPRINT_SPEED := 300.0
const MOVE_ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down", &"sprint"]

var facing: String = "down"
var sprinting := false
var movement_enabled: bool = true:
	set(value):
		if movement_enabled != value:
			reset_input()
		movement_enabled = value
var _requires_release := false
var _window_focused := true
var _visual: PlayerVisual

class PlayerVisual extends Node2D:
	var facing: String = "down"
	var walking := false
	var sprinting := false
	var step_time := 0.0

	func _draw() -> void:
		# Deliberately procedural greybox, not a production sprite or AI asset.
		var stride := 1.0 if walking and fmod(step_time, 0.32) < 0.16 else 0.0
		# Small integer-pixel dust marks plus a faster gait distinguish sprinting.
		# No stamina resource, camera shake, screen flash or persistent effect state.
		if sprinting:
			var behind := Vector2.DOWN
			match facing:
				"down": behind = Vector2.UP
				"left": behind = Vector2.RIGHT
				"right": behind = Vector2.LEFT
			var side := Vector2(-behind.y, behind.x)
			var spread := 15.0 if behind.y != 0.0 else 4.0
			var phase := 2.0 if fmod(step_time, 0.24) < 0.12 else 0.0
			draw_rect(Rect2((behind * (12 + phase) + side * spread).round(), Vector2(4, 2)), Color("#d19a5c"))
			draw_rect(Rect2((behind * (17 + phase) - side * spread).round(), Vector2(3, 2)), Color("#a9ada4"))
		draw_rect(Rect2(-12, -2, 24, 5), Color("#343b38"))
		draw_rect(Rect2(-8, -10 + stride, 6, 11), Color("#303745"))
		draw_rect(Rect2(2, -10 - stride, 6, 11), Color("#303745"))
		draw_rect(Rect2(-9, -1 + stride, 7, 3), Color("#232a31"))
		draw_rect(Rect2(2, -1 - stride, 7, 3), Color("#232a31"))
		draw_rect(Rect2(-10, -28, 20, 21), Color("#34586b"))
		draw_rect(Rect2(-6, -28, 5, 17), Color("#517e89"))
		draw_rect(Rect2(-11, -12, 22, 4), Color("#ba935a"))
		draw_rect(Rect2(-13, -26, 4, 14), Color("#426676"))
		draw_rect(Rect2(9, -26, 4, 14), Color("#426676"))
		draw_rect(Rect2(-13, -13, 4, 5), Color("#d5ad80"))
		draw_rect(Rect2(9, -13, 4, 5), Color("#d5ad80"))
		draw_rect(Rect2(-7, -40, 14, 12), Color("#d5ad80"))
		draw_rect(Rect2(-8, -42, 16, 6), Color("#283138"))
		draw_rect(Rect2(-3, -44, 6, 3), Color("#283138"))
		if facing == "up":
			draw_rect(Rect2(-7, -38, 14, 9), Color("#283138"))
			draw_rect(Rect2(-2, -29, 4, 13), Color("#283138"))
		else:
			var eye_x := -4.0 if facing == "left" else 3.0
			draw_rect(Rect2(eye_x, -35, 2, 2), Color("#30353c"))
			if facing == "down":
				draw_rect(Rect2(-4, -35, 2, 2), Color("#30353c"))

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.02
	var collision := CollisionShape2D.new()
	collision.name = "FeetCollision"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 12)
	collision.shape = rectangle
	add_child(collision)
	_visual = PlayerVisual.new()
	_visual.name = "Visual"
	add_child(_visual)
	_sync_visual(0.0)

func reset_input() -> void:
	# Do not globally release actions: menus and other input owners need them.
	velocity = Vector2.ZERO
	sprinting = false
	_requires_release = true

func facing_vector() -> Vector2:
	match facing:
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up": return Vector2.UP
		_: return Vector2.DOWN

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		reset_input()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
		reset_input()
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		reset_input()

func _physics_process(delta: float) -> void:
	var app := get_node_or_null("/root/App")
	var context_active: bool = app == null or app.current_context() == &"exploration"
	if not movement_enabled or not _window_focused or not context_active:
		reset_input()
		_sync_visual(delta)
		return
	if _requires_release:
		for action in MOVE_ACTIONS:
			if Input.is_action_pressed(action):
				_sync_visual(delta)
				return
		_requires_release = false
		_sync_visual(delta)
		return
	var direction := _read_cardinal_direction()
	if direction != Vector2.ZERO:
		if direction.x != 0.0:
			facing = "right" if direction.x > 0.0 else "left"
		else:
			facing = "down" if direction.y > 0.0 else "up"
	var sprint_requested := Input.is_action_pressed("sprint")
	velocity = direction * (SPRINT_SPEED if sprint_requested else WALK_SPEED)
	var before := position
	move_and_slide()
	sprinting = sprint_requested and position.distance_squared_to(before) > 0.0001
	_sync_visual(delta)

func _read_cardinal_direction() -> Vector2:
	# get_vector normalizes diagonals, which would incorrectly slow a chosen axis.
	var horizontal := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var vertical := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	if absf(horizontal) >= absf(vertical) and horizontal != 0.0:
		return Vector2(signf(horizontal), 0.0)
	if vertical != 0.0:
		return Vector2(0.0, signf(vertical))
	return Vector2.ZERO

func _sync_visual(delta: float) -> void:
	if not is_instance_valid(_visual):
		return
	# Round only drawing: the CharacterBody keeps fractional physics coordinates.
	_visual.global_position = global_position.round()
	_visual.facing = facing
	_visual.walking = velocity.length_squared() > 0.0
	_visual.sprinting = sprinting
	_visual.step_time += delta * (SPRINT_SPEED / WALK_SPEED if sprinting else 1.0)
	_visual.queue_redraw()
