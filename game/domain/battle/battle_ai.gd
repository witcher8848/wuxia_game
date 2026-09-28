class_name BattleAI
extends RefCounted
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")


static func intent(battle: RefCounted, actor: String, reveal_details := false) -> Dictionary:
	var unit: Dictionary = battle.unit(actor)
	if unit.is_empty():
		return {}
	var ranged: bool = unit["archetype"] == "EN_YAMEN_BOW"
	var result := {"kind": "拉开距离，寻找直线射击" if ranged else "近身压迫，低血交替守势", "reachable": Grid.reachable(battle, actor, maxi(0, int(unit["move"]) - (2 if unit["statuses"].has("pin") else 0))).keys()}
	if reveal_details and actor == battle.current_actor_id():
		result["plan"] = plan(battle, actor)
	return result


static func plan(battle: RefCounted, actor: String, basic_only := false) -> Dictionary:
	if battle.outcome != "ongoing" or actor != battle.current_actor_id():
		return {}
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
	var ranged: bool = unit["archetype"] == "EN_YAMEN_BOW"
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
