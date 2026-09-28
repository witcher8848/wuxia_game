extends SceneTree
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const D := "ENEMY_BOW"
var fixture: Dictionary
var checks := 0
var failures: Array[String] = []


func _initialize() -> void: _run.call_deferred()


func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/tools/battle_lab/combat_encounter.json"))
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	_support_and_bleed()
	_ai_behavior()
	_ultimate_and_retry()
	_shapes_and_capacity()
	_escape_without_kills()
	print("COMBAT_EDGES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("COMBAT_EDGE_FAIL ", label)


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(data).is_empty(), "fixture valid")
	return battle


func close_data() -> Dictionary:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	data["units"][0]["cell"] = [1,1]
	data["units"][0]["agility"] = 8
	data["units"][1]["cell"] = [1,2]
	data["units"][1]["agility"] = 1
	data["units"][2]["cell"] = [2,2]
	data["units"][2]["agility"] = 6
	data["units"][3]["cell"] = [3,2]
	return data


func rest(battle: CombatEncounter) -> void:
	var actor := battle.current_actor_id()
	check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"], "legal rest")


func _support_and_bleed() -> void:
	var data := close_data()
	var battle := create(data)
	check(battle.perform_action(A,"SK_YUE_GUARD",Vector2i(1,1),battle.revision)["ok"], "grant adjacent support")
	Effects.apply_statuses(battle, C, A, ["support"])
	var plan := battle.preview_action(B,"SK_FIST_BASIC",Vector2i(1,2))
	check(plan["hits"].size()==1 and plan["hits"][0]["receiver"]==A, "mutual support cannot recurse")
	check(battle.perform_action(B,"SK_FIST_BASIC",Vector2i(1,2),battle.revision)["ok"], "mutual support strike resolves")
	check(battle.unit(A)["statuses"].has("support") and not battle.unit(C)["statuses"].has("support"), "only first target support consumed")
	rest(battle)
	rest(battle)
	check(battle.round_number==2 and not battle.unit(A)["statuses"].has("support"), "support expires at round boundary")
	check(not battle.unit(A)["statuses"].has("guard"), "guard not retained beyond next own start")
	battle = create(data)
	Effects.apply_statuses(battle, A, C, ["support"])
	check(battle.move_actor(A,Vector2i(0,0),battle.revision)["ok"], "protector can move away")
	rest(battle)
	plan = battle.preview_action(B,"SK_FIST_BASIC",Vector2i(1,2))
	check(plan["hits"][0]["receiver"]==C, "distant protector cannot intercept")
	# Bleed has an enemy source, triggers once per finished action, and removes
	# a dying actor before the next initiative advance (no extra turn granted).
	battle = create(data)
	Effects.hurt(battle,B,A,15,"fixture setup")
	Effects.apply_statuses(battle,B,A,["bleed"])
	rest(battle)
	check(battle.unit(A)["hp"]==0 and battle.current_actor_id()==B and not A in battle.pending_ids(), "bleed death skips dead actor without skipping next actor")
	check(battle.unit(B)["takedowns"]==1 and battle.outcome=="ongoing", "bleed defeat credit once; surviving companion continues")


func _ai_behavior() -> void:
	var data := close_data()
	var battle := create(data)
	rest(battle)
	var blade := AI.plan(battle,B)
	check(blade["skill_id"]=="EN_BLADE_PIN", "blade actively uses available control")
	check(AI.take_turn(battle)["ok"], "blade AI executes control")
	var bow := AI.plan(battle,D)
	check(bow["skill_id"]=="EN_BOW_BLEED", "bow actively uses available bleed")
	check(Grid.distance(bow["destination"], bow["target"])>=3, "bow seeks ranged separation rather than melee")
	check(AI.take_turn(battle)["ok"], "ranged plan legal after movement")
	check(AI.intent(battle,B)["kind"] != AI.intent(battle,D)["kind"], "archetypes visibly distinct")
	data["units"][2]["hp"] = 2
	battle = create(data)
	rest(battle)
	check(AI.plan(battle,B)["skill_id"]=="SK_STICK_GUARD", "low HP blade guards")
	check(AI.take_turn(battle)["ok"], "guard turn completes")
	while battle.current_actor_id()!=B: rest(battle)
	check(AI.plan(battle,B)["skill_id"]!="SK_STICK_GUARD", "blade cannot guard forever")
	# Fully isolated enemy: finite plan still completes an action.
	data = close_data()
	data["units"][2]["cell"] = [8,6]
	data["blocked"] = [[7,6],[9,6],[8,5],[8,7]]
	battle = create(data)
	rest(battle)
	check(AI.plan(battle,B)["skill_id"]=="ACT_BREATH" and AI.take_turn(battle)["ok"], "no legal attack/path still ends turn")


func _ultimate_and_retry() -> void:
	var data := close_data()
	data["units"][1]["agility"] = 9
	data["units"][2]["hp"] = 1
	data["units"][3]["cell"] = [2,3]
	data["units"][3]["hp"] = 4 # Ultimate remains lethal through the bow's guard.
	var battle := create(data)
	var initial := battle.snapshot()
	check(battle.perform_action(C,"SK_FIST_BASIC",Vector2i(2,2),battle.revision)["ok"], "companion defeats first enemy")
	check(battle.unit(C)["takedowns"]==1 and Actions.unavailable(battle,C,"ULT_FIST").is_empty(), "takedown condition unlocked")
	var before := battle.snapshot()
	check(not battle.perform_action(C,"ULT_FIST",Vector2i(2,3),battle.revision)["ok"] and battle.snapshot()==before, "kill does not grant same-turn ultimate")
	while battle.current_actor_id()!=C: rest(battle)
	check(battle.move_actor(C,Vector2i(1,3),battle.revision)["ok"], "approach remaining enemy")
	check(battle.perform_action(C,"ULT_FIST",Vector2i(2,3),battle.revision)["ok"], "unlocked companion ultimate executes")
	check(battle.unit(C)["ultimate_used"] and battle.unit(C)["takedowns"]==2, "ultimate defeat cannot reset used flag")
	for attempt: int in range(3):
		check(battle.retry(), "repeated retry")
		var restored := battle.snapshot()
		restored["revision"] = initial["revision"]
		check(restored==initial, "full snapshot restored including resources/statuses/cooldowns/order/progress")
		Effects.apply_statuses(battle,B,C,["broken","pin","bleed"])
		Effects.hurt(battle,B,C,100,"defeat fixture")
		Effects.hurt(battle,B,A,100,"defeat fixture")
		# Outcome reducer is exercised by actual public action in normal tests;
		# fixture damage here stresses retry from arbitrary mutated transient state.
	check(battle.retry(), "final retry after mutation")


func _shapes_and_capacity() -> void:
	var data := close_data()
	data["units"][0]["cell"] = [0,0]
	data["units"][1]["cell"] = [1,0]
	data["units"][2]["cell"] = [2,0]
	data["units"][3]["cell"] = [8,7]
	var battle := create(data)
	check(not battle.preview_action(A,"SK_YUE_THRUST",Vector2i(2,0))["ok"], "intermediate unit blocks straight strike")
	check(not battle.preview_action(A,"SK_FIST_BASIC",Vector2i(1,0))["ok"], "no friendly fire")
	check(not battle.preview_action(A,"SK_WATER_STEP",Vector2i(1,0))["ok"], "step cannot land on occupied cell")
	data["blocked"] = [[0,1],[1,1]]
	battle = create(data)
	check(not battle.preview_action(A,"SK_WATER_STEP",Vector2i(0,2))["ok"], "water step does not cross hard walls")
	for index: int in range(2):
		var extra: Dictionary = data["units"][0].duplicate(true)
		extra["id"] = "EXTRA_ALLY_" + str(index)
		extra["cell"] = [index+5,0]
		data["units"].append(extra)
	battle = create(data)
	check(battle.unit_ids().size()==6, "combat reducer supports four allies")
	var visited: Dictionary = {}
	for index: int in range(6):
		var actor := battle.current_actor_id()
		check(not visited.has(actor), "each of four allies/two enemies acts once")
		visited[actor] = true
		rest(battle)
	check(battle.round_number==2, "four-player capacity advances round")


func _escape_without_kills() -> void:
	var data := fixture.duplicate(true)
	data["objective"] = {"kind":"escape", "unit_id":A, "cell":[9,7]}
	var battle := create(data)
	var turns := 0
	while battle.outcome=="ongoing" and turns<60:
		turns += 1
		var actor := battle.current_actor_id()
		if battle.unit(actor)["team"]=="enemy":
			check(AI.take_turn(battle)["ok"], "escape encounters actual hostile AI")
			continue
		if actor==A:
			var paths := Grid.reachable(battle,A,64)
			check(paths.has(Vector2i(9,7)), "default escape objective reachable")
			if not paths.has(Vector2i(9,7)): break
			var path: Array = paths[Vector2i(9,7)]
			var destination: Vector2i = path[mini(battle.move_budget,path.size()-1)]
			check(battle.move_actor(A,destination,battle.revision)["ok"], "escape move respects path budget")
		if battle.outcome=="ongoing": rest(battle)
	check(battle.outcome=="victory" and battle.unit(B)["hp"]>0 and battle.unit(D)["hp"]>0, "full default escape scenario winnable without attacking/clearing enemies")
	print("ESCAPE_ROUTE turns=",turns," outcome=",battle.outcome," protagonist_hp=",battle.unit(A)["hp"])
