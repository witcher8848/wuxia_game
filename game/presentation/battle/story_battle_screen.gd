extends "res://game/presentation/battle/battle_screen.gd"
## Story wrapper; permanent changes are requested from the session, never made here.
signal settlement_requested
signal retry_requested
var reveal_intent := false
var ferry_deployment := false
var briefing: Panel
var briefing_body: RichTextLabel

func _ready() -> void:
	super._ready()
	briefing = Panel.new()
	briefing.position = Vector2(12, 8)
	briefing.size = Vector2(616, 344)
	briefing.z_index = 10
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#171820")
	style.border_color = Color("#bca77c")
	style.set_border_width_all(2)
	style.expand_margin_left = 12
	style.expand_margin_right = 12
	style.expand_margin_top = 8
	style.expand_margin_bottom = 8
	briefing.add_theme_stylebox_override("panel", style)
	add_child(briefing)
	var title := _label(Vector2(16, 12), Vector2(580, 28), 18)
	title.text = tr("BATTLE_STORY_TITLE")
	title.reparent(briefing, false)
	briefing_body = RichTextLabel.new()
	briefing_body.position = Vector2(16, 48)
	briefing_body.size = Vector2(580, 242)
	briefing_body.add_theme_font_override("normal_font", preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf"))
	briefing_body.add_theme_font_size_override("normal_font_size", 14)
	briefing.add_child(briefing_body)
	var keys := _label(Vector2(16, 302), Vector2(580, 32), 12)
	keys.text = tr("BATTLE_STORY_KEYS")
	keys.reparent(briefing, false)
	_open_briefing()

func _process(delta: float) -> void:
	if is_instance_valid(briefing) and briefing.visible: return
	super._process(delta)

func _open_briefing() -> void:
	briefing_body.text = "\n\n".join([
		tr("BATTLE_STORY_CAUSE"),
		tr("BATTLE_INTEL_HOME" if reveal_intent else "BATTLE_NO_HOME"),
		tr("BATTLE_INTEL_DOCK" if ferry_deployment else "BATTLE_NO_DOCK"),
		tr("BATTLE_STORY_LIMITS"),
		"战斗规则（PgDn）\n" + Text.STATUS_HELP + "\n" + Text.resource_help(battle, "CHAR_PROTAGONIST")])
	briefing_body.scroll_to_line(0)
	briefing.show()

func options() -> Array[String]:
	if mode == "result":
		if battle.outcome == "victory": return ["确认胜利结算", "原配置重试", "查看目标说明", "返回出发前"]
		return ["原配置重试", "返回出发前", "查看目标说明"]
	return super.options()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(briefing) and briefing.visible:
		get_viewport().set_input_as_handled()
		if event.is_echo(): return
		if event.is_action_pressed("confirm") or event.is_action_pressed("cancel") or (event is InputEventKey and event.pressed and event.physical_keycode in [KEY_TAB, KEY_F1]):
			briefing.hide()
		elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_PAGEDOWN, KEY_PAGEUP]:
			briefing_body.get_v_scroll_bar().value += 100 if event.physical_keycode == KEY_PAGEDOWN else -100
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		_open_briefing()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		get_viewport().set_input_as_handled()
		return # A story battle cannot switch to a different laboratory objective.
	var previous_mode := mode
	super._unhandled_input(event)
	# The first F inspection demonstrates the earned information immediately.
	if previous_mode == "command" and mode == "inspect" and reveal_intent and battle.round_number == 1:
		for identifier: String in battle.pending_ids():
			if battle.unit(identifier)["team"] == "enemy":
				cursor = Grid.cell_of(battle.unit(identifier))
				refresh()
				break

func confirm() -> void:
	if is_instance_valid(briefing) and briefing.visible:
		briefing.hide()
		return
	if mode == "retry":
		retry_requested.emit()
		return
	if mode == "result":
		if battle.outcome == "victory":
			match selection:
				0: settlement_requested.emit()
				1: _open_mode("retry")
				2: _open_briefing()
				3: _open_mode("quit")
		else:
			match selection:
				0: _open_mode("retry")
				1: _open_mode("quit")
				2: _open_briefing()
		return
	super.confirm()

func refresh() -> void:
	super.refresh()
	if battle == null or board == null: return
	if mode == "command" and selection > 0 and battle.unit(battle.current_actor_id()).get("team") == "ally":
		# Keep both the shared range legend and the focused command's explanation.
		# Replacing the shared controls line makes room for story context without
		# hiding the reason a gray skill cannot execute or overflowing the footer.
		var shared_lines := footer.text.split("\n")
		footer.text = shared_lines[0] + "\n" + shared_lines[-1] + "\nE确认 · Esc返回 · F查看 · F1情报 · R重试｜首轮推演:%s · 近道:%s" % ["有" if reveal_intent else "无", "有" if ferry_deployment else "无"]
	elif mode in ["command", "result", "retry", "quit", "help"]:
		footer.text = "E 确认 · Esc 返回 · F 查看单位 · F1 目标/情报 · R 重试\n" + ("住所校勘→首轮F推演" if reveal_intent else "未校勘→无首轮推演") + " · " + ("码头质证→近道部署" if ferry_deployment else "未质证→旧道部署")
		footer.text += "\n" + (message if not message.is_empty() else "击退追兵，掩护证人撤离；只有胜利结算才推进时段")
	if mode == "result":
		detail.text = "待确认：解救目标完成，信任+1，\n推进1时段。原件归属不变。" if battle.outcome == "victory" else "失败不结算、不推进时段。\n可重试或恢复出发前继续调查。"
	elif mode == "quit":
		menu.text = "返回出发前？\n放弃本局；任务和时间恢复原状。\nE确认，Esc继续战斗。"
	elif mode == "help":
		detail.text = "击退刀役与弓役，掩护老妇撤离。\nF查看敌人；情报只在首轮有效。"
	elif mode == "inspect":
		footer.text = "方向键查看单位 · Esc返回 · R重试（确认）\n战中不能保存；只有胜利结算才推进时段"
		var inspected := battle.unit(battle.unit_at(cursor))
		if not inspected.is_empty(): detail.text = Text.status_detail(battle, inspected)
		_show_forecast()
		if get("inspect_status") == true and not inspected.is_empty():
			detail.text = Text.status_detail(battle, inspected)
		footer.text += "\nV 状态期限／推演说明"
	board.queue_redraw()

func _show_forecast() -> void:
	var inspected: Dictionary = battle.unit(battle.unit_at(cursor))
	if inspected.is_empty() or inspected["team"] != "enemy": return
	if not reveal_intent or battle.round_number != 1:
		detail.text = "未获首轮编组情报。仅显示移动。\nEsc返回。" if not reveal_intent else "编组情报仅适用于首轮。\n紫色显示移动范围。Esc返回。"
		return
	var forecast: CombatEncounter = battle.forecast_turn(inspected["id"])
	if forecast == null:
		detail.text = "该敌人本轮已行动。\n紫色显示移动范围。Esc返回。"
		return
	var plan: Dictionary = AI.plan(forecast, inspected["id"])
	if plan.is_empty(): return
	var destination: Vector2i = plan["destination"]
	if destination != Grid.cell_of(inspected):
		forecast.move_actor(inspected["id"], destination, forecast.revision)
	var ability: Dictionary = forecast.skill(plan["skill_id"])
	var range_skill: String = plan["skill_id"]
	if ability["target"] != "enemy":
		range_skill = ""
		# Show a theoretical attack shape only for a registered attack in this
		# actor's own loadout; no archetype-specific phantom skills are injected.
		for identifier: String in inspected.get("skills", []):
			if forecast.skill(identifier).get("target") == "enemy":
				range_skill = identifier
				break
		if range_skill.is_empty():
			for identifier: String in forecast.abilities(inspected["id"]):
				if forecast.skill(identifier).get("target") == "enemy":
					range_skill = identifier
					break
	var model: Dictionary = SkillPreview.build(forecast, inspected["id"], range_skill, plan["target"]) if not range_skill.is_empty() else {"range": [], "affected": []}
	board.range_cells = model["range"]
	board.range_offensive = not range_skill.is_empty()
	board.valid_targets = [plan["target"]] if ability["target"] == "enemy" else []
	board.affected = model["affected"] if ability["target"] == "enemy" else []
	board.path = [Grid.cell_of(inspected), destination]
	var target_name: String = battle.unit(battle.unit_at(plan["target"])).get("name", "自身")
	if ability["target"] != "enemy": target_name = "自身"
	menu.text += "\n住所校勘情报：预计移至(%d,%d)" % [destination.x, destination.y]
	menu.text += "\n%s → %s" % [ability["name"], target_name]
	detail.text = "攻击距离 %d 格（非移动距离）。\n按当前站位推演，行动前会重算。\n首轮有效；不保证后续站位不变。" % int(forecast.skill(range_skill).get("range", 0))
	footer.text = "紫色移动 · 淡色为推演落点攻击范围（不等于本轮会攻击）\n亮框为预计攻击目标 · 方向键查看 · Esc返回；推演不消耗行动"
