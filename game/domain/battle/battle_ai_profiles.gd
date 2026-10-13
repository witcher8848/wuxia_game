class_name BattleAIProfiles
extends RefCounted
## Pure configuration boundary. No scene, save, investigation or RNG access.
const State = preload("res://game/domain/battle/battle_state.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const FIELDS := ["style", "intent_label", "target_priority", "preferred_range", "skill_priority", "effect_priority", "low_hp_guard_threshold"]


static func validate(value: Variant, indexed_skills: Dictionary, units: Array) -> String:
	if not value is Dictionary or not GameState.is_json_value(value):
		return "AI profiles must be a finite JSON dictionary."
	for identifier: Variant in value:
		if not identifier is String or not identifier.is_valid_identifier():
			return "Invalid AI profile ID."
		var profile: Variant = value[identifier]
		if not profile is Dictionary or profile.size() != FIELDS.size():
			return "AI profile needs the supported fields: " + identifier
		for field: String in FIELDS:
			if not profile.has(field): return "Missing AI profile field: " + field
		if not profile["style"] in ["pressure", "ranged", "capture"]:
			return "Unknown AI style."
		if not profile["intent_label"] is String or profile["intent_label"].strip_edges().is_empty() or profile["intent_label"].length() > 120:
			return "Invalid AI intent label."
		if not profile["target_priority"] in ["nearest", "lowest_hp", "configured"]:
			return "Unknown AI target priority."
		if not State._pair(profile["preferred_range"]) or profile["preferred_range"][0] < 1 or profile["preferred_range"][1] > 32 or profile["preferred_range"][0] > profile["preferred_range"][1]:
			return "Invalid AI preferred range."
		if not State._whole(profile["low_hp_guard_threshold"]) or profile["low_hp_guard_threshold"] < 0 or profile["low_hp_guard_threshold"] > 999:
			return "Invalid AI low HP guard threshold."
		if not profile["skill_priority"] is Array or profile["skill_priority"].is_empty():
			return "AI needs skill priorities."
		var seen: Dictionary = {}
		for skill_id: Variant in profile["skill_priority"]:
			if not skill_id is String or not indexed_skills.has(skill_id) or seen.has(skill_id):
				return "Invalid AI skill priority."
			if not indexed_skills[skill_id] is Dictionary: return "AI validation requires indexed skill dictionaries."
			var skill: Dictionary = indexed_skills[skill_id]
			if skill.get("target") != "enemy": return "AI attack priority must target an enemy."
			seen[skill_id] = true
		if not profile["effect_priority"] is Array:
			return "AI effects must be an array."
		seen.clear()
		for effect: Variant in profile["effect_priority"]:
			if not effect is String or not effect in Skills.STATUSES or effect in ["guard", "support"] or seen.has(effect):
				return "Invalid AI offensive effect priority."
			seen[effect] = true
	var indexed_units: Dictionary = {}
	for unit: Variant in units:
		if not unit is Dictionary or not unit.get("id") is String or indexed_units.has(unit["id"]) or not unit.get("team") in ["ally", "enemy"]:
			return "AI validation needs unique units with legal teams."
		indexed_units[unit["id"]] = unit
	for unit: Dictionary in units:
		if not unit.has("ai_profile"):
			if unit.has("ai_target_ids"): return "AI targets require an explicit profile."
			continue
		if not unit["ai_profile"] is String or not value.has(unit["ai_profile"]):
			return "Unknown unit AI profile."
		if unit["team"] != "enemy": return "Only enemies may bind AI profiles."
		var profile: Dictionary = value[unit["ai_profile"]]
		if not unit.get("skills") is Array or not unit.get("ultimate") is Dictionary:
			return "AI unit needs a validated skill loadout."
		var available: Array = Skills.BASE + unit["skills"] + [unit["ultimate"].get("skill_id", "")]
		for skill_id: String in profile["skill_priority"]:
			if not skill_id in available: return "AI priority references a skill outside the unit loadout."
		var targets: Variant = unit.get("ai_target_ids", [])
		if not targets is Array or (profile["target_priority"] == "configured" and targets.is_empty()):
			return "Configured AI requires target IDs."
		var seen: Dictionary = {}
		for target_id: Variant in targets:
			if not target_id is String or not indexed_units.has(target_id) or seen.has(target_id):
				return "Invalid or duplicate AI target ID."
			var target: Dictionary = indexed_units[target_id]
			if target["team"] == unit["team"] or not State._whole(target.get("hp")) or target["hp"] <= 0:
				return "AI priority target must be a live opponent."
			seen[target_id] = true
	return ""


static func index(value: Dictionary) -> Dictionary:
	return value.duplicate(true)
