class_name ExplorationPlayer
extends CharacterBody2D
## Scene-local movement only. The region owns persistence and interaction state.
## Origin is the feet anchor (16, 44) of the shared 32 × 48 character atlas.

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

class PlayerVisual extends "res://game/presentation/characters/hero_visual.gd":
	func _ready() -> void:
		external_clock = true
		super._ready()

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
