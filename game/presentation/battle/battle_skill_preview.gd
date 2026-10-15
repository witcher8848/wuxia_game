extends RefCounted
## Read-only presentation model shared by menu hover and target selection.
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")


static func build(battle: CombatEncounter, actor: String, identifier: String, cursor: Vector2i) -> Dictionary:
	var ranges := Actions.target_cells(battle, actor, identifier)
	var targets: Array[Vector2i] = []
	var hits: Array[Dictionary] = []
	for cell: Vector2i in ranges:
		var action := battle.preview_action(actor, identifier, cell)
		if action["ok"]:
			targets.append(cell)
			hits.append_array(action["hits"])
	var skill := battle.skill(identifier)
	var origin := Grid.cell_of(battle.unit(actor))
	# Support is cast on self but affects adjacent allies: show the area as well.
	if skill["area_pattern"] == "adjacent_allies":
		for direction: Vector2i in Grid.DIRECTIONS:
			var cell := origin + direction
			if battle.contains(cell) and not battle.is_obstacle(cell): ranges.append(cell)
	var affected: Array[Vector2i] = []
	var action := battle.preview_action(actor, identifier, cursor)
	if skill["area_pattern"] == "front_arc":
		for cell: Vector2i in Actions.affected_cells(battle,actor,identifier,cursor):
			if not cell in ranges: ranges.append(cell)
	if action["ok"]:
		if skill["range_pattern"] == "step": affected.append(cursor)
		elif skill["area_pattern"] == "front_arc":
			for hit: Dictionary in action["hits"]:
				var receiver_cell := Grid.cell_of(battle.unit(hit["receiver"]))
				if not receiver_cell in affected: affected.append(receiver_cell)
		elif not action["hits"].is_empty():
			for hit: Dictionary in action["hits"]: affected.append(Grid.cell_of(battle.unit(hit["receiver"])))
		else:
			for target: String in action["affected"]: affected.append(Grid.cell_of(battle.unit(target)))
	return {"range":ranges, "targets":targets, "affected":affected, "hits":hits, "reason":Actions.unavailable(battle,actor,identifier)}
