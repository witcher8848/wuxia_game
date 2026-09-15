extends Node2D

const CELL := 32
const START := Vector2(304, 172)
var player_position := START

func _ready() -> void:
	var saved_position: Dictionary = GameSession.state.player_state.get("position", {"x": START.x, "y": START.y})
	player_position = Vector2(float(saved_position["x"]), float(saved_position["y"]))

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("#171820"))
	draw_rect(Rect2(32, 64, 576, 224), Color("#333b46"))
	for x in range(32, 609, CELL):
		draw_line(Vector2(x, 64), Vector2(x, 288), Color("#4c5660"))
	for y in range(64, 289, CELL):
		draw_line(Vector2(32, y), Vector2(608, y), Color("#4c5660"))
	draw_rect(Rect2(32, 64, 576, 224), Color("#a9ada4"), false, 2.0)
	draw_circle(player_position + Vector2(0, 4), 9.0, Color("#242833"))
	draw_rect(Rect2(player_position - Vector2(7, 23), Vector2(14, 25)), Color("#335f79"))
	draw_rect(Rect2(player_position - Vector2(5, 32), Vector2(10, 10)), Color("#d19a5c"))

func _physics_process(delta: float) -> void:
	if App.current_context() != &"exploration":
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# One axis at a time: the art baseline only supplies four directions.
	if absf(direction.x) >= absf(direction.y):
		direction.y = 0.0
	else:
		direction.x = 0.0
	var speed := 128.0 if Input.is_action_pressed("sprint") else 80.0
	player_position += direction * speed * delta
	player_position = player_position.clamp(Vector2(44, 100), Vector2(596, 278))
	GameSession.update_player_position(player_position)
	queue_redraw()
