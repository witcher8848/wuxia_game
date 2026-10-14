extends SceneTree
## Real production entry, production BattleScreen and player keyboard commands.
const TrialScene = preload("res://game/presentation/battle/combat_v1_trial.tscn")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
var trial: Node2D
var session: Node
var checks := 0
var failures: Array[String] = []
var captures := false
var packed := false
var captured: Array[String] = []
var exit_count := 0


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("WEEK6_TRIAL_FAIL ", label)


func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func same_non_martial(left: Dictionary, right: Dictionary) -> bool:
	left = left.duplicate(true)
	right = right.duplicate(true)
	left.erase("martial_states")
	right.erase("martial_states")
	return left == right


func install() -> bool:
	trial = TrialScene.instantiate()
	check(trial.has_signal("exit_requested"), "production trial scene compiles with its controller")
	if not trial.has_signal("exit_requested"): trial.queue_free(); return false
	trial.exit_requested.connect(func() -> void: exit_count += 1)
	root.add_child(trial)
	await process_frame
	check(trial.phase == "selection" and trial.startup_error.is_empty(), "production trial scene opens at goal selection")
	return trial.phase == "selection" and trial.startup_error.is_empty()


func capture(label: String) -> void:
	await process_frame
	if trial.phase in ["selection","quit"]:
		for node: Label in [trial.heading, trial.cards[0], trial.cards[1], trial.detail, trial.footer]:
			check(Rect2(0,0,640,360).encloses(node.get_rect()) and node.get_minimum_size().y <= node.size.y, label+" selection text fits viewport")
	elif trial.phase == "preparation":
		check(Rect2(0,0,640,360).encloses(trial.preparation.get_rect()), label+" preparation fits viewport")
		for row: Label in trial.preparation.rows: check(row.get_minimum_size().y <= row.size.y, label+" preparation rows fit")
	elif trial.phase == "battle":
		for node: Label in [trial.screen.heading,trial.screen.stats,trial.screen.menu,trial.screen.disabled_menu,trial.screen.detail,trial.screen.footer]:
			check(Rect2(0,0,640,360).encloses(node.get_rect()) and node.get_minimum_size().y <= node.size.y, label+" battle text fits viewport")
		check(not trial.screen.menu.get_rect().intersects(trial.screen.detail.get_rect()) and not trial.screen.detail.get_rect().intersects(trial.screen.footer.get_rect()), label+" command/detail/footer panels never overlap")
		if trial.screen.menu.get_rect().intersects(trial.screen.detail.get_rect()): print("WEEK6_TRIAL_LAYOUT ", label, " menu=", trial.screen.menu.get_rect(), " min=", trial.screen.menu.get_minimum_size(), " detail=", trial.screen.detail.get_rect(), " footer=", trial.screen.footer.get_rect())
	if not captures: return
	check(DisplayServer.get_name() != "headless", "native renderer required for trial screenshot")
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("WUXIA_CAPTURE_DIR")
	if directory.is_empty(): directory = "res://builds/qa"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "capture directory ready")
	var path := directory.path_join("week6_trial_"+label+".png")
	var screenshot := root.get_texture().get_image()
	check(screenshot.get_size() == Vector2i(640,360), "native trial screenshot logical dimensions")
	check(screenshot.save_png(path) == OK, "actual trial capture "+label)
	captured.append(label)


func _definition_validation() -> void:
	# Inject detached data, never rewrite res:// JSON. The same test runs from a
	# source checkout or the frozen PCK's production resources and controller.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(trial.DATA_PATH))
	var archetypes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/enemy_archetypes.json"))
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_ai_profiles.json"))
	var martial: Dictionary = session.martial_configuration()["state"]
	martial["loadout"] = {"external":["SK_TRIP_WRIST","SK_YUE_CROSSCUT"],"movement":"","internal":""}
	var before: Dictionary = session.state.to_dict()
	var inputs := JSON.stringify([raw, archetypes, profiles, martial])
	for kind: String in ["eliminate", "survive"]:
		var original: Dictionary = trial.definition_from_data(kind,martial,raw,archetypes,profiles)
		var swapped := raw.duplicate(true)
		swapped["allies"].reverse()
		var reordered: Dictionary = trial.definition_from_data(kind,martial,swapped,archetypes,profiles)
		check(original["error"].is_empty() and reordered["error"].is_empty(), "both legal allied-array orders accepted " + kind)
		var original_battle := CombatEncounter.new()
		var swapped_battle := CombatEncounter.new()
		check(original_battle.configure(original["definition"]).is_empty() and swapped_battle.configure(reordered["definition"]).is_empty(), "both ordered definitions pass actual domain " + kind)
		check(swapped_battle.unit("CHAR_PROTAGONIST")["loadout"] == martial["loadout"] and swapped_battle.unit("CHAR_PROTAGONIST")["mastery"] == martial["mastery"], "主角 ID receives selected configuration after reorder " + kind)
		check(swapped_battle.unit("CHAR_PROTAGONIST")["max_qi"] == 3 and swapped_battle.action_restore_qi("CHAR_PROTAGONIST","SK_FIST_BASIC") == 0, "reordered protagonist really runs unequipped passive rules " + kind)
		check(not swapped_battle.unit("CHAR_COMPANION").has("loadout") and swapped_battle.unit("CHAR_COMPANION")["skills"] == raw["allies"][1]["skills"], "reordered companion retains only its own fixed kit " + kind)
		check(original_battle.snapshot() == swapped_battle.snapshot(), "legal array reorder changes no actual encounter state " + kind)
	check(JSON.stringify([raw, archetypes, profiles, martial]) == inputs and session.state.to_dict() == before, "building both configurations mutates no inputs or persistent state")
	var detached: Dictionary = trial.definition_from_data("eliminate",martial,raw,archetypes,profiles)
	detached["definition"]["size"][0] = 1
	detached["definition"]["units"][0]["mastery"].clear()
	detached["definition"]["ai_profiles"].clear()
	check(JSON.stringify([raw, archetypes, profiles, martial]) == inputs, "returned board, martial and AI data own deep copies")
	var cases: Array = []
	for value: Variant in [null, [], "raw"]: cases.append([value, archetypes, profiles])
	for field: String in ["id","size","blocked","allies","enemies","scenarios"]:
		var bad := raw.duplicate(true)
		bad.erase(field)
		cases.append([bad, archetypes, profiles])
	for change: Dictionary in [{"id":null},{"id":""},{"size":"10,8"},{"size":[10]},{"size":[1.5,8]},{"blocked":null},{"blocked":[null]},{"blocked":[[1,"2"]]},{"allies":null},{"enemies":null},{"scenarios":null}]:
		var bad := raw.duplicate(true)
		bad.merge(change,true)
		cases.append([bad, archetypes, profiles])
	for scenarios: Array in [[null],["scenario"],[{}],[{"id":"eliminate"}],[{"objective":{"kind":"eliminate"}}],[{"id":1,"objective":{"kind":"eliminate"}}],[{"id":"eliminate","objective":[]}],[{"id":"eliminate","objective":{}}],[{"id":"eliminate","objective":{"kind":null}}]]:
		var bad := raw.duplicate(true)
		bad["scenarios"] = scenarios.duplicate(true)
		cases.append([bad, archetypes, profiles])
	var duplicate_scenario := raw.duplicate(true)
	duplicate_scenario["scenarios"].append(duplicate_scenario["scenarios"][0].duplicate(true))
	cases.append([duplicate_scenario, archetypes, profiles])
	for ally: Variant in [null, "ally", {}, {"id":"CHAR_PROTAGONIST","team":"ally"}]:
		var bad := raw.duplicate(true)
		bad["allies"][0] = ally
		cases.append([bad, archetypes, profiles])
	for change: Dictionary in [{"id":"OTHER_ALLY"},{"id":"CHAR_COMPANION"},{"id":null},{"team":"enemy"},{"team":null},{"archetype":null}]:
		var bad := raw.duplicate(true)
		bad["allies"][0].merge(change,true)
		cases.append([bad, archetypes, profiles])
	var duplicate_hero := raw.duplicate(true)
	duplicate_hero["allies"][1] = duplicate_hero["allies"][0].duplicate(true)
	cases.append([duplicate_hero, archetypes, profiles])
	for placement: Variant in [null,"enemy",{}, {"id":"ENEMY_BLADE"},{"archetype":"EN_YAMEN_BLADE"}]:
		var bad := raw.duplicate(true)
		bad["enemies"][0] = placement
		cases.append([bad, archetypes, profiles])
	for change: Dictionary in [{"id":null},{"archetype":null},{"archetype":"MISSING"},{"cell":null},{"cell":[6,"3"]}]:
		var bad := raw.duplicate(true)
		bad["enemies"][0].merge(change,true)
		cases.append([bad, archetypes, profiles])
	for value: Variant in [null, [], "archetypes"]: cases.append([raw,value,profiles])
	for value: Variant in [null, [], "profile"]: cases.append([raw,archetypes,value])
	var missing_archetype := archetypes.duplicate(true)
	missing_archetype.erase("EN_YAMEN_BLADE")
	cases.append([raw,missing_archetype,profiles])
	var malformed_archetype := archetypes.duplicate(true)
	malformed_archetype["EN_YAMEN_BLADE"] = "not a unit"
	cases.append([raw,malformed_archetype,profiles])
	for index: int in range(cases.size()):
		var item: Array = cases[index]
		var input_before := JSON.stringify(item)
		var result: Dictionary = trial.definition_from_data("eliminate",martial,item[0],item[1],item[2])
		check(not result["error"].is_empty() and result["definition"].is_empty(), "malformed adapter configuration returns explicit empty failure " + str(index))
		check(JSON.stringify(item) == input_before and session.state.to_dict() == before and trial.phase == "selection" and trial.battle == null and not session.combat_active(), "rejected adapter configuration is atomic and never starts/locks battle " + str(index))
	var unknown: Dictionary = trial.definition_from_data("unknown",martial,raw,archetypes,profiles)
	check(not unknown["error"].is_empty() and unknown["definition"].is_empty(), "unknown configured scenario returns explicit failure")
	# The adapter protects accesses without replacing the authoritative domain's
	# stronger semantic checks (out-of-board coordinates, resource limits, AI).
	var bad_semantic := raw.duplicate(true)
	bad_semantic["size"] = [0,8]
	var prepared: Dictionary = trial.definition_from_data("eliminate",martial,bad_semantic,archetypes,profiles)
	var guarded := CombatEncounter.new()
	check(prepared["error"].is_empty() and not guarded.configure(prepared["definition"]).is_empty(), "domain remains authoritative for semantic board validation")
	check(session.state.to_dict() == before and not session.combat_active(), "all pure configuration validation leaves session and ownership unchanged")
	print("WEEK6_TRIAL_CONFIGURATION_CASES bad=%d orders=2 scenarios=2 source_writes=0" % cases.size())


func _selection_and_preparation() -> void:
	var before: Dictionary = session.state.to_dict()
	await capture("selection")
	await key(KEY_RIGHT)
	check(trial.selected_scenario == 1 and trial.phase == "selection", "keyboard chooses three-round protection goal")
	await key(KEY_LEFT)
	check(trial.selected_scenario == 0 and session.state.to_dict() == before, "goal preview is read-only")
	await key(KEY_M)
	check(trial.phase == "preparation" and not session.combat_active(), "M opens reusable preparation while unlocked")
	await capture("preparation")
	await key(KEY_LEFT)
	check(session.state.to_dict() == before, "changing draft does not change persistent martial state")
	await key(KEY_ESCAPE)
	check(trial.phase == "selection" and session.state.to_dict() == before, "cancelled preparation discards draft")
	await key(KEY_M)
	await key(KEY_E)
	check(trial.phase == "preparation" and session.martial_configuration()["error"].is_empty(), "E applies only validated equipment through GameSession")
	check(same_non_martial(before,session.state.to_dict()), "preparation application changes no HP, time, evidence, quests or inventory")
	await key(KEY_ESCAPE)
	check(trial.phase == "selection", "confirmed equipment returns to goal selection")
	# A concurrently owned battle token must not be stolen by a second entry.
	var foreign_token: String = session.lock_martial_trial()
	check(not foreign_token.is_empty(), "foreign trial owns a valid session token")
	before = session.state.to_dict()
	await key(KEY_E)
	check(trial.phase == "selection" and trial.trial_token.is_empty() and session.combat_active(), "busy session prevents a second real battle without stealing its token")
	check(session.state.to_dict() == before, "denied concurrent entry leaves permanent state untouched")
	check(session.unlock_martial_trial(foreign_token), "only the correct foreign owner can unlock its trial")


func _entry_lock_and_retry() -> void:
	var before: Dictionary = session.state.to_dict()
	await key(KEY_E)
	check(trial.phase == "battle" and trial.battle.unit_ids().size() == 5 and session.combat_active(), "E starts real two-versus-three battle and acquires lock")
	trial.screen.auto_ai = false
	check(trial.battle.objective["kind"] == "eliminate", "selected clear objective, not a legacy escape mode")
	check(trial.screen.board.hero_visual.manifest_path() == Hero.ACTIVE_DATA_PATH and Hero.ACTIVE_DATA_PATH == Hero.IMAGEGEN_DATA_PATH, "production trial board uses accepted new character renderer")
	var martial: Dictionary = session.martial_configuration()["state"]
	check(trial.battle.unit("CHAR_PROTAGONIST")["loadout"] == martial["loadout"], "trial actually adopts confirmed protagonist slots")
	check(not "IN_BREATH_BASIC" in trial.battle.abilities("CHAR_PROTAGONIST"), "passive internal art is not a battle command")
	check(session.set_martial_loadout(martial["loadout"]) == ERR_BUSY, "active trial cannot reconfigure permanent equipment")
	check(session.replace_state(GameState.from_dict(before)) == ERR_BUSY, "state replacement cannot bypass active trial lock")
	check(root.get_node("SaveService").save_game("manual_01",session.state) == ERR_BUSY, "active trial cannot serialize transient state")
	check(session.state.to_dict() == before, "starting and rejected commands preserve all persistent state")
	var original: Dictionary = trial.battle.snapshot()
	await key(KEY_M)
	check(trial.phase == "battle" and trial.battle.snapshot() == original, "M cannot open equipment during battle")
	await key(KEY_F2)
	check(trial.screen.mode == "trial_return" and trial.battle.objective["kind"] == "eliminate", "F2 opens explicit return confirmation, never escape scenario")
	await key(KEY_ESCAPE)
	check(trial.screen.mode == "command" and trial.battle.snapshot() == original, "cancel F2 preserves full battle")
	await player_action(AI.plan(trial.battle,trial.battle.current_actor_id()))
	check(trial.battle.snapshot() != original, "real player action changes transient encounter")
	check(trial.battle.current_actor_id() == "CHAR_PROTAGONIST" and trial.screen.options().size() == 9, "actual protagonist exposes complete three-external loadout command list")
	await capture("eliminate")
	await key(KEY_R)
	check(trial.screen.mode == "retry", "R asks confirmation instead of restarting immediately")
	await key(KEY_E)
	var restored: Dictionary = trial.battle.snapshot()
	restored["revision"] = original["revision"]
	check(restored == original and session.combat_active(), "retry restores exact war-start configuration and retains lock")
	check(session.state.to_dict() == before, "retry never alters persistent state")


func move_cursor(target: Vector2i) -> void:
	for _step: int in range(64):
		if trial.screen.cursor == target: return
		if trial.screen.cursor.x < target.x: await key(KEY_RIGHT)
		elif trial.screen.cursor.x > target.x: await key(KEY_LEFT)
		elif trial.screen.cursor.y < target.y: await key(KEY_DOWN)
		else: await key(KEY_UP)
	check(false, "bounded actual keyboard target navigation")


func select_command(index: int) -> void:
	for _step: int in range(32):
		if trial.screen.selection == index: return
		await key(KEY_DOWN)
	check(false, "bounded actual keyboard command navigation")


func player_action(planned: Dictionary) -> void:
	if planned.is_empty(): check(false, "real player planning must find legal turn"); return
	var actor: String = trial.battle.current_actor_id()
	check(trial.battle.unit(actor)["team"] == "ally", "keyboard policy only controls allied actors")
	if planned["destination"] != Grid.cell_of(trial.battle.unit(actor)):
		await select_command(0)
		await key(KEY_E)
		check(trial.screen.mode == "move", "keyboard opens movement mode")
		await move_cursor(planned["destination"])
		await key(KEY_E)
		check(trial.screen.mode == "move_confirm", "keyboard previews movement before committing")
		await key(KEY_E)
		check(Grid.cell_of(trial.battle.unit(actor)) == planned["destination"], "keyboard movement commits requested path")
	var index: int = trial.battle.abilities(actor).find(planned["skill_id"])+1
	check(index > 0, "planned skill is an actual equipped command")
	await select_command(index)
	await key(KEY_E)
	check(trial.screen.mode == "target", "keyboard opens actual ability target preview")
	await move_cursor(planned["target"])
	await key(KEY_E)
	check(trial.screen.mode == "action_confirm", "keyboard confirms legal action preview")
	await key(KEY_E)
	check(trial.battle.unit(actor)["last_action"] == planned["skill_id"], "keyboard executes real selected action")


func play_to_end() -> void:
	var before: Dictionary = session.state.to_dict()
	var turns := 0
	var seen: Dictionary = {}
	while trial.battle.outcome == "ongoing" and turns < 100:
		var actor: String = trial.battle.current_actor_id()
		if trial.battle.unit(actor)["team"] == "ally":
			await player_action(AI.plan(trial.battle,actor))
		else:
			seen[actor] = true
			var revision: int = trial.battle.revision
			# Invoke the production automatic dispatcher with elapsed time; no
			# private battle fields, units, effects or reducers are patched.
			trial.screen.auto_ai = true
			trial.screen._process(0.9)
			trial.screen.auto_ai = false
			await process_frame
			check(trial.battle.revision > revision and trial.screen.message.is_empty(), "real production enemy dispatcher executes legal configured AI")
		turns += 1
	check(trial.battle.outcome == "victory" and trial.screen.mode == "result" and turns < 100, "real keyboard two-versus-three scenario completes with victory")
	check(seen.size() == 3, "all three enemy strategies actually act in keyboard scenario")
	check(session.state.to_dict() == before and session.combat_active(), "result grants no story rewards and keeps equipment locked until return")
	print("WEEK6_TRIAL_PLAY kind=%s turns=%d outcome=%s round=%d hero_hp=%d companion_hp=%d" % [trial.battle.objective["kind"],turns,trial.battle.outcome,trial.battle.round_number,trial.battle.unit("CHAR_PROTAGONIST")["hp"],trial.battle.unit("CHAR_COMPANION")["hp"]])


func _return_and_protection() -> void:
	var before: Dictionary = session.state.to_dict()
	await capture("result")
	await key(KEY_DOWN)
	await key(KEY_E)
	check(trial.screen.mode == "trial_return", "result return requires confirmation")
	await key(KEY_E)
	check(trial.phase == "selection" and not session.combat_active() and trial.battle == null, "confirmed result return releases session and destroys transient battle")
	check(session.state.to_dict() == before, "return leaves persistent HP, time, evidence and rewards untouched")
	await key(KEY_RIGHT)
	await key(KEY_E)
	trial.screen.auto_ai = false
	check(trial.battle.objective.size() == 3 and trial.battle.objective["kind"] == "survive" and int(trial.battle.objective["rounds"]) == 3 and trial.battle.objective["protected_unit_id"] == "CHAR_COMPANION", "actual keyboard selects protection objective, not escape")
	await capture("protection")
	await play_to_end()
	check(trial.battle.round_number == 3 and trial.battle.pending_ids().is_empty() and trial.battle.unit("CHAR_COMPANION")["hp"] > 0, "production protection completes all three rounds with living companion")
	await key(KEY_F2)
	await key(KEY_E)
	check(trial.phase == "selection" and not session.combat_active(), "F2 real return unlocks second trial")
	await key(KEY_ESCAPE)
	check(trial.phase == "quit", "selection escape asks return confirmation")
	await key(KEY_ESCAPE)
	check(trial.phase == "selection" and exit_count == 0, "selection return confirmation may be cancelled")
	await key(KEY_E)
	trial.screen.auto_ai = false
	check(session.combat_active(), "third real battle locks equipment before early exit test")
	await key(KEY_ESCAPE)
	check(trial.screen.mode == "quit" and session.combat_active(), "battle exit confirmation keeps lock until accepted")
	await key(KEY_ESCAPE)
	check(trial.screen.mode == "command" and session.combat_active(), "cancelling battle exit keeps current attempt locked")
	await key(KEY_ESCAPE)
	await key(KEY_E)
	check(exit_count == 1 and not session.combat_active(), "early production battle exit signal releases trial lock")
	check(session.state.to_dict() == before, "early battle exit has no permanent consequences")


func _run() -> void:
	create_timer(150).timeout.connect(func() -> void: printerr("WEEK6_TRIAL_FAIL watchdog"); quit(1))
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	captures = "--capture-week6-trial" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args():
		check(packed, "real PCK only, no source overlay")
		if not packed: quit(1); return
	if captures:
		root.content_scale_size = Vector2i(640,360)
		root.size = Vector2i(1280,720)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	session = root.get_node("GameSession")
	var app: Node = root.get_node("App")
	var original_contexts: Array = app.contexts.duplicate()
	if not await install(): quit(1); return
	_definition_validation()
	await _selection_and_preparation()
	await _entry_lock_and_retry()
	await play_to_end()
	await _return_and_protection()
	root.remove_child(trial)
	trial.queue_free()
	await process_frame
	check(app.contexts == original_contexts and not session.combat_active(), "removing production wrapper releases input context and lock")
	if captures: check(captured.size() == 5, "exactly five native trial captures produced")
	print("WEEK6_TRIAL: %d checks, %d failures" % [checks,failures.size()])
	if failures.is_empty(): print("WEEK6_TRIAL_PASS packed=%s captures=%d checks=%d" % [packed,captured.size(),checks])
	quit(0 if failures.is_empty() else 1)
