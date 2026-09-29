extends RefCounted
const AI = preload("res://game/domain/battle/battle_ai.gd")


static func enemy_cells(battle: CombatEncounter, actor: String) -> Array[Vector2i]:
	# Union at current positions, not a predicted attack zone or AI destination.
	var cells: Array[Vector2i] = []
	var unit := battle.unit(actor)
	if unit.is_empty(): return cells
	for identifier: String in battle.unit_ids():
		var other := battle.unit(identifier)
		if other["hp"] <= 0 or other["team"] == unit["team"]: continue
		for cell: Vector2i in AI.intent(battle, identifier)["reachable"]:
			if not cell in cells: cells.append(cell)
	return cells
