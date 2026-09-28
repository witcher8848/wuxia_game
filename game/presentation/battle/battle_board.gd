extends Node2D
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const ORIGIN := Vector2(12, 36)
const CELL := 32
var battle: CombatEncounter
var cursor := Vector2i.ZERO
var highlights: Array = []
var path: Array = []
var affected: Array = []
var inspect_enemy := false


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("#141e29"))
	if battle == null:
		return
	for y: int in range(battle.board_size.y):
		for x: int in range(battle.board_size.x):
			var cell := Vector2i(x, y)
			var rectangle := Rect2(ORIGIN + Vector2(cell) * CELL, Vector2(31,31))
			var color := Color("#343f49")
			if battle.is_obstacle(cell): color = Color("#796f5c")
			elif cell in highlights: color = Color("#574360") if inspect_enemy else Color("#315a65")
			draw_rect(rectangle, color)
			if battle.objective.get("kind") == "escape" and cell == Vector2i(battle.objective["cell"][0], battle.objective["cell"][1]):
				draw_rect(rectangle.grow(-2), Color("#7ccc83"), false, 2)
	for index: int in range(1, path.size()):
		draw_line(ORIGIN + Vector2(path[index-1]) * CELL + Vector2(16,16), ORIGIN + Vector2(path[index]) * CELL + Vector2(16,16), Color("#b0dcce"), 3)
	for identifier: String in battle.unit_ids():
		var unit := battle.unit(identifier)
		var at := ORIGIN + Vector2(Grid.cell_of(unit)) * CELL
		if unit["hp"] == 0:
			draw_line(at + Vector2(10,10), at + Vector2(22,22), Color("#7b7777"), 2)
			continue
		draw_rect(Rect2(at + Vector2(7,4), Vector2(18,22)), Color("#69bfd5") if unit["team"] == "ally" else Color("#dd876e"))
		draw_string(FONT, at + Vector2(8,21), unit["name"].substr(0,1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#121a22"))
		draw_rect(Rect2(at + Vector2(4,28), Vector2(24,2)), Color("#17232b"))
		draw_rect(Rect2(at + Vector2(4,28), Vector2(24.0 * float(unit["hp"]) / float(unit["max_hp"]),2)), Color("#95c979"))
		if not unit["statuses"].is_empty(): draw_circle(at + Vector2(27,5), 2, Color("#d9bd68"))
		if identifier == battle.current_actor_id(): draw_rect(Rect2(at + Vector2(2,2), Vector2(28,28)), Color("#f6d379"), false, 2)
	for cell: Vector2i in affected:
		draw_rect(Rect2(ORIGIN + Vector2(cell)*CELL + Vector2(1,1), Vector2(29,29)), Color("#e88e77"), false, 2)
	draw_rect(Rect2(ORIGIN + Vector2(cursor)*CELL, Vector2(31,31)), Color.WHITE, false, 1)
