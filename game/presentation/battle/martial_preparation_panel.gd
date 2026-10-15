class_name MartialPreparationPanel
extends PanelContainer
## A detached draft: only the owning session may accept a submitted loadout.

signal loadout_submitted(loadout: Dictionary)
signal closed

const Rules = preload("res://game/domain/battle/martial_loadout.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const ROW_NAMES := ["外功一", "外功二", "外功三", "身法", "内功", "应用整备"]
var selection := 0
var draft: Dictionary = {}
var mastery: Dictionary = {}
var skills: Dictionary = {}
var rows: Array[Label] = []
var detail: Label
var notice: Label
var _message := ""


func _ready() -> void:
	position = Vector2(28, 20)
	size = Vector2(584, 320)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#171820")
	style.border_color = Color("#bcb28f")
	style.set_border_width_all(1)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)
	var surface := Control.new()
	surface.custom_minimum_size = Vector2(584, 320)
	add_child(surface)
	_label(surface, Vector2(16, 10), Vector2(552, 26), 20).text = "武学整备 · 外功3／身法1／内功1"
	_label(surface, Vector2(16, 41), Vector2(552, 32), 12).text = "四外功择三：破势续攻／控距爆发／群控／援护各有用途。\n熟练测试种子；普攻、守势、恢复不占槽，内功为被动。"
	for index in range(6):
		rows.append(_label(surface, Vector2(16, 79 + 27 * index), Vector2(552, 24), 14))
	detail = _label(surface, Vector2(16, 244), Vector2(552, 34), 12)
	notice = _label(surface, Vector2(16, 280), Vector2(552, 17), 12)
	_label(surface, Vector2(16, 301), Vector2(552, 17), 12).text = "↑↓选槽 · ←→换招 · E应用全部 · Esc/M取消 · 不推进时辰"
	refresh()


func _label(parent: Control, at: Vector2, extent: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = extent
	label.add_theme_font_override("font", preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func configure(martial_state: Dictionary, skill_definitions: Array) -> void:
	var normalized := Rules.normalize_state(martial_state, skill_definitions)
	skills = Skills.index(skill_definitions) if Skills.validate(skill_definitions).is_empty() else {}
	mastery = normalized.get("state", {}).get("mastery", {}).duplicate(true)
	draft = normalized.get("state", {}).get("loadout", {}).duplicate(true)
	if not draft.is_empty():
		while draft["external"].size() < 3: draft["external"].append("")
	selection = 0
	_message = "" if normalized["error"].is_empty() else "武学数据无效；不允许覆盖或自动清洗。"
	refresh()


func selected_id() -> String:
	if draft.is_empty() or selection >= 5: return ""
	if selection < 3: return draft["external"][selection]
	return draft["movement" if selection == 3 else "internal"]


func loadout() -> Dictionary:
	if draft.is_empty(): return {}
	var result := draft.duplicate(true)
	result["external"] = []
	for identifier: String in draft["external"]:
		if not identifier.is_empty(): result["external"].append(identifier)
	return result


func handle_key(code: int) -> bool:
	match code:
		KEY_ESCAPE, KEY_M:
			closed.emit()
		KEY_UP, KEY_W:
			selection = posmod(selection - 1, 6)
		KEY_DOWN, KEY_S:
			selection = posmod(selection + 1, 6)
		KEY_LEFT, KEY_A:
			_cycle(-1)
		KEY_RIGHT, KEY_D:
			_cycle(1)
		KEY_E, KEY_ENTER, KEY_SPACE:
			var error := _draft_error()
			if error.is_empty(): loadout_submitted.emit(loadout())
			else: _message = error
		_:
			return false
	refresh()
	return true


func handle_input(event: InputEvent) -> bool:
	if event.is_echo(): return true
	if event is InputEventKey:
		return handle_key(event.physical_keycode if event.physical_keycode != 0 else event.keycode) if event.pressed else false
	for pair: Array in [["move_up",KEY_UP],["move_down",KEY_DOWN],["move_left",KEY_LEFT],["move_right",KEY_RIGHT],["confirm",KEY_E],["cancel",KEY_ESCAPE],["open_martial",KEY_M]]:
		if event.is_action_pressed(pair[0]): return handle_key(pair[1])
	return false


func _cycle(direction: int) -> void:
	if draft.is_empty() or selection >= 5: return
	var category: String = "外功" if selection < 3 else ("身法" if selection == 3 else "内功")
	var choices: Array[String] = [""]
	for identifier: String in Rules.catalog(skills):
		if skills[identifier]["category"] == category: choices.append(identifier)
	var next: String = choices[posmod(choices.find(selected_id()) + direction, choices.size())]
	if selection < 3: draft["external"][selection] = next
	else: draft["movement" if selection == 3 else "internal"] = next
	_message = "尚未应用；取消会保留原配置。"


func _draft_error() -> String:
	if draft.is_empty(): return "武学数据无效；无法应用。"
	var selected: Dictionary = {}
	var proposal := loadout()
	var identifiers: Array = proposal["external"].duplicate()
	identifiers.append(proposal["movement"])
	identifiers.append(proposal["internal"])
	for identifier: String in identifiers:
		if identifier.is_empty(): continue
		if selected.has(identifier): return "不可应用：外功槽位重复；请换招或选择空槽。"
		if mastery.get(identifier, "识招") == "识招": return "不可应用：仅识招；达到熟练后才能配置。"
		selected[identifier] = true
	return "" if Rules.validate_loadout(proposal, mastery, skills).is_empty() else "不可应用：武学或槽位数据无效。"


func set_message(value: String) -> void:
	_message = value
	refresh()


func refresh() -> void:
	if not is_instance_valid(detail): return
	for index in range(6):
		var text: String = ROW_NAMES[index]
		var identifier := ""
		if index < 5 and not draft.is_empty():
			identifier = draft["external"][index] if index < 3 else draft["movement" if index == 3 else "internal"]
			text += "　" + ("空槽" if identifier.is_empty() else skills[identifier]["name"] + "　[" + mastery.get(identifier,"识招") + "]")
		rows[index].text = ("› " if index == selection else "  ") + text
		rows[index].add_theme_color_override("font_color", Color("#898a92") if not identifier.is_empty() and mastery.get(identifier,"识招") == "识招" else Color("#f1e6cf"))
	var identifier := selected_id()
	if selection == 5:
		detail.text = "应用只改变武学配置，不扣气血、不耗时、不写磁盘。\n退出后F5快速存档或暂停菜单手动存档。"
	elif identifier.is_empty():
		detail.text = "空槽：可卸下当前武学。\n未配内功：内力上限3；普攻回0／吐纳辅助回1。" if selection == 4 else "空槽：左右选择对应类别武学；基础行动不受影响。"
	else:
		var skill: Dictionary = skills[identifier]
		if skill["category"] == "内功":
			var passive: Dictionary = skill["passive_rules"]
			detail.text = "被动内功：内力上限%d；普攻回%d／吐纳辅助回%d。\n常驻生效，不是可主动施放的招式。" % [passive["max_qi"],passive["basic_restore_qi"],passive["breath_restore_qi"]]
		else:
			var effects: Dictionary = {"guard":"守势","broken":"破势","pin":"牵制","bleed":"流血","support":"援护"}
			var names: Array[String] = []
			for effect: String in skill["effects"]: names.append(effects[effect])
			var role: String = "效果：" + "／".join(names)
			if skill.get("broken_mode","") == "next_hit": role = "破势续攻：给下一击开护体-2窗口。"
			elif skill["area_pattern"] == "front_arc": role = "群控：定向前排3格，伤敌并牵制追击。"
			elif "support" in skill["effects"]: role = "护持：自身守势，替邻友承受首击。"
			elif skill["range_pattern"] == "step": role = "机动：穿人不穿墙，移步并获守势。"
			elif skill["distance_bonus"] > 0: role = "控距：2格加伤；注意贴身伤害与内力消耗。"
			detail.text = "%s · 范围%d · 耗内力%d · 冷却%d轮 · 基础威力%d\n%s" % [skill["category"],skill["range"],skill["qi_cost"],skill["cooldown_rounds"],skill["power"], "识招仅能查看，熟练后可配置。" if mastery.get(identifier,"识招") == "识招" else role]
	var error := _draft_error()
	notice.text = _message if not _message.is_empty() else (error if not error.is_empty() else "草稿已准备好；按E应用，Esc取消不会改配置。")
