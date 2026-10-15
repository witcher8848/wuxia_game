class_name BattleEffects
extends RefCounted
## Internal reducer; only CombatEncounter commands call these mutations.


static func hurt(battle: RefCounted, source: String, receiver: String, amount: int, label: String) -> void:
	var target: Dictionary = battle._units[receiver]
	var actual := mini(int(target["hp"]), maxi(0, amount))
	if actual == 0:
		battle.events.append("%s：伤害0" % target["name"])
		return
	target["hp"] -= actual
	if battle._units.has(source) and battle._units[source]["team"] != target["team"]:
		target["damage_received"] += actual
		if target["hp"] == 0:
			battle._units[source]["takedowns"] += 1
	battle.events.append("%s → %s -%d%s" % [label, target["name"], actual, "（倒地）" if target["hp"] == 0 else ""])
	if target["hp"] == 0:
		battle._pending.erase(receiver)


static func execute(battle: RefCounted, plan: Dictionary) -> void:
	var actor: String = plan["actor"]
	var unit: Dictionary = battle._units[actor]
	var skill: Dictionary = battle.skill(plan["skill_id"])
	unit["qi"] = plan["qi_after"]
	if skill["cooldown_rounds"] > 0:
		unit["cooldowns"][skill["id"]] = battle.round_number + int(skill["cooldown_rounds"]) + 1
	if skill["ultimate"]:
		unit["ultimate_used"] = true
	unit["last_action"] = skill["id"]
	battle.events.append("%s：%s" % [unit["name"], skill["name"]])
	if skill["range_pattern"] == "step":
		unit["cell"] = [plan["target"].x, plan["target"].y]
	for hit: Dictionary in plan["hits"]:
		if hit["redirected"]:
			battle._units[hit["target"]]["statuses"].erase("support")
		battle._units[hit["receiver"]]["statuses"].erase("guard")
		var old_broken: Dictionary = battle._units[hit["receiver"]]["statuses"].get("broken", {})
		if old_broken.get("mode", "") == "next_hit":
			battle._units[hit["receiver"]]["statuses"].erase("broken")
		hurt(battle, actor, hit["receiver"], hit["damage"], skill["name"])
		# Debuffs follow the actual recipient of an intercepted strike.
		apply_statuses(battle, actor, hit["receiver"], skill["effects"], str(skill.get("broken_mode", "")))
	if plan["hits"].is_empty():
		for recipient: String in plan["affected"]:
			apply_statuses(battle, actor, recipient, skill["effects"], str(skill.get("broken_mode", "")))


static func apply_statuses(battle: RefCounted, source: String, recipient: String, effects: Array, broken_mode := "") -> void:
	var unit: Dictionary = battle._units[recipient]
	if unit["hp"] <= 0:
		return
	for status: String in effects:
		if status == "support" and source == recipient:
			continue
		if status == "guard" and source != recipient:
			continue
		unit["statuses"][status] = {"source": source, "remaining": 2 if status == "bleed" else 1, "expires_round": battle.round_number + 1}
		if status == "broken" and broken_mode == "next_hit":
			unit["statuses"][status]["mode"] = "next_hit"
			unit["statuses"][status]["expires_round"] = battle.round_number + 2


static func start_turn(battle: RefCounted) -> void:
	var actor: String = battle.current_actor_id()
	if actor.is_empty():
		return
	var unit: Dictionary = battle._units[actor]
	unit["statuses"].erase("guard")
	battle.moved = false
	battle.move_spent = 0
	battle.move_budget = maxi(0, int(unit["move"]) - (2 if unit["statuses"].has("pin") else 0))


static func end_turn(battle: RefCounted, actor: String) -> void:
	var unit: Dictionary = battle._units[actor]
	var statuses: Dictionary = unit["statuses"]
	if unit["hp"] > 0 and statuses.has("bleed"):
		var bleed: Dictionary = statuses["bleed"]
		hurt(battle, bleed["source"], actor, 1, "流血")
		bleed["remaining"] -= 1
		if bleed["remaining"] == 0:
			statuses.erase("bleed")
	if statuses.get("broken", {}).get("mode", "") != "next_hit": statuses.erase("broken")
	statuses.erase("pin")


static func begin_round(battle: RefCounted) -> void:
	for unit: Dictionary in battle._units.values():
		var statuses: Dictionary = unit["statuses"]
		if statuses.has("support") and statuses["support"]["expires_round"] <= battle.round_number:
			statuses.erase("support")
		if statuses.get("broken", {}).get("mode", "") == "next_hit" and statuses["broken"]["expires_round"] <= battle.round_number:
			statuses.erase("broken")
