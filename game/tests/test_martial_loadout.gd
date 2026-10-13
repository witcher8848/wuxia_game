extends SceneTree
const Loadout = preload("res://game/domain/battle/martial_loadout.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const A := "CHAR_PROTAGONIST"
const B := "ENEMY_BLADE"
const C := "CHAR_COMPANION"
var checks := 0
var failures: Array[String] = []
var definitions: Array
var indexed: Dictionary
var fixture: Dictionary
var seed: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := "--require-pack" in OS.get_cmdline_user_args()
	if packed:
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported pack only; no source overlay")
		if not failures.is_empty(): quit(1); return
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	indexed = Skills.index(definitions)
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/graves_encounter.json"))["battle"]
	fixture["skill_definitions"] = definitions.duplicate(true)
	seed = Loadout.normalize_state({}, definitions)["state"]
	_test_catalog_and_validation()
	_test_state_and_slots()
	_test_atomic_configure()
	_test_passive_resources()
	_test_six_arts()
	_test_hypothetical_line()
	_test_survival()
	print("MARTIAL_LOADOUT: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty(): print("MARTIAL_LOADOUT_PASS checks=%d packed=%s" % [checks,str(packed)])
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("MARTIAL_FAIL ", label)


func duel(with_internal := true, qi := 0) -> Dictionary:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	data["units"] = [data["units"][0], data["units"][2]]
	data["units"][0]["cell"] = [1, 1]
	data["units"][0]["agility"] = 9
	data["units"][0]["qi"] = qi
	data["units"][0]["max_qi"] = 3 # Equipped passive raises this before validation.
	data["units"][0]["mastery"] = seed["mastery"].duplicate(true)
	data["units"][0]["loadout"] = seed["loadout"].duplicate(true)
	if not with_internal: data["units"][0]["loadout"]["internal"] = ""
	data["units"][1]["cell"] = [2, 1]
	data["units"][1]["hp"] = 100
	data["units"][1]["max_hp"] = 100
	return data


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(data).is_empty(), "valid V1 encounter")
	return battle


func use(battle: CombatEncounter, skill_id: String, at: Vector2i) -> Dictionary:
	var actor := battle.current_actor_id()
	var before := battle.snapshot()
	var preview := battle.preview_action(actor, skill_id, at)
	check(preview.get("ok", false), "legal preview " + skill_id)
	check(battle.snapshot() == before, "preview is read-only " + skill_id)
	var result := battle.perform_action(actor, skill_id, at, battle.revision)
	check(result.get("ok", false), "legal execute " + skill_id)
	if result.get("ok", false):
		check(result["plan"] == preview, "execution consumes identical preview " + skill_id)
		check(battle.unit(actor)["qi"] == preview["qi_after"], "qi after matches preview " + skill_id)
	return result


func rest(battle: CombatEncounter) -> void:
	use(battle, "ACT_BREATH", Grid.cell_of(battle.unit(battle.current_actor_id())))


func _test_catalog_and_validation() -> void:
	check(Skills.validate(definitions).is_empty(), "complete skill data validates")
	var arts := Loadout.catalog(indexed)
	check(arts.size() == 6, "six actual learnable arts, not six menu actions")
	for identifier: String in Loadout.SEED_IDS:
		check(identifier in arts, "six-art identity " + identifier)
	for identifier: String in ["SK_FIST_BASIC", "SK_STICK_GUARD", "ACT_BREATH", "ULT_SWORD", "ULT_FIST", "EN_BLADE_PIN", "EN_BOW_SHOT", "EN_BOW_BLEED", "EN_CATCHER_LOCK"]:
		check(not identifier in arts, "do not count baseline/auxiliary/ultimate/enemy " + identifier)
	var internal_index := -1
	for index: int in range(definitions.size()):
		if definitions[index]["id"] == "IN_BREATH_BASIC": internal_index = index
	check(internal_index >= 0, "passive definition is present")
	for field: String in ["max_qi", "basic_restore_qi", "breath_restore_qi"]:
		for bad: Variant in [-1, 0.5, "1", null, true, 33]:
			var data := definitions.duplicate(true)
			data[internal_index]["passive_rules"][field] = bad
			check(not Skills.validate(data).is_empty(), "reject malformed passive " + field + " " + str(bad))
	for change: Dictionary in [{"passive_rules": {}}, {"category": "被动"}, {"effects": ["guard"]}, {"power": 1}, {"ultimate": true}, {"target": "enemy"}, {"range_pattern": "step"}, {"restore_qi": 1}]:
		var data := definitions.duplicate(true)
		data[internal_index].merge(change, true)
		check(not Skills.validate(data).is_empty(), "passive cannot smuggle active action " + str(change))
	var bad := definitions.duplicate(true)
	bad[0]["passive_rules"] = {"max_qi":5,"basic_restore_qi":1,"breath_restore_qi":2}
	check(not Skills.validate(bad).is_empty(), "external art cannot define internal rules")
	bad = definitions.duplicate(true)
	bad[internal_index]["passive_rules"]["max_qi"] = 0
	check(not Skills.validate(bad).is_empty(), "zero qi capacity rejected")


func _test_state_and_slots() -> void:
	for empty: Dictionary in [{}, {"mastery": {}, "loadout": {}}]:
		var before := empty.duplicate(true)
		var normalized := Loadout.normalize_state(empty, definitions)
		check(normalized["error"].is_empty() and normalized["state"] == seed, "legacy empty state receives explicit compatibility seed")
		check(empty == before, "normalization does not mutate source state")
	check(seed["mastery"].size() == 6 and seed["loadout"]["external"].size() == 3, "six mastered V1 test seeds and three external slots")
	var returned := Loadout.normalize_state(seed, definitions)
	returned["state"]["loadout"]["external"].clear()
	check(seed["loadout"]["external"].size() == 3, "state result detached from caller")
	var loadout: Dictionary = seed["loadout"].duplicate(true)
	loadout["external"] = []
	loadout["movement"] = ""
	loadout["internal"] = ""
	check(Loadout.validate_loadout(loadout, seed["mastery"], indexed).is_empty(), "empty slots are legal and not auto-filled")
	for change: Dictionary in [{"external": ["SK_YUE_THRUST", "SK_YUE_GUARD", "SK_TRIP_WRIST", "SK_YUE_CROSSCUT"]}, {"external": ["SK_YUE_THRUST", "SK_YUE_THRUST"]}, {"external": ["SK_WATER_STEP"]}, {"external": ["IN_BREATH_BASIC"]}, {"external": ["SK_FIST_BASIC"]}, {"external": ["ULT_SWORD"]}, {"external": ["EN_CATCHER_LOCK"]}, {"external": ["MISSING"]}, {"external": "SK_YUE_THRUST"}, {"external": [null]}, {"movement": "SK_YUE_GUARD"}, {"movement": []}, {"internal": "ACT_BREATH"}, {"internal": []}, {"bonus": true}]:
		var wrong: Dictionary = seed["loadout"].duplicate(true)
		wrong.merge(change, true)
		var before := wrong.duplicate(true)
		check(not Loadout.validate_loadout(wrong, seed["mastery"], indexed).is_empty(), "reject wrong martial slots " + str(change))
		check(wrong == before, "slot rejection leaves source unchanged")
	for stage: Variant in ["识招", "初学", null, 1, true]:
		var mastery: Dictionary = seed["mastery"].duplicate(true)
		mastery["SK_YUE_THRUST"] = stage
		check(not Loadout.validate_loadout(seed["loadout"], mastery, indexed).is_empty(), "unlearned/bad stage cannot equip " + str(stage))
	var mastery: Dictionary = seed["mastery"].duplicate(true)
	mastery.erase("SK_YUE_THRUST")
	check(not Loadout.validate_loadout(seed["loadout"], mastery, indexed).is_empty(), "missing mastery cannot equip")
	for identifier: String in ["SK_WATER_STEP", "IN_BREATH_BASIC"]:
		mastery = seed["mastery"].duplicate(true)
		mastery[identifier] = "识招"
		check(not Loadout.validate_loadout(seed["loadout"], mastery, indexed).is_empty(), "movement/internal identification is not mastery " + identifier)
	mastery = seed["mastery"].duplicate(true)
	mastery["SK_TRIP_WRIST"] = "识招"
	check(Loadout.validate_loadout(seed["loadout"],mastery,indexed).is_empty(), "identified unassigned art may coexist with equipped mastered arts")
	mastery = seed["mastery"].duplicate(true)
	mastery["SK_YUE_THRUST"] = "化用"
	check(Loadout.validate_loadout(seed["loadout"], mastery, indexed).is_empty(), "validated 化用 may equip standard slot")
	for malformed: Variant in [null, [], "state", {"mastery":{}}, {"loadout":{}}, {"mastery":{},"loadout":{},"other":1}, {"mastery":{"SK_FIST_BASIC":"熟练"},"loadout":loadout}, {"mastery":{"MISSING":"熟练"},"loadout":loadout}]:
		check(not Loadout.normalize_state(malformed, definitions)["error"].is_empty(), "reject malformed state rather than reset it " + str(malformed))


func _test_atomic_configure() -> void:
	var battle := create(duel(true, 5))
	check(battle.unit(A)["max_qi"] == 5 and battle.unit(A)["qi"] == 5, "passive capacity applied before base resource probe")
	var before := battle.snapshot()
	var initial_skill := battle.skill("IN_BREATH_BASIC")
	var source_definition := duel(true,5)
	var source_before := source_definition.duplicate(true)
	var pure_result := Loadout.normalize_unit(source_definition["units"][0],indexed)
	check(pure_result["error"].is_empty() and source_definition == source_before, "unit normalization does not mutate source encounter")
	pure_result["unit"]["loadout"]["external"].clear()
	check(source_definition == source_before, "unit normalization output deeply detached")
	var bad_cases: Array[Dictionary] = []
	for change: Dictionary in [{"mastery":{}}, {"loadout":{}}, {"loadout":{"external":["SK_YUE_THRUST"],"movement":"","internal":"MISSING"}}, {"qi":-1}, {"qi":0.5}, {"qi":"5"}, {"max_qi":null}]:
		var data := duel(true, 5)
		data["units"][0].merge(change, true)
		bad_cases.append(data)
	for objective: Variant in [{"kind":"survive","rounds":0,"protected_unit_id":C}, {"kind":"survive","rounds":1.5,"protected_unit_id":A}, {"kind":"survive","rounds":100,"protected_unit_id":A}, {"kind":"survive","rounds":3,"protected_unit_id":B}, {"kind":"survive","rounds":3,"protected_unit_id":"MISSING"}, {"kind":"survive","rounds":3,"unit_id":A}]:
		var data := duel()
		data["objective"] = objective
		bad_cases.append(data)
	for data: Dictionary in bad_cases:
		check(not battle.configure(data).is_empty(), "bad configured V1 state rejected")
		check(battle.snapshot() == before and battle.skill("IN_BREATH_BASIC") == initial_skill, "bad configure atomically preserves live state and definitions")
	var legacy := fixture.duplicate(true)
	legacy["units"][0]["skills"].append("IN_BREATH_BASIC")
	check(not battle.configure(legacy).is_empty() and battle.snapshot() == before, "passive rejected in legacy active skill array")
	var failed_definition := duel(true,5)
	for configured_skill: Dictionary in failed_definition["skill_definitions"]:
		if configured_skill["id"] == "IN_BREATH_BASIC": configured_skill["passive_rules"]["max_qi"] = 9
	failed_definition["units"][1]["cell"] = [1,1]
	check(not battle.configure(failed_definition).is_empty() and battle.snapshot() == before and battle.skill("IN_BREATH_BASIC") == initial_skill, "late collision failure does not partially replace passive catalog")
	var external := battle.unit(A)
	external["loadout"]["external"].clear()
	external["passive_rules"]["max_qi"] = 1
	check(battle.unit(A)["loadout"]["external"].size() == 3 and battle.unit(A)["max_qi"] == 5, "configured unit queries deeply detached")
	check(not "IN_BREATH_BASIC" in battle.abilities(A), "internal art never appears in action menu")
	check(not battle.preview_action(A, "IN_BREATH_BASIC", Vector2i(1,1))["ok"], "passive cannot execute even by direct command")
	var old := create(fixture)
	check(old.unit(A)["max_qi"] == 5 and old.action_restore_qi(A,"SK_FIST_BASIC") == 1 and old.action_restore_qi(A,"ACT_BREATH") == 2, "legacy flat configurations preserve original cycle")


func _test_passive_resources() -> void:
	for internal: bool in [false, true]:
		var battle := create(duel(internal, 0))
		check(battle.unit(A)["max_qi"] == (5 if internal else 3), "equip/no internal capacity differs")
		var preview := battle.preview_action(A,"SK_FIST_BASIC",Vector2i(2,1))
		check(preview["qi_before"] == 0 and preview["qi_after"] == (1 if internal else 0) and preview["restore_qi"] == (1 if internal else 0), "equip/no internal basic recovery preview differs")
		check(preview["cooldown_ready_round"] == 0 and preview["destination"] == Vector2i(1,1), "non-cooldown stationary preview metadata")
		use(battle,"SK_FIST_BASIC",Vector2i(2,1))
		rest(battle)
		preview = battle.preview_action(A,"ACT_BREATH",Vector2i(1,1))
		check(preview["restore_qi"] == (2 if internal else 1), "equip/no internal breathing preview differs")
		rest(battle)
		check(battle.unit(A)["statuses"].has("guard"), "breathing still grants guard and occupies action")
		check(battle.retry() and battle.unit(A)["qi"] == 0, "retry restores passive-compatible resources")
	var capped := create(duel(true,4))
	var preview := capped.preview_action(A,"ACT_BREATH",Vector2i(1,1))
	check(preview["qi_after"] == 5 and preview["restore_qi"] == 1, "preview reports actual capped recovery, not nominal two")
	rest(capped)
	var stale := create(duel(true,4))
	var prepared := stale.preview_action(A,"ACT_BREATH",Vector2i(1,1))
	check(stale.move_actor(A,Vector2i(1,2),stale.revision)["ok"], "new movement invalidates prepared passive recovery")
	var stable := stale.snapshot()
	check(not stale.perform_action(A,"ACT_BREATH",Vector2i(1,1),prepared["revision"])["ok"] and stale.snapshot() == stable, "stale passive resource preview cannot double-spend or recover")
	var no_internal := create(duel(false,5))
	check(no_internal.unit(A)["qi"] == 3, "unequipped qi clamped to new capacity")
	preview = no_internal.preview_action(A,"ACT_BREATH",Vector2i(1,1))
	check(preview["restore_qi"] == 0 and preview["qi_after"] == 3, "full qi recovery preview is zero")
	var custom := duel(true,0)
	for skill: Dictionary in custom["skill_definitions"]:
		if skill["id"] == "IN_BREATH_BASIC": skill["passive_rules"] = {"max_qi":7,"basic_restore_qi":3,"breath_restore_qi":4}
	var data_driven := create(custom)
	check(data_driven.unit(A)["max_qi"] == 7 and data_driven.preview_action(A,"ACT_BREATH",Vector2i(1,1))["qi_after"] == 4, "passive behavior follows data, not the art ID")
	use(data_driven,"SK_FIST_BASIC",Vector2i(2,1))
	check(data_driven.unit(A)["qi"] == 3, "custom passive actually changes reducer result")


func _test_six_arts() -> void:
	var data := duel(true,5)
	data["units"][0]["loadout"]["external"] = ["SK_TRIP_WRIST","SK_YUE_THRUST","SK_YUE_GUARD"]
	var battle := create(data)
	var hp: int = battle.unit(B)["hp"]
	var preview := battle.preview_action(A,"SK_TRIP_WRIST",Vector2i(2,1))
	use(battle,"SK_TRIP_WRIST",Vector2i(2,1))
	check(battle.unit(B)["hp"] == hp-preview["hits"][0]["actual"] and battle.unit(B)["statuses"].has("broken"), "绊腕 applies exact damage and broken")
	data = duel(true,5)
	data["units"][1]["cell"] = [3,1]
	battle = create(data)
	preview = battle.preview_action(A,"SK_YUE_THRUST",Vector2i(3,1))
	check(preview["hits"][0]["damage"] == 5, "直势 unique second-cell bonus")
	use(battle,"SK_YUE_THRUST",Vector2i(3,1))
	data = duel(true,5)
	var ally: Dictionary = fixture["units"][1].duplicate(true)
	ally["cell"] = [1,2]
	ally["agility"] = 0
	data["units"].append(ally)
	battle = create(data)
	use(battle,"SK_YUE_GUARD",Vector2i(1,1))
	check(battle.unit(A)["statuses"].has("guard") and battle.unit(C)["statuses"].has("support"), "护剑 grants self guard and allied support")
	battle = create(duel(true,5))
	preview = battle.preview_action(A,"SK_WATER_STEP",Vector2i(3,1))
	check(preview["destination"] == Vector2i(3,1) and preview["qi_after"] == 4 and preview["cooldown_ready_round"] == 4, "step metadata has landing, resources and exact cooldown round")
	use(battle,"SK_WATER_STEP",Vector2i(3,1))
	check(battle.unit(A)["cell"] == [3,1] and battle.unit(A)["statuses"].has("guard"), "掠水步 crosses enemy and lands guarded")
	battle = create(duel(true,5))
	preview = battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(2,1))
	check(preview["effects"] == ["pin"] and preview["cooldown_ready_round"] == 3, "横截 distinct pin and one-full-round cooldown")
	use(battle,"SK_YUE_CROSSCUT",Vector2i(2,1))
	check(battle.unit(B)["statuses"].has("pin") and battle.move_budget == 1, "横截 immediately reduces target's next turn movement")
	check(battle.unit(A)["cooldowns"]["SK_YUE_CROSSCUT"] == preview["cooldown_ready_round"], "preview cooldown agrees with reducer")
	# Internal art behavior was exercised above, not merely counted by a label.
	var forecast := battle.forecast_turn(B)
	check(forecast != null and forecast.unit(A)["passive_rules"] == battle.unit(A)["passive_rules"], "read-only forecast preserves real passive rules")


func _test_survival() -> void:
	var data := duel(true,0)
	data["objective"] = {"kind":"survive","rounds":3,"protected_unit_id":A}
	var battle := create(data)
	var initial := battle.snapshot()
	for round_index: int in range(1,4):
		check(battle.round_number == round_index and battle.outcome == "ongoing", "entering survival round does not win early")
		rest(battle)
		check(battle.outcome == "ongoing", "not won before all units finish survival round")
		rest(battle)
		check(battle.outcome == ("victory" if round_index == 3 else "ongoing"), "survival checks complete rounds exactly")
	check(battle.round_number == 3 and battle.pending_ids().is_empty(), "final survival result stays at completed third round")
	check(battle.retry() and battle.round_number == 1 and battle.outcome == "ongoing" and battle.unit(A)["qi"] == initial["units"][A]["qi"], "retry resets survivor turns, outcome and resources")
	var old_revision := battle.revision
	rest(battle)
	check(not battle.perform_action(A,"ACT_BREATH",Vector2i(1,1),old_revision)["ok"], "stale survival action rejected")
	data = duel(true,5)
	data["objective"] = {"kind":"survive","rounds":3,"protected_unit_id":A}
	data["units"][1]["hp"] = 1
	battle = create(data)
	use(battle,"SK_FIST_BASIC",Vector2i(2,1))
	check(battle.outcome == "ongoing" and battle.round_number == 2, "early enemy elimination does not satisfy survival")
	rest(battle)
	check(battle.outcome == "ongoing" and battle.round_number == 3, "empty enemy side still requires third completed ally round")
	rest(battle)
	check(battle.outcome == "victory" and battle.round_number == 3, "remaining survivor can complete objective without infinite loop")
	data = duel(true,0)
	var companion: Dictionary = fixture["units"][1].duplicate(true)
	companion["cell"] = [1,2]
	companion["hp"] = 1
	companion["agility"] = 0
	data["units"].append(companion)
	data["objective"] = {"kind":"survive","rounds":1,"protected_unit_id":C}
	battle = create(data)
	rest(battle)
	rest(battle)
	check(battle.current_actor_id() == C, "protected ally gets final turn")
	Effects.apply_statuses(battle,B,C,["bleed"])
	rest(battle)
	check(battle.outcome == "defeat" and battle.unit(A)["hp"] > 0, "protected-unit bleeding defeat overrides final-round victory")
	check(battle.retry() and battle.unit(C)["hp"] == 1 and battle.unit(C)["statuses"].is_empty(), "retry restores protected unit and clears discarded attempt effects")
	data = duel(true,0)
	data["units"][0]["hp"] = 1
	data["units"][1]["power"] = 99
	data["objective"] = {"kind":"survive","rounds":1,"protected_unit_id":A}
	battle = create(data)
	rest(battle)
	use(battle,"SK_FIST_BASIC",Vector2i(1,1))
	check(battle.outcome == "defeat", "all-allies defeat takes precedence on survival's final completion")


func _test_hypothetical_line() -> void:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	data["units"] = [data["units"][0], data["units"][2]]
	data["units"][0]["cell"] = [2,1]
	data["units"][0]["agility"] = 9
	data["units"][0]["skills"] = ["EN_BOW_SHOT"]
	data["units"][1]["cell"] = [1,1]
	var battle := create(data)
	var before := battle.snapshot()
	var preview := Actions.preview(battle,A,"EN_BOW_SHOT",Vector2i(1,1),Vector2i(4,1))
	check(preview["ok"] and battle.snapshot() == before, "hypothetical retreat ray ignores only actor's vacated old cell, read-only")
	check(battle.move_actor(A,Vector2i(4,1),battle.revision)["ok"], "actual retreat before ray confirmation")
	var actual := battle.preview_action(A,"EN_BOW_SHOT",Vector2i(1,1))
	check(actual["ok"] and actual["hits"] == preview["hits"] and actual["qi_after"] == preview["qi_after"], "hypothetical ray agrees with post-move executable ray")
	use(battle,"EN_BOW_SHOT",Vector2i(1,1))
	var blocker: Dictionary = fixture["units"][1].duplicate(true)
	blocker["cell"] = [3,1]
	blocker["agility"] = 0
	data["units"].append(blocker)
	battle = create(data)
	check(not Actions.preview(battle,A,"EN_BOW_SHOT",Vector2i(1,1),Vector2i(4,1))["ok"], "hypothetical ray still blocked by another unit")
	data["units"].pop_back()
	data["blocked"] = [[3,1]]
	battle = create(data)
	check(not Actions.preview(battle,A,"EN_BOW_SHOT",Vector2i(1,1),Vector2i(4,1))["ok"], "hypothetical ray still blocked by wall")
