extends Node2D
## Reusable battle view; entry wrapper supplies state. Never accesses GameSession.
signal exit_requested
signal scenario_requested(kind: String)
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
const Board = preload("res://game/presentation/battle/battle_board.gd")
var battle: CombatEncounter
var board: Node2D
var heading: Label
var stats: Label
var menu: Label
var detail: Label
var footer: Label
var cursor := Vector2i.ZERO
var mode := "command"
var selection := 0
var selected_skill := ""
var preview: Dictionary = {}
var message := ""
var ai_delay := 0.0
var auto_ai := true
var startup_error := ""


func _ready() -> void:
	board = Board.new()
	add_child(board)
	heading = _label(Vector2(12,5), Vector2(620,27), 16)
	stats = _label(Vector2(346,36), Vector2(282,49), 13)
	menu = _label(Vector2(346,87), Vector2(282,145), 12)
	menu.add_theme_constant_override("line_spacing", -4)
	detail = _label(Vector2(346,234), Vector2(282,62), 12)
	footer = _label(Vector2(12,300), Vector2(616,57), 12)
	if battle == null:
		startup_error = "BattleScreen requires an encounter."
		push_error(startup_error)
		return
	actor_changed()


func _label(at: Vector2, extent: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = extent
	label.add_theme_font_override("font", preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func actor_changed() -> void:
	selection = 0
	preview.clear()
	mode = "result" if battle.outcome != "ongoing" else "command"
	var unit := battle.unit(battle.current_actor_id())
	if not unit.is_empty(): cursor = Grid.cell_of(unit)
	ai_delay = 0.0
	refresh()


func _process(delta: float) -> void:
	if battle == null or not auto_ai or mode != "command" or battle.outcome != "ongoing": return
	if battle.unit(battle.current_actor_id())["team"] != "enemy": return
	ai_delay += delta
	if ai_delay < 0.85: return
	var result: Dictionary = AI.take_turn(battle)
	message = "" if result["ok"] else result["reason"]
	actor_changed()


func options() -> Array[String]:
	if mode == "result": return ["原配置重试", "返回战前选择目标", "查看目标说明", "退出实验场"]
	if mode == "scenario": return ["击退刀役与弓役", "主角撤离至绿框（无需清场）"]
	var result: Array[String] = ["移动" if not battle.moved else "移动（已用）"]
	for identifier: String in battle.abilities(battle.current_actor_id()): result.append(battle.skill(identifier)["name"])
	return result


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or battle == null: return
	# Scene switching may detach this node during a confirmation callback.
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_F1:
		mode = "help" if mode != "help" else ("result" if battle.outcome != "ongoing" else "command")
		selection = 0
	elif event.keycode == KEY_R:
		mode = "retry"
	elif event.keycode == KEY_F2:
		mode = "scenario"
		selection = 0
	elif event.is_action_pressed("cancel"):
		cancel()
	elif event.is_action_pressed("confirm"):
		confirm()
	elif mode in ["command", "result", "scenario"]:
		if event.is_action_pressed("move_up"): selection = posmod(selection-1, options().size())
		elif event.is_action_pressed("move_down"): selection = posmod(selection+1, options().size())
		elif event.keycode == KEY_F and mode == "command": mode = "inspect"
	elif mode in ["move", "target", "inspect"]:
		var direction := Vector2i.ZERO
		if event.is_action_pressed("move_up"): direction = Vector2i.UP
		elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
		elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
		elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT
		if battle.contains(cursor+direction): cursor += direction
	refresh()


func cancel() -> void:
	match mode:
		"command", "result": mode = "quit"
		"move_confirm": mode = "move"
		"action_confirm": mode = "target"
		_: mode = "result" if battle.outcome != "ongoing" else "command"
	selection = 0
	preview.clear()
	message = ""


func confirm() -> void:
	var actor := battle.current_actor_id()
	match mode:
		"quit": exit_requested.emit()
		"retry":
			battle.retry()
			message = "已恢复战前快照"
			actor_changed()
		"help": cancel()
		"scenario": scenario_requested.emit("eliminate" if selection == 0 else "escape")
		"result":
			match selection:
				0: mode = "retry"
				1: mode = "scenario"; selection = 0
				2: mode = "help"
				3: mode = "quit"
		"command":
			if battle.unit(actor)["team"] != "ally": return
			if selection == 0:
				if battle.moved: message = "移动已确认；本回合不能重新移动"; return
				mode = "move"
			else:
				selected_skill = battle.abilities(actor)[selection-1]
				mode = "target"
				cursor = Grid.cell_of(battle.unit(actor))
		"move":
			preview = battle.preview_move(actor, cursor)
			if preview["ok"]: mode = "move_confirm"
			else: message = preview["reason"]
		"target":
			preview = battle.preview_action(actor, selected_skill, cursor)
			if preview["ok"]: mode = "action_confirm"
			else: message = preview["reason"]
		"move_confirm":
			var result := battle.move_actor(actor, cursor, preview["revision"])
			message = "移动已确认，请选择一次行动" if result["ok"] else result["reason"]
			actor_changed()
		"action_confirm":
			var result := battle.perform_action(actor, selected_skill, cursor, preview["revision"])
			message = "" if result["ok"] else result["reason"]
			actor_changed()


func refresh() -> void:
	if battle == null or board == null: return
	var actor := battle.current_actor_id()
	var unit := battle.unit(actor)
	var goal := "击退全部敌人" if battle.objective["kind"] == "eliminate" else "主角抵达右下绿框"
	var order: Array[String] = []
	for identifier: String in battle.pending_ids(): order.append(battle.unit(identifier)["name"])
	heading.text = "第%d轮 · %s｜%s" % [battle.round_number, goal, "→".join(order)]
	stats.text = "战斗结束：" + ("胜利" if battle.outcome == "victory" else "失败") if unit.is_empty() else "%s  气血%d/%d  内力%d/%d\n状态：%s" % [unit["name"], unit["hp"], unit["max_hp"], unit["qi"], unit["max_qi"], Text.statuses(unit)]
	board.battle = battle
	board.cursor = cursor
	board.highlights = []
	board.path = []
	board.affected = []
	board.inspect_enemy = false
	detail.text = ""
	footer.text = "↑↓/W/S 选项 · E/Enter 确认 · Esc 返回 · F 查看单位\nF1 规则 · F2 战前目标 · R 重试（确认） · 不写探索存档"
	if not message.is_empty(): footer.text += "\n" + message
	elif not battle.events.is_empty(): footer.text += "\n最近：" + battle.events[-1]
	match mode:
		"command", "result", "scenario":
			var lines: Array[String] = []
			var choices := options()
			for index: int in range(choices.size()): lines.append(("› " if index == selection else "  ") + choices[index])
			menu.text = "\n".join(lines)
			if mode == "command" and unit["team"] == "enemy":
				menu.text = "敌方行动中…\n" + AI.intent(battle, actor)["kind"]
				board.highlights = AI.intent(battle, actor)["reachable"]
				board.inspect_enemy = true
			elif mode == "command" and selection > 0: detail.text = Text.skill_detail(battle, actor, battle.abilities(actor)[selection-1])
			elif mode == "command": detail.text = "移动额度%d格，四向路径。\n确认前可取消；确认后只能行动。" % battle.move_budget
			elif mode == "result": detail.text = "本局没有永久奖励或时间推进。\n重试恢复站位、资源、状态与队列。"
		"move", "move_confirm":
			board.highlights = battle.movement_paths(actor).keys()
			var move := battle.preview_move(actor, cursor)
			if move["ok"]: board.path = move["path"]
			menu.text = "选择目的地 (%d,%d)\n可用%d格\n%s" % [cursor.x, cursor.y, battle.move_budget, "路径消耗%d格" % move["cost"] if move["ok"] else move["reason"]]
			detail.text = "再次确认才移动；Esc撤回预览" if mode == "move_confirm" else "方向键/WASD移动光标\nE预览；Esc取消，不消耗移动"
		"target", "action_confirm":
			var action := battle.preview_action(actor, selected_skill, cursor)
			for y: int in range(battle.board_size.y):
				for x: int in range(battle.board_size.x):
					if battle.preview_action(actor, selected_skill, Vector2i(x,y))["ok"]: board.highlights.append(Vector2i(x,y))
			menu.text = battle.skill(selected_skill)["name"] + "\n" + Text.skill_detail(battle, actor, selected_skill) + "\n\n" + Text.preview_detail(battle, action)
			if action["ok"]:
				for identifier: String in action["affected"]: board.affected.append(Grid.cell_of(battle.unit(identifier)))
			detail.text = "再次确认执行一次行动；Esc返回" if mode == "action_confirm" else "方向键选目标；E预览；Esc返回\n有色格为当前合法目标"
		"inspect":
			var inspected := battle.unit(battle.unit_at(cursor))
			menu.text = "空地／障碍" if inspected.is_empty() else "%s 气血%d/%d\n内力%d/%d 身法%d\n状态：%s" % [inspected["name"], inspected["hp"], inspected["max_hp"], inspected["qi"], inspected["max_qi"], inspected["agility"], Text.statuses(inspected)]
			if not inspected.is_empty() and inspected["team"] == "enemy":
				var intent := AI.intent(battle, inspected["id"])
				menu.text += "\n" + intent["kind"]
				board.highlights = intent["reachable"]
				board.inspect_enemy = true
			detail.text = "紫色为移动范围；没有额外情报时\n不显示具体攻击目标。Esc返回。"
		"help": menu.text = Text.STATUS_HELP; detail.text = goal + "\n普攻回内力1；吐纳回2并守势。"
		"retry": menu.text = "重试当前配置？\n全部临时战斗进度将恢复。\nE确认，Esc保留当前战斗。"
		"quit": menu.text = "退出战斗实验场？\n不会影响探索进度。\nE退出，Esc继续。"
	board.queue_redraw()
