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
	_definitions = get_node("/root/ContentDB").martial_definitions()
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
	heading.text = "战斗V1演武 · 2对3 · 试验目标，不结算剧情"
	cards[0].text = "› 清场演武" if selected_scenario == 0 else "清场演武"
	cards[0].text += "\n击倒刀役、弓役与捕手。\n任一我方存活即可继续。"
	cards[1].text = "› 保护同伴" if selected_scenario == 1 else "保护同伴"
	cards[1].text += "\n坚持完整3轮；同伴必须存活。\n清敌不会提前结束计时。"
	var configuration: Dictionary = _session.martial_configuration()
	var names: Array[String] = []
	if configuration.get("error", "").is_empty():
		var equipped: Dictionary = configuration["state"]["loadout"]
		var indexed := Skills.index(_definitions)
		for identifier: String in equipped["external"] + [equipped["movement"],equipped["internal"]]:
			if not identifier.is_empty(): names.append(indexed[identifier]["name"])
	detail.text = "敌人：刀役近压 · 弓役远射 · 捕手锁拿主角\n主角整备：%s\n演武不消耗永久气血、调查证据或时间；无调查加成。" % " / ".join(names)
	footer.text = "←→ / A D 选择目标 · M 战前整备 · E / Enter 开战\nEsc 返回探索；战内 R 原配置重试 · F2 返回整备（确认）"
	if phase == "quit": footer.text = "退出演武并返回？E确认 · Esc取消；本局不结算任何奖励。"
	elif not message.is_empty(): footer.text = message + "\n←→选择 · M整备 · E开战 · Esc返回"
	queue_redraw()


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
	var archetypes: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/enemy_archetypes.json"))
	var profiles: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_ai_profiles.json"))
	if not raw is Dictionary or not archetypes is Dictionary or not profiles is Dictionary or not raw.get("allies") is Array or not raw.get("enemies") is Array or not raw.get("scenarios") is Array:
		return {"error":"演武配置缺失或结构错误。", "definition":{}}
	var normalized := Loadout.normalize_state(martial_state, _definitions)
	if not normalized["error"].is_empty(): return {"error":normalized["error"], "definition":{}}
	var objective: Dictionary = {}
	for scenario: Dictionary in raw["scenarios"]:
		if scenario["id"] == kind: objective = scenario["objective"].duplicate(true)
	if objective.is_empty(): return {"error":"未注册的演武目标。", "definition":{}}
	var units: Array = raw["allies"].duplicate(true)
	if units.size() != 2: return {"error":"演武需要两名我方。", "definition":{}}
	units[0]["loadout"] = normalized["state"]["loadout"].duplicate(true)
	units[0]["mastery"] = normalized["state"]["mastery"].duplicate(true)
	for placement: Dictionary in raw["enemies"]:
		if not archetypes.has(placement.get("archetype", "")): return {"error":"未知敌人原型。", "definition":{}}
		var enemy: Dictionary = archetypes[placement["archetype"]].duplicate(true)
		enemy.merge(placement, true)
		units.append(enemy)
	return {"error":"", "definition":{"size":raw["size"], "blocked":raw["blocked"].duplicate(true), "objective":objective, "units":units, "skill_definitions":_definitions.duplicate(true), "ai_profiles":profiles.duplicate(true)}}


func start_trial() -> void:
	if phase != "selection": return
	var configuration: Dictionary = _session.martial_configuration()
	if not configuration.get("error", "").is_empty(): message = configuration["error"]; _refresh_selection(); return
	var prepared := definition_for("eliminate" if selected_scenario == 0 else "survive", configuration["state"])
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
