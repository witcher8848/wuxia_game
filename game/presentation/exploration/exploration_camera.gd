class_name ExplorationCamera
extends Camera2D
## Explicit logical-pixel camera. Region calls follow after moving the player.

const LOGICAL_VIEWPORT := Vector2(640, 360)
var _bounds := Rect2(Vector2.ZERO, LOGICAL_VIEWPORT)

func _ready() -> void:
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	zoom = Vector2.ONE
	offset = Vector2.ZERO
	ignore_rotation = true
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	follow(global_position)

func configure_bounds(bounds: Rect2) -> void:
	_bounds = bounds.abs()
	if _bounds.size.x < LOGICAL_VIEWPORT.x or _bounds.size.y < LOGICAL_VIEWPORT.y:
		push_warning("Exploration camera region is smaller than the logical viewport.")
	follow(global_position)

func follow(target_position: Vector2) -> void:
	var half := LOGICAL_VIEWPORT * 0.5
	var minimum := (_bounds.position + half).ceil()
	var maximum := (_bounds.end - half).floor()
	var center := target_position.round()
	center.x = clampf(center.x, minimum.x, maximum.x) if minimum.x <= maximum.x else roundf(_bounds.get_center().x)
	center.y = clampf(center.y, minimum.y, maximum.y) if minimum.y <= maximum.y else roundf(_bounds.get_center().y)
	global_position = center
	force_update_scroll()
