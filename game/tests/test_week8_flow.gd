extends SceneTree
## Actual new-route services, legal battle, follow-up and persistence. No human
## duration claim. Phase mode proves only what the independent harness checks.
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const IO = preload("res://game/persistence/save_file_io.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var saves: Node
var content: Node
var fixture := ""
var phase := ""
var choice := "home"
var packed := false

func _initialize() -> void:
	create_timer(85).timeout.connect(func() -> void: printerr("WEEK8_FLOW_FAIL watchdog"); quit(124))
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); printerr("WEEK8_FLOW_FAIL ",label)
	return ok

static func same(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	saves = root.get_node("SaveService")
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--choice="): choice = argument.trim_prefix("--choice=")
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed,"actual PCK without source overlay")
	if fixture.is_empty(): fixture = "user://tests/week8_flow_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	if not check(fixture.begins_with("user://tests/week8_flow_") and fixture.trim_prefix("user://tests/").is_valid_identifier() and fixture.trim_prefix("user://tests/").length() <= 96,"isolated fixture"):
		quit(1); return
	saves.test_root = fixture
	if not check(content.last_error.is_empty(),"content preflight loaded all bilingual definitions"):
		quit(1); return
	if phase == "read": _read()
	elif phase == "write": _write()
	elif phase.is_empty():
		_impossible_states()
		for route: String in ["home","dock"]: _flow(route,true)
		for route: String in ["home","dock"]: _without_intel(route)
		_failure_recovery()
	else: check(false,"invalid phase")
	print("WEEK8_FLOW_PASS checks=%d failures=%d packed=%s phase=%s choice=%s pid=%d fixture=%s" % [checks,failures.size(),str(packed),phase,choice,OS.get_process_id(),fixture])
	quit(0 if failures.is_empty() else 1)

func _seed() -> void:
	session.start_new_game(true)
	check(session.state.world_flags.get("FACT_W8_ACTIVE",false),"production route explicitly activated")
	for step: String in ["STEP_RECEIVE_INDEX","STEP_ACCEPT_SEARCH"]:
		check(session.apply_investigation_step(step)["error"] == OK,"actual starting step "+step)

func _impossible_states() -> void:
	session.start_new_game(true)
	var before: Dictionary = session.state.to_dict()
	for flag: String in ["FACT_W8_FERRY_ASSISTANCE","FACT_BURIAL_MISMATCH","FACT_W8_REVIEWED","APPLIED_STEP_W8_COLLECT_GRAVES","APPLIED_STEP_W8_COMPARE_GRAVES","APPLIED_STEP_W8_REVIEW","APPLIED_STEP_W8_SUPPLEMENT","APPLIED_STEP_W8_SUPPLEMENT_BOATMAN"]:
		var impossible := GameState.from_dict(before)
		impossible.world_flags[flag] = true
		check(not content.validate_persistent_state(impossible).is_empty(),"orphan W8 progress refused "+flag)
		check(session.replace_state(impossible) != OK and same(session.state.to_dict(),before),"replacement is atomic on orphan "+flag)
		check(saves.save_game("manual_05",impossible) != OK,"no impossible W8 milestone written "+flag)
		impossible.world_flags[flag] = false
		check(content.validate_persistent_state(impossible).is_empty(),"false future marker remains legal "+flag)

func _flow(route: String, supplement: bool) -> void:
	_seed()
	var before: Dictionary = session.state.to_dict()
	var step := "STEP_INSPECT_BLANK" if route == "home" else "STEP_RECORD_BOATMAN"
	var denied: Dictionary = session.apply_investigation_step(step)
	check(denied.get("activity") == "@branch" and same(session.state.to_dict(),before),"first full investigation cannot bypass common choice")
	check(session.begin_story_encounter().get("activity") == "@branch","no-intel departure still requires explicit choice")
	var preview: Dictionary = session.preview_branch_choice(route)
	if not check(preview.get("error") == OK,"real anchor preview "+route): return
	var result: Dictionary = session.confirm_branch_choice(preview["token"])
	if not check(result.get("error") == OK and result.get("saved") == true,"choice automatically persists "+route): return
	check(not session.branch_required() and not session.pending_branch_save(),"successful saved commitment unlocks chosen investigation")
	if route == "home":
		check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] == OK,"home original acquired")
		check(session.resolve_inquiry("INQ_INDEX",["EV_INDEX_01","EV_BLANK_DEATH_01"])["error"] == OK,"home true index comparison")
		check(content.dialogue_entry("NPC_DOCK_WORKER",session.state) == "D_W8_BOATMAN_QUESTIONED","witness questioning visible on opposite route")
		check(session.apply_investigation_step("STEP_TAKE_FERRY_TOKEN")["error"] != OK,"first battle cannot gain opposite full opportunity")
	else:
		for acquire: String in ["STEP_RECORD_BOATMAN","STEP_TAKE_FERRY_TOKEN"]: check(session.apply_investigation_step(acquire)["error"] == OK,"witness route material "+acquire)
		check(session.resolve_inquiry("INQ_BOATMAN",["EV_FERRY_TOKEN_01"])["error"] == OK,"actual witness challenge")
		check(session.state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false),"known route and actual assistance are distinct")
		check(content.dialogue_entry("DOC_HOME_NOTE",session.state) == "D_W8_HOME_SEIZED","confiscation visible opposite route")
		check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] != OK,"cannot materialize confiscated original")
	check(saves.save_game("manual_01",session.state) == OK,"prebattle manual snapshot")
	before = session.state.to_dict()
	check(session.enter_region("SCENE_RIVER_DOCK","SPAWN_FROM_TOWN") == OK,"actual registered dock")
	check(session.mark_inspected("NPC_DOCK_WORKER") == OK,"actual registered encounter source")
	var start: Dictionary = session.begin_story_encounter()
	if not check(start.get("error") == OK,"committed route enters actual encounter"): return
	check(start["reveal"] == (route == "home") and start["ferry"] == (route == "dock"),"mutually exclusive real tactical advantages")
	var staged: Dictionary = session.state.to_dict()
	check(session.retry_story_encounter(start["token"]) == OK and same(session.state.to_dict(),staged),"retry does not spend time or replay opportunity")
	var battle: CombatEncounter = start["battle"]
	for turn: int in 180:
		if battle.outcome != "ongoing": break
		var actor := battle.current_actor_id()
		var plan := AI.plan(battle,actor)
		if not check(not plan.is_empty(),"legal battle plan"): break
		if plan["destination"] != Grid.cell_of(battle.unit(actor)): check(battle.move_actor(actor,plan["destination"],battle.revision)["ok"],"legal battle movement")
		check(battle.perform_action(actor,plan["skill_id"],plan["target"],battle.revision)["ok"],"legal battle action")
	if not check(battle.outcome == "victory","actual battle won"): return
	result = session.finish_story_encounter(start["token"])
	check(result.get("error") == OK and result.get("saved") == true,"settlement and followup automatically persist")
	var after: Dictionary = session.state.to_dict()
	check(session.finish_story_encounter(start["token"])["error"] != OK and same(session.state.to_dict(),after),"settlement cannot replay")
	check(session.apply_investigation_step("STEP_W8_COLLECT_GRAVES")["error"] == OK,"collect actual post-rescue evidence")
	after = session.state.to_dict()
	check(session.resolve_inquiry("INQ_W8_GRAVES",["EV_INDEX_01","EV_GRAVE_TAG_03"])["error"] != OK and same(session.state.to_dict(),after),"wrong comparison is free and side-effect free")
	check(session.resolve_inquiry("INQ_W8_GRAVES",["EV_GRAVE_TAG_03","EV_BURIAL_PAGE_01"])["error"] == OK,"grave records form real verified fact")
	check(session.apply_investigation_step("STEP_W8_REVIEW")["error"] == OK,"review settles first case and next objective")
	check(content.validate_persistent_state(session.state).is_empty(),"follow-up active/resolved state legal under intact battle receipt")
	check(content.dialogue_entry("NPC_DOCK_WORKER",session.state) == "D_W8_END","clear internal slice end")
	if supplement:
		if route == "dock":
			before = session.state.to_dict()
			check(session.apply_investigation_step("STEP_W8_SUPPLEMENT")["error"] != OK and same(session.state.to_dict(),before),"dock cannot award a remote home excerpt")
			check(session.enter_region("SCENE_HOME_COURTYARD","SPAWN_FROM_TOWN") == OK,"return to actual home source")
			check(session.mark_inspected("DOC_HOME_NOTE") == OK,"inspect actual home source")
			check(session.apply_investigation_step("STEP_W8_SUPPLEMENT")["error"] != OK,"historical inspection cannot replace proximity")
			check(session.update_player_position(Vector2(448,392)) == OK,"approach home desk")
			check(session.apply_investigation_step("STEP_W8_SUPPLEMENT")["error"] == OK,"short excerpt after confiscation")
			check(session.state.evidence_states.has("EV_HOME_EXTRACT_01") and not session.state.evidence_states.has("EV_BLANK_DEATH_01"),"excerpt remains distinct from missing original")
		else:
			before = session.state.to_dict()
			check(session.apply_investigation_step("STEP_W8_SUPPLEMENT_BOATMAN")["error"] != OK and same(session.state.to_dict(),before),"distant inspected witness cannot grant late testimony")
			var npc: Dictionary = content.world_npc(session.state,"NPC_DOCK_WORKER")["npc"]
			check(session.update_player_position(Vector2(npc["position"][0],npc["position"][1])+Vector2(0,40)) == OK,"approach boatman for actual correction")
			result = session.apply_investigation_step("STEP_W8_SUPPLEMENT_BOATMAN")
			check(result["error"] == OK and result.get("feedback_key") == "W8_BOATMAN_ADMITS_LATE","late investigation does not promise already missed advantage")
			check(not session.state.world_flags.get("FACT_W8_FERRY_ASSISTANCE",false),"late knowledge never regrants first-battle assistance")
		check(session.begin_story_encounter()["error"] != OK,"supplement cannot farm completed battle")
	check(saves.save_game("quick",session.state) == OK,"complete route final snapshot")
	var loaded: Dictionary = saves.load_game("quick",false)
	check(loaded.get("error") == OK and same(loaded["state"].to_dict(),session.state.to_dict()),"complete route source roundtrip")

func _failure_recovery() -> void:
	_seed()
	var preview: Dictionary = session.preview_branch_choice("home")
	if not check(preview.get("error") == OK,"failure test anchor created"): return
	for slot: String in ["auto_01","auto_02","auto_03"]:
		var future: Dictionary = saves._make_envelope(slot,session.state)
		future["schema_version"] = GameState.SCHEMA_VERSION+1
		check(IO.write_text(saves.slot_path(slot),JSON.stringify(future)) == OK,"owned isolated future slot blocks writing")
	var result: Dictionary = session.confirm_branch_choice(preview["token"])
	check(result.get("error") == OK and result.get("saved") == false and session.pending_branch_save(),"failed post-choice save retains whole committed state and clear pending status")
	var before: Dictionary = session.state.to_dict()
	check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] != OK and same(session.state.to_dict(),before),"pending save blocks subsequent quest changes")
	check(session.confirm_branch_choice(preview["token"])["error"] != OK and same(session.state.to_dict(),before),"save retry cannot reexecute choice")
	for slot: String in ["auto_01","auto_02","auto_03"]: check(IO.remove_file(saves.slot_path(slot)) == OK,"remove only future fixtures this test just created")
	check(session.retry_branch_save().get("saved") == true and not session.pending_branch_save(),"retry persists existing decision and clears lock")
	check(same(session.state.to_dict(),before),"retry writes but never changes world or replays rewards")

func _without_intel(route: String) -> void:
	_seed()
	var preview: Dictionary = session.preview_branch_choice(route)
	if not check(preview.get("error") == OK,"no-intel route still previews deliberate choice"): return
	if not check(session.confirm_branch_choice(preview["token"]).get("saved") == true,"no-intel deliberate choice is saved"): return
	check(session.enter_region("SCENE_RIVER_DOCK","SPAWN_FROM_TOWN") == OK and session.mark_inspected("NPC_DOCK_WORKER") == OK,"no-intel actual dock approach")
	var start: Dictionary = session.begin_story_encounter()
	if not check(start.get("error") == OK,"no-intel route can proceed "+route): return
	check(not start["reveal"] and not start["ferry"],"no-intel never gets unearned tactical advantages")
	var battle: CombatEncounter = start["battle"]
	for turn: int in 180:
		if battle.outcome != "ongoing": break
		var actor := battle.current_actor_id()
		var plan := AI.plan(battle,actor)
		if not check(not plan.is_empty(),"no-intel legal action plan"): break
		if plan["destination"] != Grid.cell_of(battle.unit(actor)): check(battle.move_actor(actor,plan["destination"],battle.revision)["ok"],"no-intel legal movement")
		check(battle.perform_action(actor,plan["skill_id"],plan["target"],battle.revision)["ok"],"no-intel legal action")
	check(battle.outcome == "victory","no-intel win remains achievable "+route)
	check(session.finish_story_encounter(start["token"]).get("saved") == true,"no-intel victory settles and autosaves")
	check(content.validate_persistent_state(session.state).is_empty(),"no-intel settled save remains valid")

func _write() -> void:
	_flow(choice,true)
	if not failures.is_empty(): return
	var anchor_path: String = saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")
	check(IO.write_text(fixture.path_join("expected.json"),JSON.stringify({"after":session.state.to_dict(),"writer":OS.get_process_id(),"anchor_hash":FileAccess.get_sha256(anchor_path)})) == OK,"persist whole final expectation")

func _read() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("expected.json")))
	if not check(data is Dictionary and data.get("writer") != OS.get_process_id(),"requires different successful writer process"): return
	var loaded: Dictionary = saves.load_game("quick",false)
	if not check(loaded.get("error") == OK,"cold complete route exact load"): return
	check(same(loaded["state"].to_dict(),data["after"]),"all choice/evidence/quest/ownership/martial/world fields cold restore")
	check(session.replace_state(loaded["state"]) == OK,"cold full route accepted by Session")
	check(FileAccess.get_sha256(saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")) == data["anchor_hash"],"first choice anchor unchanged after full route and restart")
	check(not session.pending_branch_save() and not session.branch_required(),"transient pending does not resurrect after valid persisted outcome")
	check(session.preview_branch_choice("dock" if choice == "home" else "home")["error"] != OK,"cold route cannot reselect")
	check(session.begin_story_encounter()["error"] != OK,"cold completed encounter cannot farm")
