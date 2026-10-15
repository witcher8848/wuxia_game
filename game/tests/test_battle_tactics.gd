extends SceneTree
## Pure combat-rule verification. No UI, story settlement or style acceptance.
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const Loadout = preload("res://game/domain/battle/martial_loadout.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const D := "ENEMY_BOW"
const E := "ENEMY_CATCHER"
const S := "ENEMY_SUPPORTER"
const TACTICS_PATH := "res://game/content/data/battle_skills_tactics.json"
var checks := 0
var failures: Array[String] = []
var tactical: Array
var legacy: Array
var seed: Dictionary
var packed := false


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("BATTLE_TACTICS_FAIL ", label)


func make_unit(identifier: String, team: String, cell: Array, agility: int, armor := 1) -> Dictionary:
	return {"id":identifier,"name":identifier,"archetype":"ALLY_SWORD" if team == "ally" else "EN_TEST","team":team,"cell":cell,"hp":100,"max_hp":100,"qi":5,"max_qi":5,"agility":agility,"move":3,"power":3 if identifier == A else 2,"guard":armor,"skills":["SK_TRIP_WRIST","SK_YUE_GUARD","SK_WATER_STEP","SK_YUE_CROSSCUT","EN_BLADE_PIN"],"ultimate":{"skill_id":"ULT_SWORD","kind":"damage_received","threshold":99}}


func fixture(with_tactics := true, with_companion := true) -> Dictionary:
	var actor := make_unit(A,"ally",[2,2],9)
	actor["mastery"] = seed["mastery"].duplicate(true)
	actor["loadout"] = {"external":["SK_TRIP_WRIST","SK_YUE_THRUST","SK_YUE_CROSSCUT"],"movement":"SK_WATER_STEP","internal":"IN_BREATH_BASIC"}
	var units: Array = [actor,make_unit(B,"enemy",[3,2],6,2)]
	if with_companion: units.append(make_unit(C,"ally",[0,6],8))
	return {"size":[8,8],"blocked":[],"objective":{"kind":"eliminate"},"units":units,"skill_definitions":(tactical if with_tactics else legacy).duplicate(true)}


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(data).is_empty(),"valid tactical fixture")
	return battle


func use(battle: CombatEncounter, identifier: String, at: Vector2i) -> Dictionary:
	var actor := battle.current_actor_id()
	var before := battle.snapshot()
	var preview := battle.preview_action(actor,identifier,at)
	check(preview.get("ok",false),"legal tactical preview "+identifier)
	check(battle.snapshot() == before,"preview is read-only "+identifier)
	if not preview.get("ok",false): return {}
	var result := battle.perform_action(actor,identifier,at,battle.revision)
	check(result.get("ok",false) and result.get("plan") == preview,"same authority consumes exact preview "+identifier)
	check(battle.unit(actor)["qi"] == preview["qi_after"],"resource matches preview "+identifier)
	var seen: Dictionary = {}
	for hit: Dictionary in preview["hits"]:
		check(not seen.has(hit["receiver"]),"one sweep strikes an actual recipient only once")
		seen[hit["receiver"]] = true
		check(battle.unit(hit["receiver"])["hp"] == before["units"][hit["receiver"]]["hp"] - hit["actual"],"actual HP matches each predicted recipient "+hit["receiver"])
	return preview


func rest(battle: CombatEncounter) -> void:
	use(battle,"ACT_BREATH",Grid.cell_of(battle.unit(battle.current_actor_id())))


func wait_for(battle: CombatEncounter, identifier: String) -> void:
	var count := 0
	while battle.current_actor_id() != identifier and battle.outcome == "ongoing" and count < 40:
		rest(battle)
		count += 1
	check(battle.current_actor_id() == identifier,"bounded legal turn advance "+identifier)


func _definitions() -> void:
	check(Skills.validate(legacy).is_empty() and Skills.validate(tactical).is_empty(),"both distinct skill tables validate")
	var indexed := Skills.index(tactical)
	check(Loadout.catalog(indexed).size() == 6,"six real martial arts remain, no action padding")
	check(Skills.index(legacy).keys() == indexed.keys(),"tactical variant retains all original IDs")
	check(indexed["SK_YUE_THRUST"]["qi_cost"] == 2 and indexed["SK_YUE_THRUST"]["cooldown_rounds"] == 0,"thrust choice uses range/resources, not mandatory cooldown rotation")
	check(indexed["SK_STICK_GUARD"]["effects"] == ["guard"] and indexed["ACT_BREATH"]["effects"].is_empty(),"guard and recovery are not the same effect")
	check(indexed["EN_BLADE_PIN"]["effects"] == ["broken"] and indexed["EN_CATCHER_LOCK"]["effects"] == ["pin"],"pressure and capture have distinct effects without adding a sixth status")
	for patch: Dictionary in [{"range_pattern":"line"},{"target":"self"},{"range":2},{"range_pattern":"step","target":"empty"}]:
		var bad := tactical.duplicate(true)
		for skill: Dictionary in bad:
			if skill["id"] == "SK_YUE_CROSSCUT": skill.merge(patch,true)
		check(not Skills.validate(bad).is_empty(),"front arc rejects incompatible geometry "+str(patch))
	for mode: Variant in [null,true,1,"","after_turn"]:
		var bad := tactical.duplicate(true)
		for skill: Dictionary in bad:
			if skill["id"] == "SK_TRIP_WRIST": skill["broken_mode"] = mode
		check(not Skills.validate(bad).is_empty(),"next-hit mode strictly validates "+str(mode))
	var bad := tactical.duplicate(true)
	bad[0]["broken_mode"] = "next_hit"
	check(not Skills.validate(bad).is_empty(),"a mode cannot invent a broken effect")
	var battle := create(fixture())
	var before := battle.snapshot()
	var definition := fixture()
	definition["skill_definitions"] = bad
	check(not battle.configure(definition).is_empty() and battle.snapshot() == before,"bad optional field atomically preserves current encounter")


func _guard_breath_and_legacy() -> void:
	var damages: Array[int] = []
	for identifier: String in ["SK_STICK_GUARD","ACT_BREATH"]:
		var data := fixture()
		data["units"][0]["qi"] = 0
		var battle := create(data)
		use(battle,identifier,Vector2i(2,2))
		check(battle.unit(A)["statuses"].has("guard") == (identifier == "SK_STICK_GUARD"),"only guard protects before attack "+identifier)
		check(battle.unit(A)["qi"] == (0 if identifier == "SK_STICK_GUARD" else 2),"only breathing restores resources "+identifier)
		wait_for(battle,B)
		var attack := use(battle,"EN_BLADE_PIN",Vector2i(2,2))
		damages.append(attack["hits"][0]["actual"])
	check(damages == [1,3],"same actual enemy strike proves defending/recovering risk tradeoff")
	var old := create(fixture(false,false))
	use(old,"ACT_BREATH",Vector2i(2,2))
	check(old.unit(A)["statuses"].has("guard") and old.unit(A)["statuses"]["guard"].size() == 3,"legacy breath and status dictionary retain old rules")
	var old_data := fixture(false,false)
	old_data["units"][0].erase("loadout")
	old_data["units"][0].erase("mastery")
	old_data["units"][0]["skills"] = ["SK_TRIP_WRIST","SK_YUE_THRUST"]
	old = create(old_data)
	use(old,"SK_TRIP_WRIST",Vector2i(3,2))
	check(not old.unit(B)["statuses"]["broken"].has("mode"),"legacy flat wrist has no new status flag")
	rest(old)
	check(not old.unit(B)["statuses"].has("broken"),"legacy broken still ends with target action")


func _range_and_resource() -> void:
	var near := create(fixture())
	var short := near.preview_action(A,"SK_YUE_THRUST",Vector2i(3,2))
	check(short["hits"][0]["damage"] == 2 and near.preview_action(A,"SK_FIST_BASIC",Vector2i(3,2))["hits"][0]["damage"] == 3,"adjacent thrust is weaker and dearer than basic")
	var data := fixture(false)
	data["units"][1]["cell"] = [4,2]
	var old := create(data)
	check(old.preview_action(A,"SK_YUE_THRUST",Vector2i(4,2))["qi_cost"] == 1,"legacy table keeps original cost")
	data["skill_definitions"] = tactical.duplicate(true)
	var battle := create(data)
	var first := use(battle,"SK_YUE_THRUST",Vector2i(4,2))
	check(first["hits"][0]["damage"] == 5 and first["qi_after"] == 3 and first["cooldown_ready_round"] == 0,"two-cell burst spends two without forced cooldown")
	wait_for(battle,A)
	use(battle,"SK_YUE_THRUST",Vector2i(4,2))
	wait_for(battle,A)
	var before := battle.snapshot()
	check(not battle.preview_action(A,"SK_YUE_THRUST",Vector2i(4,2))["ok"],"two bursts leave insufficient qi for a third")
	check(not battle.perform_action(A,"SK_YUE_THRUST",Vector2i(4,2),battle.revision)["ok"] and battle.snapshot() == before,"failed burst does not silently spend or advance")
	check(battle.move_actor(A,Vector2i(3,2),battle.revision)["ok"],"closing distance permits a resource-building attack")
	use(battle,"SK_FIST_BASIC",Vector2i(4,2))
	check(battle.unit(A)["qi"] == 2,"basic actually rebuilds enough qi, sacrificing range and burst damage")
	check(not battle.perform_action(A,"ACT_BREATH",Vector2i(3,2),battle.revision)["ok"],"no extra action follows resource-building attack")


func _broken_window() -> void:
	var data := fixture()
	data["units"][2]["agility"] = 10
	data["units"][2]["cell"] = [3,3]
	var battle := create(data)
	rest(battle)
	use(battle,"SK_TRIP_WRIST",Vector2i(3,2))
	check(battle.unit(B)["statuses"]["broken"].get("mode") == "next_hit" and battle.unit(B)["statuses"]["broken"]["expires_round"] == 3,"wrist opens next-hit window through next complete round")
	rest(battle)
	check(battle.round_number == 2 and battle.current_actor_id() == C and battle.unit(B)["statuses"].has("broken"),"late protagonist mark survives enemy turn for earlier companion next round")
	var follow := use(battle,"SK_FIST_BASIC",Vector2i(3,2))
	check(follow["hits"][0]["damage"] == 4 and not battle.unit(B)["statuses"].has("broken"),"first actual follow-up receives minus-two armor and consumes mark")
	var second := use(battle,"SK_FIST_BASIC",Vector2i(3,2))
	check(second["hits"][0]["damage"] == 3,"second hit cannot reuse consumed break")
	# Consume an older mark before applying this hit's fresh mark, rather than
	# accidentally erasing the newly applied effect.
	battle = create(data)
	use(battle,"SK_TRIP_WRIST",Vector2i(3,2))
	var replaced := use(battle,"SK_TRIP_WRIST",Vector2i(3,2))
	check(replaced["hits"][0]["damage"] == 4 and battle.unit(B)["statuses"]["broken"]["source"] == A,"new break hit consumes old benefit then refreshes one new mark")
	# A window unused for the complete following round expires, not forever.
	battle = create(fixture(true,false))
	use(battle,"SK_TRIP_WRIST",Vector2i(3,2))
	rest(battle)
	check(battle.round_number == 2 and battle.unit(B)["statuses"].has("broken"),"mark remains at start of following round")
	rest(battle)
	check(battle.unit(B)["statuses"].has("broken"),"unused mark remains until complete following round ends")
	rest(battle)
	check(battle.round_number == 3 and not battle.unit(B)["statuses"].has("broken"),"unhit mark expires exactly after following complete round")


func arc_fixture() -> Dictionary:
	var data := fixture()
	data["units"].append(make_unit(D,"enemy",[3,1],5))
	data["units"].append(make_unit(E,"enemy",[3,3],4))
	return data


func _arc_geometry_and_hits() -> void:
	var battle := create(arc_fixture())
	var before := battle.snapshot()
	var cells := [Vector2i(3,2),Vector2i(3,1),Vector2i(3,3)]
	check(Actions.affected_cells(battle,A,"SK_YUE_CROSSCUT",Vector2i(3,2)) == cells,"three front-row cells are explicit ordered geometry")
	var preview := use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(preview["area_cells"] == cells and preview["hits"].size() == 3 and preview["affected"] == [B,D,E],"all three enemies are real hits/affected, not merely painted tiles")
	check(preview["qi_after"] == 3 and preview["cooldown_ready_round"] == 3,"one sweep pays once, one-full-round cooldown")
	for identifier: String in [B,D,E]: check(battle.unit(identifier)["statuses"].has("pin"),"each actual enemy recipient is pinned "+identifier)
	wait_for(battle,B)
	check(battle.move_budget == 1,"next actual enemy action has reduced movement budget")
	wait_for(battle,A)
	var cooling_before := battle.snapshot()
	check(battle.unit(A)["qi"] == 3 and not battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))["ok"] and battle.snapshot() == cooling_before,"sweep's own cooldown blocks despite sufficient qi without mutating state")
	check(battle.retry(),"tactical retry accepted")
	var retried := battle.snapshot()
	retried["revision"] = before["revision"]
	check(retried == before,"retry restores complete pre-sweep state, not its spent resources or marks")
	var data := arc_fixture()
	data["units"][1]["cell"] = [6,6]
	data["units"][2]["cell"] = [3,2]
	battle = create(data)
	var ally_hp: int = battle.unit(C)["hp"]
	preview = use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(preview["hits"].size() == 2 and not C in preview["affected"] and battle.unit(C)["hp"] == ally_hp and battle.unit(C)["statuses"].is_empty(),"friendly aim center permits side enemies but never harms/buffs that ally")
	data["units"][2]["cell"] = [0,6]
	battle = create(data)
	check(battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))["ok"],"empty adjacent aim center may orient a real side hit")
	data["units"][3]["cell"] = [6,1]
	data["units"][4]["cell"] = [6,3]
	battle = create(data)
	before = battle.snapshot()
	check(not battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))["ok"] and battle.snapshot() == before,"empty sweep cannot consume an action")
	check(Vector2i(3,2) in Actions.target_cells(battle,A,"SK_YUE_CROSSCUT"),"physical direction choices stay inspectable without an enemy")
	check(not battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(4,2))["ok"],"two-cell aim cannot extend sweep geometry")
	data = arc_fixture()
	for configured: Dictionary in data["units"]:
		if configured["team"] == "enemy": configured["hp"] = 1
	battle = create(data)
	preview = use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(battle.outcome == "victory" and battle.unit(A)["takedowns"] == 3 and battle.unit(A)["qi"] == 3,"three lethal hits count three actual takedowns but only one paid action")
	for identifier: String in [B,D,E]: check(not battle.unit(identifier)["statuses"].has("pin"),"dead sweep recipients do not acquire new pin "+identifier)


func _arc_walls_edges_and_projection() -> void:
	for forward: Vector2i in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
		var data := fixture(true,false)
		var target := Vector2i(2,2)+forward
		data["units"][1]["cell"] = [target.x,target.y]
		var battle := create(data)
		var left := Vector2i(forward.y,-forward.x)
		check(Actions.affected_cells(battle,A,"SK_YUE_CROSSCUT",target) == [target,target+left,target-left],"sweep rotates correctly "+str(forward))
		use(battle,"SK_YUE_CROSSCUT",target)
	var data := arc_fixture()
	data["units"][0]["cell"] = [0,0]
	data["units"][1]["cell"] = [1,0]
	data["units"][3]["cell"] = [1,1]
	data["units"][4]["cell"] = [6,3]
	var battle := create(data)
	check(Actions.affected_cells(battle,A,"SK_YUE_CROSSCUT",Vector2i(1,0)) == [Vector2i(1,0),Vector2i(1,1)],"board edge removes out-of-board side only")
	check(battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(1,0))["hits"].size() == 2,"edge still permits two real hits")
	check(not battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(0,-1))["ok"],"off-board forward center rejected")
	data = arc_fixture()
	data["units"][3]["cell"] = [6,1]
	data["blocked"] = [[3,1]]
	battle = create(data)
	check(Actions.affected_cells(battle,A,"SK_YUE_CROSSCUT",Vector2i(3,2)) == [Vector2i(3,2),Vector2i(3,3)],"side wall excludes its tile rather than hitting through it")
	check(battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))["hits"].size() == 2,"wall geometry and actual hit count agree")
	data["units"][1]["cell"] = [6,6]
	data["blocked"] = [[3,2]]
	battle = create(data)
	check(Actions.affected_cells(battle,A,"SK_YUE_CROSSCUT",Vector2i(3,2)).is_empty() and not battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))["ok"],"center wall blocks entire forward sweep")
	data = arc_fixture()
	data["units"][1]["cell"] = [3,4]
	data["units"][3]["cell"] = [3,3]
	data["units"][4]["cell"] = [3,5]
	battle = create(data)
	var before := battle.snapshot()
	var hypothetical := Actions.preview(battle,A,"SK_YUE_CROSSCUT",Vector2i(3,4),Vector2i(2,4))
	check(hypothetical["ok"] and battle.snapshot() == before,"hypothetical move+sweep does not mutate live state")
	check(battle.move_actor(A,Vector2i(2,4),battle.revision)["ok"],"hypothetical origin reached through real movement")
	var actual := battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,4))
	check(actual["hits"] == hypothetical["hits"] and actual["area_cells"] == hypothetical["area_cells"] and actual["qi_after"] == hypothetical["qi_after"],"hypothetical geometry/results agree with actual post-move preview")
	use(battle,"SK_YUE_CROSSCUT",Vector2i(3,4))


func _interception_and_once_per_receiver() -> void:
	var data := arc_fixture()
	var battle := create(data)
	Effects.apply_statuses(battle,B,D,["support"])
	Effects.apply_statuses(battle,B,E,["support"])
	Effects.apply_statuses(battle,B,B,["guard"])
	Effects.apply_statuses(battle,A,B,["broken"],"next_hit")
	var preview := use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(preview["hits"].size() == 1 and preview["affected"] == [B],"swept protector and two wards cannot multiply one actual recipient hit")
	check(preview["hits"][0]["damage"] == 2 and not battle.unit(B)["statuses"].has("guard") and not battle.unit(B)["statuses"].has("broken"),"shared receiver uses/consumes guard and next-hit exactly once")
	check(battle.unit(D)["hp"] == 100 and battle.unit(E)["hp"] == 100 and battle.unit(D)["statuses"].has("support") and battle.unit(E)["statuses"].has("support"),"skipped duplicate nominal hits leave their wards and HP untouched")
	data["units"][1]["hp"] = 1
	battle = create(data)
	Effects.apply_statuses(battle,B,D,["support"])
	Effects.apply_statuses(battle,B,E,["support"])
	preview = use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(preview["hits"].size() == 1 and preview["hits"][0]["actual"] == 1 and battle.unit(A)["takedowns"] == 1,"pre-cast once-per-recipient rule stays exact when protector dies")
	check(battle.unit(D)["hp"] == 100 and battle.unit(E)["hp"] == 100,"protector death does not invent unpreviewed later hits")
	# A ward can redirect outside the geometric area. The actual receiver is
	# still highlighted, struck and debuffed, never the nominal ward.
	data = arc_fixture()
	data["units"].append(make_unit(S,"enemy",[2,1],3,2))
	battle = create(data)
	Effects.apply_statuses(battle,S,D,["support"])
	Effects.apply_statuses(battle,A,D,["broken"],"next_hit")
	Effects.apply_statuses(battle,A,S,["broken"],"next_hit")
	preview = use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(preview["hits"].size() == 3 and preview["hits"][1]["receiver"] == S and not Vector2i(2,1) in preview["area_cells"] and S in preview["affected"],"outside-area protector is an explicit actual affected receiver")
	check(battle.unit(D)["hp"] == 100 and battle.unit(D)["statuses"].has("broken") and not battle.unit(D)["statuses"].has("pin") and not battle.unit(D)["statuses"].has("support"),"intercepted nominal ward retains its unused break and gets no new pin")
	check(not battle.unit(S)["statuses"].has("broken") and battle.unit(S)["statuses"].has("pin"),"actual interceptor consumes old mark and receives new effect")
	data = fixture(true,false)
	data["units"][1]["guard"] = 9
	battle = create(data)
	Effects.apply_statuses(battle,A,B,["broken"],"next_hit")
	Effects.apply_statuses(battle,B,B,["guard"])
	preview = use(battle,"SK_YUE_CROSSCUT",Vector2i(3,2))
	check(preview["hits"][0]["actual"] == 0 and not battle.unit(B)["statuses"].has("broken") and not battle.unit(B)["statuses"].has("guard") and battle.unit(B)["statuses"].has("pin"),"a mitigated contact still consumes the one-hit mark and guard then applies its own pin")
	# New break must follow actual receiver, including a fully mitigated hit.
	# S must be adjacent to B to intercept this single-target test.
	var single := fixture(true,false)
	single["units"].append(make_unit(S,"enemy",[3,3],4,2))
	battle = create(single)
	Effects.apply_statuses(battle,S,B,["support"])
	Effects.apply_statuses(battle,S,S,["guard"])
	preview = use(battle,"SK_TRIP_WRIST",Vector2i(3,2))
	check(preview["hits"][0]["actual"] == 0 and preview["hits"][0]["receiver"] == S and battle.unit(S)["statuses"]["broken"].get("mode") == "next_hit" and not battle.unit(B)["statuses"].has("broken"),"zero-damage intercepted contact applies fresh break only to actual receiver")


func _read_only_and_stale() -> void:
	var battle := create(arc_fixture())
	var before := battle.snapshot()
	var preview := battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))
	for _index in range(5): check(battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2)) == preview and battle.snapshot() == before,"repeat previews are deterministic and detached")
	var revision: int = preview["revision"]
	preview["hits"][0]["damage"] = 999
	preview["area_cells"].clear()
	preview["affected"].clear()
	check(battle.snapshot() == before and battle.preview_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2))["hits"][0]["damage"] == 2,"caller cannot mutate combat through multi-hit preview")
	check(battle.move_actor(A,Vector2i(2,3),battle.revision)["ok"],"legal move invalidates old sweep intent")
	before = battle.snapshot()
	check(not battle.perform_action(A,"SK_YUE_CROSSCUT",Vector2i(3,2),revision)["ok"] and battle.snapshot() == before,"stale sweep cannot spend qi or apply area status")
	var forecast := battle.forecast_turn(A)
	check(forecast != null and forecast.skill("SK_YUE_CROSSCUT")["area_pattern"] == "front_arc" and battle.snapshot() == before,"disposable forecast carries chosen tactics rules without changing live state")


func _run() -> void:
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args():
		check(packed,"real exported PCK, no source overlay")
		if not packed: quit(1); return
	tactical = JSON.parse_string(FileAccess.get_file_as_string(TACTICS_PATH))
	legacy = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	seed = Loadout.normalize_state({},tactical)["state"]
	_definitions()
	_guard_breath_and_legacy()
	_range_and_resource()
	_broken_window()
	_arc_geometry_and_hits()
	_arc_walls_edges_and_projection()
	_interception_and_once_per_receiver()
	_read_only_and_stale()
	print("BATTLE_TACTICS: %d checks, %d failures; rules only, not human tactical acceptance" % [checks,failures.size()])
	if failures.is_empty(): print("BATTLE_TACTICS_PASS checks=%d packed=%s" % [checks,str(packed)])
	quit(0 if failures.is_empty() else 1)
