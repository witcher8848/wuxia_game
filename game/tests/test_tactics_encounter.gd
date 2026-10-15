extends SceneTree
## Production tactical trial, legal player commands and production enemy turns.
## No writes to resource JSON and no private HP/qi/position edits in playthroughs.
const TrialScene = preload("res://game/presentation/battle/combat_v1_trial.tscn")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const E := "ENEMY_CATCHER"
var checks := 0
var failures: Array[String] = []
var trial: Node2D
var session: Node
var raw: Dictionary
var archetypes: Dictionary
var profiles: Dictionary
var seed: Dictionary
var metrics: Array[Dictionary] = []


func _initialize() -> void:
	create_timer(170).timeout.connect(func() -> void: printerr("TACTICS_ENCOUNTER_FAIL watchdog"); quit(1))
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("TACTICS_ENCOUNTER_FAIL ", label)


func _run() -> void:
	var packed := FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args():
		check(packed, "actual exported resources only")
		if not packed: quit(1); return
	session = root.get_node("GameSession")
	trial = TrialScene.instantiate()
	root.add_child(trial)
	await process_frame
	raw = JSON.parse_string(FileAccess.get_file_as_string(trial.DATA_PATH))
	archetypes = JSON.parse_string(FileAccess.get_file_as_string(trial.ARCHETYPES_PATH))
	profiles = JSON.parse_string(FileAccess.get_file_as_string(trial.PROFILES_PATH))
	seed = session.martial_configuration()["state"]
	_validation()
	_nearest_and_area()
	for scenario: int in range(2): await _two_round_roles(scenario)
	await _production_sweep_window()
	for external: Array in [["SK_YUE_THRUST","SK_TRIP_WRIST","SK_YUE_CROSSCUT"],["SK_YUE_THRUST","SK_YUE_GUARD","SK_YUE_CROSSCUT"]]:
		for scenario: int in range(2): await _play_loadout(external,scenario)
	check(metrics.size() == 4, "two genuinely distinct loadouts played in both scenes")
	if metrics.size() == 4:
		check(metrics[0]["skills"] != metrics[2]["skills"], "clear playstyles actually use different commands, not just menu labels")
		check(metrics[1]["support_used"] == 0 and metrics[3]["support_used"] > 0, "protection support is a real equipped action that attack kit lacks")
		check(metrics[0]["hp_remaining"] != metrics[2]["hp_remaining"] or metrics[0]["actions"] != metrics[2]["actions"] or metrics[0]["qi_spent"] != metrics[2]["qi_spent"], "clear equipment changes observable HP/turn/resource cost")
		check(metrics[1]["protected_hp"] != metrics[3]["protected_hp"] or metrics[1]["hero_hp"] != metrics[3]["hero_hp"], "protection equipment changes actual HP allocation/risk")
		check(metrics[0]["protected_hp"] > metrics[2]["protected_hp"] and metrics[0]["qi_spent"] > metrics[2]["qi_spent"], "clear breaking setup preserves more companion HP at a real qi price")
		check(metrics[3]["protected_hp"] > metrics[1]["protected_hp"] and metrics[3]["hero_hp"] < metrics[1]["hero_hp"], "support kit really protects carrier by taking more personal damage")
	root.remove_child(trial)
	trial.queue_free()
	await process_frame
	check(not session.combat_active(), "production wrapper releases ownership after tests")
	print("TACTICS_ENCOUNTER: %d checks, %d failures" % [checks,failures.size()])
	if failures.is_empty(): print("TACTICS_ENCOUNTER_PASS checks=%d packed=%s configurations=%d" % [checks,str(packed),metrics.size()])
	quit(0 if failures.is_empty() else 1)


func _definition(kind: String, data: Dictionary = {}) -> Dictionary:
	return trial.definition_from_data(kind,seed,raw if data.is_empty() else data,archetypes,profiles)


func _validation() -> void:
	var before: Dictionary = session.state.to_dict()
	var original := JSON.stringify([raw,archetypes,profiles,seed])
	var clear: Dictionary = _definition("eliminate")
	var protect: Dictionary = _definition("survive")
	check(clear["error"].is_empty() and protect["error"].is_empty(), "both actual tactical definitions assemble")
	var battle := CombatEncounter.new()
	check(battle.configure(clear["definition"]).is_empty(), "actual clear definition validates in domain")
	check(battle.unit(B)["guard"] == 3 and battle.skill("EN_BLADE_PIN")["effects"] == ["broken"], "armored pressure enemy really breaks posture")
	check(battle.unit(E)["move"] == 4 and battle.unit(E)["power"] == 1 and battle.ai_profile(E)["low_hp_guard_threshold"] == 0, "capture is mobile/low-damage and does not low-HP turtle")
	check(battle.unit(E)["ai_target_ids"] == [A], "clear capture is bound to actual hero carrier")
	check(battle.configure(protect["definition"]).is_empty() and battle.unit(E)["ai_target_ids"] == [C], "protect scene binds actual protected carrier")
	check(clear["definition"]["units"][0]["cell"] != protect["definition"]["units"][0]["cell"], "scene deployment genuinely changes")
	var reordered := raw.duplicate(true)
	reordered["allies"].reverse()
	var swapped: Dictionary = _definition("survive",reordered)
	var swapped_battle := CombatEncounter.new()
	check(swapped["error"].is_empty() and swapped_battle.configure(swapped["definition"]).is_empty(), "tactical assembly remains ally-array-order independent")
	check(swapped_battle.unit(A)["loadout"] == seed["loadout"] and not swapped_battle.unit(C).has("loadout"), "only real hero receives confirmed martial slots")
	var cases: Array[Dictionary] = []
	for change: Dictionary in [{"deployment":[]},{"deployment":{"MISSING":[1,1]}},{"deployment":{A:"1,1"}},{"ai_targets":[]},{"ai_targets":{E:[]}},{"ai_targets":{E:[C,C]}},{"ai_targets":{E:["MISSING"]}},{"ai_targets":{E:[B]}},{"ai_targets":{A:[C]}},{"ai_targets":{"MISSING":[C]}},{"objective":{"kind":"survive","rounds":"3","protected_unit_id":C}},{"title":null},{"description":null}]:
		var bad := raw.duplicate(true)
		bad["scenarios"][1].merge(change,true)
		cases.append(bad)
	for member: Variant in [null,"enemy",{}]:
		var bad := raw.duplicate(true)
		bad["enemies"][0] = member
		cases.append(bad)
	for count: int in [0,1,2,4]:
		var bad := raw.duplicate(true)
		while bad["enemies"].size() > count: bad["enemies"].pop_back()
		while bad["enemies"].size() < count: bad["enemies"].append(raw["enemies"][0].duplicate(true))
		cases.append(bad)
	for change: Dictionary in [{"id":"OTHER"},{"id":C},{"team":"enemy"},{"team":null}]:
		var bad := raw.duplicate(true)
		bad["allies"][0].merge(change,true)
		cases.append(bad)
	for bad: Dictionary in cases:
		var input_before := JSON.stringify(bad)
		var rejected: Dictionary = _definition("survive",bad)
		check(not rejected["error"].is_empty() and rejected["definition"].is_empty(), "invalid tactical override explicitly rejected")
		check(JSON.stringify(bad) == input_before and session.state.to_dict() == before and not session.combat_active(), "bad configuration changes neither input nor state/ownership")
	check(JSON.stringify([raw,archetypes,profiles,seed]) == original, "actual definition sources remain immutable")
	var changed := raw.duplicate(true)
	changed["scenarios"][1]["objective"]["rounds"] = 5
	changed["scenarios"][1]["title"] = "五轮护证"
	changed["scenarios"][1]["description"] = "完整五轮；携卷同伴倒地即失败。"
	var table: Dictionary = trial._scenario_table(changed)
	check(table["error"].is_empty() and table["scenarios"][1]["title"] == "五轮护证" and table["scenarios"][1]["objective"]["rounds"] == 5, "view contract reads configured title/description/objective rather than fixed three-round labels")


func _nearest_and_area() -> void:
	var data := raw.duplicate(true)
	data["scenarios"][0]["deployment"].merge({A:[7,4],C:[5,6],B:[6,6]},true)
	var prepared: Dictionary = _definition("eliminate",data)
	var battle := CombatEncounter.new()
	check(prepared["error"].is_empty() and battle.configure(prepared["definition"]).is_empty(), "nearest policy fixture uses legal public configuration")
	var before := battle.snapshot()
	var forecast := battle.forecast_turn(B)
	var plan: Dictionary = AI.plan(forecast,B)
	check(AI.intent(forecast,B,false,true).get("priority_target") == C and plan["target"] == Grid.cell_of(battle.unit(C)), "nearest is chosen from starting distance, not two hypothetical adjacent destinations")
	check(battle.snapshot() == before and not AI.intent(forecast,B,false,true).has("plan"), "public policy target neither mutates state nor leaks uncommitted plan")
	check(not AI.intent(forecast,B).has("priority_target"), "ordinary legacy query preserves original non-target disclosure contract")
	data = raw.duplicate(true)
	data["scenarios"][0]["deployment"].merge({A:[5,2],C:[5,4],B:[6,3]},true)
	var area_archetypes := archetypes.duplicate(true)
	area_archetypes["EN_YAMEN_BLADE"]["skills"] = ["SK_YUE_CROSSCUT"]
	var area_profiles := profiles.duplicate(true)
	area_profiles["AI_PRESSURE"]["skill_priority"] = ["SK_YUE_CROSSCUT","SK_FIST_BASIC"]
	area_profiles["AI_PRESSURE"]["effect_priority"] = ["pin"]
	prepared = trial.definition_from_data("eliminate",seed,data,area_archetypes,area_profiles)
	check(prepared["error"].is_empty() and battle.configure(prepared["definition"]).is_empty(), "area policy fixture is validated public data, not private reducer edits")
	forecast = battle.forecast_turn(B)
	plan = AI.plan(forecast,B)
	var preview := Actions.preview(forecast,B,plan["skill_id"],plan["target"],plan["destination"])
	check(plan["skill_id"] == "SK_YUE_CROSSCUT" and preview["hits"].size() == 2 and forecast.unit_at(plan["target"]).is_empty(), "explicit AI evaluates all actual hits and selects empty-center front arc")


func _start(external: Array, scenario: int) -> bool:
	if trial.phase == "battle": trial.return_to_selection()
	session.start_new_game()
	var selected: Dictionary = seed["loadout"].duplicate(true)
	selected["external"] = external.duplicate()
	check(session.set_martial_loadout(selected) == OK, "actual session accepts selected three-slot kit")
	trial.selected_scenario = scenario
	trial.start_trial()
	check(trial.phase == "battle" and session.combat_active() and trial.battle.unit_ids().size() == 5, "actual production entry starts selected tactical battle")
	if trial.phase != "battle": return false
	trial.screen.auto_ai = false
	for ally: Dictionary in raw["allies"]:
		check(trial.battle.unit(ally["id"])["hp"] == ally["hp"] and trial.battle.unit(ally["id"])["max_hp"] == ally["max_hp"], "playthrough HP exactly authored initial resources, never hidden aid")
	return true


func _enemy_turn() -> Dictionary:
	var battle: CombatEncounter = trial.battle
	var actor := battle.current_actor_id()
	var plan := AI.plan(battle,actor)
	var row := {"round":battle.round_number,"actor":actor,"origin":Grid.cell_of(battle.unit(actor)),"priority":AI.intent(battle,actor,false,true).get("priority_target",""),"plan":plan.duplicate(true)}
	check(not plan.is_empty(), "enemy has legal explicit-profile plan")
	var preview := Actions.preview(battle,actor,plan["skill_id"],plan["target"],plan["destination"])
	var revision: int = battle.revision
	trial.screen.auto_ai = true
	trial.screen._process(0.9)
	trial.screen.auto_ai = false
	check(battle.revision > revision and trial.screen.message.is_empty(), "real production enemy dispatcher executes planned movement/action")
	row["actual_destination"] = Grid.cell_of(battle.unit(actor))
	row["actual_skill"] = battle.unit(actor)["last_action"]
	row["effects_confirmed"] = []
	for hit: Dictionary in preview.get("hits",[]):
		for effect: String in preview.get("effects",[]):
			if battle.unit(hit["receiver"])["statuses"].has(effect): row["effects_confirmed"].append(effect)
	check(row["actual_destination"] == plan["destination"] and row["actual_skill"] == plan["skill_id"], "production dispatcher executes that actual policy without hidden reassignment")
	return row


func _two_round_roles(scenario: int) -> void:
	if not _start(["SK_YUE_THRUST","SK_YUE_GUARD","SK_YUE_CROSSCUT"],scenario): return
	var before: Dictionary = session.state.to_dict()
	var roles: Dictionary = {B:[],E:[]}
	var actions := 0
	while trial.battle.outcome == "ongoing" and trial.battle.round_number <= 2 and actions < 20:
		var actor: String = trial.battle.current_actor_id()
		if trial.battle.unit(actor)["team"] == "ally":
			check(trial.battle.perform_action(actor,"SK_STICK_GUARD",Grid.cell_of(trial.battle.unit(actor)),trial.battle.revision)["ok"], "two-round role observation uses legal guard, never blocks enemy turns")
			trial.screen.actor_changed()
		else:
			var row := _enemy_turn()
			if roles.has(actor): roles[actor].append(row)
		actions += 1
		await process_frame
	check(roles[B].size() == 2 and roles[E].size() == 2, "both enemy roles act in two consecutive actual production rounds")
	if roles[B].size() == 2 and roles[E].size() == 2:
		for index: int in range(2):
			check(roles[B][index]["priority"] != roles[E][index]["priority"], "near pressure and explicit pursuit choose different opponents on real round " + str(index+1))
			check(roles[B][index]["plan"]["destination"] != roles[E][index]["plan"]["destination"], "pressure and pursuit follow different real routes on round " + str(index+1))
		check(trial.battle.skill("EN_BLADE_PIN")["effects"] == ["broken"] and trial.battle.skill("EN_CATCHER_LOCK")["effects"] == ["pin"], "production role abilities have genuinely different effects")
		check("broken" in roles[B][0]["effects_confirmed"] and "pin" in roles[E][1]["effects_confirmed"], "real pressure and pursuit actually apply break and pin, not only metadata")
		check(trial.battle.unit(B)["last_action"] != trial.battle.unit(E)["last_action"], "real second-round role commands differ")
	print("TACTICS_ENEMY_ROLES scenario=%s traces=%s" % [raw["scenarios"][scenario]["id"],JSON.stringify(roles)])
	check(session.state.to_dict() == before, "observing both actual rounds changes no permanent fields")
	trial.return_to_selection()


func _support_plan(battle: CombatEncounter, actor: String) -> Dictionary:
	if actor != A or battle.objective["kind"] != "survive" or not "SK_YUE_GUARD" in battle.abilities(actor): return {}
	var threatened := false
	for enemy: String in battle.pending_ids():
		if battle.unit(enemy)["team"] != "enemy": continue
		var forecast := battle.forecast_turn(enemy)
		var plan := AI.plan(forecast,enemy)
		if plan.is_empty(): continue
		var preview := Actions.preview(forecast,enemy,plan["skill_id"],plan["target"],plan["destination"])
		for hit: Dictionary in preview.get("hits",[]):
			if hit["receiver"] == C and hit["actual"] > 0: threatened = true
	if not threatened: return {}
	var best: Dictionary = {}
	var cost := 999
	for destination: Vector2i in battle.movement_paths(actor):
		var preview := Actions.preview(battle,actor,"SK_YUE_GUARD",destination,destination)
		if not preview["ok"] or not C in preview["affected"]: continue
		var movement_cost: int = battle.movement_paths(actor)[destination].size()-1
		if movement_cost < cost:
			cost = movement_cost
			best = {"destination":destination,"skill_id":"SK_YUE_GUARD","target":destination}
	return best


func _production_sweep_window() -> void:
	# The actual clear formation creates a directional interception window after
	# both enemy roles advance. No unit coordinates/HP are altered for this check.
	if not _start(["SK_YUE_THRUST","SK_YUE_GUARD","SK_YUE_CROSSCUT"],0): return
	var before: Dictionary = session.state.to_dict()
	var actions := 0
	while trial.battle.round_number == 1 and trial.battle.outcome == "ongoing" and actions < 5:
		var actor: String = trial.battle.current_actor_id()
		if trial.battle.unit(actor)["team"] == "enemy": _enemy_turn()
		else:
			check(trial.battle.perform_action(actor,"SK_STICK_GUARD",Grid.cell_of(trial.battle.unit(actor)),trial.battle.revision)["ok"], "production interception opens by legal first-round holding actions")
			trial.screen.actor_changed()
		actions += 1
		await process_frame
	check(trial.battle.current_actor_id() == C and trial.battle.round_number == 2, "interception window comes from completing the real first round")
	check(trial.battle.perform_action(C,"SK_STICK_GUARD",Grid.cell_of(trial.battle.unit(C)),trial.battle.revision)["ok"], "companion legally holds its actual round-two turn")
	trial.screen.actor_changed()
	check(trial.battle.current_actor_id() == A and trial.battle.move_actor(A,Vector2i(3,4),trial.battle.revision)["ok"], "hero legally moves to intercept advancing enemy lanes")
	var preview: Dictionary = trial.battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,5))
	check(preview["ok"] and preview["hits"].size() == 2 and trial.battle.unit_at(Vector2i(3,5)).is_empty() and preview["qi_cost"] == 2, "real production board offers empty-center two-enemy sweep at real qi cost")
	check(trial.battle.perform_action(A,"SK_YUE_CROSSCUT",Vector2i(3,5),trial.battle.revision)["ok"], "real directional sweep legally executes")
	check(trial.battle.unit(B)["statuses"].has("pin") and trial.battle.unit(E)["statuses"].has("pin"), "real sweep simultaneously constrains pressure and pursuit routes")
	check(session.state.to_dict() == before, "actual production sweep changes no permanent route fields")
	print("TACTICS_PRODUCTION_SWEEP round=2 origin=(3,4) direction=(3,5) hits=%d cost=%d" % [preview["hits"].size(),preview["qi_cost"]])
	trial.return_to_selection()


func _player_plan(battle: CombatEncounter, actor: String) -> Dictionary:
	var support := _support_plan(battle,actor)
	if not support.is_empty(): return support
	var paths := battle.movement_paths(actor)
	if paths.is_empty(): paths[Grid.cell_of(battle.unit(actor))] = [Grid.cell_of(battle.unit(actor))]
	var best: Dictionary = {}
	var best_score := -100000
	for destination: Vector2i in paths:
		for identifier: String in battle.abilities(actor):
			var skill := battle.skill(identifier)
			if skill["target"] != "enemy": continue
			var targets: Array[Vector2i] = []
			if skill["area_pattern"] == "front_arc":
				for direction: Vector2i in Grid.DIRECTIONS: targets.append(destination+direction)
			else:
				for enemy: String in battle.unit_ids():
					if battle.unit(enemy)["team"] == "enemy" and battle.unit(enemy)["hp"] > 0: targets.append(Grid.cell_of(battle.unit(enemy)))
			for target: Vector2i in targets:
				var preview := Actions.preview(battle,actor,identifier,target,destination)
				if not preview["ok"]: continue
				var score: int = 10000 - int(skill["qi_cost"])*5 - (paths[destination].size()-1)*2 + int(preview["restore_qi"])*15
				for hit: Dictionary in preview["hits"]:
					score += int(hit["actual"])*40
					if hit["actual"] == battle.unit(hit["receiver"])["hp"]: score += 1000
					for effect: String in preview["effects"]:
						if not battle.unit(hit["receiver"])["statuses"].has(effect):
							# Broken reserves a +2 follow-up strike even across target
							# initiative; value that real near-term team opportunity.
							var armor: int = battle.unit(hit["receiver"])["guard"]
							var teammate: String = C if actor == A else A
							var can_follow: bool = battle.unit(teammate)["hp"] > 0 and Grid.distance(Grid.cell_of(battle.unit(teammate)),Grid.cell_of(battle.unit(hit["receiver"]))) <= int(battle.unit(teammate)["move"])+2
							if effect == "broken" and armor >= 2 and can_follow: score += 130
							else: score += 45
				if score > best_score:
					best_score = score
					best = {"destination":destination,"skill_id":identifier,"target":target}
	return best if not best.is_empty() else AI.plan(battle,actor)


func _play_loadout(external: Array, scenario: int) -> void:
	if not _start(external,scenario): return
	var before: Dictionary = session.state.to_dict()
	var actions := 0
	var used: Dictionary = {}
	var support_used := 0
	var qi_spent := 0
	var qi_restored := 0
	while trial.battle.outcome == "ongoing" and actions < 100:
		var actor: String = trial.battle.current_actor_id()
		if trial.battle.unit(actor)["team"] == "enemy": _enemy_turn()
		else:
			var plan := _player_plan(trial.battle,actor)
			check(not plan.is_empty(), "equipped player kit has a legal contextual action")
			if plan.is_empty(): break
			if plan["destination"] != Grid.cell_of(trial.battle.unit(actor)):
				check(trial.battle.move_actor(actor,plan["destination"],trial.battle.revision)["ok"], "planned player movement legally commits")
			var result: Dictionary = trial.battle.perform_action(actor,plan["skill_id"],plan["target"],trial.battle.revision)
			check(result["ok"], "planned player action legally commits without fixture aid")
			if actor == A:
				used[plan["skill_id"]] = int(used.get(plan["skill_id"],0))+1
				if plan["skill_id"] == "SK_YUE_GUARD": support_used += 1
				if result["ok"]:
					qi_spent += int(result["plan"]["qi_cost"])
					qi_restored += int(result["plan"]["restore_qi"])
			trial.screen.actor_changed()
		actions += 1
		await process_frame
	var battle: CombatEncounter = trial.battle
	check(battle.outcome == "victory" and actions < 100, "distinct equipped kit actually wins configured scenario")
	check(session.state.to_dict() == before, "whole production playthrough preserves route/HP/time/evidence/configuration")
	var row := {"scenario":raw["scenarios"][scenario]["id"],"external":external.duplicate(),"actions":actions,"round":battle.round_number,"hero_hp":battle.unit(A)["hp"],"protected_hp":battle.unit(C)["hp"],"hp_remaining":battle.unit(A)["hp"]+battle.unit(C)["hp"],"skills":used,"support_used":support_used,"qi_spent":qi_spent,"qi_restored":qi_restored,"outcome":battle.outcome}
	metrics.append(row)
	print("TACTICS_LOADOUT_PLAY ",JSON.stringify(row))
	trial.return_to_selection()
