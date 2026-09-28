class_name BattleGrid
extends RefCounted
## Deterministic four-way BFS. Paths include the origin and never mutate state.
const DIRECTIONS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]


static func reachable(battle: RefCounted, identifier: String, budget: int, origin := Vector2i(-1, -1), ignore_units := false) -> Dictionary:
	var unit: Dictionary = battle.unit(identifier)
	if unit.is_empty() or unit["hp"] <= 0 or budget < 0:
		return {}
	if origin == Vector2i(-1, -1):
		origin = cell_of(unit)
	if not battle.contains(origin) or battle.is_obstacle(origin):
		return {}
	var paths: Dictionary = {origin: [origin]}
	var queue: Array[Vector2i] = [origin]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if paths[cell].size() - 1 >= budget:
			continue
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			if paths.has(next) or not battle.contains(next) or battle.is_obstacle(next):
				continue
			var occupant: String = battle.unit_at(next)
			if not ignore_units and not occupant.is_empty() and occupant != identifier:
				continue
			var path: Array = paths[cell].duplicate()
			path.append(next)
			paths[next] = path
			queue.append(next)
	return paths


static func line_clear(battle: RefCounted, origin: Vector2i, target: Vector2i) -> bool:
	if origin == target or (origin.x != target.x and origin.y != target.y):
		return false
	var direction := Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
	var cell := origin + direction
	while cell != target:
		if battle.is_obstacle(cell) or not battle.unit_at(cell).is_empty():
			return false
		cell += direction
	return battle.contains(target) and not battle.is_obstacle(target)


static func cell_of(unit: Dictionary) -> Vector2i:
	return Vector2i(int(unit["cell"][0]), int(unit["cell"][1]))


static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
