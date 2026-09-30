class_name CombatEncounter
extends BattleState
## Single transient combat authority. UI/AI submit revision-checked commands.
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
var revision := 0
var outcome := "ongoing"
var objective: Dictionary = {}
var moved := false
var move_spent := 0
var move_budget := 0
var events: Array[String] = []
var _skills: Dictionary = {}
var _initial: Dictionary = {}


func configure(definition: Dictionary) -> String:
	if not GameState.is_json_value(definition):
		return "Combat definition must be finite JSON."
	var probe := BattleState.new()
	var error := probe.configure(definition)
	if not error.is_empty():
		return error
	error = Skills.validate(definition.get("skill_definitions"))
	if not error.is_empty():
		return error
	var indexed: Dictionary = Skills.index(definition["skill_definitions"])
	for unit_data: Dictionary in definition["units"]:
		if not unit_data.get("skills") is Array:
			return "Unit needs skill loadout."
		var unique: Dictionary = {}
		for identifier: Variant in unit_data["skills"]:
			if not identifier is String or not indexed.has(identifier) or indexed[identifier]["ultimate"] or unique.has(identifier):
				return "Invalid skill loadout."
			unique[identifier] = true
		var ultimate: Variant = unit_data.get("ultimate")
		if not ultimate is Dictionary or not ultimate.get("skill_id") is String or not indexed.has(ultimate["skill_id"]) or not indexed[ultimate["skill_id"]]["ultimate"]:
			return "Unit needs a registered ultimate."
		if not ultimate.get("kind") in ["damage_received", "takedowns"] or not BattleState._whole(ultimate.get("threshold")) or ultimate["threshold"] < 1 or ultimate["threshold"] > 999:
			return "Invalid ultimate requirement."
	var goal: Variant = definition.get("objective")
	if not goal is Dictionary or not goal.get("kind") in ["eliminate", "escape"]:
		return "Unsupported prototype objective."
	if goal["kind"] == "escape":
		if not goal.get("unit_id") is String or probe.unit(goal["unit_id"]).get("team", "") != "ally" or not BattleState._pair(goal.get("cell")):
			return "Invalid escaping unit or cell."
		var cell := Vector2i(goal["cell"][0], goal["cell"][1])
		if not probe.contains(cell) or probe.is_obstacle(cell):
			return "Escape cell must be walkable."
	var teams := {"ally": false, "enemy": false}
	for identifier: String in probe.unit_ids():
		if probe.unit(identifier)["hp"] > 0:
			teams[probe.unit(identifier)["team"]] = true
	if not teams["ally"] or not teams["enemy"]:
		return "Encounter requires two live sides."
	# All checks complete before replacing the live encounter.
	super.configure(definition)
	_skills = indexed
	objective = goal.duplicate(true)
	outcome = "ongoing"
	events.clear()
	for unit_data: Dictionary in _units.values():
		unit_data["statuses"] = {}
		unit_data["cooldowns"] = {}
		unit_data["damage_received"] = 0
		unit_data["takedowns"] = 0
		unit_data["ultimate_used"] = false
		unit_data["last_action"] = ""
	revision += 1
	Effects.start_turn(self)
	_check_outcome()
	_initial = snapshot()
	return ""


func skill(identifier: String) -> Dictionary:
	return _skills.get(identifier, {}).duplicate(true)


func abilities(actor: String) -> Array[String]:
	var result: Array[String] = []
	if not _units.has(actor):
		return result
	for identifier: String in Skills.BASE + _units[actor]["skills"] + [_units[actor]["ultimate"]["skill_id"]]:
		if not identifier in result:
			result.append(identifier)
	return result


func movement_paths(actor: String) -> Dictionary:
	if actor != current_actor_id() or outcome != "ongoing" or moved:
		return {}
	return Grid.reachable(self, actor, move_budget)


func preview_move(actor: String, destination: Vector2i) -> Dictionary:
	var paths := movement_paths(actor)
	if not paths.has(destination):
		return {"ok": false, "reason": "无法移动至该格／本回合已移动", "revision": revision}
	return {"ok": true, "path": paths[destination].duplicate(), "cost": paths[destination].size() - 1, "revision": revision}


func move_actor(actor: String, destination: Vector2i, expected_revision: int) -> Dictionary:
	if expected_revision != revision:
		return _denied("移动预览已过期")
	var preview := preview_move(actor, destination)
	if not preview["ok"]:
		return preview
	_units[actor]["cell"] = [destination.x, destination.y]
	moved = true
	move_spent = preview["cost"]
	revision += 1
	events.append("%s 移动%d格" % [_units[actor]["name"], move_spent])
	_check_outcome()
	return {"ok": true, "cost": move_spent}


func preview_action(actor: String, skill_id: String, target: Vector2i) -> Dictionary:
	return Actions.preview(self, actor, skill_id, target)


func perform_action(actor: String, skill_id: String, target: Vector2i, expected_revision: int) -> Dictionary:
	if expected_revision != revision:
		return _denied("行动预览已过期")
	var plan := preview_action(actor, skill_id, target)
	if not plan["ok"]:
		return plan
	Effects.execute(self, plan)
	Effects.end_turn(self, actor)
	_pending.erase(actor)
	revision += 1
	_check_outcome()
	if outcome == "ongoing":
		if _pending.is_empty():
			_begin_round()
			Effects.begin_round(self)
		Effects.start_turn(self)
	return {"ok": true, "plan": plan, "outcome": outcome}


func finish_turn(_expected_actor: String) -> bool:
	# A player cannot bypass the one-action reducer; use guard/breath to pass.
	return false


func _check_outcome() -> void:
	var live := {"ally": 0, "enemy": 0}
	for unit_data: Dictionary in _units.values():
		if unit_data["hp"] > 0:
			live[unit_data["team"]] += 1
	if live["ally"] == 0:
		outcome = "defeat"
	elif objective["kind"] == "escape" and _units[objective["unit_id"]]["hp"] == 0:
		outcome = "defeat"
	elif objective["kind"] == "escape" and Grid.cell_of(_units[objective["unit_id"]]) == Vector2i(objective["cell"][0], objective["cell"][1]):
		outcome = "victory"
	elif objective["kind"] == "eliminate" and live["enemy"] == 0:
		outcome = "victory"
	# In escape mode defeating enemies is not the objective; movement continues.
	if outcome != "ongoing":
		_pending.clear()


func result() -> Dictionary:
	return {"outcome": outcome, "objective": objective.duplicate(true), "rounds": round_number, "units": _units.duplicate(true)}


func snapshot() -> Dictionary:
	return {"size": board_size, "blocked": _blocked.duplicate(), "units": _units.duplicate(true), "order": _order.duplicate(), "pending": _pending.duplicate(), "round": round_number, "objective": objective.duplicate(true), "outcome": outcome, "moved": moved, "move_spent": move_spent, "move_budget": move_budget, "revision": revision, "events": events.duplicate()}


func retry() -> bool:
	if _initial.is_empty():
		return false
	var data := _initial.duplicate(true)
	board_size = data["size"]
	_blocked = data["blocked"]
	_units = data["units"]
	_order.assign(data["order"])
	_pending.assign(data["pending"])
	round_number = data["round"]
	objective = data["objective"]
	outcome = data["outcome"]
	moved = data["moved"]
	move_spent = data["move_spent"]
	move_budget = data["move_budget"]
	events.assign(data["events"])
	revision += 1 # Invalidate previews from the discarded attempt.
	return true


func forecast_turn(actor: String) -> CombatEncounter:
	# A disposable copy at today's positions, not a prediction of intervening
	# allies' actions. Never reorder, move or spend resources on the live battle.
	if outcome != "ongoing" or not actor in _pending: return null
	var forecast := CombatEncounter.new()
	forecast.board_size = board_size
	forecast._blocked = _blocked.duplicate()
	forecast._units = _units.duplicate(true)
	forecast._order.assign(_order)
	forecast._pending.assign(_pending)
	forecast.round_number = round_number
	forecast.objective = objective.duplicate(true)
	forecast._skills = _skills.duplicate(true)
	forecast.revision = revision
	forecast.events.assign(events)
	forecast.moved = moved
	forecast.move_spent = move_spent
	forecast.move_budget = move_budget
	if actor != current_actor_id():
		forecast._pending.erase(actor)
		forecast._pending.push_front(actor)
		Effects.start_turn(forecast)
	return forecast


static func _denied(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
