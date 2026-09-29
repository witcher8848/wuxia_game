extends SceneTree
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
const Model = preload("res://game/presentation/battle/battle_skill_preview.gd")
const Screen = preload("res://game/presentation/battle/battle_screen.gd")
const Commands = preload("res://game/presentation/battle/battle_command_options.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const D := "ENEMY_BOW"
var fixture: Dictionary
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var captures := false


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("SKILL_PREVIEW_FAIL ", label)


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(data).is_empty(), "valid preview fixture")
	return battle


func close_data() -> Dictionary:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	data["units"][0]["cell"] = [1,1]
	data["units"][0]["agility"] = 8
	data["units"][1]["cell"] = [1,2]
	data["units"][2]["cell"] = [2,1]
	data["units"][3]["cell"] = [3,1]
	return data


func _rules() -> void:
	var battle := create(close_data())
	var before := battle.snapshot()
	var model := Model.build(battle,A,"SK_YUE_THRUST",Vector2i(2,1))
	check(Vector2i(1,0) in model["range"] and Vector2i(1,0) not in model["targets"], "empty cells visible but not attackable")
	check(Vector2i(2,1) in model["targets"] and Vector2i(3,1) not in model["range"], "unit blocks farther straight line")
	check(Vector2i(2,2) not in model["range"], "straight range excludes diagonals")
	check(Text.damage_summary(battle,A,"SK_YUE_THRUST")=="当前可命中：实扣4（含状态）", "armor included in live damage")
	check("参考" in Text.damage_summary(battle,A,"ULT_SWORD"), "locked ultimate shows conditional reference")
	check(not Model.build(battle,A,"ULT_SWORD",Vector2i(2,1))["range"].is_empty(), "locked ultimate retains physical range")
	check(Model.build(battle,A,"ULT_SWORD",Vector2i(2,1))["targets"].is_empty(), "locked ultimate cannot target")
	check(battle.snapshot()==before, "hover and range queries do not mutate combat")
	Effects.apply_statuses(battle,B,B,["guard"])
	check("实扣2" in Text.damage_summary(battle,A,"SK_YUE_THRUST"), "guard included in live damage")
	Effects.apply_statuses(battle,A,B,["broken"])
	check("实扣4" in Text.damage_summary(battle,A,"SK_YUE_THRUST"), "broken armor included in live damage")
	Effects.apply_statuses(battle,D,B,["support"])
	model = Model.build(battle,A,"SK_YUE_THRUST",Vector2i(2,1))
	check(model["affected"]==[Vector2i(3,1)] and model["hits"][0]["receiver"]==D, "highlight actual support receiver, not selected unit")
	var plan := battle.preview_action(A,"SK_YUE_THRUST",Vector2i(2,1))
	check("援护代受" in Text.preview_detail(battle,plan), "preview identifies interception")
	var hp: int = battle.unit(D)["hp"]
	check(battle.perform_action(A,"SK_YUE_THRUST",Vector2i(2,1),battle.revision)["ok"], "execute previewed action")
	check(hp-battle.unit(D)["hp"]==plan["hits"][0]["actual"], "displayed actual damage equals execution")
	var data := close_data()
	data["units"][2]["hp"] = 1
	battle = create(data)
	check("实扣1" in Text.damage_summary(battle,A,"SK_FIST_BASIC"), "overkill capped by target HP")
	data = close_data()
	data["units"][1]["cell"] = [5,5]
	data["units"][3]["cell"] = [1,3]
	battle = create(data)
	check("实扣4～6" in Text.damage_summary(battle,A,"SK_YUE_THRUST"), "menu summarizes different legal targets including distance bonus")
	check(battle.preview_action(A,"SK_YUE_THRUST",Vector2i(1,3))["hits"][0]["damage"]==6, "second-cell damage bonus reflected in preview")
	battle = create(fixture)
	check(Text.damage_summary(battle,A,"SK_YUE_THRUST")=="参考6～7伤（护体0、无状态）", "no target shows explicit assumptions and distance bonus")
	data = close_data()
	data["blocked"] = [[0,1],[1,0]]
	battle = create(data)
	model = Model.build(battle,A,"SK_WATER_STEP",Vector2i(1,3))
	check(Vector2i(1,3) in model["targets"], "water step crosses intermediate ally")
	check(Vector2i(1,2) not in model["range"] and Vector2i(1,1) not in model["range"], "water step cannot land on units or self")
	check(Vector2i(0,0) not in model["range"], "water step cannot cross hard walls")
	check(model["affected"]==[Vector2i(1,3)], "step highlights destination effect")
	check(Vector2i(0,1) not in Actions.target_cells(battle,A,"SK_YUE_THRUST"), "attack range excludes wall")
	model = Model.build(battle,A,"SK_YUE_GUARD",Vector2i(1,1))
	check(model["targets"]==[Vector2i(1,1)] and Vector2i(2,1) in model["range"], "support area distinct from self cast target")
	check(model["affected"].size()==2 and Vector2i(1,2) in model["affected"] and Vector2i(2,1) not in model["affected"], "support affects allies, not enemy within area")
	check(Model.build(battle,A,"SK_YUE_GUARD",Vector2i(1,2))["affected"].is_empty(), "invalid self cast does not show affected units")
	check(Text.damage_summary(battle,A,"ACT_BREATH")=="不造成伤害", "defense and recovery have no fictitious damage")
	for identifier: String in ["SK_STICK_GUARD","ACT_BREATH","SK_YUE_GUARD","SK_WATER_STEP","SK_TRIP_WRIST"]:
		check(not Text.effect_summary(battle.skill(identifier)).is_empty(), "effect description " + identifier)
	check(Text.skill_type(battle.skill("SK_TRIP_WRIST"))=="攻击／减益", "attack plus debuff category")
	check(Text.skill_type(battle.skill("SK_YUE_GUARD"))=="防御／援护", "support category")
	check(Text.skill_type(battle.skill("ACT_BREATH"))=="恢复／防御", "recovery category")
	check(Text.skill_type(battle.skill("SK_WATER_STEP"))=="机动／防御", "mobility category")
	check("回内力1" in Text.effect_summary(battle.skill("SK_FIST_BASIC")), "basic attack resource benefit visible")
	data = close_data()
	data["units"][0]["qi"] = 0
	battle = create(data)
	before = battle.snapshot()
	model = Model.build(battle,A,"SK_YUE_THRUST",Vector2i(2,1))
	check(not model["range"].is_empty() and model["targets"].is_empty() and "内力不足" in model["reason"], "qi lock distinguishes theoretical and legal range")
	check(not battle.perform_action(A,"SK_YUE_THRUST",Vector2i(2,1),battle.revision)["ok"] and battle.snapshot()==before, "range display grants no unavailable action")
	battle = create(close_data())
	check(battle.perform_action(A,"SK_YUE_GUARD",Vector2i(1,1),battle.revision)["ok"], "start cooldown")
	while battle.current_actor_id()!=A:
		var actor := battle.current_actor_id()
		check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"], "advance to next turn")
	model = Model.build(battle,A,"SK_YUE_GUARD",Vector2i(1,1))
	check(not model["range"].is_empty() and model["targets"].is_empty() and "冷却中" in model["reason"], "cooldown range remains visible and blocked")


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func layout(label: String, save := false) -> void:
	await process_frame
	for node: Label in [screen.heading,screen.stats,screen.menu,screen.disabled_menu,screen.detail,screen.footer]:
		check(Rect2(0,0,640,360).encloses(node.get_rect()), label + " viewport bounds")
		check(node.get_minimum_size().y<=node.size.y, label + " text fits")
	check(not screen.stats.get_rect().intersects(screen.menu.get_rect()), label + " stats/menu separate")
	check(not screen.menu.get_rect().intersects(screen.detail.get_rect()), label + " menu/detail separate")
	check(not screen.disabled_menu.get_rect().intersects(screen.detail.get_rect()), label + " disabled menu/detail separate")
	check(not screen.detail.get_rect().intersects(screen.footer.get_rect()), label + " detail/footer separate")
	if captures and save:
		check(DisplayServer.get_name()!="headless", "capture requires real renderer")
		if DisplayServer.get_name()=="headless": return
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://builds/qa/skill_"+label+".png")==OK, "save skill capture")


func selectable_layout(prefix: String) -> void:
	var rows := Commands.entries(screen.battle)
	for index: int in range(rows.size()):
		for attempt: int in range(rows.size()):
			if screen.selection == index: break
			await key(KEY_DOWN)
		check(screen.selection==index, "all rows focusable for inspection")
		await layout(prefix+"_menu_%d" % index, prefix=="main" and index==5)
		if not rows[index]["enabled"]:
			check(rows[index]["disabled_label"] in screen.disabled_menu.text, "disabled row visible with reason")
			var before: Dictionary = screen.battle.snapshot()
			await key(KEY_E)
			check(screen.mode=="command" and screen.selection==index and screen.battle.snapshot()==before, "inspection cannot activate disabled command")
			continue
		await key(KEY_E)
		await layout(prefix+"_target_%d" % index, prefix=="main" and index==5)
		await key(KEY_ESCAPE)


func _ui() -> void:
	var data := close_data()
	data["units"][0]["agility"] = 4
	data["units"][2]["cell"] = [2,2]
	screen = Screen.new()
	screen.battle = create(data)
	screen.auto_ai = false
	root.add_child(screen)
	await process_frame
	var before: Dictionary = screen.battle.snapshot()
	for index: int in range(4): await key(KEY_DOWN)
	check(screen.selection==4 and "攻击／减益" in screen.options()[4], "typed skills retain familiar command ordering")
	check(Vector2i(0,2) in screen.board.range_cells and Vector2i(2,2) in screen.board.valid_targets, "menu hover shows empty range and legal target before confirmation")
	await layout("attack_menu",true)
	await key(KEY_E)
	await key(KEY_RIGHT)
	check(screen.cursor==Vector2i(2,2), "target cursor follows keyboard")
	await layout("attack_target",true)
	await key(KEY_E)
	check(screen.mode=="action_confirm", "valid attack confirmation")
	var prepared: Dictionary = screen.preview.duplicate(true)
	await key(KEY_F1)
	await key(KEY_F1)
	check(screen.mode=="action_confirm" and screen.preview==prepared, "rules toggle restores prepared confirmation")
	await key(KEY_ESCAPE)
	check(screen.mode=="target" and screen.cursor==Vector2i(2,2), "back from confirm retains target")
	for popup: Key in [KEY_F1,KEY_R,KEY_F2]:
		await key(popup)
		await key(KEY_ESCAPE)
		check(screen.mode=="target" and screen.cursor==Vector2i(2,2), "popup back resumes target " + str(popup))
	await key(KEY_ESCAPE)
	check(screen.mode=="command" and screen.selection==4, "back retains skill selection, not first command")
	for popup: Key in [KEY_F1,KEY_R,KEY_F2,KEY_F,KEY_ESCAPE]:
		await key(popup)
		await key(KEY_ESCAPE)
		check(screen.mode=="command" and screen.selection==4, "popup back retains menu selection " + str(popup))
	await key(KEY_E)
	check(screen.cursor==Vector2i(2,2), "re-enter same skill remembers last target")
	check(screen.battle.snapshot()==before, "navigation has no resource or revision cost")
	await key(KEY_ESCAPE)
	await key(KEY_DOWN)
	await key(KEY_E)
	check(screen.cursor==Vector2i(1,2), "another skill has independent cursor memory")
	await key(KEY_RIGHT)
	await key(KEY_RIGHT)
	await key(KEY_ESCAPE)
	await key(KEY_UP)
	await key(KEY_E)
	check(screen.cursor==Vector2i(2,2), "switching back retains original skill cursor")
	await key(KEY_ESCAPE)
	await selectable_layout("companion")
	await key(KEY_R)
	await key(KEY_E)
	check(screen.selection==0 and screen._target_cursors.is_empty(), "retry clears stale navigation cache")
	# Real confirmed action moves to the other ally, with a fresh menu.
	for index: int in range(3): await key(KEY_DOWN)
	await key(KEY_E)
	await key(KEY_E)
	await key(KEY_E)
	check(screen.battle.current_actor_id()==A and screen.selection==0, "actor change resets selection")
	await selectable_layout("main")
	# Gray rows remain inspectable; only activation is forbidden.
	await key(KEY_DOWN)
	check(screen.selection==0 and "绝技未解锁" in screen.disabled_menu.text, "all-row navigation wraps after inspectable ultimate")
	root.remove_child(screen)
	screen.queue_free()
	await process_frame


func _run() -> void:
	create_timer(60).timeout.connect(func() -> void: printerr("SKILL_PREVIEW_FAIL watchdog"); quit(1))
	captures = "--capture-skills" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/tools/battle_lab/combat_encounter.json"))
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	_rules()
	await _ui()
	print("SKILL_PREVIEW: %d checks, %d failures (automated, not human playtest)" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
