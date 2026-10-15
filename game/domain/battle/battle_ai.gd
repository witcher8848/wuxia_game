class_name BattleAI
extends RefCounted
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")


static func intent(battle: RefCounted, actor: String, reveal_details := false, reveal_policy := false) -> Dictionary:
	var unit: Dictionary = battle.unit(actor)
	if unit.is_empty():
		return {}
	var profile := _profile(battle, actor)
	var label := str(profile.get("intent_label", ""))
	if unit.has("ai_profile") and profile.is_empty():
		label = "AI配置无效：无法执行"
	elif label.is_empty():
		label = "拉开距离，寻找直线射击" if _is_ranged(battle, actor) else "近身压迫，低血交替守势"
	var result := {"kind": label, "reachable": Grid.reachable(battle, actor, maxi(0, int(unit["move"]) - (2 if unit["statuses"].has("pin") else 0))).keys()}
	if reveal_policy and not profile.is_empty():
		var targets := _targets(battle, actor)
		var priority: String = _priority_target(unit, targets) if profile["target_priority"] == "configured" else (_nearest_target(battle, targets, Grid.cell_of(unit)) if profile["target_priority"] == "nearest" else "")
		# This is the policy's current preferred opponent, not a promised action
		# or destination. A changed board causes the policy to resolve it again.
		if not priority.is_empty(): result["priority_target"] = priority
	if reveal_details and actor == battle.current_actor_id():
		result["plan"] = plan(battle, actor)
	return result


static func plan(battle: RefCounted, actor: String, basic_only := false) -> Dictionary:
	if battle.outcome != "ongoing" or actor != battle.current_actor_id():
		return {}
	var unit: Dictionary = battle.unit(actor)
	if unit.is_empty() or unit["hp"] <= 0: return {}
	if unit.has("ai_profile"):
		var profile := _profile(battle, actor)
		# A malformed explicit profile is not an implicit melee profile. The
		# encounter's atomic validator must reject it before a battle begins.
		if profile.is_empty(): return {}
		return _profile_plan(battle, actor, profile, basic_only)
	return _legacy_plan(battle, actor, basic_only)


static func _legacy_plan(battle: RefCounted, actor: String, basic_only: bool) -> Dictionary:
	var unit: Dictionary = battle.unit(actor)
	var origin := Grid.cell_of(unit)
	var paths: Dictionary = battle.movement_paths(actor)
	if paths.is_empty():
		paths[origin] = [origin]
	var targets: Array[String] = []
	for identifier: String in battle.unit_ids():
		var other: Dictionary = battle.unit(identifier)
		if other["hp"] > 0 and other["team"] != unit["team"]:
			targets.append(identifier)
	var best: Dictionary = {}
	var best_score := -100000
	var ranged := _is_ranged(battle, actor)
	var attacks: Array = ["SK_FIST_BASIC"] if basic_only else battle.abilities(actor)
	for destination: Vector2i in paths:
		var nearest := 999
		for identifier: String in targets:
			nearest = mini(nearest, Grid.distance(destination, Grid.cell_of(battle.unit(identifier))))
		for skill_id: String in attacks:
			var skill: Dictionary = battle.skill(skill_id)
			if skill["target"] != "enemy":
				continue
			for identifier: String in targets:
				var target := Grid.cell_of(battle.unit(identifier))
				var preview: Dictionary = Actions.preview(battle, actor, skill_id, target, destination)
				if not preview["ok"]:
					continue
				var score := 1000 + int(preview["hits"][0]["actual"]) * 10 - int(skill["qi_cost"])
				for effect: String in skill["effects"]:
					if not battle.unit(identifier)["statuses"].has(effect): score += 12
				if ranged:
					score += mini(nearest, 4) * 15
				else:
					score -= nearest * 4
				score -= paths[destination].size() - 1
				if score > best_score:
					best_score = score
					best = {"destination": destination, "skill_id": skill_id, "target": target}
		# If attacks are blocked, approach; the archer seeks range when possible.
		var walk_score: int = -nearest * 10 - (paths[destination].size() - 1)
		if walk_score > best_score:
			best_score = walk_score
			best = {"destination": destination, "skill_id": "ACT_BREATH", "target": destination}
	if not ranged and unit["team"] == "enemy" and unit["hp"] <= 2 and unit["last_action"] != "SK_STICK_GUARD":
		best = {"destination": origin, "skill_id": "SK_STICK_GUARD", "target": origin}
	if best.is_empty():
		best = {"destination": origin, "skill_id": "ACT_BREATH", "target": origin}
	return best


static func _profile(battle: RefCounted, actor: String) -> Dictionary:
	if not battle.has_method("ai_profile"): return {}
	return battle.ai_profile(actor)


static func _is_ranged(battle: RefCounted, actor: String) -> bool:
	# Legacy compatibility is inferred from actual usable loadout metadata,
	# not the archetype's spelling. New content must bind an explicit profile.
	for identifier: String in battle.abilities(actor):
		var skill: Dictionary = battle.skill(identifier)
		if skill.get("target") == "enemy" and skill.get("range_pattern") == "line" and int(skill.get("range", 0)) >= 3:
			return true
	return false


static func _targets(battle: RefCounted, actor: String) -> Array[String]:
	var result: Array[String] = []
	var team: String = battle.unit(actor)["team"]
	for identifier: String in battle.unit_ids():
		var other: Dictionary = battle.unit(identifier)
		if other["hp"] > 0 and other["team"] != team: result.append(identifier)
	return result


static func _priority_target(unit: Dictionary, targets: Array[String]) -> String:
	for identifier: String in unit.get("ai_target_ids", []):
		if identifier in targets: return identifier
	return ""


static func _nearest_target(battle: RefCounted, targets: Array[String], origin: Vector2i) -> String:
	var result := ""
	var distance := 999
	for identifier: String in targets:
		var candidate := Grid.distance(origin, Grid.cell_of(battle.unit(identifier)))
		if candidate < distance:
			distance = candidate
			result = identifier
	return result


static func _attack_targets(battle: RefCounted, targets: Array[String], origin: Vector2i, skill: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if skill.get("area_pattern") == "front_arc":
		# The direction tile may be empty/friendly while enemies occupy a wing.
		for direction: Vector2i in Grid.DIRECTIONS:
			if battle.contains(origin+direction): result.append(origin+direction)
	else:
		for identifier: String in targets: result.append(Grid.cell_of(battle.unit(identifier)))
	return result


static func _approach_distances(battle: RefCounted, actor: String, target: String) -> Dictionary:
	# Reverse BFS to legal adjacent attack cells, not a Manhattan shortcut through
	# a wall. The actor's old cell is free in hypothetical movement; others block.
	var distances: Dictionary = {}
	var queue: Array[Vector2i] = []
	var target_cell := Grid.cell_of(battle.unit(target))
	for direction: Vector2i in Grid.DIRECTIONS:
		var cell := target_cell+direction
		if not battle.contains(cell) or battle.is_obstacle(cell): continue
		var occupant: String = battle.unit_at(cell)
		if not occupant.is_empty() and occupant != actor: continue
		distances[cell] = 0
		queue.append(cell)
	var index := 0
	while index < queue.size():
		var origin: Vector2i = queue[index]
		index += 1
		for direction: Vector2i in Grid.DIRECTIONS:
			var cell := origin+direction
			if distances.has(cell) or not battle.contains(cell) or battle.is_obstacle(cell): continue
			var occupant: String = battle.unit_at(cell)
			if not occupant.is_empty() and occupant != actor: continue
			distances[cell] = int(distances[origin])+1
			queue.append(cell)
	return distances


static func _profile_plan(battle: RefCounted, actor: String, profile: Dictionary, basic_only: bool) -> Dictionary:
	var unit: Dictionary = battle.unit(actor)
	var origin := Grid.cell_of(unit)
	var paths: Dictionary = battle.movement_paths(actor)
	if paths.is_empty(): paths[origin] = [origin]
	var targets := _targets(battle, actor)
	var preferred: String = _priority_target(unit, targets) if profile["target_priority"] == "configured" else ""
	if profile["target_priority"] == "nearest": preferred = _nearest_target(battle, targets, origin)
	var approach_maps: Dictionary = {}
	for identifier: String in targets: approach_maps[identifier] = _approach_distances(battle, actor, identifier)
	var attacks: Array = ["SK_FIST_BASIC"] if basic_only else battle.abilities(actor)
	var best: Dictionary = {}
	var best_score := -1000000
	for destination: Vector2i in paths:
		var nearest := 999
		for identifier: String in targets:
			nearest = mini(nearest, Grid.distance(destination, Grid.cell_of(battle.unit(identifier))))
		var move_cost: int = paths[destination].size() - 1
		for skill_id: String in attacks:
			var skill: Dictionary = battle.skill(skill_id)
			if skill.get("target") != "enemy": continue
			for target: Vector2i in _attack_targets(battle, targets, destination, skill):
				var preview: Dictionary = Actions.preview(battle, actor, skill_id, target, destination)
				if not preview["ok"]: continue
				var score := 10000 - int(skill["qi_cost"]) * 5 - move_cost
				var strikes_preferred := false
				for hit: Dictionary in preview["hits"]:
					var recipient: Dictionary = battle.unit(hit["receiver"])
					var intended: Dictionary = battle.unit(hit["target"])
					score += int(hit["actual"]) * 40
					if int(hit["actual"]) == int(recipient["hp"]): score += 1000
					if hit["target"] == preferred: strikes_preferred = true
					if profile["target_priority"] == "lowest_hp": score += maxi(0, 100 - int(intended["hp"])) * 3
					if profile["target_priority"] == "nearest": score -= Grid.distance(origin, Grid.cell_of(intended)) * 6
					for effect: String in skill["effects"]:
						var effect_rank: int = profile["effect_priority"].find(effect)
						if effect_rank < 0: continue
						var weight: int = profile["effect_priority"].size() - effect_rank
						# Each actual intercepted recipient is scored once. Never
						# spend qi only to renew a pin/break that is already active.
						score += (-180 if recipient["statuses"].has(effect) else 120) * weight
				if strikes_preferred: score += 20000
				var skill_rank: int = profile["skill_priority"].find(skill_id)
				if skill_rank >= 0: score += (profile["skill_priority"].size() - skill_rank) * 8
				if profile["style"] == "ranged":
					var low: int = profile["preferred_range"][0]
					var high: int = profile["preferred_range"][1]
					var separation_penalty := maxi(0, low - nearest) * 90 + maxi(0, nearest - high) * 10
					score += mini(nearest, high) * 15 - separation_penalty
				else:
					score -= Grid.distance(destination, target) * 4
				if score > best_score:
					best_score = score
					best = {"destination": destination, "skill_id": skill_id, "target": target}
		# Approach the policy's starting-position target. Measuring only after
		# hypothetical movement makes every reachable melee target equally near.
		var approach_distance := 999
		var walk_score := 0
		if not preferred.is_empty():
			approach_distance = int(approach_maps[preferred].get(destination,999))
			walk_score += 20000
		else:
			for identifier: String in targets: approach_distance = mini(approach_distance,int(approach_maps[identifier].get(destination,999)))
		walk_score -= approach_distance * 20 + move_cost
		if walk_score > best_score and Actions.preview(battle, actor, "ACT_BREATH", destination, destination)["ok"]:
			best_score = walk_score
			best = {"destination": destination, "skill_id": "ACT_BREATH", "target": destination}
	if not basic_only and unit["team"] == "enemy" and int(profile["low_hp_guard_threshold"]) > 0 and unit["hp"] <= profile["low_hp_guard_threshold"] and unit["last_action"] != "SK_STICK_GUARD" and Actions.preview(battle, actor, "SK_STICK_GUARD", origin)["ok"]:
		# The next real turn must attack/approach/breathe rather than guard
		# again. No persistent hidden counter and no permanent low-HP loop.
		best = {"destination": origin, "skill_id": "SK_STICK_GUARD", "target": origin}
	if best.is_empty() and Actions.preview(battle, actor, "ACT_BREATH", origin)["ok"]:
		best = {"destination": origin, "skill_id": "ACT_BREATH", "target": origin}
	return best


static func take_turn(battle: RefCounted) -> Dictionary:
	var actor: String = battle.current_actor_id()
	if actor.is_empty() or battle.unit(actor)["team"] != "enemy":
		return {"ok": false, "reason": "不是敌方回合"}
	var next: Dictionary = plan(battle, actor)
	if next.is_empty():
		return {"ok": false, "reason": "没有合法回合"}
	if next["destination"] != Grid.cell_of(battle.unit(actor)):
		var movement: Dictionary = battle.move_actor(actor, next["destination"], battle.revision)
		if not movement["ok"]:
			return movement
	return battle.perform_action(actor, next["skill_id"], next["target"], battle.revision)
