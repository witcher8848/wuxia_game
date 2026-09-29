extends SceneTree
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Commands = preload("res://game/presentation/battle/battle_command_options.gd")
const Movement = preload("res://game/presentation/battle/battle_movement_preview.gd")
const Screen = preload("res://game/presentation/battle/battle_screen.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Effects = preload("res://game/domain/battle/battle_effects.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
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
	if not ok: failures.append(label); printerr("COMMAND_OPTIONS_FAIL ",label)


func create(data: Dictionary) -> CombatEncounter:
	var battle := Combat.new()
	check(battle.configure(data).is_empty(), "valid command fixture")
	return battle


func close_data() -> Dictionary:
	var data := fixture.duplicate(true)
	data["blocked"] = []
	data["units"][0]["cell"] = [1,1]
	data["units"][0]["agility"] = 8
	data["units"][1]["cell"] = [1,2]
	data["units"][2]["cell"] = [2,1]
	data["units"][3]["cell"] = [8,5]
	return data


func _rules() -> void:
	var battle := create(fixture)
	var before := battle.snapshot()
	var rows := Commands.entries(battle)
	check(rows[0]["enabled"] and not rows[1]["enabled"] and rows[2]["enabled"] and rows[3]["enabled"], "no target attacks disabled, movement/guard/breath retained")
	check(not rows[4]["enabled"] and rows[5]["enabled"] and not rows[6]["enabled"], "debuff needs target, step available, ultimate locked")
	check(rows[1]["reason"]=="无合法目标" and "绝技未解锁" in rows[6]["disabled_label"], "disabled reasons visible")
	check(Commands.next_enabled(rows,0,1)==2 and Commands.next_enabled(rows,0,-1)==5, "initial focus helper finds executable options")
	check(Commands.next_enabled(rows,1)==2 and Commands.next_enabled(rows,3)==3, "initial focus can avoid unavailable options")
	check(battle.snapshot()==before, "command query read-only")
	check(Commands.next_enabled([],-1,1)==-1, "empty choices terminate")
	var none: Array[Dictionary] = [{"enabled":false},{"enabled":false}]
	check(Commands.next_enabled(none,0,1)==-1, "all-disabled navigation terminates")
	var data := close_data()
	data["units"][0]["qi"] = 0
	battle = create(data)
	rows = Commands.entries(battle)
	check(rows[1]["enabled"] and not rows[4]["enabled"] and "内力不足" in rows[4]["reason"], "qi does not block basic attack but blocks martial skill")
	check(rows[2]["enabled"] and rows[3]["enabled"], "zero qi always has guard/breath escape from menu")
	data = close_data()
	data["blocked"] = [[0,1],[1,0]]
	data["units"][2]["cell"] = [2,1]
	battle = create(data)
	check(not Commands.entries(battle)[0]["enabled"], "surrounded actor cannot select movement")
	data = close_data()
	data["units"][0]["move"] = 0
	battle = create(data)
	check(not Commands.entries(battle)[0]["enabled"], "zero movement cannot select movement")
	battle = create(close_data())
	check(battle.move_actor(A,Vector2i(0,1),battle.revision)["ok"], "real movement command")
	rows = Commands.entries(battle)
	check(not rows[0]["enabled"] and rows[0]["reason"]=="移动已用", "confirmed movement disabled")
	check(not rows[1]["enabled"] and rows[4]["enabled"], "availability recalculated from new location")
	check(battle.perform_action(A,"SK_YUE_GUARD",Vector2i(0,1),battle.revision)["ok"], "real cooldown skill")
	while battle.current_actor_id()!=A:
		var actor := battle.current_actor_id()
		check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"], "advance turn")
	check(not Commands.entries(battle)[5]["enabled"] and "冷却中" in Commands.entries(battle)[5]["disabled_label"], "cooldown disabled")
	check(battle.retry() and Commands.entries(battle)[5]["enabled"], "retry recomputes availability")
	Effects.hurt(battle,B,A,6,"unlock fixture")
	check(Commands.entries(battle)[7]["enabled"], "ultimate enables with condition plus target")
	check(battle.perform_action(A,"ULT_SWORD",Vector2i(2,1),battle.revision)["ok"], "ultimate executes once")
	while battle.current_actor_id()!=A:
		var actor := battle.current_actor_id()
		check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"], "advance after ultimate")
	check(not Commands.entries(battle)[7]["enabled"] and "本战已用" in Commands.entries(battle)[7]["disabled_label"], "used ultimate disabled")
	check("本战绝技已用" in Commands.hint(battle,7) and "已用1/1" in Text.skill_detail(battle,A,"ULT_SWORD"), "used ultimate retains condition and usage status")


func _enemy_ranges() -> void:
	var battle := create(close_data())
	var before := battle.snapshot()
	var cells := Movement.enemy_cells(battle,A)
	var expected: Array[Vector2i] = []
	for identifier: String in [B,D]:
		for cell: Vector2i in Grid.reachable(battle,identifier,int(battle.unit(identifier)["move"])):
			if not cell in expected: expected.append(cell)
	check(cells.size()==expected.size(), "enemy union has no duplicate cells")
	for cell: Vector2i in expected: check(cell in cells, "all living enemies' movement included")
	check(Vector2i(8,2) not in cells, "bow movement is not bow attack range")
	check(Vector2i(1,1) not in cells and Vector2i(1,2) not in cells, "current ally occupancy blocks enemy routes")
	check(battle.snapshot()==before, "enemy overlay does not plan or advance enemy turns")
	Effects.apply_statuses(battle,A,B,["pin"])
	Effects.hurt(battle,A,D,99,"defeated enemy fixture")
	cells = Movement.enemy_cells(battle,A)
	var pinned := Grid.reachable(battle,B,1)
	check(cells.size()==pinned.size(), "pin reduces budget; defeated enemies excluded")
	for cell: Vector2i in cells: check(pinned.has(cell), "pinned cells match real path budget")
	var data := close_data()
	data["blocked"] = [[3,1],[2,0],[2,2]]
	battle = create(data)
	Effects.hurt(battle,A,D,99,"defeated enemy fixture")
	cells = Movement.enemy_cells(battle,A)
	check(cells==[Vector2i(2,1)], "walls and ally enclosure cannot be crossed")


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


func capture(label: String) -> void:
	await process_frame
	for node: Label in [screen.heading,screen.stats,screen.menu,screen.disabled_menu,screen.detail,screen.footer]:
		check(Rect2(0,0,640,360).encloses(node.get_rect()) and node.get_minimum_size().y<=node.size.y, label+" visible text fits")
	check(not screen.menu.get_rect().intersects(screen.detail.get_rect()) and not screen.disabled_menu.get_rect().intersects(screen.detail.get_rect()), label+" menu/detail separate")
	if not captures: return
	check(DisplayServer.get_name()!="headless", "real renderer required")
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://builds/qa/command_"+label+".png")==OK, "capture "+label)


func _ui() -> void:
	screen = Screen.new()
	screen.battle = create(fixture)
	screen.auto_ai = false
	root.add_child(screen)
	await process_frame
	var before: Dictionary = screen.battle.snapshot()
	await capture("disabled")
	check("无合法目标" in screen.disabled_menu.text and "绝技未解锁" in screen.disabled_menu.text, "gray menu retains reasons")
	for index: int in [1,2,3,4,5,6,0]:
		await key(KEY_DOWN)
		check(screen.selection==index, "keyboard inspects every row forward")
	for index: int in [6,5,4,3,2,1,0]:
		await key(KEY_UP)
		check(screen.selection==index, "keyboard inspects every row backward")
	await key(KEY_UP)
	check(screen.selection==6 and "本人击倒 0/1" in screen.detail.text, "companion trigger and progress readable before unlock")
	check("本人击倒1名敌人" in screen.footer.text and screen.board.range_disabled, "locked explanation and read-only range visible")
	check(screen.menu.text.get_slice("\n",6)=="›", "bright pointer identifies focused gray row")
	await capture("ultimate_companion")
	await key(KEY_E)
	check(screen.mode=="command" and screen.selection==6 and screen.battle.snapshot()==before, "gray-row confirm preserves focus without entering target or spending resources")
	await key(KEY_F1)
	await key(KEY_ESCAPE)
	check(screen.selection==6 and "本人击倒 0/1" in screen.detail.text, "popup returns to inspectable gray row")
	await key(KEY_DOWN)
	await key(KEY_E)
	check(screen.mode=="move" and not screen.board.enemy_reach.is_empty(), "movement shows enemy ranges immediately")
	var enemy_cells: Array = screen.board.enemy_reach.duplicate()
	await key(KEY_RIGHT)
	await capture("movement")
	check(screen.board.enemy_reach==enemy_cells and screen.battle.snapshot()==before, "cursor alone does not pretend units moved")
	await key(KEY_E)
	check(screen.mode=="move_confirm" and screen.board.enemy_reach==enemy_cells, "enemy ranges retained in movement confirmation")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(screen.mode=="command" and screen.board.enemy_reach.is_empty() and screen.battle.snapshot()==before, "cancel clears overlay and preserves state")
	await key(KEY_E)
	await key(KEY_RIGHT)
	await key(KEY_E)
	await key(KEY_E)
	check(screen.battle.moved and screen.selection!=0 and "移动已用" in screen.disabled_menu.text, "confirmed move skips now-disabled row")
	await key(KEY_F1)
	await key(KEY_ESCAPE)
	check(screen.selection!=0 and screen.mode=="command", "popup return cannot focus spent movement")
	await key(KEY_R)
	await key(KEY_E)
	check(screen.selection==0 and not screen.battle.moved and screen.board.enemy_reach.is_empty(), "retry restores availability and clears overlay")
	# Close fixture makes overlapping friendly/enemy movement visible.
	check(screen.battle.configure(close_data()).is_empty(), "load overlap fixture")
	screen.actor_changed()
	await key(KEY_E)
	var overlap := false
	for cell: Vector2i in screen.board.highlights:
		if cell in screen.board.enemy_reach: overlap = true
	check(overlap, "friendly and enemy overlays both retain overlapping cells")
	await capture("overlap")
	await key(KEY_ESCAPE)
	await _condition_help()
	root.remove_child(screen)
	screen.queue_free()
	await process_frame


func _condition_help() -> void:
	await key(KEY_UP)
	check(screen.selection==7 and "实际受敌伤 0/6" in screen.detail.text, "protagonist trigger differs from companion")
	Effects.hurt(screen.battle,B,A,3,"partial progress fixture")
	screen.refresh()
	check("实际受敌伤 3/6" in screen.detail.text and "伤害3点" in screen.footer.text, "partial progress and remaining requirement update")
	await capture("ultimate_progress")
	var before: Dictionary = screen.battle.snapshot()
	await key(KEY_E)
	check(screen.mode=="command" and screen.battle.snapshot()==before, "partial progress does not unlock ultimate")
	Effects.hurt(screen.battle,B,A,3,"full progress fixture")
	screen.refresh()
	check("实际受敌伤 6/6" in screen.detail.text and "触发条件已满足" in screen.footer.text and not screen.board.range_disabled, "same inspected option becomes executable after threshold")
	await capture("ultimate_ready")
	await key(KEY_E)
	await key(KEY_RIGHT)
	await key(KEY_E)
	check(screen.mode=="action_confirm", "unlocked skill enters real target confirmation")
	await key(KEY_E)
	while screen.battle.current_actor_id()!=A:
		var actor: String = screen.battle.current_actor_id()
		check(screen.battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(screen.battle.unit(actor)),screen.battle.revision)["ok"], "advance after inspected ultimate")
	screen.actor_changed()
	await key(KEY_UP)
	check("本战绝技已用" in screen.footer.text and "实际受敌伤 6/6" in screen.detail.text, "used skill still explains trigger but blocks reuse")
	await capture("ultimate_used")
	before = screen.battle.snapshot()
	await key(KEY_E)
	check(screen.mode=="command" and screen.battle.snapshot()==before, "used ultimate inspection cannot execute twice")
	await key(KEY_R)
	await key(KEY_E)
	await key(KEY_UP)
	check("实际受敌伤 0/6" in screen.detail.text and "本战已用" not in screen.footer.text, "retry resets progress and usage explanation")
	var data := close_data()
	data["units"][0]["qi"] = 0
	# An independent resource blocker must not hide the ultimate's trigger.
	for skill: Dictionary in data["skill_definitions"]:
		if skill["id"]=="ULT_SWORD": skill["qi_cost"] = 1
	check(screen.battle.configure(data).is_empty(), "resource blocker fixture")
	screen.actor_changed()
	await key(KEY_UP)
	check("当前0，需要1" in screen.footer.text and "实际受敌伤 0/6" in screen.detail.text, "resource hint and ultimate condition visible together")
	await capture("ultimate_resource")
	check(screen.battle.configure(close_data()).is_empty(), "restore normal fixture")
	check(screen.battle.perform_action(A,"SK_YUE_GUARD",Vector2i(1,1),screen.battle.revision)["ok"], "start cooldown help fixture")
	while screen.battle.current_actor_id()!=A:
		var actor: String = screen.battle.current_actor_id()
		check(screen.battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(screen.battle.unit(actor)),screen.battle.revision)["ok"], "advance cooldown help fixture")
	screen.actor_changed()
	for index: int in range(5): await key(KEY_DOWN)
	check("当前第2轮，第4轮恢复" in screen.footer.text, "cooldown hint gives current and available round")
	await capture("cooldown_help")
	data = fixture.duplicate(true)
	data["units"][0]["agility"] = 8
	check(screen.battle.configure(data).is_empty(), "no target after unlock fixture")
	Effects.hurt(screen.battle,B,A,6,"unlock without target fixture")
	screen.actor_changed()
	await key(KEY_UP)
	check("触发条件已满足，但范围内无合法目标" in screen.footer.text, "unlock distinguished from target availability")
	await capture("ultimate_no_target")
	before = screen.battle.snapshot()
	await key(KEY_E)
	check(screen.mode=="command" and screen.battle.snapshot()==before, "no target still prevents activation after unlock")


func _run() -> void:
	create_timer(60).timeout.connect(func() -> void: printerr("COMMAND_OPTIONS_FAIL watchdog"); quit(1))
	captures = "--capture-commands" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/tools/battle_lab/combat_encounter.json"))
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	_rules()
	_enemy_ranges()
	await _ui()
	print("COMMAND_OPTIONS: %d checks, %d failures (automated, not human playtest)" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
