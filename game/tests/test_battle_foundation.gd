extends SceneTree

const State = preload("res://game/domain/battle/battle_state.gd")
var checks := 0
var failures: Array[String] = []
var fixture: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("BATTLE_CHECK_FAIL: ", message)


func snapshot(battle: BattleState) -> Dictionary:
	var units: Array = []
	for identifier: String in battle.unit_ids():
		units.append(battle.unit(identifier))
	return {"units": units, "pending": battle.pending_ids(), "round": battle.round_number, "size": battle.board_size}


func reject(battle: BattleState, bad: Dictionary, label: String) -> void:
	var before := snapshot(battle)
	check(not battle.configure(bad).is_empty(), "reject " + label)
	check(snapshot(battle) == before, "transaction preserves state: " + label)


func _run() -> void:
	create_timer(25).timeout.connect(func() -> void: printerr("BATTLE_CHECK_FAIL watchdog"); quit(1))
	await process_frame
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/tools/battle_lab/encounter.json"))
	var battle := State.new()
	check(battle.current_actor_id().is_empty() and not battle.finish_turn("none"), "unconfigured state is safe")
	check(not battle.contains(Vector2i.ZERO), "unconfigured board has no legal cells")
	check(battle.configure(fixture).is_empty(), "fixture validates")
	check(battle.board_size == Vector2i(10, 8) and battle.round_number == 1, "board and first round")
	var expected: Array[String] = ["CHAR_COMPANION", "CHAR_PROTAGONIST", "ENEMY_BOW", "ENEMY_BLADE"]
	check(battle.pending_ids() == expected, "descending agility")
	for y: int in range(8):
		for x: int in range(10):
			var cell := Vector2i(x, y)
			check(battle.contains(cell), "inside %s" % cell)
			check(battle.is_free(cell) == (not battle.is_obstacle(cell) and battle.unit_at(cell).is_empty()), "occupancy %s" % cell)
	for cell in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(10, 0), Vector2i(0, 8)]:
		check(not battle.is_free(cell), "outside rejected %s" % cell)
	check(battle.is_obstacle(Vector2i(4, 2)) and not battle.is_free(Vector2i(4, 2)), "obstacle blocks standing")
	check(battle.unit_at(Vector2i(1, 3)) == "CHAR_PROTAGONIST", "unit lookup")
	var external := battle.unit("CHAR_PROTAGONIST")
	external["cell"][0] = 9
	check(battle.unit("CHAR_PROTAGONIST")["cell"][0] == 1, "unit getter deep copy")
	var pending := battle.pending_ids()
	pending.clear()
	check(battle.pending_ids().size() == 4, "queue getter copy")
	var ids := battle.unit_ids()
	ids.clear()
	check(battle.unit_ids().size() == 4, "ID getter copy")
	var source := fixture.duplicate(true)
	check(battle.configure(source).is_empty(), "reconfigure")
	source["units"][0]["hp"] = 1
	check(battle.unit("CHAR_PROTAGONIST")["hp"] == 16, "input data detached")
	var before := snapshot(battle)
	check(not battle.finish_turn("ENEMY_BLADE") and snapshot(battle) == before, "wrong/stale actor cannot advance")
	for round_index: int in range(1, 5):
		var acted: Dictionary = {}
		for identifier: String in expected:
			check(battle.current_actor_id() == identifier, "stable order round " + str(round_index))
			check(not acted.has(identifier), "one turn per unit per round")
			acted[identifier] = true
			check(battle.finish_turn(identifier), "finish valid turn")
		check(battle.round_number == round_index + 1, "round rollover")
	check(battle.set_agility("ENEMY_BLADE", 6), "initiative change accepted")
	check(battle.current_actor_id() == "CHAR_COMPANION", "no mid-round reordering")
	for identifier: String in expected:
		battle.finish_turn(identifier)
	check(battle.current_actor_id() == "ENEMY_BLADE", "next round reflects initiative")
	battle.set_agility("ENEMY_BLADE", 5)
	var changed_order := battle.pending_ids()
	for identifier: String in changed_order:
		battle.finish_turn(identifier)
	check(battle.pending_ids()[0] == "ENEMY_BLADE" and battle.pending_ids()[1] == "CHAR_COMPANION", "tie retains previous round order")
	check(not battle.set_agility("missing", 3) and not battle.set_agility("ENEMY_BLADE", -1), "bad initiative command rejected")
	check(battle.mark_defeated("ENEMY_BLADE"), "current actor can be defeated")
	check(battle.current_actor_id() == "CHAR_COMPANION", "defeated current actor skipped")
	check(battle.mark_defeated("CHAR_PROTAGONIST") and not battle.pending_ids().has("CHAR_PROTAGONIST"), "later defeated actor removed")
	check(battle.is_free(Vector2i(1, 3)), "defeated cell no longer occupied")
	check(not battle.mark_defeated("CHAR_PROTAGONIST") and not battle.mark_defeated("missing"), "duplicate defeat is not another event")
	for identifier: String in battle.unit_ids():
		battle.mark_defeated(identifier)
	var final_round: int = battle.round_number
	check(battle.current_actor_id().is_empty() and not battle.finish_turn("CHAR_COMPANION"), "all defeated terminates advancement")
	check(battle.round_number == final_round, "empty queue does not create endless rounds")
	battle.configure(fixture)
	for size_value in [[0, 8], [33, 8], [10.5, 8], [10], "10x8", [NAN, 8]]:
		var bad := fixture.duplicate(true)
		bad["size"] = size_value
		reject(battle, bad, "size " + str(size_value))
	for field: String in ["hp", "max_hp", "qi", "max_qi", "agility", "move", "power", "guard"]:
		for value in [-1, 0.5, "3", NAN, 1000, null]:
			var bad := fixture.duplicate(true)
			bad["units"][0][field] = value
			reject(battle, bad, field + "=" + str(value))
	for change: Dictionary in [{"id": "ENEMY_BOW"}, {"id": "bad id"}, {"team": "other"}, {"team": []}, {"name": ""}, {"archetype": ""}, {"cell": [2, 5]}, {"cell": [4, 2]}, {"cell": [10, 8]}, {"cell": [1.5, 3]}, {"max_hp": 0}, {"hp": 17}, {"qi": 6}]:
		var bad := fixture.duplicate(true)
		bad["units"][0].merge(change, true)
		reject(battle, bad, str(change))
	for change: Dictionary in [{"blocked": [[4, 2], [4, 2]]}, {"blocked": [[-1, 0]]}, {"blocked": [[1.5, 2]]}, {"blocked": {}}, {"units": []}, {"units": ["bad"]}]:
		var bad := fixture.duplicate(true)
		bad.merge(change, true)
		reject(battle, bad, str(change))
	var expanded := fixture.duplicate(true)
	for index: int in range(2):
		var extra: Dictionary = fixture["units"][0].duplicate(true)
		extra["id"] = "EXTRA_ALLY_" + str(index)
		extra["cell"] = [index, 0]
		expanded["units"].append(extra)
	check(battle.configure(expanded).is_empty() and battle.unit_ids().size() == 6, "four allies supported without two-slot assumption")
	var extra: Dictionary = fixture["units"][0].duplicate(true)
	extra["id"] = "FIFTH_ALLY"
	extra["cell"] = [3, 0]
	expanded["units"].append(extra)
	reject(battle, expanded, "fifth ally")
	var enemy_capacity := fixture.duplicate(true)
	for index: int in range(4):
		var enemy: Dictionary = fixture["units"][2].duplicate(true)
		enemy["id"] = "EXTRA_ENEMY_" + str(index)
		enemy["cell"] = [index, 0]
		enemy_capacity["units"].append(enemy)
		if index == 2:
			check(battle.configure(enemy_capacity).is_empty(), "five enemies supported")
	reject(battle, enemy_capacity, "sixth enemy")
	await _check_view()
	if failures.is_empty():
		print("BATTLE_FOUNDATION_PASS checks=", checks, " (Day 15 only; injected keyboard; no combat/AI/human-play claim)")
	quit(0 if failures.is_empty() else 1)


func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _check_view() -> void:
	var session: Node = root.get_node("GameSession")
	var app: Node = root.get_node("App")
	var before: String = JSON.stringify(session.state.to_dict())
	var context: StringName = app.current_context()
	var lab: Node2D = load("res://game/tools/battle_lab/battle_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	check(lab.startup_error.is_empty(), "viewer loaded JSON")
	check(lab.battle.current_actor_id() == "CHAR_COMPANION", "viewer starts correct actor")
	var cursor_before: Vector2i = lab.cursor
	await key(KEY_RIGHT)
	check(lab.cursor == cursor_before + Vector2i.RIGHT, "keyboard cursor")
	var companion_cell: Array = lab.battle.unit("CHAR_COMPANION")["cell"]
	check(Vector2i(companion_cell[0], companion_cell[1]) == Vector2i(2, 5), "cursor is not movement command")
	await key(KEY_E, true)
	check(lab.battle.current_actor_id() == "CHAR_COMPANION", "echo cannot advance turns")
	await key(KEY_E)
	check(lab.battle.current_actor_id() == "CHAR_PROTAGONIST", "confirm advances exactly one actor")
	await key(KEY_R)
	check(lab.battle.round_number == 1 and lab.battle.current_actor_id() == "CHAR_COMPANION", "keyboard reset")
	await key(KEY_F5)
	check(JSON.stringify(session.state.to_dict()) == before and app.current_context() == context, "lab leaves persistent game state and input contexts untouched")
	for label: Label in [lab.heading, lab.info, lab.footer]:
		check(Rect2(0, 0, 640, 360).encloses(label.get_rect()), "label inside logical viewport")
		check(label.get_minimum_size().y <= label.size.y, "label text fits height")
	check(not lab.info.get_rect().intersects(lab.footer.get_rect()), "sidebar cannot overlap footer")
	if "--capture-battle" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name() != "headless", "capture needs real renderer")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://builds/qa")
			check(root.get_texture().get_image().save_png("res://builds/qa/week3_day15.png") == OK, "render capture saved")
	root.remove_child(lab)
	lab.queue_free()
	await process_frame
