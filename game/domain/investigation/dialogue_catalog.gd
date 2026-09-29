class_name DialogueCatalog
extends RefCounted
## Finite data-only dialogue graph. Reading choices never commits effects.

var _data: Dictionary = {}
var _nodes: Dictionary = {}
var _rules: InvestigationRules

func configure(data: Dictionary, rules: InvestigationRules, text_keys: Dictionary, interactions: Array) -> String:
	if not GameState.is_json_value(data) or data.size() != 2 or not data.get("nodes") is Array or not data.get("entries") is Dictionary or data["nodes"].is_empty():
		return "Dialogue requires finite nodes and entries."
	var nodes: Dictionary = {}
	var steps: Dictionary = {}
	for step: Dictionary in rules.definitions().get("steps", []):
		steps[step["id"]] = true
		if not _text(step["feedback_key"], text_keys):
			return "Missing investigation feedback translation."
		for effect: Dictionary in step["effects"]:
			if effect["op"] == "set_quest" and not effect["reason_key"].is_empty() and not _text(effect["reason_key"], text_keys):
				return "Missing changed-quest reason translation."
	for evidence: Dictionary in rules.definitions().get("evidence", []):
		if not _text(evidence["title_key"], text_keys) or not _text(evidence["description_key"], text_keys):
			return "Missing evidence translation."
	for quest: Dictionary in rules.definitions().get("quests", []):
		if not _text(quest["title_key"], text_keys):
			return "Missing quest translation."
	for node: Variant in data["nodes"]:
		if not node is Dictionary or not _id(node.get("id")) or nodes.has(node["id"]):
			return "Duplicate or invalid dialogue node."
		if not _text(node.get("speaker_key"), text_keys) or not _text(node.get("text_key"), text_keys):
			return "Dialogue speaker/text must exist in both locales."
		if not node.get("choices") is Array or node["choices"].size() < 2 or node["choices"].size() > 4:
			return "Dialogue requires two to four choices."
		var choice_ids: Dictionary = {}
		for choice: Variant in node["choices"]:
			if not choice is Dictionary or not _id(choice.get("id")) or choice_ids.has(choice["id"]):
				return "Duplicate or invalid choice."
			choice_ids[choice["id"]] = true
			if not _text(choice.get("text_key"), text_keys) or not choice.get("next") is String or not choice.get("command") is String:
				return "Choice requires text, next and registered command."
			if not choice["command"].is_empty() and not steps.has(choice["command"]):
				return "Unknown dialogue command."
			if not _conditions(choice.get("requires"), rules):
				return "Invalid choice condition."
			# No scripts, effects or property paths can hide beside a legal command.
			if choice.size() != 5:
				return "Unexpected choice field."
		if node.size() != 4:
			return "Unexpected node field."
		nodes[node["id"]] = node.duplicate(true)
	for node: Dictionary in nodes.values():
		for choice: Dictionary in node["choices"]:
			if not choice["next"] in ["", "@entry"] and not nodes.has(choice["next"]):
				return "Broken dialogue link."
	for target: Variant in data["entries"]:
		if not target in interactions or not data["entries"][target] is Array or data["entries"][target].is_empty():
			return "Unknown interaction or empty entry routes."
		var routes: Array = data["entries"][target]
		for index: int in routes.size():
			var route: Variant = routes[index]
			if not route is Dictionary or route.size() != 2 or not route.get("node") is String or not nodes.has(route["node"]) or not _conditions(route.get("requires"), rules):
				return "Invalid entry route."
			if route["requires"].is_empty() != (index == routes.size() - 1):
				return "Only the last entry route must be unconditional."
	var pending: Array[String] = []
	for routes: Array in data["entries"].values():
		for route: Dictionary in routes:
			pending.append(route["node"])
	var reachable: Dictionary = {}
	while not pending.is_empty():
		var identifier: String = pending.pop_back()
		if reachable.has(identifier):
			continue
		reachable[identifier] = true
		for choice: Dictionary in nodes[identifier]["choices"]:
			if nodes.has(choice["next"]):
				pending.append(choice["next"])
	if reachable.size() != nodes.size():
		return "Unreachable dialogue node."
	_data = data.duplicate(true)
	_nodes = nodes
	_rules = rules
	return ""

func definitions() -> Dictionary:
	return _data.duplicate(true)

func entry(target: String, state: GameState) -> String:
	for route: Dictionary in _data.get("entries", {}).get(target, []):
		if _matches(route["requires"], state):
			return route["node"]
	return ""

func node_view(identifier: String, state: GameState) -> Dictionary:
	if not _nodes.has(identifier) or not _rules.validate_state(state).is_empty():
		return {}
	var view: Dictionary = _nodes[identifier].duplicate(true)
	for choice: Dictionary in view["choices"]:
		choice["enabled"] = _matches(choice["requires"], state)
		choice["reason"] = "INV_REQUIREMENTS"
		if not choice["command"].is_empty():
			var proposal: Dictionary = _rules.prepare_step(state, choice["command"])
			choice["enabled"] = choice["enabled"] and proposal["error"] == OK
			if proposal["error"] == ERR_ALREADY_EXISTS:
				choice["reason"] = "INV_ALREADY_RECORDED"
	return view

func _matches(conditions: Array, state: GameState) -> bool:
	for condition: Dictionary in conditions:
		if not _rules.condition_matches(state, condition):
			return false
	return true

static func _conditions(value: Variant, rules: InvestigationRules) -> bool:
	if not value is Array:
		return false
	for condition: Variant in value:
		if not rules.valid_condition(condition):
			return false
	return true

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.is_valid_identifier()

static func _text(value: Variant, keys: Dictionary) -> bool:
	return _id(value) and keys.has(value)
