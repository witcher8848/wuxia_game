extends Node2D
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const ORIGIN := Vector2(12, 44)
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const CELL := 32
var battle: CombatEncounter
var cursor := Vector2i.ZERO
var highlights: Array = []
var path: Array = []
var affected: Array = []
var inspect_enemy := false
var range_cells: Array = []
var valid_targets: Array = []
var range_disabled := false
var range_offensive := false
var enemy_reach: Array = []
var hero_visual: Node2D
var hero_position := Vector2.ZERO
var _motion: Array = []
var _motion_time := 0.0
var _last_hp := -1
var _bound_battle: CombatEncounter

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero_visual = Hero.new()
	add_child(hero_visual)
	hero_visual.hide() # Drawn in the board's sorted actor pass, not above all units.

func reset_presentation() -> void:
	_motion.clear()
	_last_hp = -1
	if is_instance_valid(hero_visual): hero_visual.reset_pose()
	sync_visuals()

func sync_visuals() -> void:
	if battle == null or not is_instance_valid(hero_visual): return
	if _bound_battle != battle:
		_bound_battle = battle
		_motion.clear()
		_last_hp = -1
		hero_visual.reset_pose()
	var unit: Dictionary = battle.unit("CHAR_PROTAGONIST")
	if unit.is_empty(): return
	if _motion.is_empty(): hero_position = _feet(Grid.cell_of(unit))
	var hp: int = unit["hp"]
	if hp == 0:
		# Repeated synchronization must not restart a multi-frame falling clip.
		if hero_visual._action != "down": hero_visual.play_action("down",hero_visual.facing)
	elif _last_hp >= 0 and hp < _last_hp: hero_visual.play_action("hit",hero_visual.facing)
	elif _last_hp >= 0 and hp > _last_hp: reset_presentation(); return
	_last_hp = hp

func _feet(cell: Vector2i) -> Vector2:
	return ORIGIN+Vector2(cell)*CELL+Vector2(16,29)

func _sorted_actor_ids() -> Array[String]:
	var sorted: Array[String] = battle.unit_ids()
	# A confirmed move updates the logical cell immediately, while its visual
	# feet travel through the path. Occlusion follows the visible feet.
	sorted.sort_custom(func(a: String,b: String) -> bool:
		var a_y := hero_position.y if a == "CHAR_PROTAGONIST" else _feet(Grid.cell_of(battle.unit(a))).y
		var b_y := hero_position.y if b == "CHAR_PROTAGONIST" else _feet(Grid.cell_of(battle.unit(b))).y
		return a_y < b_y
	)
	return sorted

func _direction(offset: Vector2) -> String:
	if offset == Vector2.ZERO: return hero_visual.facing
	if absf(offset.x) >= absf(offset.y): return "right" if offset.x > 0 else "left"
	return "down" if offset.y > 0 else "up"

func animate_move(actor: String, cells: Array) -> void:
	if actor != "CHAR_PROTAGONIST" or cells.size() < 2: return
	_motion = cells.duplicate()
	_motion_time = 0.0
	hero_visual.reset_pose()
	hero_visual.walking = true
	hero_position = _feet(_motion[0])

func animate_action(plan: Dictionary) -> void:
	if plan.get("actor") != "CHAR_PROTAGONIST": return
	_motion.clear() # Rapid confirmed input may finish the preceding visual move.
	var origin := Grid.cell_of(battle.unit("CHAR_PROTAGONIST"))
	hero_position = _feet(origin)
	var skill: Dictionary = battle.skill(plan["skill_id"])
	var direction := _direction(Vector2(plan["target"])-Vector2(origin))
	var clip := "guard"
	if skill["target"] == "enemy":
		clip = ("slash" if skill["ultimate"] else "thrust") if skill["weapon_tag"] == "剑" else "strike"
	hero_visual.play_action(clip,direction)

func _process(delta: float) -> void:
	if _motion.size() > 1:
		_motion_time += delta
		var segment := mini(int(_motion_time/0.08),_motion.size()-2)
		var weight := clampf((_motion_time-segment*0.08)/0.08,0,1)
		var from := _feet(_motion[segment])
		var to := _feet(_motion[segment+1])
		hero_position = from.lerp(to,weight).round()
		hero_visual.facing = _direction(to-from)
		if _motion_time >= (_motion.size()-1)*0.08:
			_motion.clear()
			hero_visual.walking = false
			sync_visuals()
	queue_redraw()


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
			elif cell in enemy_reach: color = Color("#574360")
			elif cell in range_cells:
				color = Color("#634b48") if range_offensive else Color("#315a65")
				if range_disabled: color = Color("#51545c")
			draw_rect(rectangle, color)
			if cell in enemy_reach: draw_rect(rectangle.grow(-2), Color("#b78bc9"), false, 1)
			if cell in valid_targets: draw_rect(rectangle.grow(-4), Color("#a5dfeb"), false, 2)
			if battle.objective.get("kind") == "escape" and cell == Vector2i(battle.objective["cell"][0], battle.objective["cell"][1]):
				draw_rect(rectangle.grow(-2), Color("#7ccc83"), false, 2)
	for index: int in range(1, path.size()):
		draw_line(ORIGIN + Vector2(path[index-1]) * CELL + Vector2(16,16), ORIGIN + Vector2(path[index]) * CELL + Vector2(16,16), Color("#b0dcce"), 3)
	var sorted := _sorted_actor_ids()
	for identifier: String in sorted:
		var unit := battle.unit(identifier)
		var at := ORIGIN + Vector2(Grid.cell_of(unit)) * CELL
		if unit["hp"] == 0:
			if identifier == "CHAR_PROTAGONIST": hero_visual.draw_at(self,hero_position)
			else: draw_line(at + Vector2(10,10), at + Vector2(22,22), Color("#7b7777"), 2)
			continue
		if identifier == "CHAR_PROTAGONIST": hero_visual.draw_at(self,hero_position)
		else:
			draw_rect(Rect2(at + Vector2(7,4), Vector2(18,22)), Color("#69bfd5") if unit["team"] == "ally" else Color("#dd876e"))
			draw_string(FONT, at + Vector2(8,21), unit["name"].substr(0,1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#121a22"))
		draw_rect(Rect2(at + Vector2(4,28), Vector2(24,2)), Color("#17232b"))
		draw_rect(Rect2(at + Vector2(4,28), Vector2(24.0 * float(unit["hp"]) / float(unit["max_hp"]),2)), Color("#95c979"))
		if not unit["statuses"].is_empty(): draw_circle(at + Vector2(27,5), 2, Color("#d9bd68"))
		if identifier == battle.current_actor_id(): draw_rect(Rect2(at + Vector2(2,2), Vector2(28,28)), Color("#f6d379"), false, 2)
	for cell: Vector2i in affected:
		draw_rect(Rect2(ORIGIN + Vector2(cell)*CELL + Vector2(1,1), Vector2(29,29)), Color("#e88e77"), false, 2)
	draw_rect(Rect2(ORIGIN + Vector2(cursor)*CELL, Vector2(31,31)), Color.WHITE, false, 1)
