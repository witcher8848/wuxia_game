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
	var shapes := {"adjacent":"相邻1格", "line":"直线1～%d格" % skill["range"], "self":"自身", "step":"%d步内空格" % skill["range"]}
	if skill["area_pattern"] == "adjacent_allies": shapes["self"] = "自身＋相邻友军"
	var detail := "%s｜%s\n%s\n%s\n耗内力%d · 冷却%d轮" % [skill_type(skill), shapes[skill["range_pattern"]], damage_summary(battle,actor,identifier), effect_summary(skill), skill["qi_cost"], skill["cooldown_rounds"]]
	var reason := Actions.unavailable(battle, actor, identifier)
	if skill["ultimate"]:
		var unit := battle.unit(actor)
		var condition: Dictionary = unit["ultimate"]
		var damage_condition: bool = condition["kind"] == "damage_received"
		detail += "\n本战%s %d/%d｜%s" % ["实际受敌伤" if damage_condition else "本人击倒", unit["damage_received"] if damage_condition else unit["takedowns"], condition["threshold"], "已用1/1" if unit["ultimate_used"] else "每战1次"]
	elif not reason.is_empty(): detail += "\n" + reason
	return detail


static func skill_type(skill: Dictionary) -> String:
	if skill["target"] == "enemy": return "攻击／减益" if not skill["effects"].is_empty() else "攻击"
	if skill["range_pattern"] == "step": return "机动／防御"
	if "support" in skill["effects"]: return "防御／援护"
	if skill["restore_qi"] > 0: return "恢复／防御"
	return "防御"


static func effect_summary(skill: Dictionary) -> String:
	if skill["range_pattern"] == "step": return "穿单位不穿墙；自身守势减伤2"
	if "support" in skill["effects"]: return "自身减伤2；邻友首击代受减伤1"
	var effects: Array[String] = []
	var descriptions := {"guard":"自身守势：下次受击减伤2", "broken":"破势：受击者护体-2", "pin":"牵制：下次移动-2（最低0）", "bleed":"流血：行动后失血1，共2次"}
	for status: String in skill["effects"]: effects.append(descriptions[status])
	if skill["restore_qi"] > 0: effects.append("回内力%d" % skill["restore_qi"])
	return "；".join(effects) if not effects.is_empty() else "无附加状态"


static func damage_summary(battle: CombatEncounter, actor: String, identifier: String) -> String:
	var skill := battle.skill(identifier)
	if skill["target"] != "enemy": return "不造成伤害"
	var amounts: Array[int] = []
	for cell: Vector2i in Actions.target_cells(battle,actor,identifier):
		var action := battle.preview_action(actor,identifier,cell)
		if action["ok"]: amounts.append(int(action["hits"][0]["actual"]))
	if not amounts.is_empty():
		var span := str(amounts.min()) if amounts.min() == amounts.max() else "%d～%d" % [amounts.min(),amounts.max()]
		return "当前可命中：实扣%s（含状态）" % span
	var base := maxi(1,int(skill["power"]) + int(battle.unit(actor)["power"]))
	var bonus := int(skill["distance_bonus"]) if skill["range"] >= 2 else 0
	return "参考%s伤（护体0、无状态）" % (str(base) if bonus == 0 else "%d～%d" % [base,base+bonus])


static func preview_detail(battle: CombatEncounter, preview: Dictionary) -> String:
	if not preview.get("ok", false): return preview.get("reason", "请选择目标")
	var detail := "内力消耗%d／恢复%d" % [preview["qi_cost"], preview["restore_qi"]]
	for hit: Dictionary in preview["hits"]:
		detail += "\n%s%s：伤害%d（实扣%d）" % [battle.unit(hit["receiver"])["name"], "援护代受" if hit["redirected"] else "", hit["damage"], hit["actual"]]
	var effects: Array[String] = []
	for effect: String in preview["effects"]: effects.append(STATUS_NAMES[effect])
	if not effects.is_empty(): detail += "\n施加：" + "／".join(effects)
	return detail
