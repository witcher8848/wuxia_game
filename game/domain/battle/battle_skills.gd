class_name BattleSkills
extends RefCounted
const BASE := ["SK_FIST_BASIC", "SK_STICK_GUARD", "ACT_BREATH"]
const STATUSES := ["guard", "broken", "pin", "bleed", "support"]
const CATEGORIES := ["外功", "身法", "内功", "辅助", "敌方", "绝技"]


static func validate(data: Variant) -> String:
	if not data is Array or data.is_empty() or not GameState.is_json_value(data):
		return "Skills must be a finite JSON array."
	var ids: Dictionary = {}
	for skill: Variant in data:
		if not skill is Dictionary or not skill.get("id") is String or not skill["id"].is_valid_identifier() or ids.has(skill["id"]):
			return "Invalid or duplicate skill ID."
		for field: String in ["name", "category", "weapon_tag", "mastery_stage", "presentation_key"]:
			if not skill.get(field) is String or skill[field].is_empty():
				return "Missing skill text: " + field
		if not skill["category"] in CATEGORIES or not skill["mastery_stage"] in ["识招", "熟练", "化用"]:
			return "Unknown skill category or mastery stage."
		if not skill.get("range_pattern") in ["adjacent", "line", "self", "step"] or not skill.get("area_pattern") in ["single", "adjacent_allies", "front_arc"] or not skill.get("target") in ["enemy", "self", "empty"]:
			return "Invalid skill range/target."
		for field: String in ["range", "power", "qi_cost", "cooldown_rounds", "restore_qi", "distance_bonus"]:
			if not BattleState._whole(skill.get(field)) or skill[field] < 0 or skill[field] > 32:
				return "Invalid skill number: " + field
		if not skill.get("ultimate") is bool or not skill.get("effects") is Array or not skill.get("narrative_tags") is Array:
			return "Invalid skill effects or metadata."
		for status: Variant in skill["effects"]:
			if not status in STATUSES:
				return "Unknown status."
		if skill.has("broken_mode") and (not skill["broken_mode"] is String or skill["broken_mode"] != "next_hit" or not "broken" in skill["effects"]):
			return "Next-hit broken mode requires the broken effect."
		if skill["category"] == "内功":
			if skill["ultimate"] or skill["range_pattern"] != "self" or skill["area_pattern"] != "single" or skill["target"] != "self" or skill["range"] != 0 or not skill["effects"].is_empty():
				return "Internal arts must be passive self definitions."
			for field: String in ["power", "qi_cost", "cooldown_rounds", "restore_qi", "distance_bonus"]:
				if skill[field] != 0: return "Internal arts cannot perform active effects."
			var rules: Variant = skill.get("passive_rules")
			if not rules is Dictionary or rules.size() != 3:
				return "Missing internal passive rules."
			for field: String in ["max_qi", "basic_restore_qi", "breath_restore_qi"]:
				if not BattleState._whole(rules.get(field)) or rules[field] < 0 or rules[field] > 32:
					return "Invalid internal passive rule: " + field
			if rules["max_qi"] < 1: return "Internal qi capacity must be positive."
		elif skill.has("passive_rules"):
			return "Only internal arts define passive rules."
		if skill["ultimate"] != (skill["category"] == "绝技"):
			return "Ultimate category and action flag disagree."
		var pattern: String = skill["range_pattern"]
		if (pattern == "self" and (skill["target"] != "self" or skill["range"] != 0)) or (pattern == "step" and skill["target"] != "empty") or (pattern in ["adjacent", "line"] and (skill["target"] != "enemy" or skill["range"] < 1)):
			return "Inconsistent range and target."
		if pattern == "adjacent" and skill["range"] != 1:
			return "Adjacent attacks have range one."
		if skill["area_pattern"] == "adjacent_allies" and pattern != "self":
			return "Area support must originate at self."
		if skill["area_pattern"] == "front_arc" and (pattern != "adjacent" or skill["target"] != "enemy"):
			return "Front arc requires an adjacent enemy attack."
		# There is no unrestricted pass command. At zero qi, with every route
		# blocked or no enemy in range, both the player and AI must still have
		# an active self action that can finish the turn. Recovery and effects
		# remain authored balance data, including W6's guard-free breath.
		if skill["id"] == "ACT_BREATH" and (skill["category"] == "内功" or skill["ultimate"] or pattern != "self" or skill["target"] != "self" or skill["area_pattern"] != "single" or skill["qi_cost"] != 0 or skill["cooldown_rounds"] != 0):
			return "Breath must remain a free, cooldown-free active self fallback."
		ids[skill["id"]] = true
	for identifier: String in BASE:
		if not ids.has(identifier):
			return "Missing basic action: " + identifier
	return ""


static func index(data: Array) -> Dictionary:
	var result: Dictionary = {}
	for skill: Dictionary in data:
		result[skill["id"]] = skill.duplicate(true)
	return result
