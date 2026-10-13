extends SceneTree
## Actual StoryBattleScreen keyboard regressions; source and packed resources.
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Screen = preload("res://game/presentation/battle/story_battle_screen.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const D := "ENEMY_BOW"
var fixture: Dictionary
var screen: Node2D
var checks := 0
var failures: Array[String] = []
var captures := false
var packed := false
var capture_folder := ""
var captured: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK6_PREVIEW_FAIL ", label)


func data() -> Dictionary:
	var result := fixture.duplicate(true)
	result["blocked"] = []
	result["units"][0]["agility"] = 20
	result["units"][0]["name"] = "主角"
	result["units"][0]["cell"] = [1, 1]
	result["units"][1]["cell"] = [1, 2]
	result["units"][1]["name"] = "同伴"
	result["units"][2]["cell"] = [2, 1]
	result["units"][2]["hp"] = 20
	result["units"][2]["max_hp"] = 20
	result["units"][3]["cell"] = [7, 1]
	return result


func with_internal(definition: Dictionary, enabled := true) -> Dictionary:
	var result := definition.duplicate(true)
	result["units"][0]["loadout"] = {"external": ["SK_YUE_THRUST", "SK_YUE_GUARD"], "movement": "SK_WATER_STEP", "internal": "IN_BREATH_BASIC" if enabled else ""}
	result["units"][0]["mastery"] = {"SK_YUE_THRUST": "熟练", "SK_YUE_GUARD": "熟练", "SK_WATER_STEP": "熟练", "IN_BREATH_BASIC": "熟练"}
	return result


func create(definition: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(definition).is_empty(), "valid preview fixture")
	return battle


func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func move_cursor(target: Vector2i) -> void:
	for _step: int in range(64):
		if screen.cursor == target: return
		if screen.cursor.x < target.x: await key(KEY_RIGHT)
		elif screen.cursor.x > target.x: await key(KEY_LEFT)
		elif screen.cursor.y < target.y: await key(KEY_DOWN)
		else: await key(KEY_UP)
	check(false, "bounded keyboard cursor navigation")


func select_skill(identifier: String) -> void:
	var position: int = screen.battle.abilities(screen.battle.current_actor_id()).find(identifier)+1
	check(position > 0, "skill exists in actor loadout " + identifier)
	for _step: int in range(32):
		if screen.selection == position: return
		await key(KEY_DOWN)
	check(false, "bounded keyboard skill navigation " + identifier)


func install(definition: Dictionary, intel := false) -> void:
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await process_frame
	screen = Screen.new()
	screen.battle = create(definition)
	screen.auto_ai = false
	screen.reveal_intent = intel
	screen.ferry_deployment = false
	root.add_child(screen)
	await process_frame
	var before: Dictionary = screen.battle.snapshot()
	check(screen.briefing.visible, "actual story arrival acknowledgement shown")
	await key(KEY_E)
	check(not screen.briefing.visible and screen.mode == "command", "story acknowledgement does not activate a command")
	check(screen.battle.snapshot() == before, "briefing dismissal is read-only")


func layout(label: String, save := false) -> void:
	await process_frame
	for node: Label in [screen.heading, screen.stats, screen.menu, screen.disabled_menu, screen.detail, screen.footer]:
		check(Rect2(0, 0, 640, 360).encloses(node.get_rect()), label+" text stays in design viewport")
		check(node.get_minimum_size().y <= node.size.y, label+" text fits its panel")
	check(not screen.menu.get_rect().intersects(screen.detail.get_rect()), label+" menu/detail do not overlap")
	check(not screen.detail.get_rect().intersects(screen.footer.get_rect()), label+" detail/footer do not overlap")
	if not captures or not save: return
	check(DisplayServer.get_name() != "headless", "actual renderer required for capture")
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var filename := "week6_preview_"+label+".png"
	var result: Error = root.get_texture().get_image().save_png(capture_folder.path_join(filename))
	check(result == OK, "actual capture " + label)
	if result == OK: captured.append(filename)


func advance_to_hero() -> void:
	for _step: int in range(16):
		if screen.battle.current_actor_id() == A: break
		var actor: String = screen.battle.current_actor_id()
		check(not actor.is_empty(), "fixture stays ongoing until hero returns")
		if actor.is_empty(): return
		check(screen.battle.perform_action(actor, "ACT_BREATH", Grid.cell_of(screen.battle.unit(actor)), screen.battle.revision)["ok"], "legal other actor breath fixture")
	screen.actor_changed()
	await process_frame
	check(screen.battle.current_actor_id() == A, "hero returns within bounded legal turns")


func _gray_story_commands() -> void:
	await install(data(), true)
	var before: Dictionary = screen.battle.snapshot()
	await select_skill("ULT_SWORD")
	check(screen.detail.text.contains("实际受敌伤 0/6"), "story retains ultimate progress detail")
	check(screen.footer.text.contains("伤害6点") and screen.footer.text.contains("仅查看"), "story retains parent missing-trigger explanation")
	check(screen.footer.text.contains("淡色格：范围") and screen.footer.text.contains("橙框：实际受影响"), "story retains range legend while inspecting gray skill")
	check(screen.footer.text.contains("首轮推演:有") and screen.footer.text.contains("近道:无"), "story annotates intel without replacing skill explanation")
	await layout("story_locked", true)
	await key(KEY_E)
	check(screen.mode == "command" and screen.battle.snapshot() == before, "gray confirmation cannot enter target or mutate combat")
	check(screen.footer.text.contains("伤害6点"), "gray confirm retains missing-trigger explanation")
	await key(KEY_F1)
	check(screen.briefing.visible, "story F1 reopens factual briefing")
	await key(KEY_ESCAPE)
	check(screen.selection == screen.battle.abilities(A).find("ULT_SWORD")+1, "closing story briefing retains inspected option")
	check(screen.battle.snapshot() == before, "story popup navigation is read-only")
	var definition := data()
	definition["units"][0]["qi"] = 0
	await install(definition)
	await select_skill("SK_YUE_THRUST")
	check(screen.footer.text.contains("当前0，需要1"), "formal story preserves qi blocker and recovery hint")
	await layout("story_qi_blocked", true)
	before = screen.battle.snapshot()
	await key(KEY_E)
	check(screen.mode == "command" and screen.battle.snapshot() == before, "qi blocker cannot execute")


func _preview_matches_execute() -> void:
	var definition := with_internal(data())
	definition["units"][0]["qi"] = 4
	await install(definition)
	check(screen.battle.unit(A).get("internal_skill") == "IN_BREATH_BASIC", "preview resource fixture uses actual configured internal passive")
	check(not "IN_BREATH_BASIC" in screen.battle.abilities(A), "passive inner discipline is not falsely offered as an active command")
	await select_skill("SK_FIST_BASIC")
	var before: Dictionary = screen.battle.snapshot()
	await key(KEY_E)
	await move_cursor(Vector2i(2, 1))
	await key(KEY_E)
	check(screen.mode == "action_confirm", "real keyboard reaches attack confirmation")
	var plan: Dictionary = screen.preview.duplicate(true)
	check(screen.detail.text.contains("内力4→5") and screen.detail.text.contains("实回1"), "preview shows passive/basic resource result")
	var actual: int = int(plan["hits"][0]["actual"])
	check(screen.detail.text.contains("气血20→%d" % (20-actual)), "preview names actual recipient HP result")
	check(screen.battle.snapshot() == before, "attack preview is read-only")
	await layout("attack_confirm", true)
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(screen.battle.snapshot() == before and screen.mode == "command", "cancel target/confirm restores menu without resource cost")
	await key(KEY_E)
	check(screen.cursor == Vector2i(2, 1), "story remembers the canceled target cursor")
	await key(KEY_E)
	await key(KEY_E)
	check(screen.battle.unit(A)["qi"] == 5 and screen.battle.unit(B)["hp"] == 20-actual, "actual reducer matches displayed qi and receiver HP")
	await advance_to_hero()
	await select_skill("ACT_BREATH")
	await key(KEY_E)
	await move_cursor(Grid.cell_of(screen.battle.unit(A)))
	await key(KEY_E)
	check(screen.detail.text.contains("内力5→5") and screen.detail.text.contains("实回0"), "capped resource preview does not promise nominal recovery")
	await layout("breath_capped", true)
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	await select_skill("SK_YUE_GUARD")
	await key(KEY_E)
	await move_cursor(Grid.cell_of(screen.battle.unit(A)))
	await key(KEY_E)
	var ready: int = screen.battle.round_number+3
	check(screen.detail.text.contains("第%d轮恢复可用" % ready), "defense preview shows exact cooldown return round")
	check(screen.detail.text.contains("内力5→4"), "defense preview shows spent resource")
	await layout("guard_confirm", true)
	await key(KEY_E)
	check(int(screen.battle.unit(A)["cooldowns"].get("SK_YUE_GUARD", 0)) == ready, "displayed cooldown equals authority cooldown")
	await advance_to_hero()
	await select_skill("SK_YUE_GUARD")
	check(screen.footer.text.contains("当前第") and screen.footer.text.contains("第%d轮恢复" % ready), "story preserves cooldown blocker recovery explanation")
	await layout("story_cooldown", true)
	await install(with_internal(data()))
	await select_skill("SK_WATER_STEP")
	before = screen.battle.snapshot()
	await key(KEY_E)
	await move_cursor(Vector2i(2, 2))
	await key(KEY_E)
	check(screen.mode == "action_confirm" and screen.detail.text.contains("落点(2,2)"), "step preview names selected final cell")
	check(screen.detail.text.contains("内力5→4") and screen.detail.text.contains("第4轮恢复可用"), "step shows resource and cooldown")
	check(screen.battle.snapshot() == before, "step preview is read-only")
	await layout("step_confirm", true)
	await key(KEY_E)
	check(screen.battle.unit(A)["cell"] == [2, 2] and screen.battle.unit(A)["qi"] == 4, "actual step lands at advertised cell and cost")
	definition = with_internal(data(), false)
	definition["units"][0]["qi"] = 1
	await install(definition)
	check(screen.battle.unit(A)["max_qi"] == 3, "unequipped passive gives real lower capacity")
	check(screen.briefing_body.text.contains("普攻回内力0；吐纳回1"), "story rules do not advertise equipped-passive recovery after it was removed")
	await select_skill("SK_FIST_BASIC")
	check(not screen.detail.text.contains("回内力1"), "skill card does not advertise recovery without its inner passive")
	await key(KEY_E)
	await move_cursor(Vector2i(2, 1))
	await key(KEY_E)
	check(screen.detail.text.contains("内力1→1") and screen.detail.text.contains("实回0"), "unequipped passive changes real attack resource preview")
	await layout("no_internal", true)
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	await select_skill("ACT_BREATH")
	await key(KEY_E)
	await move_cursor(Vector2i(1, 1))
	await key(KEY_E)
	check(screen.detail.text.contains("内力1→2") and screen.detail.text.contains("实回1"), "unequipped passive uses base one-point breathing")
	await key(KEY_E)
	check(screen.battle.unit(A)["qi"] == 2, "unequipped passive actual breath matches shown recovery")


func _status_and_forecast() -> void:
	await install(data(), true)
	# Reducer calls below prepare extreme status combinations, not a gameplay
	# claim; the checks themselves drive the actual story inspection keyboard.
	Effects.apply_statuses(screen.battle, B, A, ["broken", "pin", "bleed"])
	Effects.apply_statuses(screen.battle, C, A, ["support"])
	Effects.apply_statuses(screen.battle, A, A, ["guard"])
	var before: Dictionary = screen.battle.snapshot()
	await key(KEY_F)
	await move_cursor(Vector2i(1, 1))
	await key(KEY_V)
	check(screen.get("inspect_status") == true, "real V key switches into status-expiry inspection")
	check(screen.detail.text.contains("下次行动") and screen.detail.text.contains("余2次"), "inspection shows actual status expiry rules")
	check(screen.detail.text.contains("同伴代受首击") and screen.detail.text.contains("本轮末到期"), "inspection identifies support source and expiry")
	check(screen.battle.snapshot() == before, "status inspection never consumes duration or resources")
	await layout("status_expiry", true)
	await key(KEY_ESCAPE)
	check(screen.mode == "command", "state inspection returns to remembered command")
	check(screen.get("inspect_status") == false, "cancel resets state inspection toggle")
	await select_skill("ACT_BREATH")
	await key(KEY_E)
	await move_cursor(Vector2i(1, 1))
	await key(KEY_E)
	await key(KEY_E)
	await advance_to_hero()
	await key(KEY_F)
	await move_cursor(Vector2i(1, 1))
	await key(KEY_V)
	check(screen.detail.text.contains("余1次"), "status inspection uses actual remaining bleed after one legal action")
	check(not screen.detail.text.contains("牵制") and not screen.detail.text.contains("破势") and not screen.detail.text.contains("援护"), "expired one-action and one-round statuses disappear from inspection")
	await key(KEY_ESCAPE)
	# A non-bow enemy with only a registered line attack must not display the
	# former hard-coded EN_BLADE_PIN shape when forecasting a guard/breath plan.
	var definition := data()
	definition["units"][2]["archetype"] = "EN_CUSTOM_LINE"
	definition["units"][2]["agility"] = 4
	definition["units"][2]["hp"] = 2
	definition["units"][2]["skills"] = ["EN_BOW_SHOT"]
	definition["units"][2]["ai_profile"] = "AI_PREVIEW_LINE"
	definition["ai_profiles"] = definition.get("ai_profiles", {}).duplicate(true)
	definition["ai_profiles"]["AI_PREVIEW_LINE"] = {"style": "pressure", "intent_label": "持械戒备，低血交替守势", "target_priority": "nearest", "preferred_range": [1, 1], "skill_priority": ["EN_BOW_SHOT", "SK_FIST_BASIC"], "effect_priority": [], "low_hp_guard_threshold": 2}
	await install(definition, true)
	before = screen.battle.snapshot()
	await key(KEY_F)
	check(screen.cursor == Vector2i(2, 1), "earned first inspection selects a pending enemy")
	check(screen.menu.text.contains("守势 → 自身"), "registered-shape regression really exercises a non-attack forecast fallback")
	check(screen.menu.text.contains("情报：") and screen.detail.text.contains("攻击距离 5 格"), "fallback forecast shape comes from registered attack, not archetype")
	check(screen.battle.snapshot() == before, "forecast planning and range rendering leave live snapshot intact")
	await layout("registered_range", true)
	var range_before: Array = screen.board.range_cells.duplicate()
	var plan_before: String = screen.menu.text
	await key(KEY_V)
	check(screen.get("inspect_status") == true and screen.detail.text == "状态：无", "enemy V inspects the live status rather than the forecast copy's imminent guard")
	check(screen.board.range_cells == range_before and screen.menu.text == plan_before, "status toggle preserves earned forecast overlays and plan")
	check(screen.battle.snapshot() == before, "earned forecast V toggle does not mutate live state")
	await key(KEY_V)
	check(screen.detail.text.contains("攻击距离 5 格"), "second V returns to forecast explanation")
	await key(KEY_ESCAPE)
	await install(definition, false)
	await key(KEY_F)
	await move_cursor(Vector2i(2, 1))
	check(not screen.menu.text.contains("情报：") and screen.board.range_cells.is_empty(), "no facts reveal neither exact plan nor attack range")
	await key(KEY_V)
	check(not screen.menu.text.contains("情报：") and screen.board.range_cells.is_empty(), "state inspection toggle never grants unknown forecast information")
	await key(KEY_ESCAPE)
	await install(definition, true)
	check(screen.battle.perform_action(A, "ACT_BREATH", Vector2i(1, 1), screen.battle.revision)["ok"], "legal first hero action")
	while screen.battle.current_actor_id() != B:
		var actor: String = screen.battle.current_actor_id()
		check(screen.battle.perform_action(actor, "ACT_BREATH", Grid.cell_of(screen.battle.unit(actor)), screen.battle.revision)["ok"], "legal advance toward enemy")
	check(screen.battle.perform_action(B, "ACT_BREATH", Vector2i(2, 1), screen.battle.revision)["ok"], "legal enemy completes its first turn")
	screen.actor_changed()
	await key(KEY_F)
	await move_cursor(Vector2i(2, 1))
	check(screen.detail.text.contains("本轮已行动") and screen.board.range_cells.is_empty(), "already-acted enemy is not forecast again")
	await key(KEY_ESCAPE)
	await advance_to_hero()
	await key(KEY_F)
	await move_cursor(Vector2i(2, 1))
	check(screen.detail.text.contains("仅适用于首轮") and screen.board.range_cells.is_empty(), "earned forecast expires after first round")


func _interception_hp_preview() -> void:
	var definition := with_internal(data())
	definition["units"][3]["cell"] = [3, 1]
	await install(definition)
	Effects.apply_statuses(screen.battle, D, B, ["support"])
	var before: Dictionary = screen.battle.snapshot()
	await select_skill("SK_FIST_BASIC")
	await key(KEY_E)
	await move_cursor(Vector2i(2, 1))
	await key(KEY_E)
	var hit: Dictionary = screen.preview["hits"][0]
	var expected: int = int(screen.battle.unit(D)["hp"])-int(hit["actual"])
	check(hit["receiver"] == D and screen.detail.text.contains("弓役援护代受：气血6→%d" % expected), "HP preview follows actual protector, not selected enemy")
	check(screen.board.affected == [Vector2i(3, 1)], "affected outline follows actual interception recipient")
	check(screen.battle.snapshot() == before, "interception HP preview does not consume support")
	await layout("support_confirm", true)
	await key(KEY_E)
	check(screen.battle.unit(D)["hp"] == expected and screen.battle.unit(B)["hp"] == 20, "authority damages only previewed protector")
	check(not screen.battle.unit(B)["statuses"].has("support"), "actual interception consumes selected target support once")


func _legacy_preview_and_objective() -> void:
	var battle := create(data())
	var plan := battle.preview_action(A, "SK_WATER_STEP", Vector2i(2, 2))
	for field: String in ["qi_before", "qi_after", "cooldown_ready_round", "destination"]: plan.erase(field)
	var detail := Text.preview_detail(battle, plan)
	check(detail.contains("内力5→4") and detail.contains("落点(2,2)") and detail.contains("第4轮恢复可用"), "legacy preview metadata fallback remains truthful")
	var objective := {"kind": "survive", "protected_unit_id": C, "rounds": 3}
	# A text-only detached test, not evidence of the domain survive win rule.
	battle.objective = objective
	check(Text.objective_summary(battle) == "保护同伴，坚持完整3轮", "survival text distinguishes complete rounds and protected actor")


func _survive_heading() -> void:
	var definition := data()
	definition["objective"] = {"kind": "survive", "protected_unit_id": C, "rounds": 3}
	await install(definition)
	check(screen.heading.text.contains("保护同伴，坚持完整3轮"), "actual battle heading names protected actor and completed-round requirement")
	check(not screen.heading.text.contains("绿框"), "survival does not reuse escape goal wording")
	await layout("survive_goal", true)


func _run() -> void:
	create_timer(90).timeout.connect(func() -> void: printerr("WEEK6_PREVIEW_FAIL watchdog"); quit(1))
	captures = "--capture-week6-preview" in OS.get_cmdline_user_args()
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args():
		check(packed, "packed resources have no source overlay")
		if not packed:
			quit(1)
			return
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/graves_encounter.json"))["battle"]
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	if captures:
		capture_folder = OS.get_environment("WUXIA_CAPTURE_DIR")
		if capture_folder.is_empty(): capture_folder = ProjectSettings.globalize_path("res://builds/qa")
		check(capture_folder.is_absolute_path(), "capture directory is explicit absolute path")
		check(DirAccess.make_dir_recursive_absolute(capture_folder) == OK, "create isolated screenshot directory")
	_legacy_preview_and_objective()
	await _gray_story_commands()
	await _preview_matches_execute()
	await _interception_hp_preview()
	await _status_and_forecast()
	await _survive_heading()
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await process_frame
	print("WEEK6_BATTLE_PREVIEW: %d checks, %d failures (keyboard simulation; not human playtest)" % [checks, failures.size()])
	if failures.is_empty(): print("WEEK6_BATTLE_PREVIEW_PASS checks=%d packed=%s captures=%d" % [checks, packed, captured.size()])
	quit(0 if failures.is_empty() else 1)
