extends SceneTree
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
var checks := 0
var failures: Array[String] = []
var fixture: Dictionary
const A := "CHAR_PROTAGONIST"
const B := "ENEMY_BLADE"
const C := "CHAR_COMPANION"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/tools/battle_lab/combat_encounter.json"))
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	_test_validation()
	_test_movement()
	_test_actions()
	_test_statuses()
	_test_ultimates()
	_test_ai_and_outcomes()
	print("COMBAT_RULES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("COMBAT_FAIL ", label)


func duel() -> Dictionary:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	data["units"] = [data["units"][0], data["units"][2]]
	data["units"][0]["cell"] = [1, 1]
	data["units"][1]["cell"] = [2, 1]
	data["units"][1]["hp"] = 40
	data["units"][1]["max_hp"] = 40
	return data


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(data).is_empty(), "configure valid encounter")
	return battle


func use(battle: CombatEncounter, skill: String, target: Vector2i) -> Dictionary:
	var result := battle.perform_action(battle.current_actor_id(), skill, target, battle.revision)
	check(result["ok"], "legal action " + skill + " " + str(result.get("reason", "")))
	return result


func rest(battle: CombatEncounter) -> void:
	use(battle, "ACT_BREATH", Grid.cell_of(battle.unit(battle.current_actor_id())))


func same_except_revision(left: Dictionary, right: Dictionary) -> bool:
	left = left.duplicate(true)
	right = right.duplicate(true)
	left.erase("revision")
	right.erase("revision")
	return left == right


func _test_validation() -> void:
	var battle := create(fixture)
	var before := battle.snapshot()
	var bad_cases: Array[Dictionary] = []
	for value: Variant in [null, {}, [], "skills"]:
		var bad := fixture.duplicate(true)
		bad["skill_definitions"] = value
		bad_cases.append(bad)
	for field: String in ["range", "power", "qi_cost", "cooldown_rounds", "restore_qi", "distance_bonus"]:
		for value: Variant in [-1, 0.5, "2", null]:
			var bad := fixture.duplicate(true)
			bad["skill_definitions"][0][field] = value
			bad_cases.append(bad)
	for change: Dictionary in [{"skills": ["MISSING"]}, {"skills": ["ULT_SWORD"]}, {"ultimate": {}}, {"ultimate": {"skill_id":"ULT_SWORD", "kind":"damage_received", "threshold":0}}]:
		var bad := fixture.duplicate(true)
		bad["units"][0].merge(change, true)
		bad_cases.append(bad)
	for goal: Variant in [{}, null, {"kind":"escape", "unit_id": A, "cell":[4,3]}, {"kind":"escape", "unit_id":B, "cell":[0,0]}, {"kind":"protect"}]:
		var bad := fixture.duplicate(true)
		bad["objective"] = goal
		bad_cases.append(bad)
	for bad: Dictionary in bad_cases:
		check(not battle.configure(bad).is_empty(), "reject malformed encounter")
		check(battle.snapshot() == before, "bad configure atomic")
	var external := battle.skill("SK_FIST_BASIC")
	external["effects"].append("bleed")
	check(battle.skill("SK_FIST_BASIC")["effects"].is_empty(), "skill query detached")
	check(not battle.finish_turn(C), "cannot bypass command reducer")


func _test_movement() -> void:
	var data := duel()
	data["units"][1]["cell"] = [8, 7]
	data["blocked"] = [[2,1],[2,2],[2,3]]
	var battle := create(data)
	var before := battle.snapshot()
	var paths := battle.movement_paths(A)
	for destination: Vector2i in paths:
		var path: Array = paths[destination]
		check(path.size() - 1 <= 3 and path[0] == Vector2i(1,1) and path[-1] == destination, "BFS endpoints and budget")
		for index: int in range(1, path.size()):
			check(Grid.distance(path[index-1], path[index]) == 1 and battle.is_free(path[index]), "four-way unoccupied step")
	check(not paths.has(Vector2i(3,1)), "detour cannot exceed movement budget")
	check(not battle.preview_move(A, Vector2i(2,1))["ok"] and battle.snapshot() == before, "wall preview is read only")
	check(not battle.move_actor(A, Vector2i(8,7), battle.revision)["ok"] and battle.snapshot() == before, "occupied target rejected atomically")
	var preview := battle.preview_move(A, Vector2i(2,0))
	check(preview["cost"] == 2, "path length not Manhattan through obstacle")
	check(battle.move_actor(A, Vector2i(2,0), preview["revision"])["ok"], "confirm movement")
	check(battle.move_spent == 2 and battle.current_actor_id() == A, "movement retains action")
	before = battle.snapshot()
	check(not battle.move_actor(A, Vector2i(3,0), battle.revision)["ok"] and battle.snapshot() == before, "cannot refresh movement allowance")
	rest(battle)
	check(not battle.move_actor(A, Vector2i(3,0), battle.revision)["ok"], "cannot move after action")
	check(battle.retry() and same_except_revision(battle.snapshot(), create(data).snapshot()), "retry restores movement and queue")
	var trapped := duel()
	trapped["blocked"] = [[0,1],[1,0],[1,2]]
	battle = create(trapped)
	check(battle.movement_paths(A).size() == 1, "units and walls close narrow passage")


func _test_actions() -> void:
	var data := duel()
	data["units"][0]["qi"] = 0
	var battle := create(data)
	var before := battle.snapshot()
	check(not battle.preview_action(A, "SK_YUE_THRUST", Vector2i(2,1))["ok"], "insufficient qi blocked")
	check(battle.snapshot() == before, "preview does not consume qi")
	var preview := battle.preview_action(A, "SK_FIST_BASIC", Vector2i(2,1))
	check(preview["hits"][0]["actual"] == 3, "deterministic base formula")
	use(battle, "SK_FIST_BASIC", Vector2i(2,1))
	check(battle.unit(B)["hp"] == 37 and battle.unit(A)["qi"] == 1, "attack applies preview and recovers one qi")
	before = battle.snapshot()
	check(not battle.perform_action(A, "SK_FIST_BASIC", Vector2i(2,1), preview["revision"])["ok"] and battle.snapshot() == before, "repeat confirmation cannot duplicate action")
	rest(battle)
	use(battle, "SK_YUE_THRUST", Vector2i(2,1))
	check(battle.unit(A)["qi"] == 0, "martial qi cost applies once")
	data = duel()
	data["units"][1]["cell"] = [3,1]
	battle = create(data)
	check(battle.preview_action(A, "SK_YUE_THRUST", Vector2i(3,1))["hits"][0]["damage"] == 5, "second-cell thrust bonus")
	data["blocked"] = [[2,1]]
	battle = create(data)
	check(not battle.preview_action(A, "SK_YUE_THRUST", Vector2i(3,1))["ok"], "hard wall blocks ray")
	data = duel()
	battle = create(data)
	check(battle.preview_action(A, "SK_WATER_STEP", Vector2i(3,1))["ok"], "water step crosses occupied cell")
	use(battle, "SK_WATER_STEP", Vector2i(3,1))
	check(battle.unit(A)["cell"] == [3,1] and battle.unit(A)["statuses"].has("guard"), "movement skill and guard resolve together")
	rest(battle)
	check(not battle.preview_action(A, "SK_WATER_STEP", Vector2i(4,1))["ok"], "cooldown blocks next round")
	for index: int in range(4): rest(battle)
	check(battle.round_number == 4 and battle.preview_action(A, "SK_WATER_STEP", Vector2i(4,1))["ok"], "two full cooldown rounds expire")
	check(battle.unit(A)["qi"] == 5, "breathing caps qi")


func _test_statuses() -> void:
	var data := duel()
	data["units"][0]["skills"].append("SK_TRIP_WRIST")
	var battle := create(data)
	use(battle, "SK_TRIP_WRIST", Vector2i(2,1))
	check(battle.unit(B)["statuses"].has("broken"), "broken lasts through target action")
	use(battle, "EN_BLADE_PIN", Vector2i(1,1))
	check(not battle.unit(B)["statuses"].has("broken") and battle.move_budget == 1, "broken expires and pin reduces next movement")
	rest(battle)
	check(not battle.unit(A)["statuses"].has("pin"), "pin lasts exactly one action")
	use(battle, "SK_FIST_BASIC", Vector2i(1,1))
	check(not battle.unit(A)["statuses"].has("guard"), "guard consumed by hit")
	data = duel()
	data["units"][0]["move"] = 1
	battle = create(data)
	rest(battle)
	use(battle, "EN_BLADE_PIN", Vector2i(1,1))
	check(battle.move_budget == 0, "pin never negative")
	data = duel()
	data["units"][1]["skills"].append("EN_BOW_BLEED")
	battle = create(data)
	rest(battle)
	use(battle, "EN_BOW_BLEED", Vector2i(1,1))
	var hp: int = battle.unit(A)["hp"]
	rest(battle)
	check(battle.unit(A)["hp"] == hp-1, "bleed ignores guard after own action")
	rest(battle)
	rest(battle)
	check(battle.unit(A)["hp"] == hp-2 and not battle.unit(A)["statuses"].has("bleed"), "bleed exactly two completions")
	data = duel()
	var companion: Dictionary = fixture["units"][1].duplicate(true)
	companion["cell"] = [1,2]
	companion["agility"] = 1
	data["units"].append(companion)
	data["units"][1]["cell"] = [2,2]
	battle = create(data)
	use(battle, "SK_YUE_GUARD", Vector2i(1,1))
	var shielded := battle.preview_action(B, "SK_FIST_BASIC", Vector2i(1,2))
	check(shielded["hits"][0]["receiver"] == A and shielded["hits"][0]["actual"] == 0, "support redirects once and stacks explicit mitigation")
	use(battle, "SK_FIST_BASIC", Vector2i(1,2))
	check(battle.unit(C)["hp"] == 14 and battle.unit(A)["damage_received"] == 0, "no damage or ultimate farming on zero hit")
	check(not battle.unit(C)["statuses"].has("support"), "support consumed only once")


func _test_ultimates() -> void:
	var data := duel()
	data["units"][1]["power"] = 8
	var battle := create(data)
	check(not battle.preview_action(A, "ULT_SWORD", Vector2i(2,1))["ok"], "ultimate locked before condition")
	rest(battle)
	use(battle, "SK_FIST_BASIC", Vector2i(1,1))
	check(battle.unit(A)["damage_received"] == 7 and battle.preview_action(A, "ULT_SWORD", Vector2i(2,1))["ok"], "actual enemy damage unlocks ultimate")
	use(battle, "ULT_SWORD", Vector2i(2,1))
	check(battle.unit(A)["ultimate_used"], "ultimate use is recorded")
	rest(battle)
	check(not battle.preview_action(A, "ULT_SWORD", Vector2i(2,1))["ok"], "no repeated ultimate")
	check(battle.retry() and battle.unit(A)["damage_received"] == 0 and not battle.unit(A)["ultimate_used"], "retry resets all ultimate progress")
	# Internal damage reducer edge cases, not a playable debug reward path.
	Effects.hurt(battle, B, A, 1000, "test overkill")
	check(battle.unit(A)["damage_received"] == 16 and battle.unit(B)["takedowns"] == 1, "overkill counts actual HP and first defeat only")
	Effects.hurt(battle, B, A, 1000, "repeat")
	check(battle.unit(B)["takedowns"] == 1, "duplicate defeat gives no credit")
	battle.retry()
	Effects.hurt(battle, A, A, 2, "self")
	check(battle.unit(A)["damage_received"] == 0, "self damage cannot charge ultimate")


func _test_ai_and_outcomes() -> void:
	for attempt: int in range(3):
		var battle := create(fixture)
		var initial := battle.snapshot()
		var turns := 0
		while battle.outcome == "ongoing" and turns < 100:
			turns += 1
			var actor := battle.current_actor_id()
			if battle.unit(actor)["team"] == "enemy":
				var plan := AI.plan(battle, actor)
				check(plan == AI.plan(battle, actor), "AI tie breaking deterministic")
				check(AI.take_turn(battle)["ok"], "real enemy AI turn resolves")
			else:
				var plan := AI.plan(battle, actor, true)
				if plan["destination"] != Grid.cell_of(battle.unit(actor)):
					check(battle.move_actor(actor, plan["destination"], battle.revision)["ok"], "baseline player approach")
				use(battle, plan["skill_id"], plan["target"])
		check(battle.outcome == "victory" and turns < 100, "default encounter winnable using basic attacks/breath, no ultimates")
		check(battle.retry() and same_except_revision(battle.snapshot(), initial), "full battle retry restores snapshot")
		var result := battle.result()
		result["units"].clear()
		check(battle.unit_ids().size() == 4, "structured result detached")
	var data := duel()
	data["objective"] = {"kind":"escape", "unit_id":A, "cell":[1,3]}
	var battle := create(data)
	check(battle.move_actor(A, Vector2i(1,3), battle.revision)["ok"] and battle.outcome == "victory" and battle.unit(B)["hp"] > 0, "escape wins without clearing enemies")
	var old_revision := battle.revision
	check(battle.retry(), "escape retry")
	check(not battle.move_actor(A, Vector2i(1,3), old_revision)["ok"], "prior attempt preview invalidated")
	data = duel()
	data["units"][0]["hp"] = 1
	data["units"][1]["power"] = 20
	battle = create(data)
	var defeat_initial := battle.snapshot()
	for attempt: int in range(3):
		rest(battle)
		use(battle, "SK_FIST_BASIC", Vector2i(1,1))
		check(battle.outcome == "defeat" and battle.current_actor_id().is_empty(), "all allies down ends battle")
		check(battle.retry() and battle.unit(A)["hp"] == 1, "retry restores configured HP not maximum")
		check(same_except_revision(battle.snapshot(),defeat_initial), "three actual defeat/retry cycles fully restore state")
	check(not AI.intent(battle, B).has("plan"), "default intent never reveals exact target")
