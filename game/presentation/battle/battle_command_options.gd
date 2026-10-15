extends RefCounted
## Availability is read-only and uses the same previews that authorize execution.
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const Text = preload("res://game/presentation/battle/battle_text.gd")


static func entries(battle: CombatEncounter) -> Array[Dictionary]:
	var actor := battle.current_actor_id()
	var unit := battle.unit(actor)
	var playable: bool = battle.outcome == "ongoing" and unit.get("team") == "ally"
	var move_reason := ""
	if not playable: move_reason = "不是我方回合"
	elif battle.moved: move_reason = "移动已用"
	elif battle.movement_paths(actor).size() <= 1: move_reason = "无可走格"
	var result: Array[Dictionary] = [_row("移动", "移动", move_reason)]
	for identifier: String in battle.abilities(actor):
		var skill := battle.skill(identifier)
		var reason := Actions.unavailable(battle, actor, identifier) if playable else "不是我方回合"
		if reason.is_empty():
			var has_target := false
			for cell: Vector2i in Actions.target_cells(battle, actor, identifier):
				if battle.preview_action(actor, identifier, cell)["ok"]:
					has_target = true
					break
			if not has_target: reason = "无合法目标"
		result.append(_row("[%s] %s" % [Text.skill_type(skill),skill["name"]], skill["name"], reason))
	return result


static func _row(label: String, name: String, reason: String) -> Dictionary:
	var short := reason
	if reason.begins_with("内力不足"): short = "内力不足"
	elif reason.begins_with("冷却中"): short = "冷却中"
	elif reason.begins_with("实际受伤") or reason.begins_with("击倒敌人"): short = "绝技未解锁"
	elif reason == "本战绝技已使用": short = "本战已用"
	return {"label":label, "enabled":reason.is_empty(), "reason":reason, "disabled_label":"× %s（%s）" % [name,short]}


static func next_enabled(rows: Array[Dictionary], selected: int, step := 0) -> int:
	# Initial focus after actor/movement changes only; browsing includes gray rows.
	if rows.is_empty(): return -1
	if step == 0 and selected >= 0 and selected < rows.size() and rows[selected]["enabled"]: return selected
	var direction := -1 if step < 0 else 1
	for offset: int in range(1,rows.size()+1):
		var index := posmod(selected+offset*direction, rows.size())
		if rows[index]["enabled"]: return index
	return -1


static func hint(battle: CombatEncounter, index: int) -> String:
	var rows := entries(battle)
	if index < 0 or index >= rows.size(): return ""
	var row := rows[index]
	var reason: String = row["reason"]
	if index == 0:
		if reason == "移动已用": return "本回合已移动；先完成一次行动，下回合恢复移动。"
		if reason == "无可走格": return "没有可到达的其他空格；可先执行守势、吐纳等行动。"
		return "按E选择目的地；预览和取消不消耗移动。" if row["enabled"] else reason
	var actor := battle.current_actor_id()
	var unit := battle.unit(actor)
	var skill := battle.skill(battle.abilities(actor)[index-1])
	if skill["ultimate"] and unit["ultimate_used"]: return "本战绝技已用（每战仅1次）；下一场战斗恢复使用次数。"
	if reason.begins_with("内力不足"):
		var recovery := "普攻或吐纳" if battle.action_restore_qi(actor,"SK_FIST_BASIC") > 0 else "吐纳"
		return "内力不足：当前%d，需要%d；可用%s恢复。" % [unit["qi"],skill["qi_cost"],recovery]
	if reason.begins_with("冷却中"):
		return "冷却中：当前第%d轮，第%d轮恢复；可先使用其他招式。" % [battle.round_number,unit["cooldowns"][skill["id"]]]
	if skill["ultimate"]:
		var condition: Dictionary = unit["ultimate"]
		var damage_condition: bool = condition["kind"] == "damage_received"
		var progress := int(unit["damage_received"] if damage_condition else unit["takedowns"])
		var remaining := maxi(0,int(condition["threshold"])-progress)
		if remaining > 0:
			return "尚未解锁：本战还需实际承受敌方伤害%d点；仅查看，不可施放。" % remaining if damage_condition else "尚未解锁：本战还需由本人击倒%d名敌人；仅查看，不可施放。" % remaining
		if reason == "无合法目标": return "触发条件已满足，但范围内无合法目标；先移动接近敌人。"
		if row["enabled"]: return "触发条件已满足；按E选择敌人施放，每战仅1次。"
	if reason == "无合法目标":
		if skill["area_pattern"] == "front_arc": return "定向前排3格没有敌人；先改变站位／方向，友军不受伤。"
		return "范围内没有可落脚空格；需改变站位，不能落在单位或障碍上。" if skill["range_pattern"] == "step" else "当前无合法目标；先移动至攻击范围内，并避开射线遮挡。"
	if row["enabled"] and skill["area_pattern"] == "front_arc": return "按E选相邻方向格（可为空）；前排3格至少一敌，不伤友军。"
	return "按E选择目标；预览不消耗行动，确认后才施放。" if row["enabled"] else reason
