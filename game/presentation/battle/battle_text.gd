extends RefCounted
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const STATUS_NAMES := {"guard":"守势", "broken":"破势", "pin":"牵制", "bleed":"流血", "support":"援护"}
const STATUS_HELP := "守势：减伤2，一击或下次行动开始到期。\n破势：护体-2，至该单位行动结束。\n牵制：下一次移动-2，最低0格。\n流血：行动后失血1，持续2次。\n援护：相邻施术者代受首击并减伤1，\n本轮结束到期，不连锁。"

static func status_help(battle: CombatEncounter) -> String:
	return STATUS_HELP.replace("破势：护体-2，至该单位行动结束。", "破势：下一击护体-2，下一轮末到期。") if battle.skill("SK_TRIP_WRIST").get("broken_mode","") == "next_hit" else STATUS_HELP


static func statuses(unit: Dictionary) -> String:
	var names: Array[String] = []
	for status: String in unit.get("statuses", {}):
		var detail: Dictionary = unit["statuses"][status]
		names.append(STATUS_NAMES[status] + ("%d" % detail["remaining"] if status == "bleed" else ""))
	return "／".join(names) if not names.is_empty() else "无"


static func status_detail(battle: CombatEncounter, unit: Dictionary) -> String:
	# Inspection adds expiry information; the compact current-actor row stays short.
	var lines: Array[String] = []
	for status: String in unit.get("statuses", {}):
		var entry: Dictionary = unit["statuses"][status]
		match status:
			"guard": lines.append("守势：减伤2；受击或本人下次行动前到期")
			"broken":
				lines.append("破势：护体-2；下一击用尽／第%d轮末到期" % (int(entry["expires_round"])-1) if entry.get("mode","") == "next_hit" else "破势：护体-2；本人下次行动结束到期")
			"pin": lines.append("牵制：移动-2；本人下次行动结束到期")
			"bleed": lines.append("流血：行动后失血1；余%d次" % int(entry.get("remaining", 0)))
			"support":
				var source_name: String = battle.unit(str(entry.get("source", ""))).get("name", "来源不明")
				lines.append("援护：邻接%s代受首击；本轮末到期" % source_name)
	return "\n".join(lines) if not lines.is_empty() else "状态：无"


static func objective_summary(battle: CombatEncounter) -> String:
	var goal: Dictionary = battle.objective
	match goal.get("kind", ""):
		"eliminate": return "击退全部敌人"
		"escape": return "%s抵达撤离格" % battle.unit(str(goal.get("unit_id", ""))).get("name", "主角")
		"survive": return "保护%s，坚持完整%d轮" % [battle.unit(str(goal.get("protected_unit_id", ""))).get("name", "指定人物"), int(goal.get("rounds", 0))]
	return "完成战斗目标"


static func resource_help(battle: CombatEncounter, actor: String) -> String:
	var breathing: Dictionary = battle.skill("ACT_BREATH")
	return "普攻回内力%d；吐纳回%d%s。" % [battle.action_restore_qi(actor, "SK_FIST_BASIC"), battle.action_restore_qi(actor, "ACT_BREATH"), "并守势" if "guard" in breathing["effects"] else "，不减伤"]


static func skill_detail(battle: CombatEncounter, actor: String, identifier: String) -> String:
	var skill := battle.skill(identifier)
	# Basic resource recovery belongs to the equipped passive, not its legacy
	# action's nominal JSON value. This query changes only the detached copy.
	skill["restore_qi"] = battle.action_restore_qi(actor, identifier)
	var shapes := {"adjacent":"相邻1格", "line":"直线1～%d格" % skill["range"], "self":"自身", "step":"%d步内空格" % skill["range"]}
	if skill["area_pattern"] == "adjacent_allies": shapes["self"] = "自身＋相邻友军"
	if skill["area_pattern"] == "front_arc": shapes["adjacent"] = "相邻定向／前排3格"
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
	if skill["area_pattern"] == "front_arc": return "群攻／截击"
	if skill["target"] == "enemy": return "攻击／减益" if not skill["effects"].is_empty() else "攻击"
	if skill["range_pattern"] == "step": return "机动／防御"
	if "support" in skill["effects"]: return "防御／援护"
	if skill["restore_qi"] > 0: return "恢复／防御" if "guard" in skill["effects"] else "恢复"
	return "防御"


static func effect_summary(skill: Dictionary) -> String:
	if skill["area_pattern"] == "front_arc": return "前排3格伤敌牵制；同一代受者只受一击"
	if skill["range_pattern"] == "step": return "穿单位不穿墙；自身守势减伤2"
	if "support" in skill["effects"]: return "自身减伤2；邻友首击代受减伤1"
	var effects: Array[String] = []
	var descriptions := {"guard":"自身守势：下次受击减伤2", "broken":"破势：受击者护体-2", "pin":"牵制：下次移动-2（最低0）", "bleed":"流血：行动后失血1，共2次"}
	if skill.get("broken_mode","") == "next_hit": descriptions["broken"] = "破势：下一击护体-2，下一轮末失效"
	for status: String in skill["effects"]: effects.append(descriptions[status])
	if skill["restore_qi"] > 0: effects.append("回内力%d" % skill["restore_qi"])
	return "；".join(effects) if not effects.is_empty() else "无附加状态"


static func damage_summary(battle: CombatEncounter, actor: String, identifier: String) -> String:
	var skill := battle.skill(identifier)
	if skill["target"] != "enemy": return "不造成伤害"
	var amounts: Array[int] = []
	for cell: Vector2i in Actions.target_cells(battle,actor,identifier):
		var action := battle.preview_action(actor,identifier,cell)
		if action["ok"]:
			for hit: Dictionary in action["hits"]: amounts.append(int(hit["actual"]))
	if not amounts.is_empty():
		var span := str(amounts.min()) if amounts.min() == amounts.max() else "%d～%d" % [amounts.min(),amounts.max()]
		return "扇形每人实扣%s（最多3目标）" % span if skill["area_pattern"] == "front_arc" else "当前可命中：实扣%s（含状态）" % span
	var base := maxi(1,int(skill["power"]) + int(battle.unit(actor)["power"]))
	var bonus := int(skill["distance_bonus"]) if skill["range"] >= 2 else 0
	if skill["area_pattern"] == "front_arc": return "参考每人%d伤（护体0、无状态）" % base
	return "参考%s伤（护体0、无状态）" % (str(base) if bonus == 0 else "%d～%d" % [base,base+bonus])


static func preview_detail(battle: CombatEncounter, preview: Dictionary) -> String:
	if not preview.get("ok", false): return preview.get("reason", "请选择目标")
	var actor: String = str(preview.get("actor", battle.current_actor_id()))
	var unit := battle.unit(actor)
	var before := int(preview.get("qi_before", unit.get("qi", 0)))
	var cost := int(preview.get("qi_cost", 0))
	var after := int(preview.get("qi_after", mini(int(unit.get("max_qi", before)), before-cost+int(preview.get("restore_qi", 0)))))
	var restored := maxi(0, after-before+cost)
	var detail := "内力%d→%d（消耗%d／实回%d）" % [before, after, cost, restored]
	for hit: Dictionary in preview["hits"]:
		var receiver := battle.unit(hit["receiver"])
		detail += "\n%s%s：气血%d→%d（实扣%d）" % [receiver["name"], "援护代受" if hit["redirected"] else "", receiver["hp"], maxi(0, int(receiver["hp"])-int(hit["actual"])), hit["actual"]]
	var effects: Array[String] = []
	for effect: String in preview["effects"]: effects.append(STATUS_NAMES[effect])
	var skill := battle.skill(str(preview.get("skill_id", "")))
	var timing := "施加：" + "／".join(effects) if not effects.is_empty() else ""
	if int(skill.get("cooldown_rounds", 0)) > 0:
		timing += (" · " if not timing.is_empty() else "") + "第%d轮恢复可用" % int(preview.get("cooldown_ready_round", battle.round_number+int(skill["cooldown_rounds"])+1))
	if not timing.is_empty(): detail += "\n" + timing
	if skill.get("range_pattern") == "step":
		var destination: Vector2i = preview.get("destination", preview.get("target", Vector2i.ZERO))
		detail += " · 落点(%d,%d)" % [destination.x, destination.y]
	return detail
