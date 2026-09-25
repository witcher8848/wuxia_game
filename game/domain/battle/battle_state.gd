class_name BattleState
extends RefCounted
## Transient battle authority. No scene nodes, global session or save I/O.
## Day 15: validated board and turn order only; commands arrive in later tasks.

const MAX_ALLIES := 4
const MAX_ENEMIES := 5
var board_size := Vector2i.ZERO
var round_number := 0
var _blocked: Dictionary = {}
var _units: Dictionary = {}
var _order: Array[String] = []
var _pending: Array[String] = []


func configure(definition: Dictionary) -> String:
	# Validate into locals, then swap atomically. Reject rather than coerce strings,
	# fractions, duplicate IDs, illegal cells or malformed team/attribute values.
	var extent: Variant = definition.get("size")
	if not _pair(extent) or extent[0] < 1 or extent[1] < 1 or extent[0] > 32 or extent[1] > 32:
		return "Invalid board size."
	var size_candidate := Vector2i(int(extent[0]), int(extent[1]))
	if not definition.get("blocked") is Array or not definition.get("units") is Array:
		return "Missing board arrays."
	var blocked_candidate: Dictionary = {}
	for value: Variant in definition["blocked"]:
		if not _pair(value):
			return "Invalid obstacle."
		var cell := Vector2i(int(value[0]), int(value[1]))
		if not _inside(cell, size_candidate) or blocked_candidate.has(cell):
			return "Duplicate or outside obstacle."
		blocked_candidate[cell] = true
	var units_candidate: Dictionary = {}
	var occupied: Dictionary = {}
	var order_candidate: Array[String] = []
	var counts := {"ally": 0, "enemy": 0}
	for value: Variant in definition["units"]:
		if not value is Dictionary:
			return "Invalid unit record."
		var identifier: Variant = value.get("id")
		if not identifier is String or not identifier.is_valid_identifier() or units_candidate.has(identifier):
			return "Invalid or duplicate unit ID."
		if not value.get("team") is String or not counts.has(value["team"]):
			return "Invalid team."
		if not value.get("name") is String or value["name"].is_empty():
			return "Missing display name."
		if not value.get("archetype") is String or not value["archetype"].is_valid_identifier():
			return "Missing archetype ID."
		if not _pair(value.get("cell")):
			return "Invalid unit cell."
		var cell := Vector2i(int(value["cell"][0]), int(value["cell"][1]))
		if not _inside(cell, size_candidate) or blocked_candidate.has(cell) or occupied.has(cell):
			return "Unit overlaps obstacle/unit or leaves board."
		for field: String in ["hp", "max_hp", "qi", "max_qi", "agility", "move", "power", "guard"]:
			if not _whole(value.get(field)) or float(value[field]) < 0 or float(value[field]) > 999:
				return "Invalid unit attribute: " + field
		if value["max_hp"] < 1 or value["hp"] > value["max_hp"] or value["qi"] > value["max_qi"]:
			return "Invalid resource limits."
		counts[value["team"]] += 1
		if counts["ally"] > MAX_ALLIES or counts["enemy"] > MAX_ENEMIES:
			return "Team capacity exceeded."
		occupied[cell] = identifier
		units_candidate[identifier] = value.duplicate(true)
		order_candidate.append(identifier)
	if units_candidate.is_empty():
		return "Battle needs units."
	board_size = size_candidate
	_blocked = blocked_candidate
	_units = units_candidate
	_order = order_candidate
	_pending.clear()
	round_number = 0
	_begin_round()
	return ""


func contains(cell: Vector2i) -> bool:
	return _inside(cell, board_size)


func is_obstacle(cell: Vector2i) -> bool:
	return _blocked.has(cell)


func unit_at(cell: Vector2i) -> String:
	for identifier: String in _order:
		var unit: Dictionary = _units[identifier]
		if int(unit["hp"]) > 0 and Vector2i(unit["cell"][0], unit["cell"][1]) == cell:
			return identifier
	return ""


func is_free(cell: Vector2i) -> bool:
	return contains(cell) and not is_obstacle(cell) and unit_at(cell).is_empty()


func unit(identifier: String) -> Dictionary:
	return _units.get(identifier, {}).duplicate(true)


func unit_ids() -> Array[String]:
	return _order.duplicate()


func pending_ids() -> Array[String]:
	return _pending.duplicate()


func current_actor_id() -> String:
	return "" if _pending.is_empty() else _pending[0]


func finish_turn(expected_actor: String) -> bool:
	if expected_actor.is_empty() or current_actor_id() != expected_actor:
		return false
	_pending.pop_front()
	if _pending.is_empty():
		_begin_round()
	return true


func mark_defeated(identifier: String) -> bool:
	if not _units.has(identifier) or int(_units[identifier]["hp"]) == 0:
		return false
	_units[identifier]["hp"] = 0
	_pending.erase(identifier)
	if _pending.is_empty():
		_begin_round()
	return true


func set_agility(identifier: String, value: int) -> bool:
	if not _units.has(identifier) or value < 0 or value > 999:
		return false
	_units[identifier]["agility"] = value
	# Initiative changes apply next round, never granting a second current turn.
	return true


func _begin_round() -> void:
	var previous: Dictionary = {}
	for index: int in range(_order.size()):
		previous[_order[index]] = index
	_order.sort_custom(func(a: String, b: String) -> bool:
		var left: int = int(_units[a]["agility"])
		var right: int = int(_units[b]["agility"])
		return left > right if left != right else previous[a] < previous[b])
	_pending.clear()
	for identifier: String in _order:
		if int(_units[identifier]["hp"]) > 0:
			_pending.append(identifier)
	if not _pending.is_empty():
		round_number += 1


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value)


static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1])


static func _inside(cell: Vector2i, extent: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < extent.x and cell.y < extent.y
