extends Node2D
## Development-only Day 15 viewer; excluded by both export presets.
const State = preload("res://game/domain/battle/battle_state.gd")
const ORIGIN := Vector2(16, 42)
const CELL := 32
const FIXTURE := "res://game/tools/battle_lab/encounter.json"
var battle: BattleState = State.new()
var cursor := Vector2i.ZERO
var info: Label
var heading: Label
var footer: Label
var startup_error := ""


func _ready() -> void:
	heading = _label(Vector2(16, 8), Vector2(610, 28), 18)
	heading.text = "第三周 · Day 15 战斗骨架实验场"
	info = _label(Vector2(352, 42), Vector2(272, 254), 14)
	footer = _label(Vector2(16, 304), Vector2(608, 52), 14)
	footer.text = "方向键/WASD 查看格子 · E/Enter 结束占位回合 · R 重置 · Esc 退出\n当前未接入移动、攻击、AI、胜负；此处不会写入探索存档。"
	reset_battle()


func _label(position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.add_theme_font_override("font", preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func reset_battle() -> void:
	var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	startup_error = battle.configure(definition) if definition is Dictionary else "Invalid encounter JSON."
	if not startup_error.is_empty():
		info.text = startup_error
		push_error(startup_error)
		return
	var actor: Dictionary = battle.unit(battle.current_actor_id())
	cursor = Vector2i(actor["cell"][0], actor["cell"][1])
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not startup_error.is_empty():
		return
	if event.is_action_pressed("cancel"):
		get_tree().quit()
	elif event.is_action_pressed("tab_next"):
		reset_battle()
	elif event.is_action_pressed("confirm"):
		battle.finish_turn(battle.current_actor_id())
		_refresh()
	else:
		var direction := Vector2i.ZERO
		if event.is_action_pressed("move_up"):
			direction = Vector2i.UP
		elif event.is_action_pressed("move_down"):
			direction = Vector2i.DOWN
		elif event.is_action_pressed("move_left"):
			direction = Vector2i.LEFT
		elif event.is_action_pressed("move_right"):
			direction = Vector2i.RIGHT
		if direction == Vector2i.ZERO:
			return
		if battle.contains(cursor + direction):
			cursor += direction
		_refresh()
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var actor: Dictionary = battle.unit(battle.current_actor_id())
	var names: Array[String] = []
	for identifier: String in battle.pending_ids():
		names.append(battle.unit(identifier)["name"])
	var selected: Dictionary = battle.unit(battle.unit_at(cursor))
	var detail: String = "空地" if selected.is_empty() else "%s · 气血 %d/%d\n内力 %d/%d · 身法 %d" % [selected["name"], selected["hp"], selected["max_hp"], selected["qi"], selected["max_qi"], selected["agility"]]
	if battle.is_obstacle(cursor):
		detail = "障碍 · 不可站立"
	info.text = "第 %d 轮 · 当前：%s\n本轮剩余顺序\n%s\n\n格子 (%d, %d)\n%s\n\n蓝：主角/同伴 · 红：刀役/弓役\n金框：行动者 · 白框：光标" % [battle.round_number, actor.get("name", "无"), " → ".join(names), cursor.x, cursor.y, detail]
	queue_redraw()


func _draw() -> void:
	for y: int in range(battle.board_size.y):
		for x: int in range(battle.board_size.x):
			var cell := Vector2i(x, y)
			var rectangle := Rect2(ORIGIN + Vector2(cell) * CELL, Vector2(CELL - 1, CELL - 1))
			draw_rect(rectangle, Color("#77715f") if battle.is_obstacle(cell) else Color("#323d48"))
	for identifier: String in battle.unit_ids():
		var unit: Dictionary = battle.unit(identifier)
		if int(unit["hp"]) <= 0:
			continue
		var cell := Vector2(unit["cell"][0], unit["cell"][1])
		var position_value := ORIGIN + cell * CELL
		draw_rect(Rect2(position_value + Vector2(7, 6), Vector2(18, 22)), Color("#5eb3d1") if unit["team"] == "ally" else Color("#ce795e"))
		var glyph: String = unit["name"].substr(0, 1)
		draw_string(heading.get_theme_font("font"), position_value + Vector2(8, 23), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#151820"))
		if identifier == battle.current_actor_id():
			draw_rect(Rect2(position_value + Vector2(2, 2), Vector2(27, 27)), Color("#efc86c"), false, 2)
	draw_rect(Rect2(ORIGIN + Vector2(cursor) * CELL, Vector2(31, 31)), Color.WHITE, false, 1)
