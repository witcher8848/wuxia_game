extends SceneTree
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Profiles = preload("res://game/domain/battle/battle_ai_profiles.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const D := "ENEMY_BOW"
const E := "ENEMY_CATCHER"
var fixture: Dictionary
var checks := 0
var failures: Array[String] = []
var packed := false

class MissingProfileResolver extends CombatEncounter:
	func ai_profile(_actor: String) -> Dictionary: return {}


func _initialize() -> void: _run.call_deferred()


func _run() -> void:
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed, "real PCK only, no source project overlay")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/week6_ai_test_encounter.json"))
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	fixture["ai_profiles"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_ai_profiles.json"))
	_validation()
	_archetype_templates()
	_configurable_priorities()
	_pressure()
	_ranged()
	_capture()
	_secrecy_and_legacy()
	_blocked_and_empty_targets()
	_full_two_versus_three()
	_full_three_round_protection()
	print("WEEK6_AI: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty(): print("WEEK6_AI_PASS packed=%s checks=%d" % [packed, checks])
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK6_AI_FAIL ", label)


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	var error := battle.configure(data)
	check(error.is_empty(), "configure AI fixture: " + error)
	return battle


func act(battle: CombatEncounter, selected: Dictionary) -> void:
	var actor := battle.current_actor_id()
	check(not selected.is_empty(), "actual turn has a plan")
	if selected.is_empty(): return
	if selected["destination"] != Grid.cell_of(battle.unit(actor)):
		check(battle.move_actor(actor, selected["destination"], battle.revision)["ok"], "planned real movement executes")
	check(battle.perform_action(actor, selected["skill_id"], selected["target"], battle.revision)["ok"], "planned real action executes")


func rest_until(battle: CombatEncounter, actor: String) -> void:
	var turns := 0
	while battle.outcome == "ongoing" and battle.current_actor_id() != actor and turns < 12:
		var next := battle.current_actor_id()
		check(battle.perform_action(next, "ACT_BREATH", Grid.cell_of(battle.unit(next)), battle.revision)["ok"], "intervening real turn completes")
		turns += 1
	check(battle.current_actor_id() == actor, "next real actor reached")


func pair(enemy_id: String) -> Dictionary:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	var enemy: Dictionary = {}
	for unit: Dictionary in data["units"]:
		if unit["id"] == enemy_id: enemy = unit
	data["units"] = [data["units"][0], data["units"][1], enemy]
	data["units"][0]["cell"] = [1, 1]
	data["units"][1]["cell"] = [1, 4]
	for unit: Dictionary in data["units"]:
		unit["hp"] = 80
		unit["max_hp"] = 80
	enemy["cell"] = [2, 1]
	enemy["agility"] = 9
	return data


func _validation() -> void:
	var battle := create(fixture)
	var before := battle.snapshot()
	var bad_cases: Array[Dictionary] = []
	for value: Variant in [null, [], "profiles", true, {}]:
		var bad := fixture.duplicate(true)
		bad["ai_profiles"] = value
		bad_cases.append(bad)
	for field: String in Profiles.FIELDS:
		var bad := fixture.duplicate(true)
		bad["ai_profiles"]["AI_PRESSURE"].erase(field)
		bad_cases.append(bad)
	for change: Dictionary in [
		{"style":"guess"}, {"intent_label":" "}, {"intent_label":null}, {"target_priority":"random"},
		{"preferred_range":[0,1]}, {"preferred_range":[3,2]}, {"preferred_range":[1.5,3]}, {"preferred_range":[1,"3"]},
		{"skill_priority":[]}, {"skill_priority":["MISSING"]}, {"skill_priority":["SK_STICK_GUARD"]}, {"skill_priority":["EN_BLADE_PIN","EN_BLADE_PIN"]},
		{"effect_priority":["guard"]}, {"effect_priority":["unknown"]}, {"effect_priority":["pin","pin"]},
		{"low_hp_guard_threshold":-1}, {"low_hp_guard_threshold":1.5}, {"low_hp_guard_threshold":"2"}, {"unknown_field":0}
	]:
		var bad := fixture.duplicate(true)
		bad["ai_profiles"]["AI_PRESSURE"].merge(change, true)
		bad_cases.append(bad)
	for target_ids: Variant in [[], "CHAR_PROTAGONIST", [A,A], [E], ["MISSING"]]:
		var bad := fixture.duplicate(true)
		bad["units"][4]["ai_target_ids"] = target_ids
		bad_cases.append(bad)
	for index: int in [0, 2]:
		var bad := fixture.duplicate(true)
		bad["units"][index]["ai_profile"] = "MISSING"
		bad_cases.append(bad)
	var missing_skill := fixture.duplicate(true)
	missing_skill["units"][2]["skills"] = []
	bad_cases.append(missing_skill)
	var dead_target := fixture.duplicate(true)
	dead_target["units"][0]["hp"] = 0
	bad_cases.append(dead_target)
	var allied_ai := fixture.duplicate(true)
	allied_ai["units"][0]["ai_profile"] = "AI_PRESSURE"
	bad_cases.append(allied_ai)
	for bad: Dictionary in bad_cases:
		check(not Profiles.validate(bad.get("ai_profiles"), Skills.index(fixture["skill_definitions"]), bad["units"]).is_empty(), "pure validator rejects invalid AI configuration")
		check(not battle.configure(bad).is_empty(), "encounter rejects invalid AI configuration")
		check(battle.snapshot() == before, "AI validation rejection is atomic")
		check(battle.ai_profile(B) == fixture["ai_profiles"]["AI_PRESSURE"], "rejection preserves prior AI table")
	var detached := battle.ai_profile(B)
	detached["skill_priority"].clear()
	check(battle.ai_profile(B)["skill_priority"].size() == 2, "profile query is deeply detached")
	var cloned := Profiles.index(fixture["ai_profiles"])
	cloned["AI_CAPTURE"]["skill_priority"].clear()
	check(fixture["ai_profiles"]["AI_CAPTURE"]["skill_priority"].size() == 2, "profile index cannot mutate source data")
	if not packed:
		var source := FileAccess.get_file_as_string("res://game/domain/battle/battle_ai.gd")
		check(not source.is_empty() and not source.contains("GameSession"), "nonempty AI source has no permanent session dependency")


func _pressure() -> void:
	var battle := create(pair(B))
	var before := battle.snapshot()
	var planned := AI.plan(battle, B)
	check(planned == AI.plan(battle, B) and battle.snapshot() == before, "pressure planning deterministic and pure")
	check(planned["skill_id"] == "EN_BLADE_PIN", "pressure chooses available control")
	act(battle, planned)
	check(battle.unit(A)["statuses"].has("pin") and battle.unit(B)["qi"] == 2, "pressure control really applies and spends qi")
	var data := pair(B)
	data["units"][2]["hp"] = 2
	battle = create(data)
	var guard_turns := 0
	var attack_turns := 0
	for turn: int in range(4):
		rest_until(battle, B)
		planned = AI.plan(battle, B)
		if planned["skill_id"] == "SK_STICK_GUARD": guard_turns += 1
		else: attack_turns += 1
		act(battle, planned)
	check(guard_turns == 2 and attack_turns == 2, "four executed low-HP turns alternate, never permanent guarding")


func _archetype_templates() -> void:
	var templates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/enemy_archetypes.json"))
	check(templates.size() == 3, "three enemy archetypes are data-defined")
	for archetype: String in templates:
		var original: Dictionary = templates[archetype].duplicate(true)
		var data := fixture.duplicate(true)
		var unit: Dictionary = templates[archetype].duplicate(true)
		unit["id"] = "DATA_DRIVEN_ENEMY"
		unit["cell"] = [6,3]
		if unit["ai_profile"] == "AI_CAPTURE": unit["ai_target_ids"] = [C]
		data["units"] = [data["units"][0], data["units"][1], unit]
		var battle := create(data)
		check(battle.unit(unit["id"])["archetype"] == archetype and battle.ai_profile(unit["id"])["style"] in ["pressure","ranged","capture"], "data template composes into a validated live encounter")
		check(templates[archetype] == original, "instantiating an archetype does not mutate the shared template")
		rest_until(battle, unit["id"])
		act(battle, AI.plan(battle, unit["id"]))


func _configurable_priorities() -> void:
	var data := pair(D)
	data["units"][2]["cell"] = [3, 3]
	data["units"][2]["move"] = 0
	data["units"][0]["cell"] = [3, 2]
	data["units"][0]["hp"] = 50
	data["units"][1]["cell"] = [1, 3]
	data["units"][1]["hp"] = 10
	var battle := create(data)
	var planned := AI.plan(battle, D)
	check(planned["target"] == Vector2i(1,3), "lowest-HP profile chooses weaker opponent over nearer healthy opponent")
	act(battle, planned)
	data["ai_profiles"]["AI_RANGED"]["target_priority"] = "nearest"
	battle = create(data)
	planned = AI.plan(battle, D)
	check(planned["target"] == Vector2i(3,2), "changing only target-priority config changes legal selected target")
	act(battle, planned)
	data = pair(D)
	data["ai_profiles"]["AI_RANGED"]["preferred_range"] = [1,2]
	battle = create(data)
	planned = AI.plan(battle, D)
	check(Grid.distance(planned["destination"], planned["target"]) == 2, "preferred separation is configurable, not a hard-coded three cells")
	act(battle, planned)
	# Fault-injection boundary only: a broken resolver must never execute the
	# legacy melee strategy for an explicitly configured enemy.
	var unresolved := MissingProfileResolver.new()
	check(unresolved.configure(pair(B)).is_empty(), "valid explicit profile fixture before resolver fault")
	var before := unresolved.snapshot()
	check(AI.plan(unresolved, B).is_empty() and AI.intent(unresolved, B)["kind"].contains("无效"), "missing explicit runtime profile reports error instead of silently falling back")
	check(not AI.take_turn(unresolved)["ok"] and unresolved.snapshot() == before, "resolver fault cannot mutate battle through an implicit fallback")


func _ranged() -> void:
	var data := pair(D)
	var battle := create(data)
	var planned := AI.plan(battle, D)
	check(planned["skill_id"] == "EN_BOW_BLEED", "ranged uses novel bleed when resources legal")
	check(Grid.distance(planned["destination"], planned["target"]) >= 3, "ranged keeps configured preferred separation")
	act(battle, planned)
	check(battle.unit(A)["statuses"].has("bleed") and Grid.distance(Grid.cell_of(battle.unit(D)), Grid.cell_of(battle.unit(A))) >= 3, "ranged plan really moves and applies bleed")
	rest_until(battle, D)
	planned = AI.plan(battle, D)
	check(planned["skill_id"] == "EN_BOW_SHOT", "ranged respects bleed cooldown after real turn")
	act(battle, planned)
	data = pair(D)
	data["units"][2]["qi"] = 0
	battle = create(data)
	planned = AI.plan(battle, D)
	check(planned["skill_id"] == "EN_BOW_SHOT", "ranged qi-zero fallback is a legal owned shot")
	act(battle, planned)


func _capture() -> void:
	var data := pair(E)
	# Closer bystander is deliberately adjacent; the configured carrier is
	# reachable but farther. No hidden story/fact membership is consulted.
	data["units"][0]["cell"] = [5, 2]
	data["units"][1]["cell"] = [2, 2]
	data["units"][2]["cell"] = [3, 2]
	var battle := create(data)
	var planned := AI.plan(battle, E)
	check(planned["target"] == Vector2i(5, 2) and planned["skill_id"] == "EN_CATCHER_LOCK", "capture prioritizes configured carrier over adjacent bystander")
	act(battle, planned)
	check(battle.unit(A)["statuses"].has("pin") and not battle.unit(C)["statuses"].has("pin"), "capture actual reducer targets carrier")
	data = pair(E)
	data["units"][2]["ai_target_ids"] = [C]
	data["units"][1]["cell"] = [4, 1]
	battle = create(data)
	planned = AI.plan(battle, E)
	check(planned["target"] == Vector2i(4, 1), "carrier is configurable, not protagonist hard-coded")
	act(battle, planned)
	# A second catcher in this same real round sees the first pin still live.
	# It must strike rather than waste qi renewing that same pin.
	data = pair(E)
	var second: Dictionary = data["units"][2].duplicate(true)
	second["id"] = "ENEMY_CATCHER_SECOND"
	second["cell"] = [2, 2]
	second["agility"] = 8
	data["units"].append(second)
	battle = create(data)
	act(battle, AI.plan(battle, E))
	planned = AI.plan(battle, second["id"])
	check(planned["skill_id"] == "SK_FIST_BASIC" and planned["target"] == Vector2i(1, 1), "second real catcher does not re-pin an already pinned recipient")
	act(battle, planned)
	check(battle.unit(second["id"])["qi"] == 3, "nonredundant follow-up retains qi")
	# Dead configured target: use a real lethal action, then advance turns.
	data = pair(E)
	data["units"][0]["hp"] = 1
	data["units"][1]["cell"] = [2, 4]
	battle = create(data)
	act(battle, AI.plan(battle, E))
	check(battle.unit(A)["hp"] == 0 and battle.outcome == "ongoing", "carrier dies through actual action while companion survives")
	rest_until(battle, E)
	planned = AI.plan(battle, E)
	check(planned["target"] == Grid.cell_of(battle.unit(C)), "dead carrier removed from target selection")
	act(battle, planned)


func _secrecy_and_legacy() -> void:
	var battle := create(fixture)
	var labels: Dictionary = {}
	for identifier: String in [B,D,E]:
		var before := battle.snapshot()
		var ordinary := AI.intent(battle, identifier)
		labels[ordinary["kind"]] = true
		check(ordinary.keys().size() == 2 and ordinary.has("reachable") and not ordinary.has("plan"), "ordinary intent reveals only strategy label and movement")
		check(not AI.intent(battle, identifier, true).has("plan"), "non-current actor cannot reveal a precise live plan")
		var forecast := battle.forecast_turn(identifier)
		check(forecast != null and forecast.ai_profile(identifier) == battle.ai_profile(identifier), "authorized forecast copies correct profile")
		check(AI.intent(forecast, identifier, true)["plan"] == AI.plan(forecast, identifier), "current disposable forecast may show exact plan")
		check(battle.snapshot() == before, "forecast and intent never mutate live battle")
	check(labels.size() == 3, "three strategies have distinct visible intent labels")
	var data := pair(D)
	data["units"][2].erase("ai_profile")
	data["units"][2]["archetype"] = "EN_RENAMED_ARCHER"
	data.erase("ai_profiles")
	battle = create(data)
	var planned := AI.plan(battle, D)
	check(Grid.distance(planned["destination"], planned["target"]) >= 3, "legacy ranged inference uses skills, not archetype spelling")
	act(battle, planned)
	data = pair(B)
	data["units"][2].erase("ai_profile")
	data["units"][2]["archetype"] = "EN_YAMEN_BOW"
	data.erase("ai_profiles")
	battle = create(data)
	check(AI.intent(battle, B)["kind"].begins_with("近身"), "a bow-spelled unit with melee skills is not ranged")
	act(battle, AI.plan(battle, B))


func _blocked_and_empty_targets() -> void:
	for identifier: String in [B,D,E]:
		var data := pair(identifier)
		data["units"][2]["cell"] = [8, 6]
		data["blocked"] = [[7,6],[9,6],[8,5],[8,7]]
		var battle := create(data)
		var planned := AI.plan(battle, identifier)
		check(planned["destination"] == Vector2i(8,6) and planned["skill_id"] == "ACT_BREATH", "fully blocked profile still selects legal pass")
		act(battle, planned)
	# Existing escape semantics permit movement after all enemies die.
	# Allies' planner must therefore also survive an empty enemy list.
	var data := pair(B)
	data["objective"] = {"kind":"escape", "unit_id":A, "cell":[9,7]}
	data["units"][2]["hp"] = 1
	data["units"][0]["agility"] = 10
	var battle := create(data)
	check(battle.perform_action(A, "SK_FIST_BASIC", Vector2i(2,1), battle.revision)["ok"], "actual kill clears final enemy in escape objective")
	check(battle.outcome == "ongoing", "escape does not silently become eliminate")
	act(battle, AI.plan(battle, battle.current_actor_id()))
	check(AI.intent(battle, "MISSING").is_empty() and AI.plan(battle, "MISSING").is_empty(), "unknown/dead actors cannot create a plan")


func _full_two_versus_three() -> void:
	var transcripts: Array[String] = []
	for attempt: int in range(3):
		var battle := create(fixture)
		var turns := 0
		var seen_enemies: Dictionary = {}
		while battle.outcome == "ongoing" and turns < 100:
			var actor := battle.current_actor_id()
			var planned := AI.plan(battle, actor)
			check(planned == AI.plan(battle, actor), "full 2v3 deterministic plan")
			if battle.unit(actor)["team"] == "enemy": seen_enemies[actor] = true
			act(battle, planned)
			turns += 1
		check(battle.outcome == "victory" and turns < 100, "complete configured 2v3 wins without assist buffs or state injection")
		check(seen_enemies.size() == 3, "all three enemy profiles execute in full encounter")
		transcripts.append("|".join(battle.events))
		print("WEEK6_AI_2V3 attempt=%d turns=%d outcome=%s hero_hp=%d companion_hp=%d" % [attempt, turns, battle.outcome, battle.unit(A)["hp"], battle.unit(C)["hp"]])
	check(transcripts[0] == transcripts[1] and transcripts[1] == transcripts[2], "three complete real 2v3 transcripts identical")


func _full_three_round_protection() -> void:
	var data := fixture.duplicate(true)
	data["objective"] = {"kind": "survive", "rounds": 3, "protected_unit_id": C}
	for attempt: int in range(3):
		var battle := create(data)
		var turns := 0
		var seen: Dictionary = {}
		while battle.outcome == "ongoing" and turns < 100:
			var actor := battle.current_actor_id()
			var turn_key := "%d:%s" % [battle.round_number, actor]
			check(not seen.has(turn_key), "no actor gets a second action in same real protection round")
			seen[turn_key] = true
			var before_round := battle.round_number
			act(battle, AI.plan(battle, actor))
			turns += 1
			if before_round < 3: check(battle.outcome == "ongoing", "protection does not finish before three complete rounds")
		check(battle.outcome == "victory" and battle.round_number == 3 and battle.pending_ids().is_empty() and battle.unit(C)["hp"] > 0, "same 2v3 configuration survives three complete rounds without assist")
		for identifier: String in [B,D,E]: check(seen.has("1:"+identifier), "every enemy profile acts in real protection encounter")
		print("WEEK6_AI_PROTECTION attempt=%d turns=%d outcome=%s round=%d companion_hp=%d" % [attempt, turns, battle.outcome, battle.round_number, battle.unit(C)["hp"]])
