class_name BattleActions
extends RefCounted
const Grid = preload("res://game/domain/battle/battle_grid.gd")


static func preview(battle: RefCounted, actor: String, skill_id: String, target: Vector2i, origin := Vector2i(-1, -1)) -> Dictionary:
	var denied := {"ok": false, "reason": "不是该单位的行动回合", "revision": battle.revision}
	if battle.outcome != "ongoing" or actor != battle.current_actor_id():
		return denied
	var unit: Dictionary = battle.unit(actor)
	var skill: Dictionary = battle.skill(skill_id)
	if skill.is_empty() or not skill_id in battle.abilities(actor):
		denied["reason"] = "未配置该招式"
		return denied
	var availability: String = unavailable(battle, actor, skill_id)
	if not availability.is_empty():
		denied["reason"] = availability
		return denied
	if origin == Vector2i(-1, -1):
		origin = Grid.cell_of(unit)
	if not battle.contains(target):
		denied["reason"] = "目标超出战场"
		return denied
	var target_id: String = battle.unit_at(target)
	var distance: int = Grid.distance(origin, target)
	var valid := range_matches(battle, actor, skill, origin, target)
	if skill["target"] == "enemy" and skill["area_pattern"] != "front_arc":
		valid = valid and not target_id.is_empty() and battle.unit(target_id)["team"] != unit["team"]
	if not valid:
		denied["reason"] = "目标／距离／射线不合法"
		return denied
	var hits: Array[Dictionary] = []
	var area: Array[Vector2i] = []
	if skill["area_pattern"] == "front_arc":
		area = affected_cells(battle, actor, skill_id, target, origin)
		var receivers: Dictionary = {}
		# Resolve once against pre-cast support relationships, center/left/right.
		# An actual recipient can be struck only once by this single sweep. A
		# skipped duplicate does not consume a second ward or multiply damage.
		for cell: Vector2i in area:
			var identifier: String = battle.unit_at(cell)
			if identifier.is_empty() or battle.unit(identifier)["team"] == unit["team"]: continue
			var hit := damage_preview(battle, actor, identifier, skill, Grid.distance(origin, cell))
			if receivers.has(hit["receiver"]): continue
			receivers[hit["receiver"]] = true
			hits.append(hit)
		if hits.is_empty():
			denied["reason"] = "横截范围内没有敌人"
			return denied
	elif skill["target"] == "enemy":
		hits.append(damage_preview(battle, actor, target_id, skill, distance))
	var affected: Array = [actor] if skill["target"] != "enemy" else [target_id]
	if skill["area_pattern"] == "front_arc":
		affected = []
		for hit: Dictionary in hits: affected.append(hit["receiver"])
	if skill["area_pattern"] == "adjacent_allies":
		for identifier: String in battle.unit_ids():
			var other: Dictionary = battle.unit(identifier)
			if identifier != actor and other["team"] == unit["team"] and other["hp"] > 0 and Grid.distance(origin, Grid.cell_of(other)) == 1:
				affected.append(identifier)
	var qi_before: int = int(unit["qi"])
	var qi_cost: int = int(skill["qi_cost"])
	var nominal_restore: int = battle.action_restore_qi(actor, skill_id)
	var qi_after: int = mini(int(unit["max_qi"]), qi_before - qi_cost + nominal_restore)
	var actual_restore: int = qi_after - (qi_before - qi_cost)
	var result := {"ok": true, "reason": "", "revision": battle.revision, "actor": actor, "skill_id": skill_id, "target": target, "hits": hits, "affected": affected, "qi_cost": qi_cost, "restore_qi": actual_restore, "qi_before": qi_before, "qi_after": qi_after, "cooldown_ready_round": battle.round_number + int(skill["cooldown_rounds"]) + 1 if skill["cooldown_rounds"] > 0 else 0, "destination": target if skill["range_pattern"] == "step" else origin, "effects": skill["effects"].duplicate()}
	if skill["area_pattern"] == "front_arc": result["area_cells"] = area
	return result


static func affected_cells(battle: RefCounted, actor: String, skill_id: String, target: Vector2i, origin := Vector2i(-1, -1)) -> Array[Vector2i]:
	# Pure geometry: the adjacent center names a direction, not a mandatory
	# victim. Side cells are diagonal-front; units do not block the sweep, walls
	# and board edges do. A wall at the center blocks the whole forward sweep.
	var result: Array[Vector2i] = []
	var unit: Dictionary = battle.unit(actor)
	var skill: Dictionary = battle.skill(skill_id)
	if unit.is_empty() or skill.is_empty(): return result
	if origin == Vector2i(-1, -1): origin = Grid.cell_of(unit)
	if not range_matches(battle, actor, skill, origin, target): return result
	if skill["area_pattern"] != "front_arc": return [target]
	var forward := target-origin
	var left := Vector2i(forward.y, -forward.x)
	for cell: Vector2i in [target, target+left, target-left]:
		if battle.contains(cell) and not battle.is_obstacle(cell): result.append(cell)
	return result


static func range_matches(battle: RefCounted, actor: String, skill: Dictionary, origin: Vector2i, target: Vector2i) -> bool:
	if not battle.contains(target) or battle.is_obstacle(target): return false
	var distance := Grid.distance(origin, target)
	match skill["range_pattern"]:
		"self": return target == origin
		"adjacent": return distance == 1
		"line": return distance >= 1 and distance <= skill["range"] and _line_clear(battle, actor, origin, target)
		"step": return target != origin and battle.is_free(target) and Grid.reachable(battle, actor, int(skill["range"]), origin, true).has(target)
	return false


static func _line_clear(battle: RefCounted, actor: String, origin: Vector2i, target: Vector2i) -> bool:
	# AI previews a move without mutating the live board. Its old cell becomes
	# empty after that move, but other units and walls must still block the ray.
	if origin == Grid.cell_of(battle.unit(actor)):
		return Grid.line_clear(battle, origin, target)
	if origin == target or (origin.x != target.x and origin.y != target.y): return false
	var direction := Vector2i(signi(target.x-origin.x), signi(target.y-origin.y))
	var cell := origin+direction
	while cell != target:
		var occupant: String = battle.unit_at(cell)
		if battle.is_obstacle(cell) or (not occupant.is_empty() and occupant != actor): return false
		cell += direction
	return battle.contains(target) and not battle.is_obstacle(target)


static func target_cells(battle: RefCounted, actor: String, skill_id: String) -> Array[Vector2i]:
	# Physical range ignores cooldown/qi/ultimate availability and enemy presence.
	# Execution still checks all of those in preview(); this never grants an action.
	var cells: Array[Vector2i] = []
	var unit: Dictionary = battle.unit(actor)
	var skill: Dictionary = battle.skill(skill_id)
	if unit.is_empty() or unit["hp"] <= 0 or skill.is_empty() or not skill_id in battle.abilities(actor): return cells
	var origin := Grid.cell_of(unit)
	if skill["range_pattern"] == "step":
		for cell: Vector2i in Grid.reachable(battle, actor, int(skill["range"]), origin, true):
			if cell != origin and battle.is_free(cell): cells.append(cell)
		return cells
	for y: int in range(battle.board_size.y):
		for x: int in range(battle.board_size.x):
			var cell := Vector2i(x,y)
			if range_matches(battle, actor, skill, origin, cell): cells.append(cell)
	return cells


static func unavailable(battle: RefCounted, actor: String, skill_id: String) -> String:
	var unit: Dictionary = battle.unit(actor)
	var skill: Dictionary = battle.skill(skill_id)
	if unit.is_empty() or skill.is_empty():
		return "未知单位／招式"
	if unit["qi"] < skill["qi_cost"]:
		return "内力不足：需要%d" % skill["qi_cost"]
	var available_round: int = int(unit["cooldowns"].get(skill_id, 0))
	if available_round > battle.round_number:
		return "冷却中：第%d轮可用" % available_round
	if skill["ultimate"]:
		if unit["ultimate_used"]:
			return "本战绝技已使用"
		var condition: Dictionary = unit["ultimate"]
		var progress: int = int(unit["damage_received"] if condition["kind"] == "damage_received" else unit["takedowns"])
		if progress < condition["threshold"]:
			return "%s %d/%d" % ["实际受伤" if condition["kind"] == "damage_received" else "击倒敌人", progress, condition["threshold"]]
	return ""


static func damage_preview(battle: RefCounted, actor: String, target: String, skill: Dictionary, distance: int) -> Dictionary:
	var attacker: Dictionary = battle.unit(actor)
	var receiver: String = target
	var defended: Dictionary = battle.unit(target)
	var supporter: String = str(defended["statuses"].get("support", {}).get("source", ""))
	var protector: Dictionary = battle.unit(supporter)
	if not protector.is_empty() and protector["hp"] > 0 and protector["team"] == defended["team"] and supporter != target and Grid.distance(Grid.cell_of(protector), Grid.cell_of(defended)) == 1:
		receiver = supporter
		defended = protector
	var armor: int = int(defended["guard"]) - (2 if defended["statuses"].has("broken") else 0)
	var damage: int = maxi(1, int(skill["power"]) + int(attacker["power"]) - armor)
	if distance == 2:
		damage += int(skill["distance_bonus"])
	if defended["statuses"].has("guard"):
		damage -= 2
	if receiver != target:
		damage -= 1
	damage = maxi(0, damage)
	return {"target": target, "receiver": receiver, "damage": damage, "actual": mini(int(defended["hp"]), damage), "redirected": receiver != target}
