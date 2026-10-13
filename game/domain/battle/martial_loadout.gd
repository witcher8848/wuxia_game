class_name MartialLoadout
extends RefCounted
## Pure, detached configuration rules; no session, scene or save I/O.
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const STAGES := ["识招", "熟练", "化用"]
const SEED_IDS := ["SK_TRIP_WRIST", "SK_YUE_THRUST", "SK_YUE_GUARD", "SK_YUE_CROSSCUT", "SK_WATER_STEP", "IN_BREATH_BASIC"]
const DEFAULT_LOADOUT := {"external": ["SK_YUE_THRUST", "SK_YUE_GUARD", "SK_YUE_CROSSCUT"], "movement": "SK_WATER_STEP", "internal": "IN_BREATH_BASIC"}
const UNTRAINED_RULES := {"max_qi": 3, "basic_restore_qi": 0, "breath_restore_qi": 1}


static func catalog(skills: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for identifier: String in skills:
		var skill: Dictionary = skills[identifier]
		if not identifier in Skills.BASE and not skill["ultimate"] and skill["category"] in ["外功", "身法", "内功"]:
			result.append(identifier)
	return result


static func validate_mastery(mastery: Variant, skills: Dictionary) -> String:
	if not mastery is Dictionary or not GameState.is_json_value(mastery):
		return "Mastery must be a finite JSON dictionary."
	var learned := catalog(skills)
	for identifier: Variant in mastery:
		if not identifier is String or not identifier in learned or not mastery[identifier] in STAGES:
			return "Invalid martial mastery ID or stage."
	return ""


static func validate_loadout(loadout: Variant, mastery: Variant, skills: Dictionary) -> String:
	var error := validate_mastery(mastery, skills)
	if not error.is_empty(): return error
	if not loadout is Dictionary or not GameState.is_json_value(loadout) or loadout.size() != 3 or not loadout.has("external") or not loadout.has("movement") or not loadout.has("internal"):
		return "Loadout requires external, movement and internal slots only."
	if not loadout["external"] is Array or loadout["external"].size() > 3 or not loadout["movement"] is String or not loadout["internal"] is String:
		return "Invalid martial slot type or capacity."
	var selected: Dictionary = {}
	for identifier: Variant in loadout["external"]:
		error = _validate_slot(identifier, "外功", mastery, skills, selected)
		if not error.is_empty(): return error
	for pair: Array in [["movement", "身法"], ["internal", "内功"]]:
		var identifier: String = loadout[pair[0]]
		if identifier.is_empty(): continue
		error = _validate_slot(identifier, pair[1], mastery, skills, selected)
		if not error.is_empty(): return error
	return ""


static func _validate_slot(identifier: Variant, category: String, mastery: Dictionary, skills: Dictionary, selected: Dictionary) -> String:
	if not identifier is String or not skills.has(identifier) or identifier in Skills.BASE or skills[identifier]["ultimate"] or skills[identifier]["category"] != category or selected.has(identifier):
		return "Unknown, duplicate or wrong-category martial slot."
	if mastery.get(identifier, "识招") not in ["熟练", "化用"]:
		return "Only 熟练 or 化用 martial arts may be equipped."
	selected[identifier] = true
	return ""


static func normalize_state(martial: Variant, skill_definitions: Array) -> Dictionary:
	var error := Skills.validate(skill_definitions)
	if not error.is_empty(): return {"error": error, "state": {}}
	if not martial is Dictionary or not GameState.is_json_value(martial):
		return {"error": "Martial state must be a finite JSON dictionary.", "state": {}}
	var skills := Skills.index(skill_definitions)
	var legacy_empty: bool = martial.is_empty() or (martial.size() == 2 and martial.get("mastery") is Dictionary and martial.get("loadout") is Dictionary and martial["mastery"].is_empty() and martial["loadout"].is_empty())
	var candidate: Dictionary = martial.duplicate(true)
	if legacy_empty:
		var mastery: Dictionary = {}
		for identifier: String in SEED_IDS:
			if not identifier in catalog(skills): return {"error": "Missing V1 compatibility martial seed: " + identifier, "state": {}}
			mastery[identifier] = "熟练"
		candidate = {"mastery": mastery, "loadout": DEFAULT_LOADOUT.duplicate(true)}
	if candidate.size() != 2 or not candidate.has("mastery") or not candidate.has("loadout"):
		return {"error": "Martial state requires mastery and loadout only.", "state": {}}
	error = validate_loadout(candidate["loadout"], candidate["mastery"], skills)
	return {"error": error, "state": candidate if error.is_empty() else {}}


static func passive_rules(loadout: Dictionary, skills: Dictionary) -> Dictionary:
	var identifier: String = loadout["internal"]
	return UNTRAINED_RULES.duplicate(true) if identifier.is_empty() else skills[identifier]["passive_rules"].duplicate(true)


static func normalize_unit(unit: Dictionary, skills: Dictionary) -> Dictionary:
	# Legacy flat arrays retain their original resources and action recovery.
	var candidate: Dictionary = unit.duplicate(true)
	if not candidate.has("loadout"): return {"error": "", "unit": candidate}
	var error := validate_loadout(candidate["loadout"], candidate.get("mastery"), skills)
	if not error.is_empty(): return {"error": error, "unit": {}}
	for field: String in ["qi", "max_qi"]:
		if not BattleState._whole(candidate.get(field)) or candidate[field] < 0 or candidate[field] > 999:
			return {"error": "Invalid configured resource: " + field, "unit": {}}
	var rules := passive_rules(candidate["loadout"], skills)
	candidate["skills"] = candidate["loadout"]["external"].duplicate(true)
	if not candidate["loadout"]["movement"].is_empty(): candidate["skills"].append(candidate["loadout"]["movement"])
	candidate["internal_skill"] = candidate["loadout"]["internal"]
	candidate["passive_rules"] = rules
	candidate["max_qi"] = int(rules["max_qi"])
	candidate["qi"] = mini(int(candidate["qi"]), int(candidate["max_qi"]))
	return {"error": "", "unit": candidate}
