extends SceneTree
## Production keyboard views with explicit close-range UI fixtures. These
## fixtures demonstrate preview/layout, not comparative production difficulty.
## Production encounters/build tradeoffs are checked by test_tactics_encounter.
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Screen = preload("res://game/presentation/battle/battle_screen.gd")
const Trial = preload("res://game/presentation/battle/combat_v1_trial.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Model = preload("res://game/presentation/battle/battle_skill_preview.gd")
const Commands = preload("res://game/presentation/battle/battle_command_options.gd")
const Loadout = preload("res://game/domain/battle/martial_loadout.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const E := "ENEMY_CATCHER"
const D := "ENEMY_BOW"
const CAPTURES := ["overview", "martial_list", "multi_target", "threat", "tactics", "status"]
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var trial: Node2D
var fixture: Dictionary
var packed := false
var captures := false
var captured: Array[String] = []
var folder := ""
var session: Node

func _initialize() -> void:
	create_timer(100, true).timeout.connect(func() -> void: printerr("WEEK6_FEEDBACK_UI_FAIL watchdog"); quit(1))
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK6_FEEDBACK_UI_FAIL ", label)
	return ok

func tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func layout(node: Node, label: String) -> void:
	await process_frame
	for child: Node in node.get_children():
		if child is Label and child.is_visible_in_tree():
			check(Rect2(0,0,640,360).encloses(child.get_global_rect()), label+" visible text stays in viewport")
			check(child.get_minimum_size().y <= child.size.y+0.1, label+" complete glyph height fits")
		await layout(child,label)
	if node == screen:
		check(not screen.menu.get_rect().intersects(screen.detail.get_rect()), label+" menu and detail disjoint")
		check(not screen.detail.get_rect().intersects(screen.footer.get_rect()), label+" detail and footer disjoint")

func capture(name: String) -> void:
	if not captures: return
	check(name in CAPTURES and name not in captured, "unique declared capture "+name)
	await RenderingServer.frame_post_draw
	var view := root.get_texture().get_image()
	if check(view != null and view.get_size() == Vector2i(640,360), "native 640x360 viewport "+name):
		if check(view.save_png(folder.path_join("feedback_ui_"+name+".png")) == OK, "save only native QA evidence "+name): captured.append(name)

func choose(identifier: String) -> void:
	var index: int = screen.battle.abilities(screen.battle.current_actor_id()).find(identifier)+1
	if not check(index > 0, "actor really equipped "+identifier): return
	for _step in range(32):
		if screen.selection == index: return
		await tap(KEY_DOWN)
	check(false,"bounded keyboard option navigation")

func cursor_to(cell: Vector2i) -> void:
	for _step in range(40):
		if screen.cursor == cell: return
		if screen.cursor.x < cell.x: await tap(KEY_RIGHT)
		elif screen.cursor.x > cell.x: await tap(KEY_LEFT)
		elif screen.cursor.y < cell.y: await tap(KEY_DOWN)
		else: await tap(KEY_UP)
	check(false,"bounded keyboard target navigation")

func install(mode := "arc", internal := true) -> void:
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await process_frame
	var definition := fixture.duplicate(true)
	definition["blocked"] = []
	for unit: Dictionary in definition["units"]:
		match unit["id"]:
			A:
				unit["cell"] = [3,3]
				unit["agility"] = 20
				unit["loadout"] = {"external":["SK_TRIP_WRIST","SK_YUE_GUARD","SK_YUE_CROSSCUT"],"movement":"SK_WATER_STEP","internal":"IN_BREATH_BASIC" if internal else ""}
				unit["qi"] = 5 if internal else 3
				unit["mastery"] = session.martial_configuration()["state"]["mastery"].duplicate(true)
			C: unit["cell"] = [3,2]
			B: unit["cell"] = [4,3]
			E: unit["cell"] = [4,2]
			D: unit["cell"] = [4,4]
	if mode == "empty_center":
		for unit: Dictionary in definition["units"]:
			if unit["id"] == B: unit["cell"] = [7,6]
	if mode == "friend_center":
		for unit: Dictionary in definition["units"]:
			if unit["id"] == B: unit["cell"] = [7,6]
			if unit["id"] == C: unit["cell"] = [4,3]
	if mode == "resource":
		for unit: Dictionary in definition["units"]:
			if unit["id"] == A:
				unit["loadout"]["external"] = ["SK_YUE_THRUST","SK_YUE_GUARD","SK_YUE_CROSSCUT"]
				unit["qi"] = 0
	var authority := Combat.new()
	if not check(authority.configure(definition).is_empty(),"explicit UI fixture uses actual production definitions and reducer"): return
	screen = Screen.new()
	screen.battle = authority
	screen.auto_ai = false
	root.add_child(screen)
	await process_frame
	check(screen.battle.current_actor_id() == A,"real protagonist turn, no forged cursor authority")
	screen.set_process(false)
	screen.board.set_process(false)
	screen.board.hero_visual.set_process(false)

func production_preparation() -> void:
	trial = Trial.new()
	root.add_child(trial)
	await process_frame
	var before: Dictionary = session.state.to_dict()
	check(trial.startup_error.is_empty() and trial.phase == "selection", "production trial selection is usable")
	check(trial.detail.text.contains("捕手优先") and trial.heading.text.contains("取舍"), "public enemy role and equipment choice explained")
	await layout(trial,"production overview")
	await capture("overview")
	fixture = trial.definition_for("eliminate",session.martial_configuration()["state"])["definition"].duplicate(true)
	check(not fixture.is_empty() and fixture["skill_definitions"] == root.get_node("ContentDB").martial_definitions(), "production trial and normal M preparation share active tactics table")
	await tap(KEY_M)
	check(trial.phase == "preparation", "actual M opens real preparation")
	check(trial.preparation.detail.text.contains("控距") and trial.preparation.detail.text.contains("耗内力2"), "distance burst has visible real price")
	await tap(KEY_DOWN)
	check(trial.preparation.detail.text.contains("护持"), "guard/support role differs from restoration")
	await tap(KEY_DOWN)
	check(trial.preparation.detail.text.contains("群控") and trial.preparation.detail.text.contains("前排3格"), "multi-target control shown in real loadout menu")
	await layout(trial,"actual martial list")
	await capture("martial_list")
	await tap(KEY_UP)
	await tap(KEY_UP)
	await tap(KEY_LEFT)
	check(trial.preparation.detail.text.contains("破势续攻"), "wrist follow-up window explained")
	await tap(KEY_ESCAPE)
	check(session.state.to_dict() == before, "role inspection and canceled draft change no permanent state")
	root.remove_child(trial)
	trial.queue_free()
	await process_frame

func multi_target() -> void:
	await install()
	var before: Dictionary = screen.battle.snapshot()
	await choose("SK_YUE_CROSSCUT")
	check(screen.detail.text.contains("群攻／截击") and screen.detail.text.contains("同一代受者只受一击"), "skill card describes true multi-target semantics")
	# All hit values, not just the center, must be included in overview min/max.
	var amounts: Array[int] = []
	for direction: Vector2i in Actions.target_cells(screen.battle,A,"SK_YUE_CROSSCUT"):
		var action: Dictionary = screen.battle.preview_action(A,"SK_YUE_CROSSCUT",direction)
		if action["ok"]:
			for hit: Dictionary in action["hits"]: amounts.append(hit["actual"])
	var span := str(amounts.min()) if amounts.min() == amounts.max() else "%d～%d" % [amounts.min(),amounts.max()]
	check(Text.damage_summary(screen.battle,A,"SK_YUE_CROSSCUT").contains("实扣"+span), "overview accounts for every actual receiver's armor")
	await tap(KEY_E)
	await cursor_to(Vector2i(2,3))
	await tap(KEY_E)
	check(screen.mode == "target" and screen.footer.text.contains("没有敌人"), "empty direction without any enemy is blocked with explanation")
	check(screen.battle.snapshot() == before, "invalid direction costs nothing")
	await cursor_to(Vector2i(4,3))
	await tap(KEY_E)
	check(screen.mode == "action_confirm" and screen.preview["hits"].size() == 3, "real keyboard selects three-target fan confirmation")
	var plan: Dictionary = screen.preview.duplicate(true)
	for hit: Dictionary in plan["hits"]:
		var target: Dictionary = screen.battle.unit(hit["receiver"])
		check(screen.detail.text.contains("%s：气血%d→%d" % [target["name"],target["hp"],maxi(0,int(target["hp"])-int(hit["actual"]))]), "actual receiver HP delta is visible")
	check(screen.board.affected.size() == 3 and screen.board.range_cells.has(Vector2i(4,2)) and screen.board.range_cells.has(Vector2i(4,4)), "all actual hits and diagonal fan geometry visible")
	await layout(screen,"three-target preview")
	await capture("multi_target")
	await tap(KEY_ESCAPE)
	await tap(KEY_ESCAPE)
	check(screen.battle.snapshot() == before and screen.selection == screen.battle.abilities(A).find("SK_YUE_CROSSCUT")+1, "cancel retains menu focus and resources")
	await tap(KEY_E)
	check(screen.cursor == Vector2i(4,3), "reentry retains selected fan direction")
	await tap(KEY_E)
	await tap(KEY_E)
	check(screen.battle.unit(A)["qi"] == plan["qi_after"] and int(screen.battle.unit(A)["cooldowns"]["SK_YUE_CROSSCUT"]) == plan["cooldown_ready_round"], "confirmation spends displayed qi and cooldown")
	for hit: Dictionary in plan["hits"]:
		check(int(screen.battle.unit(hit["receiver"])["hp"]) == maxi(0,int(before["units"][hit["receiver"]]["hp"])-int(hit["actual"])), "execution matches each displayed receiver HP")
	check(screen.battle.unit(C)["hp"] == before["units"][C]["hp"], "friendly unit never takes sweep damage")
	for kind: String in ["empty_center","friend_center"]:
		await install(kind)
		await choose("SK_YUE_CROSSCUT")
		await tap(KEY_E)
		await cursor_to(Vector2i(4,3))
		await tap(KEY_E)
		check(screen.mode == "action_confirm" and screen.preview["hits"].size() == 2, "direction may be aimed at "+kind+" with enemies to its sides")
		check(not screen.board.affected.has(Vector2i(4,3)), "orange actual receiver frame does not falsely mark empty/friendly center")
		await layout(screen,kind+" preview")

func resource_split() -> void:
	for internal: bool in [true,false]:
		await install("resource", internal)
		await choose("SK_YUE_THRUST")
		var before: Dictionary = screen.battle.snapshot()
		check(screen.footer.text.contains("当前0，需要2") and screen.footer.text.contains("吐纳"), "burst shortage explains actual two-qi cost and recovery")
		check(screen.footer.text.contains("普攻") == internal, "no-passive recovery hint never claims basic restores qi")
		await tap(KEY_E)
		check(screen.mode == "command" and screen.battle.snapshot() == before, "unavailable expensive command inspectable but not executable")
		await choose("SK_STICK_GUARD")
		check(screen.detail.text.contains("防御") and not screen.detail.text.contains("回内力"), "guard is defense, not recovery")
		await choose("ACT_BREATH")
		check(screen.detail.text.begins_with("恢复｜") and not screen.detail.text.contains("守势"), "breath restoration card no longer promises defensive buff")
		await tap(KEY_E)
		await tap(KEY_E)
		var plan: Dictionary = screen.preview.duplicate(true)
		check(plan["qi_after"] == (2 if internal else 1) and plan["effects"].is_empty(), "passive changes true qi cycle, not decorative text")
		await layout(screen,"resource separation")
		await tap(KEY_E)
		check(screen.battle.unit(A)["qi"] == plan["qi_after"] and not screen.battle.unit(A)["statuses"].has("guard"), "actual breath recovers qi without guard")
		check(screen.board.hero_visual._action.is_empty() and screen.board._restore_flash > 0, "recovery uses idle plus qi pulse, not misleading guard animation")
		var after: Dictionary = screen.battle.snapshot()
		screen.board._process(0.6)
		check(screen.board._restore_flash == 0 and screen.battle.snapshot() == after,"recovery pulse expires without touching rules")

func threat_and_tactics() -> void:
	await install()
	var before: Dictionary = screen.battle.snapshot()
	await tap(KEY_T)
	var expected: Array[Vector2i] = []
	for identifier: String in screen.battle.unit_ids():
		if screen.battle.unit(identifier)["team"] != "enemy": continue
		for skill: String in screen.battle.abilities(identifier):
			if screen.battle.skill(skill)["target"] != "enemy": continue
			for cell: Vector2i in Actions.target_cells(screen.battle,identifier,skill):
				if not cell in expected: expected.append(cell)
	check(not expected.is_empty() and screen.board.enemy_attack_cells == expected, "T shows union of registered current-position physical attacks, not future plans")
	await tap(KEY_E)
	check(screen.mode == "move" and not screen.board.enemy_reach.is_empty(), "enemy movement remains independently purple in real movement mode")
	check(screen.footer.text.contains("非攻击范围") and screen.footer.text.contains("T红纹"), "two range meanings remain explained")
	await layout(screen,"coexisting threat ranges")
	await capture("threat")
	await tap(KEY_ESCAPE)
	await tap(KEY_F)
	await cursor_to(Grid.cell_of(screen.battle.unit(E)))
	check(screen.menu.text.contains("优先") and screen.menu.text.contains("主角"), "enemy inspection exposes public carrier chase role")
	check(not screen.detail.text.contains("预计移至"), "public priority is not falsely advertised as locked future plan")
	await layout(screen,"public tactical inspection")
	await capture("tactics")
	await tap(KEY_ESCAPE)
	await tap(KEY_F1)
	check(screen.detail.text.contains("非锁定计划") and screen.menu.text.contains("下一击"), "help explains threat limits and new status timing")
	await layout(screen,"tactical help")
	await tap(KEY_ESCAPE)
	await tap(KEY_T)
	check(screen.board.enemy_attack_cells.is_empty() and screen.battle.snapshot() == before, "T and inspection/help are entirely read-only")

func broken_window() -> void:
	await install()
	await choose("SK_TRIP_WRIST")
	await tap(KEY_E)
	await cursor_to(Vector2i(4,3))
	await tap(KEY_E)
	await tap(KEY_E)
	check(screen.battle.unit(B)["statuses"].get("broken",{}).get("mode","") == "next_hit", "actual wrist action opens follow-up status")
	var expires: int = screen.battle.unit(B)["statuses"]["broken"]["expires_round"]-1
	await tap(KEY_F)
	await cursor_to(Grid.cell_of(screen.battle.unit(B)))
	await tap(KEY_V)
	check(screen.detail.text.contains("下一击用尽") and screen.detail.text.contains("第%d轮末到期" % expires), "V displays actual next-hit and expiry information")
	await layout(screen,"status window")
	await capture("status")
	await tap(KEY_ESCAPE)
	for _turn in range(12):
		var actor: String = screen.battle.current_actor_id()
		if actor == A: break
		check(screen.battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(screen.battle.unit(actor)),screen.battle.revision)["ok"], "legal intervening turns keep follow-up window")
	check(screen.battle.current_actor_id() == A and screen.battle.unit(B)["statuses"].has("broken"), "broken survives victim's intervening action until a following strike")
	screen.actor_changed()
	await choose("SK_FIST_BASIC")
	await tap(KEY_E)
	await cursor_to(Vector2i(4,3))
	await tap(KEY_E)
	check(screen.preview["ok"] and not screen.preview["hits"].is_empty(), "follow-up attack preview is legal")
	await tap(KEY_E)
	check(not screen.battle.unit(B)["statuses"].has("broken"), "follow-up strike actually consumes the opening")

func _run() -> void:
	await process_frame
	TranslationServer.set_locale("zh_CN")
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	captures = "--capture-week6-feedback-ui" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed,"actual PCK, no source overlay")
	if captures:
		check(DisplayServer.get_name() != "headless","native renderer for evidence")
		folder = OS.get_environment("WUXIA_CAPTURE_DIR")
		if folder.is_empty(): folder = ProjectSettings.globalize_path("res://builds/qa/week6_feedback_ui")
		check(not folder.begins_with(ProjectSettings.globalize_path("res://assets")),"captures never target original art")
		check(DirAccess.make_dir_recursive_absolute(folder) == OK,"isolated QA screenshot folder")
	session = root.get_node("GameSession")
	session.start_new_game()
	await production_preparation()
	await multi_target()
	await resource_split()
	await threat_and_tactics()
	await broken_window()
	if captures: check(captured == CAPTURES,"complete ordered six current feedback captures")
	if is_instance_valid(screen): screen.queue_free()
	await process_frame
	if failures.is_empty(): print("WEEK6_FEEDBACK_UI_PASS packed=%s captures=%d checks=%d" % [packed,captured.size(),checks])
	else: printerr("WEEK6_FEEDBACK_UI_FAIL checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
