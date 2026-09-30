extends "res://game/presentation/battle/battle_screen.gd"
## Story wrapper; permanent changes are requested from the session, never made here.
signal settlement_requested
signal retry_requested
var reveal_intent := false
var ferry_deployment := false

func options() -> Array[String]:
	if mode == "result":
		if battle.outcome == "victory": return ["确认胜利结算", "原配置重试", "查看目标说明", "返回出发前"]
		return ["原配置重试", "返回出发前", "查看目标说明"]
	return super.options()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		get_viewport().set_input_as_handled()
		return # A story battle cannot switch to a different laboratory objective.
	super._unhandled_input(event)

func confirm() -> void:
	if mode == "retry":
		retry_requested.emit()
		return
	if mode == "result":
		if battle.outcome == "victory":
			match selection:
				0: settlement_requested.emit()
				1: _open_mode("retry")
				2: _open_mode("help")
				3: _open_mode("quit")
		else:
			match selection:
				0: _open_mode("retry")
				1: _open_mode("quit")
				2: _open_mode("help")
		return
	super.confirm()

func refresh() -> void:
	super.refresh()
	if battle == null or board == null: return
	if mode in ["command", "result", "retry", "quit", "help"]:
		footer.text = "E 确认 · Esc 返回 · F 查看单位 · R 重试（确认）\n" + ("近道部署" if ferry_deployment else "旧坟道部署") + " · " + ("首轮可推演敌方意图" if reveal_intent else "未获编组情报") + " · 只在胜利结算后推进时段"
		if not message.is_empty(): footer.text += "\n" + message
	if mode == "result":
		detail.text = "待确认：解救目标完成，信任+1，\n推进1时段。原件归属不变。" if battle.outcome == "victory" else "失败不结算、不推进时段。\n可重试或恢复出发前继续调查。"
	elif mode == "quit":
		menu.text = "返回出发前？\n放弃本局；任务和时间恢复原状。\nE确认，Esc继续战斗。"
	elif mode == "help":
		detail.text = "击退刀役与弓役，掩护老妇撤离。\nF查看敌人；情报只在首轮有效。"
	elif mode == "inspect":
		footer.text = "方向键查看单位 · Esc返回 · R重试（确认）\n战中不能保存；只有胜利结算才推进时段"
		_show_forecast()
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
		range_skill = "EN_BOW_SHOT" if inspected["archetype"] == "EN_YAMEN_BOW" else "EN_BLADE_PIN"
	var model := SkillPreview.build(forecast, inspected["id"], range_skill, plan["target"])
	board.range_cells = model["range"]
	board.range_offensive = true
	board.valid_targets = [plan["target"]] if ability["target"] == "enemy" else []
	board.affected = model["affected"] if ability["target"] == "enemy" else []
	board.path = [Grid.cell_of(inspected), destination]
	var target_name: String = battle.unit(battle.unit_at(plan["target"])).get("name", "自身")
	if ability["target"] != "enemy": target_name = "自身"
	menu.text += "\n情报：预计移至(%d,%d)" % [destination.x, destination.y]
	menu.text += "\n%s → %s" % [ability["name"], target_name]
	detail.text = "攻击距离 %d 格（非移动距离）。\n按当前站位推演，行动前会重算。\n首轮有效；不保证后续站位不变。" % int(forecast.skill(range_skill)["range"])
	footer.text = "紫色移动 · 淡色为推演落点攻击范围（不等于本轮会攻击）\n亮框为预计攻击目标 · 方向键查看 · Esc返回；推演不消耗行动"
