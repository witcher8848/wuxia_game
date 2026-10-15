extends Node2D
## A production battle adapter, not a second combat authority. Only confirmed
## out-of-combat equipment changes touch GameSession; trial results never do.
signal exit_requested
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const BaseScreen = preload("res://game/presentation/battle/battle_screen.gd")
const Preparation = preload("res://game/presentation/battle/martial_preparation_panel.gd")
const Loadout = preload("res://game/domain/battle/martial_loadout.gd")
const Skills = preload("res://game/domain/battle/battle_skills.gd")
const DATA_PATH := "res://game/content/data/combat_v1_trial.json"
const SKILLS_PATH := "res://game/content/data/battle_skills_tactics.json"
const ARCHETYPES_PATH := "res://game/content/data/enemy_archetypes_tactics.json"
const PROFILES_PATH := "res://game/content/data/battle_ai_profiles_tactics.json"
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
var phase := "selection"
var selected_scenario := 0
var battle: CombatEncounter
var screen: Node2D
var preparation: Control
var startup_error := ""
var message := ""
var trial_token := ""
var heading: Label
var cards: Array[Label] = []
var detail: Label
var footer: Label
var selection_root: Node2D
var _definitions: Array = []
var _context_pushed := false
var _session: Node
var _app: Node


class TrialBattleScreen extends BaseScreen:
	signal return_to_preparation_requested

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and battle != null and event.keycode == KEY_F2:
			get_viewport().set_input_as_handled()
			_open_mode("trial_return")
			refresh()
			return
		super._unhandled_input(event)

	func options() -> Array[String]:
		if mode == "result": return ["原配置重试", "返回战前整备", "查看目标说明", "退出演武"]
		return super.options()

	func confirm() -> void:
		if mode == "trial_return":
			return_to_preparation_requested.emit()
			return
		if mode == "result" and selection == 1:
			_open_mode("trial_return")
			return
		# Never delegate the experimental scene's eliminate/escape switch.
		if mode == "scenario":
			_open_mode("trial_return")
			return
		super.confirm()

	func refresh() -> void:
		super.refresh()
		if board == null: return
		footer.text = footer.text.replace("F2 战前目标", "F2 返回整备")
		if mode == "trial_return":
			menu.text = "返回战前整备？\n本局临时战斗进度将丢弃。\nE确认；Esc保留当前战斗。"
			detail.text = "可重新选择清场／保护目标与武学。\n不会推进剧情、消耗时间或结算奖励。"
			footer.text = "E返回战前 · Esc继续本局 · R原配置重试"
		elif mode == "quit":
			menu.text = "退出演武？\n本局临时进度不会保存。\nE退出；Esc继续。"
		elif mode == "result":
			detail.text = "演武结果不结算探索气血、奖励或时间。\nR恢复本局战前配置；F2返回战前。"
		elif mode == "command" and not battle.current_actor_id().is_empty() and battle.unit(battle.current_actor_id())["team"] == "enemy":
			var identifier: String = battle.current_actor_id()
			var intent: Dictionary = AI.intent(battle, identifier, false, true)
			var priority: String = intent.get("priority_target", "")
			if not priority.is_empty(): menu.text += "\n策略优先：%s（站位改变后重算）" % battle.unit(priority).get("name", priority)


func _ready() -> void:
	_session = get_node("/root/GameSession")
	_app = get_node("/root/App")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	selection_root = Node2D.new()
	add_child(selection_root)
	heading = _label(Vector2(20,12), Vector2(600,28), 18)
	cards.append(_label(Vector2(32,62), Vector2(272,110), 14))
	cards.append(_label(Vector2(336,62), Vector2(272,110), 14))
	detail = _label(Vector2(28,190), Vector2(584,106), 13)
	footer = _label(Vector2(28,306), Vector2(584,44), 12)
	var definitions: Variant = JSON.parse_string(FileAccess.get_file_as_string(SKILLS_PATH))
	_definitions = definitions.duplicate(true) if definitions is Array else []
	_app.push_context(&"battle")
	_context_pushed = true
	_refresh_selection()


func _exit_tree() -> void:
	_release_lock()
	if _context_pushed:
		_app.pop_context()
		_context_pushed = false


func _label(at: Vector2, extent: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = extent
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_root.add_child(label)
	return label


func _draw() -> void:
	draw_rect(Rect2(0,0,640,360), Color("#171d25"))
	if phase in ["selection", "quit"]:
		for index: int in range(2):
			var bounds := Rect2(22+304*index,50,292,128)
			draw_rect(bounds, Color("#263849") if selected_scenario == index else Color("#222831"))
			draw_rect(bounds, Color("#e1c78d") if selected_scenario == index else Color("#526071"), false, 2)


func _refresh_selection() -> void:
	if not is_instance_valid(selection_root): return
	heading.text = "战斗V1演武 · 2对3 · 站位与内力取舍"
	var views := scenario_views()
	if not views["error"].is_empty():
		for card: Label in cards: card.text = "配置无效，不能开战。"
		detail.text = "不回退到其他场景或旧配置。"
		footer.text = views["error"] + "\nEsc返回"
		queue_redraw()
		return
	var scenarios: Array = views["scenarios"]
	selected_scenario = clampi(selected_scenario, 0, scenarios.size()-1)
	for index: int in range(cards.size()):
		cards[index].text = ("› " if selected_scenario == index else "") + scenarios[index]["title"] + "\n" + scenarios[index]["description"]
	var configuration: Dictionary = _session.martial_configuration()
	if not configuration.get("error", "").is_empty():
		detail.text = "持久武学数据无效，不能回退默认整备。"
		footer.text = configuration["error"] + "\nEsc返回"
		queue_redraw()
		return
	var names: Array[String] = []
	if configuration.get("error", "").is_empty():
		var equipped: Dictionary = configuration["state"]["loadout"]
		var indexed := Skills.index(_definitions)
		for identifier: String in equipped["external"] + [equipped["movement"],equipped["internal"]]:
			if not identifier.is_empty(): names.append(indexed[identifier]["name"])
	var scenario: Dictionary = scenarios[selected_scenario]
	var prepared := definition_for(scenario["id"], configuration.get("state", {}))
	if not prepared["error"].is_empty():
		detail.text = "配置无效，不回退旧场景：" + prepared["error"]
		footer.text = "Esc返回；修复配置后重新进入演武。"
		queue_redraw()
		return
	var carrier := ""
	for unit: Dictionary in prepared["definition"]["units"]:
		var profile: Variant = prepared["definition"]["ai_profiles"].get(str(unit.get("ai_profile", "")), {})
		if not profile is Dictionary or profile.get("style") != "capture": continue
		var targets: Variant = unit.get("ai_target_ids", [])
		if targets is Array and not targets.is_empty() and targets[0] is String: carrier = targets[0]
	var carrier_name := _unit_name(prepared["definition"], carrier)
	var goal: Dictionary = scenario["objective"]
	var objective := "击倒全部三敌；任一我方存活可继续。"
	if goal["kind"] == "survive": objective = "保护%s，坚持完整%d轮。" % [_unit_name(prepared["definition"], goal["protected_unit_id"]), int(goal["rounds"])]
	detail.text = "主角整备：%s\n刀役近压破势 · 弓役远射 · 捕手优先%s\n目标：%s\n随目标更换武学；演武不结算剧情、永久气血或时辰。" % [" / ".join(names), carrier_name, objective]
	footer.text = "←→ / A D 选择目标 · M 战前整备 · E / Enter 开战\nEsc 返回探索；战内 R 原配置重试 · F2 返回整备（确认）"
	if phase == "quit": footer.text = "退出演武并返回？E确认 · Esc取消；本局不结算任何奖励。"
	elif not message.is_empty(): footer.text = message + "\n←→选择 · M整备 · E开战 · Esc返回"
	queue_redraw()


static func _unit_name(definition: Dictionary, identifier: String) -> String:
	for unit: Dictionary in definition.get("units", []):
		if unit["id"] == identifier: return str(unit.get("name", identifier))
	return identifier if not identifier.is_empty() else "未配置携带者"


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or phase == "battle": return
	get_viewport().set_input_as_handled()
	if phase == "preparation":
		preparation.handle_key(event.keycode)
		return
	if phase == "quit":
		if event.is_action_pressed("confirm"): _request_exit()
		elif event.is_action_pressed("cancel"): phase = "selection"; _refresh_selection()
		return
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		selected_scenario = 1-selected_scenario
		message = ""
	elif event.keycode == KEY_M: open_preparation()
	elif event.is_action_pressed("confirm"): start_trial()
	elif event.is_action_pressed("cancel"): phase = "quit"
	_refresh_selection()


func open_preparation() -> void:
	if phase != "selection": return
	var configuration: Dictionary = _session.martial_configuration()
	if not configuration.get("error", "").is_empty():
		message = configuration["error"]
		_refresh_selection()
		return
	preparation = Preparation.new()
	preparation.configure(configuration["state"], _definitions)
	preparation.loadout_submitted.connect(_submit_loadout)
	preparation.closed.connect(_close_preparation)
	add_child(preparation)
	phase = "preparation"
	selection_root.hide()
	queue_redraw()


func _submit_loadout(loadout: Dictionary) -> void:
	var error: Error = _session.set_martial_loadout(loadout)
	preparation.set_message("已应用战前武学；Esc返回目标选择。" if error == OK else "整备未应用："+error_string(error))


func _close_preparation() -> void:
	if is_instance_valid(preparation):
		remove_child(preparation)
		preparation.queue_free()
	preparation = null
	phase = "selection"
	selection_root.show()
	message = ""
	_refresh_selection()


func definition_for(kind: String, martial_state: Dictionary) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var archetypes: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARCHETYPES_PATH))
	var profiles: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILES_PATH))
	return definition_from_data(kind, martial_state, raw, archetypes, profiles)


func scenario_views() -> Dictionary:
	return _scenario_table(JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)))


static func _scenario_table(raw: Variant) -> Dictionary:
	var failure := {"error":"演武需要两个有效目标记录。", "scenarios":[]}
	if not raw is Dictionary or not raw.get("scenarios") is Array or raw["scenarios"].size() != 2 or not GameState.is_json_value(raw): return failure
	var ids: Dictionary = {}
	var kinds: Dictionary = {}
	for scenario: Variant in raw["scenarios"]:
		if not scenario is Dictionary or not scenario.get("id") is String or not scenario["id"].is_valid_identifier() or ids.has(scenario["id"]) or not scenario.get("title") is String or scenario["title"].is_empty() or not scenario.get("description") is String or scenario["description"].is_empty() or not scenario.get("objective") is Dictionary: return failure
		var goal: Dictionary = scenario["objective"]
		if not goal.get("kind") in ["eliminate", "survive"] or kinds.has(goal["kind"]): return failure
		if goal["kind"] == "survive" and (not BattleState._whole(goal.get("rounds")) or goal["rounds"] < 1 or goal["rounds"] > 99 or not goal.get("protected_unit_id") is String or not goal["protected_unit_id"].is_valid_identifier()): return failure
		for field: String in ["deployment", "ai_targets"]:
			if scenario.has(field) and not scenario[field] is Dictionary: return failure
		for identifier: Variant in scenario.get("deployment", {}):
			if not identifier is String or not identifier.is_valid_identifier() or not BattleState._pair(scenario["deployment"][identifier]): return failure
		for identifier: Variant in scenario.get("ai_targets", {}):
			var targets: Variant = scenario["ai_targets"][identifier]
			if not identifier is String or not identifier.is_valid_identifier() or not targets is Array or targets.is_empty(): return failure
			var seen: Dictionary = {}
			for target: Variant in targets:
				if not target is String or not target.is_valid_identifier() or seen.has(target): return failure
				seen[target] = true
		ids[scenario["id"]] = true
		kinds[goal["kind"]] = true
	return {"error":"", "scenarios":raw["scenarios"].duplicate(true)}


func definition_from_data(kind: String, martial_state: Dictionary, raw: Variant, archetypes: Variant, profiles: Variant) -> Dictionary:
	# Guard the adapter's casts/accesses before reading editable JSON. The combat
	# domain still owns semantic board, unit, skill, objective and AI validation.
	if not raw is Dictionary or not archetypes is Dictionary or not profiles is Dictionary or not GameState.is_json_value(raw) or not GameState.is_json_value(archetypes) or not GameState.is_json_value(profiles):
		return _definition_failure("演武配置缺失或结构错误。")
	if not raw.get("id") is String or not raw["id"].is_valid_identifier() or not BattleState._pair(raw.get("size")) or not raw.get("blocked") is Array or not raw.get("allies") is Array or not raw.get("enemies") is Array or not raw.get("scenarios") is Array:
		return _definition_failure("演武配置必需字段缺失或类型错误。")
	for cell: Variant in raw["blocked"]:
		if not BattleState._pair(cell): return _definition_failure("演武障碍格格式错误。")
	var table := _scenario_table(raw)
	if not table["error"].is_empty(): return _definition_failure(table["error"])
	var normalized := Loadout.normalize_state(martial_state, _definitions)
	if not normalized["error"].is_empty(): return _definition_failure(normalized["error"])
	var objective: Dictionary = {}
	var selected: Dictionary = {}
	for scenario: Dictionary in table["scenarios"]:
		if scenario["id"] == kind:
			selected = scenario
			objective = scenario["objective"].duplicate(true)
	if objective.is_empty(): return _definition_failure("未注册的演武目标。")
	var units: Array = raw["allies"].duplicate(true)
	if units.size() != 2: return _definition_failure("演武需要两名我方。")
	var protagonist_index := -1
	var ally_ids: Dictionary = {}
	for index: int in range(units.size()):
		var ally: Variant = units[index]
		if not ally is Dictionary or not ally.get("id") is String or not ally["id"].is_valid_identifier() or ally_ids.has(ally["id"]) or ally.get("team") != "ally" or not ally.get("archetype") is String or not ally["archetype"].is_valid_identifier():
			return _definition_failure("演武我方身份、队伍或原型格式错误。")
		ally_ids[ally["id"]] = true
		if ally["id"] == "CHAR_PROTAGONIST": protagonist_index = index
	if protagonist_index < 0: return _definition_failure("演武需要唯一的我方主角。")
	# Array order is presentation/configuration data, never character identity.
	units[protagonist_index]["loadout"] = normalized["state"]["loadout"].duplicate(true)
	units[protagonist_index]["mastery"] = normalized["state"]["mastery"].duplicate(true)
	if raw["enemies"].size() != 3: return _definition_failure("演武需要三名敌人。")
	var unit_ids: Dictionary = ally_ids.duplicate()
	for placement: Variant in raw["enemies"]:
		if not placement is Dictionary or not placement.get("id") is String or not placement["id"].is_valid_identifier() or unit_ids.has(placement["id"]) or not placement.get("archetype") is String or not placement["archetype"].is_valid_identifier() or not BattleState._pair(placement.get("cell")):
			return _definition_failure("演武敌方位置或身份格式错误。")
		if not archetypes.has(placement["archetype"]) or not archetypes[placement["archetype"]] is Dictionary:
			return _definition_failure("未知或无效的敌人原型。")
		var enemy: Dictionary = archetypes[placement["archetype"]].duplicate(true)
		enemy.merge(placement, true)
		if enemy.get("team") != "enemy": return _definition_failure("敌方原型队伍错误。")
		unit_ids[placement["id"]] = true
		units.append(enemy)
	for identifier: String in selected.get("deployment", {}):
		if not unit_ids.has(identifier): return _definition_failure("部署引用了未知人物。")
	for identifier: String in selected.get("ai_targets", {}):
		if not unit_ids.has(identifier) or ally_ids.has(identifier): return _definition_failure("追缉策略必须引用敌人。")
		for target: String in selected["ai_targets"][identifier]:
			if not ally_ids.has(target): return _definition_failure("追缉目标必须引用我方人物。")
	for unit: Dictionary in units:
		if selected.get("deployment", {}).has(unit["id"]): unit["cell"] = selected["deployment"][unit["id"]].duplicate()
		if selected.get("ai_targets", {}).has(unit["id"]): unit["ai_target_ids"] = selected["ai_targets"][unit["id"]].duplicate()
	return {"error":"", "definition":{"size":raw["size"].duplicate(), "blocked":raw["blocked"].duplicate(true), "objective":objective, "units":units, "skill_definitions":_definitions.duplicate(true), "ai_profiles":profiles.duplicate(true)}}


static func _definition_failure(reason: String) -> Dictionary:
	return {"error": reason, "definition": {}}


func start_trial() -> void:
	if phase != "selection": return
	var configuration: Dictionary = _session.martial_configuration()
	if not configuration.get("error", "").is_empty(): message = configuration["error"]; _refresh_selection(); return
	var table := scenario_views()
	if not table["error"].is_empty(): message = table["error"]; _refresh_selection(); return
	if selected_scenario < 0 or selected_scenario >= table["scenarios"].size(): message = "未选择有效目标。"; _refresh_selection(); return
	var prepared := definition_for(table["scenarios"][selected_scenario]["id"], configuration["state"])
	var candidate := Combat.new()
	startup_error = prepared["error"] if not prepared["error"].is_empty() else candidate.configure(prepared["definition"])
	if not startup_error.is_empty(): message = startup_error; _refresh_selection(); return
	var token: String = _session.lock_martial_trial()
	if token.is_empty(): message = "已有战斗进行中，不能开启演武。"; _refresh_selection(); return
	trial_token = token
	battle = candidate
	screen = TrialBattleScreen.new()
	screen.battle = battle
	screen.exit_requested.connect(_request_exit)
	screen.return_to_preparation_requested.connect(return_to_selection)
	add_child(screen)
	phase = "battle"
	selection_root.hide()
	message = ""
	queue_redraw()


func _release_lock() -> void:
	if not trial_token.is_empty():
		_session.unlock_martial_trial(trial_token)
		trial_token = ""


func return_to_selection() -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = null
	battle = null
	_release_lock()
	phase = "selection"
	selection_root.show()
	message = "已返回战前；本局未结算奖励、气血或时间。"
	_refresh_selection()


func _request_exit() -> void:
	_release_lock()
	var connected := exit_requested.get_connections().size() > 0
	exit_requested.emit()
	if not connected: get_tree().quit()
