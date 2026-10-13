extends Node2D
## Reusable battle view; entry wrapper supplies state. Never accesses GameSession.
signal exit_requested
signal scenario_requested(kind: String)
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")
const Board = preload("res://game/presentation/battle/battle_board.gd")
const SkillPreview = preload("res://game/presentation/battle/battle_skill_preview.gd")
const Commands = preload("res://game/presentation/battle/battle_command_options.gd")
const MovementPreview = preload("res://game/presentation/battle/battle_movement_preview.gd")
var battle: CombatEncounter
var board: Node2D
var heading: Label
var stats: Label
var menu: Label
var disabled_menu: Label
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
var inspect_status := false
var _navigation: Array[Dictionary] = []
var _target_cursors: Dictionary = {}


func _ready() -> void:
	board = Board.new()
	add_child(board)
	heading = _label(Vector2(12,5), Vector2(620,27), 16)
	stats = _label(Vector2(346,36), Vector2(282,44), 13)
	menu = _label(Vector2(346,84), Vector2(282,120), 12)
	menu.add_theme_constant_override("line_spacing", -4)
	# Disabled rows remain gray while a separate bright pointer permits inspection.
	disabled_menu = _label(menu.position, menu.size, 12)
	disabled_menu.add_theme_constant_override("line_spacing", -4)
	disabled_menu.add_theme_color_override("font_color", Color("#929aa3"))
	detail = _label(Vector2(346,208), Vector2(282,88), 12)
	detail.add_theme_constant_override("line_spacing", -4)
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
	inspect_status = false
	_navigation.clear()
	_target_cursors.clear()
	selected_skill = ""
	selection = 0
	preview.clear()
	mode = "result" if battle.outcome != "ongoing" else "command"
	if mode == "command": selection = Commands.next_enabled(Commands.entries(battle), 0)
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
	if result["ok"]: board.animate_action(result["plan"])
	message = "" if result["ok"] else result["reason"]
	actor_changed()


func options() -> Array[String]:
	if mode == "result": return ["原配置重试", "返回战前选择目标", "查看目标说明", "退出实验场"]
	if mode == "scenario": return ["击退刀役与弓役", "主角撤离至绿框（无需清场）"]
	var result: Array[String] = []
	for row: Dictionary in Commands.entries(battle): result.append(row["label"])
	return result


func _select(step := 0) -> void:
	# Focus means inspect, not execute. Only confirm() checks executability.
	selection = posmod(selection+step, options().size())
	if step != 0: message = ""


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or battle == null: return
	# Scene switching may detach this node during a confirmation callback.
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_V and mode == "inspect":
		inspect_status = not inspect_status
	elif event.keycode == KEY_F1:
		if mode == "help": cancel()
		else: _open_mode("help")
	elif event.keycode == KEY_R:
		_open_mode("retry")
	elif event.keycode == KEY_F2:
		_open_mode("scenario", true)
	elif event.is_action_pressed("cancel"):
		cancel()
	elif event.is_action_pressed("confirm"):
		confirm()
	elif mode in ["command", "result", "scenario"]:
		if event.is_action_pressed("move_up"): _select(-1)
		elif event.is_action_pressed("move_down"): _select(1)
		elif event.keycode == KEY_F and mode == "command": _open_mode("inspect")
	elif mode in ["move", "target", "inspect"]:
		var direction := Vector2i.ZERO
		if event.is_action_pressed("move_up"): direction = Vector2i.UP
		elif event.is_action_pressed("move_down"): direction = Vector2i.DOWN
		elif event.is_action_pressed("move_left"): direction = Vector2i.LEFT
		elif event.is_action_pressed("move_right"): direction = Vector2i.RIGHT
		if battle.contains(cursor+direction): cursor += direction
	refresh()


func _open_mode(next_mode: String, reset_selection := false) -> void:
	if next_mode == mode: return
	_navigation.append({"mode":mode, "selection":selection, "cursor":cursor, "skill":selected_skill, "preview":preview.duplicate(true), "inspect_status":inspect_status})
	mode = next_mode
	if next_mode == "inspect": inspect_status = false
	if reset_selection: selection = 0
	message = ""


func cancel() -> void:
	if mode in ["command", "result"]:
		_open_mode("quit")
		return
	if mode == "target": _target_cursors[selected_skill] = cursor
	if not _navigation.is_empty():
		var previous: Dictionary = _navigation.pop_back()
		mode = previous["mode"]
		selection = previous["selection"]
		cursor = previous["cursor"]
		selected_skill = previous["skill"]
		preview = previous["preview"]
		inspect_status = previous.get("inspect_status",false)
	else:
		mode = "result" if battle.outcome != "ongoing" else "command"
		preview.clear()
		inspect_status = false
	message = ""


func confirm() -> void:
	var actor := battle.current_actor_id()
	match mode:
		"quit": exit_requested.emit()
		"retry":
			battle.retry()
			board.reset_presentation()
			message = "已恢复战前快照"
			actor_changed()
		"help": cancel()
		"scenario": scenario_requested.emit("eliminate" if selection == 0 else "escape")
		"result":
			match selection:
				0: _open_mode("retry")
				1: _open_mode("scenario", true)
				2: _open_mode("help")
				3: _open_mode("quit")
		"command":
			if battle.unit(actor)["team"] != "ally": return
			var rows := Commands.entries(battle)
			if selection < 0 or selection >= rows.size(): return
			if not rows[selection]["enabled"]:
				message = Commands.hint(battle, selection)
				return
			if selection == 0:
				_open_mode("move")
			else:
				_open_mode("target")
				selected_skill = battle.abilities(actor)[selection-1]
				cursor = _target_cursors.get(selected_skill, Grid.cell_of(battle.unit(actor)))
		"move":
			preview = battle.preview_move(actor, cursor)
			if preview["ok"]: _open_mode("move_confirm")
			else: message = preview["reason"]
		"target":
			preview = battle.preview_action(actor, selected_skill, cursor)
			if preview["ok"]: _open_mode("action_confirm")
			else: message = preview["reason"]
		"move_confirm":
			var result := battle.move_actor(actor, cursor, preview["revision"])
			if result["ok"]: board.animate_move(actor,preview["path"])
			message = "移动已确认，请选择一次行动" if result["ok"] else result["reason"]
			actor_changed()
		"action_confirm":
			var result := battle.perform_action(actor, selected_skill, cursor, preview["revision"])
			if result["ok"]: board.animate_action(result["plan"])
			message = "" if result["ok"] else result["reason"]
			actor_changed()


func refresh() -> void:
	if battle == null or board == null: return
	if mode == "command": _select()
	var actor := battle.current_actor_id()
	var unit := battle.unit(actor)
	var command_spacing: int = -5 if mode == "command" and options().size() >= 9 else -4
	menu.add_theme_constant_override("line_spacing",command_spacing)
	disabled_menu.add_theme_constant_override("line_spacing",command_spacing)
	var goal: String = Text.objective_summary(battle)
	var order: Array[String] = []
	for identifier: String in battle.pending_ids(): order.append(battle.unit(identifier)["name"])
	heading.text = "第%d轮 · %s｜%s" % [battle.round_number, goal, "→".join(order)]
	stats.text = "战斗结束：" + ("胜利" if battle.outcome == "victory" else "失败") if unit.is_empty() else "%s  气血%d/%d  内力%d/%d\n状态：%s" % [unit["name"], unit["hp"], unit["max_hp"], unit["qi"], unit["max_qi"], Text.statuses(unit)]
	board.battle = battle
	board.sync_visuals()
	board.cursor = cursor
	board.highlights = []
	board.path = []
	board.affected = []
	board.range_cells = []
	board.valid_targets = []
	board.range_disabled = false
	board.enemy_reach = []
	board.inspect_enemy = false
	disabled_menu.text = ""
	detail.text = ""
	footer.text = "↑↓/W/S 选项 · E/Enter 确认 · Esc 返回 · F 查看单位\nF1 规则 · F2 战前目标 · R 重试（确认） · 不写探索存档"
	if not message.is_empty(): footer.text += "\n" + message
	elif not battle.events.is_empty(): footer.text += "\n最近：" + battle.events[-1]
	match mode:
		"command", "result", "scenario":
			var lines: Array[String] = []
			var disabled_lines: Array[String] = []
			var choices := options()
			var rows: Array = Commands.entries(battle) if mode == "command" else []
			for index: int in range(choices.size()):
				var disabled: bool = mode == "command" and not rows[index]["enabled"]
				lines.append(("›" if index == selection else "") if disabled else ("› " if index == selection else "  ") + choices[index])
				disabled_lines.append("  " + rows[index]["disabled_label"] if disabled else "")
			menu.text = "\n".join(lines)
			disabled_menu.text = "\n".join(disabled_lines)
			if mode == "command" and unit["team"] == "enemy":
				disabled_menu.text = ""
				menu.text = "敌方行动中…\n" + AI.intent(battle, actor)["kind"]
				board.highlights = AI.intent(battle, actor)["reachable"]
				board.inspect_enemy = true
			elif mode == "command" and selection > 0:
				var identifier: String = battle.abilities(actor)[selection-1]
				detail.text = Text.skill_detail(battle, actor, identifier)
				_show_skill_range(actor, identifier, Grid.cell_of(unit), selection)
			elif mode == "command":
				detail.text = "移动额度%d格，四向路径。\n确认前可取消；确认后只能行动。" % battle.move_budget
				if not rows[0]["enabled"]: detail.text += "\n" + Commands.hint(battle,0)
			elif mode == "result": detail.text = "本局没有永久奖励或时间推进。\n重试恢复站位、资源、状态与队列。"
		"move", "move_confirm":
			board.highlights = battle.movement_paths(actor).keys()
			board.enemy_reach = MovementPreview.enemy_cells(battle, actor)
			footer.text = "青色：我方可走 · 紫框：敌方可走（当前站位，非攻击范围）\n重叠格保留青色与紫框；紫色填充为仅敌方可走\n方向键/WASD选格 · E确认 · Esc逐级返回 · F1规则"
			if not message.is_empty(): footer.text = footer.text.get_slice("\n",0) + "\n" + message + "\n方向键选格 · E确认 · Esc返回"
			var move := battle.preview_move(actor, cursor)
			if move["ok"]: board.path = move["path"]
			menu.text = "选择目的地 (%d,%d)\n可用%d格\n%s" % [cursor.x, cursor.y, battle.move_budget, "路径消耗%d格" % move["cost"] if move["ok"] else move["reason"]]
			detail.text = "再次确认才移动；Esc撤回预览" if mode == "move_confirm" else "方向键/WASD移动光标\nE预览；Esc取消，不消耗移动"
		"target", "action_confirm":
			var action := battle.preview_action(actor, selected_skill, cursor)
			_show_skill_range(actor, selected_skill, cursor)
			menu.text = battle.skill(selected_skill)["name"] + "\n" + Text.skill_detail(battle, actor, selected_skill)
			detail.text = Text.preview_detail(battle, action) + "\n" + ("再次确认执行；Esc返回目标" if mode == "action_confirm" else "方向键选目标；E预览；Esc返回")
		"inspect":
			var inspected := battle.unit(battle.unit_at(cursor))
			menu.text = "空地／障碍" if inspected.is_empty() else "%s 气血%d/%d\n内力%d/%d 身法%d\n状态：%s" % [inspected["name"], inspected["hp"], inspected["max_hp"], inspected["qi"], inspected["max_qi"], inspected["agility"], Text.statuses(inspected)]
			if not inspected.is_empty() and inspected["team"] == "enemy":
				var intent := AI.intent(battle, inspected["id"])
				menu.text += "\n" + intent["kind"]
				board.highlights = intent["reachable"]
				board.inspect_enemy = true
			detail.text = Text.status_detail(battle,inspected) if inspect_status and not inspected.is_empty() else "紫色为移动范围；没有额外情报时\n不显示具体攻击目标。V查看状态到期；Esc返回。"
			footer.text = "方向键查看单位 · V状态/意图切换 · Esc返回 · R重试（确认）"
		"help": menu.text = Text.STATUS_HELP; detail.text = goal + "\n" + Text.resource_help(battle,actor if not unit.is_empty() else "CHAR_PROTAGONIST")
		"retry": menu.text = "重试当前配置？\n全部临时战斗进度将恢复。\nE确认，Esc保留当前战斗。"
		"quit": menu.text = "退出战斗实验场？\n不会影响探索进度。\nE退出，Esc继续。"
	# Reset requested extent after replacing text; Label may grow to its minimum.
	menu.size = Vector2(282,120)
	disabled_menu.size = menu.size
	board.queue_redraw()


func _show_skill_range(actor: String, identifier: String, at: Vector2i, command_index := -1) -> void:
	var model := SkillPreview.build(battle, actor, identifier, at)
	board.range_cells = model["range"]
	board.valid_targets = model["targets"]
	board.affected = model["affected"]
	board.range_disabled = not model["reason"].is_empty()
	board.range_offensive = battle.skill(identifier)["target"] == "enemy"
	footer.text = "淡色格：范围 · 亮框：可选目标 · 橙框：实际受影响\n方向键/WASD选择 · E确认 · Esc逐级返回 · F1规则 · R重试"
	if not message.is_empty(): footer.text += "\n" + message
	elif board.range_disabled: footer.text += "\n灰色仅展示范围；当前不可用：" + model["reason"]
	else: footer.text += "\n预览不消耗行动；攻击须选敌人，自身招式须选自己。"
	if command_index >= 0:
		board.range_disabled = not Commands.entries(battle)[command_index]["enabled"]
		footer.text = "淡色格：范围 · 亮框：可选目标 · 橙框：实际受影响\n↑↓/W/S查看 · 置灰项仅查看，不能施放 · E确认 · Esc返回\n" + Commands.hint(battle,command_index)
