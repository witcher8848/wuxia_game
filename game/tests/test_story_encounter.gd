extends SceneTree
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Rules = preload("res://game/domain/investigation/investigation_rules.gd")
const StoryRules = preload("res://game/domain/investigation/story_encounter_rules.gd")
const Catalog = preload("res://game/domain/investigation/dialogue_catalog.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var main: Node
var captures := false

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("STORY_ENCOUNTER_FAIL ", label)

func _run() -> void:
	if "--require-pack" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported pack only; no source overlay")
		if not failures.is_empty():
			quit(1)
			return
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	captures = "--capture-story" in OS.get_cmdline_user_args()
	_definitions()
	_domain()
	await _ui()
	print("STORY_ENCOUNTER: %d checks, %d failures (legal simulated combat; not human playtest)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _prepare(home: bool, dock: bool) -> void:
	session.start_new_game()
	for step: String in ["STEP_RECEIVE_INDEX", "STEP_ACCEPT_SEARCH"]:
		check(session.apply_investigation_step(step)["error"] == OK, "real starting command " + step)
	if home:
		check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] == OK, "discover home original")
		check(session.resolve_inquiry("INQ_INDEX", ["EV_INDEX_01", "EV_BLANK_DEATH_01"])["error"] == OK, "actual home comparison")
	if dock:
		check(session.apply_investigation_step("STEP_RECORD_BOATMAN")["error"] == OK, "record testimony")
		check(session.apply_investigation_step("STEP_TAKE_FERRY_TOKEN")["error"] == OK, "discover token")
		check(session.resolve_inquiry("INQ_BOATMAN", ["EV_FERRY_TOKEN_01"])["error"] == OK, "actual dock challenge")
	check(session.enter_region("SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN") == OK, "depart from dock")
	check(session.mark_inspected("NPC_DOCK_WORKER") == OK, "speak to registered boatman")

func _definitions() -> void:
	var rules := Rules.new()
	check(rules.configure(content.get_investigation_definitions()).is_empty(), "investigation definitions")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/graves_encounter.json"))
	var skills: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	var bridge := StoryRules.new()
	check(bridge.configure(data, skills, rules).is_empty(), "story definition validated")
	for field: String in data:
		var missing := data.duplicate(true)
		missing.erase(field)
		check(not bridge.configure(missing, skills, rules).is_empty(), "reject missing " + field)
	for mutation: Dictionary in [{"prepare_step":"UNKNOWN"}, {"prepare_step":"STEP_RECEIVE_INDEX"}, {"victory_step":"UNKNOWN"}, {"formation_fact":"UNKNOWN"}, {"ferry_fact":"UNKNOWN"}, {"time_cost":2}, {"time_cost":true}, {"trust_delta":3}, {"trust_character":"UNKNOWN"}, {"ferry_deployment":{"UNKNOWN":[0,0]}}, {"ferry_deployment":{"CHAR_PROTAGONIST":[4,3],"CHAR_COMPANION":[3,5]}}]:
		var bad := data.duplicate(true)
		bad.merge(mutation, true)
		check(not bridge.configure(bad, skills, rules).is_empty(), "reject malformed " + str(mutation.keys()))
	_prepare(false, false)
	check(bridge.prepare(session.state)["error"] == OK, "failed configurations retain prior working rules")
	for protected: String in ["STEP_PREPARE_RESCUE", "STEP_GRAVES_VICTORY"]:
		var graph: Dictionary = content.get_dialogue_definitions()
		graph["nodes"][0]["choices"][0]["command"] = protected
		check(not Catalog.new().configure(graph, rules, content.dialogue_text_keys(), ["DOC_STREET_NOTICE", "DOC_HOME_NOTE", "NPC_DOCK_WORKER"]).is_empty(), "dialogue cannot directly issue " + protected)
		check(session.apply_investigation_step(protected)["error"] != OK, "generic session command cannot issue " + protected)

func _domain() -> void:
	session.start_new_game()
	var before: Dictionary = session.state.to_dict()
	check(session.begin_story_encounter()["error"] != OK and session.state.to_dict() == before, "not accepted/location blocks entry")
	for route: Array in [[false,false], [true,false], [false,true], [true,true]]:
		_prepare(route[0], route[1])
		before = session.state.to_dict()
		var start: Dictionary = session.begin_story_encounter()
		check(start["error"] == OK, "real encounter begins " + str(route))
		if start["error"] != OK: continue
		var battle: CombatEncounter = start["battle"]
		check(start["reveal"] == route[0] and start["ferry"] == route[1], "advantages derive from actual facts")
		check(Grid.cell_of(battle.unit("CHAR_PROTAGONIST")) == (Vector2i(3,3) if route[1] else Vector2i(1,3)), "deployment reflects ferry intel")
		var staged: Dictionary = session.state.to_dict()
		check(staged["time_state"] == before["time_state"] and staged["relationships"] == before["relationships"], "entry has no rewards or time cost")
		check(staged["quest_states"]["QUEST_FIND_GRAVEKEEPER"]["status"] == "changed" and staged["quest_states"]["QUEST_RESCUE_GRAVEKEEPER"]["status"] == "active", "finding becomes protecting")
		check(session.begin_story_encounter()["error"] != OK, "reject simultaneous encounter")
		check(session.finish_story_encounter(start["token"])["error"] != OK, "cannot settle ongoing battle")
		check(session.finish_story_encounter("fabricated")["error"] != OK, "reject unowned instance")
		check(session.update_player_position(Vector2.ZERO) == ERR_BUSY and session.mark_inspected("DOC_HOME_NOTE") == ERR_BUSY, "exploration writes frozen during battle")
		check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] != OK, "investigation frozen during battle")
		var snap: Dictionary = battle.snapshot()
		var forecast: CombatEncounter = battle.forecast_turn("ENEMY_BOW")
		check(forecast != null and not AI.plan(forecast,"ENEMY_BOW").is_empty(), "forecast future enemy turn")
		forecast.perform_action("ENEMY_BOW", "ACT_BREATH", Grid.cell_of(forecast.unit("ENEMY_BOW")), forecast.revision)
		check(battle.snapshot() == snap, "forecast commands never mutate live encounter")
		var current_actor := battle.current_actor_id()
		check(AI.plan(battle.forecast_turn(current_actor),current_actor) == AI.plan(battle,current_actor), "current-actor forecast matches actual decision")
		_one_turn(battle)
		check(battle.forecast_turn(current_actor) == null, "already acted unit has no remaining-turn forecast")
		check(session.retry_story_encounter(start["token"]) == OK, "owned retry accepted")
		var retried := battle.snapshot()
		snap.erase("revision")
		retried.erase("revision")
		check(retried == snap and session.state.to_dict() == staged, "retry resets all transient state without permanent rewards")
		_play(battle)
		check(battle.outcome == "victory", "legal actual victory for route " + str(route))
		check(session.state.to_dict() == staged, "victory awaits upper-layer confirmation")
		check(session.finish_story_encounter(start["token"])["error"] == OK, "owned actual victory settles")
		check(session.state.time_state == {"day":1,"slot":1}, "victory spends exactly one slot")
		check(session.state.relationships["CHAR_PRISONER"]["trust"] == 1, "victory adds one trust")
		check(session.state.quest_states["QUEST_RESCUE_GRAVEKEEPER"]["status"] == "resolved" and session.state.quest_states["QUEST_TRACE_LEDGER"]["status"] == "available", "rescue resolved and next lead available")
		for field: String in ["evidence_states", "inventory", "player_state", "martial_states", "route_id"]:
			check(session.state.to_dict()[field] == before[field], "settlement preserves " + field)
		var settled: Dictionary = session.state.to_dict()
		check(session.finish_story_encounter(start["token"])["error"] != OK and session.state.to_dict() == settled, "settlement cannot repeat")
		check(session.begin_story_encounter()["error"] != OK, "completed battle cannot be farmed")
	_prepare(true, true)
	before = session.state.to_dict()
	var start: Dictionary = session.begin_story_encounter()
	_one_turn(start["battle"])
	check(session.abort_story_encounter(start["token"]) == OK and session.state.to_dict() == before, "abort restores full pre-entry state")
	start = session.begin_story_encounter()
	_play(start["battle"], true)
	check(start["battle"].outcome == "defeat", "legal passive allies can lose actual encounter")
	var defeated: Dictionary = session.state.to_dict()
	check(session.finish_story_encounter(start["token"])["error"] != OK and session.state.to_dict() == defeated, "defeat rejected with no partial state changes")
	check(session.retry_story_encounter(start["token"]) == OK and session.state.time_state == before["time_state"], "defeat retry no time advance")
	_play(start["battle"])
	var replacement := GameState.from_dict(before)
	replacement.route_id = "ROUTE_REPLACEMENT"
	check(session.replace_state(replacement) == OK, "new loaded route invalidates instance")
	check(session.finish_story_encounter(start["token"])["error"] != OK and session.abort_story_encounter(start["token"]) != OK and session.state.route_id == "ROUTE_REPLACEMENT", "stale winner cannot settle or roll back replacement")
	_prepare(false, false)
	session.state.time_state = {"day":2,"slot":7}
	session.state.relationships["CHAR_PRISONER"] = {"trust":100,"note":"preserve"}
	start = session.begin_story_encounter()
	_play(start["battle"])
	check(session.finish_story_encounter(start["token"])["error"] == OK and session.state.time_state == {"day":3,"slot":0}, "time wraps at eight slots")
	check(session.state.relationships["CHAR_PRISONER"] == {"trust":100,"note":"preserve"}, "trust cap preserves other relationship data")

func _one_turn(battle: CombatEncounter, passive := false) -> void:
	var actor := battle.current_actor_id()
	var unit := battle.unit(actor)
	if unit["team"] == "enemy":
		check(AI.take_turn(battle)["ok"], "legal enemy action")
	elif passive:
		check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(unit),battle.revision)["ok"], "legal passive ally action")
	else:
		var plan := AI.plan(battle,actor)
		check(not plan.is_empty(), "legal ally plan")
		if plan.is_empty(): return
		if plan["destination"] != Grid.cell_of(unit):
			check(battle.move_actor(actor,plan["destination"],battle.revision)["ok"], "legal ally move")
		check(battle.perform_action(actor,plan["skill_id"],plan["target"],battle.revision)["ok"], "legal ally action")

func _play(battle: CombatEncounter, passive := false) -> void:
	for turn: int in 180:
		if battle.outcome != "ongoing": return
		_one_turn(battle,passive)
	check(false, "bounded combat must finish")

func _ui() -> void:
	var saves: Node = root.get_node("SaveService")
	saves.test_root = "user://tests/story_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	main = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	# Explicit exploration fixture; New Game onboarding has its own UI tests.
	root.get_node("GameSession").start_new_game()
	main._enter_yard()
	for home: bool in [false,true]:
		_prepare(home, home)
		check(main._enter_yard() == OK, "actual dock scene")
		await _frames()
		var region: Node = main.get_node("SceneHost").get_child(0)
		region.player.position = Vector2(704,396)
		region.player.facing = "up"
		await _frames()
		await _tap(KEY_E)
		check(main.reading_panel.visible, "real boatman E interaction")
		var choice_index := 1 if home else 3
		for index: int in choice_index: await _tap(KEY_S)
		await _tap(KEY_E)
		check(main.reading_panel.node_id == "D_JOURNEY", "keyboard journey briefing")
		await _capture("story_briefing" if home else "story_no_intel_briefing")
		await _tap(KEY_E)
		check(root.get_node("App").current_context() == &"battle" and session.story_encounter_active(), "dialogue enters owned actual battle")
		if not session.story_encounter_active(): continue
		var screen: Node = main.story_battle_screen
		screen.auto_ai = false
		check(screen.briefing.visible and screen.briefing_body.text.contains("目标由"), "arrival explains finding becomes protecting")
		await _capture("story_arrival_intel" if home else "story_arrival_no_intel")
		await _tap(KEY_E)
		check(not screen.briefing.visible and screen.mode == "command", "briefing confirmation does not execute a command")
		var frozen: Dictionary = session.state.to_dict()
		check(not main.get_node("UIRoot").visible and main.get_node("SceneHost").process_mode == Node.PROCESS_MODE_DISABLED, "exploration hidden and stopped")
		await _tap(KEY_F2)
		check(screen.mode != "scenario", "story cannot switch laboratory objective")
		await _tap(KEY_F5)
		check(session.state.to_dict() == frozen, "battle quick save does not mutate exploration")
		check(not FileAccess.file_exists(saves.slot_path("quick")), "battle F5 writes no file in isolated slot")
		await _tap(KEY_F)
		screen.cursor = Grid.cell_of(screen.battle.unit("ENEMY_BOW")) # UI fixture placement, not player navigation evidence.
		screen.refresh()
		check(screen.menu.text.contains("情报：") == home, "detailed forecast gated by actual intel")
		check(not screen.footer.text.contains("F2") and not screen.footer.text.contains("不写探索存档"), "story inspector does not advertise laboratory-only controls")
		check(not screen.board.range_cells.is_empty() if home else screen.board.range_cells.is_empty(), "attack range shown only with first-round intel")
		await _capture("story_intel" if home else "story_no_intel")
		await _tap(KEY_ESCAPE)
		await _tap(KEY_R)
		await _tap(KEY_E)
		check(screen.mode == "command" and session.state.to_dict() == frozen, "keyboard retry via owned session")
		await _tap(KEY_ESCAPE)
		await _tap(KEY_E)
		check(not session.story_encounter_active() and main.reading_panel.visible and session.state.quest_states["QUEST_FIND_GRAVEKEEPER"]["status"] == "active", "keyboard abort restores search and source dialogue")
		await _tap(KEY_E) # Returned entry remembers the journey option.
		await _tap(KEY_E)
		check(session.story_encounter_active(), "abort permits returning to the same actual encounter")
		screen = main.story_battle_screen
		screen.auto_ai = false
		await _tap(KEY_E) # Acknowledge actual arrival, not a battle action.
		for turn: int in 4: _one_turn(screen.battle)
		check(screen.battle.round_number == 2, "real actions advance into round two")
		screen.mode = "inspect"
		screen.cursor = Grid.cell_of(screen.battle.unit("ENEMY_BOW"))
		screen.refresh()
		check(not screen.menu.text.contains("情报：") and screen.board.range_cells.is_empty(), "detailed forecast expires after round one")
		_play(screen.battle)
		screen.actor_changed()
		await _frames()
		await _capture("story_victory")
		check(session.state.time_state["slot"] == 0, "UI victory not auto-settled")
		await _tap(KEY_E)
		check(not session.story_encounter_active() and not main.reading_panel.visible and root.get_node("App").current_context() == &"exploration", "settlement cannot resume a remote relocated boatman's dialogue")
		check(session.state.time_state["slot"] == 1 and main.get_node("UIRoot").visible, "one settlement and exploration UI restored")
		var relocated: Dictionary = content.world_npc(session.state, "NPC_DOCK_WORKER")["npc"]
		var current_region: Node = main.get_node("SceneHost").get_child(0)
		current_region.player_position = Vector2(relocated["position"][0],relocated["position"][1])+Vector2(0,40)
		current_region.player.facing = "up"
		await _frames()
		await _tap(KEY_E)
		check(main.reading_panel.visible and main.reading_panel.node_id == "D_AFTER_GRAVES", "approaching relocated boatman reopens the actual aftermath")
		await _capture("story_aftermath")
		await _tap(KEY_ESCAPE)
	root.remove_child(main)
	main.queue_free()
	await _frames()
	saves.test_root = ""

func _tap(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames()

func _frames() -> void:
	for index: int in 2:
		await physics_frame
		await process_frame

func _capture(label: String) -> void:
	if not captures: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://docs/week4_evidence")
	check(root.get_texture().get_image().save_png("res://docs/week4_evidence/" + label + ".png") == OK, "actual rendered " + label)
