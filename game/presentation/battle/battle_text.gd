extends RefCounted
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const STATUS_NAMES := {"guard":"守势", "broken":"破势", "pin":"牵制", "bleed":"流血", "support":"援护"}
const STATUS_HELP := "守势：减伤2，一击或下次行动开始到期。\n破势：护体-2，至该单位行动结束。\n牵制：下一次移动-2，最低0格。\n流血：行动后失血1，持续2次。\n援护：相邻施术者代受首击并减伤1，\n本轮结束到期，不连锁。"


static func statuses(unit: Dictionary) -> String:
	var names: Array[String] = []
	for status: String in unit.get("statuses", {}):
		var detail: Dictionary = unit["statuses"][status]
		names.append(STATUS_NAMES[status] + ("%d" % detail["remaining"] if status == "bleed" else ""))
	return "／".join(names) if not names.is_empty() else "无"


static func skill_detail(battle: CombatEncounter, actor: String, identifier: String) -> String:
	var skill := battle.skill(identifier)
	var shapes := {"adjacent":"相邻1格", "line":"正交直线%d格" % skill["range"], "self":"自身", "step":"穿过单位至%d步内空格" % skill["range"]}
	var effects: Array[String] = []
	for status: String in skill["effects"]: effects.append(STATUS_NAMES[status])
	var detail := "%s · 内力%d · 冷却%d轮\n%s" % [shapes[skill["range_pattern"]], skill["qi_cost"], skill["cooldown_rounds"], "／".join(effects) if not effects.is_empty() else "无附加状态"]
	if skill["restore_qi"] > 0: detail += " · 回内力%d" % skill["restore_qi"]
	var reason := Actions.unavailable(battle, actor, identifier)
	if skill["ultimate"] or not reason.is_empty(): detail += "\n" + ("条件已满足，每战一次" if reason.is_empty() else reason)
	return detail


static func preview_detail(battle: CombatEncounter, preview: Dictionary) -> String:
	if not preview.get("ok", false): return preview.get("reason", "请选择目标")
	var detail := "内力消耗%d／恢复%d" % [preview["qi_cost"], preview["restore_qi"]]
	for hit: Dictionary in preview["hits"]:
		detail += "\n%s%s：伤害%d（实扣%d）" % [battle.unit(hit["receiver"])["name"], "援护代受" if hit["redirected"] else "", hit["damage"], hit["actual"]]
	var effects: Array[String] = []
	for effect: String in preview["effects"]: effects.append(STATUS_NAMES[effect])
	if not effects.is_empty(): detail += "\n施加：" + "／".join(effects)
	return detail
