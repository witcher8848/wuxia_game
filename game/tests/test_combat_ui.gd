extends SceneTree
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
var checks := 0
var failures: Array[String] = []
var lab: Node
var screen: Node2D
var captures := false


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("COMBAT_UI_FAIL ", label)


func key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func bounds(label: String) -> void:
	for node: Label in [screen.heading, screen.stats, screen.menu, screen.disabled_menu, screen.detail, screen.footer]:
		check(Rect2(0,0,640,360).encloses(node.get_rect()), label + " viewport bounds")
		check(node.get_minimum_size().y <= node.size.y, label + " text height fits")
	check(not screen.stats.get_rect().intersects(screen.menu.get_rect()), label + " stats/menu separate")
	check(not screen.menu.get_rect().intersects(screen.detail.get_rect()), label + " menu/detail separate")
	check(not screen.disabled_menu.get_rect().intersects(screen.detail.get_rect()), label + " disabled menu/detail separate")
	check(not screen.detail.get_rect().intersects(screen.footer.get_rect()), label + " detail/footer separate")


func capture(label: String) -> void:
	await process_frame
	bounds(label)
	if not captures: return
	check(DisplayServer.get_name() != "headless", "real renderer required")
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://builds/qa/week3_" + label + ".png") == OK, "capture " + label)


func cursor_to(target: Vector2i) -> void:
	while screen.cursor.x < target.x: await key(KEY_RIGHT)
	while screen.cursor.x > target.x: await key(KEY_LEFT)
	while screen.cursor.y < target.y: await key(KEY_DOWN)
	while screen.cursor.y > target.y: await key(KEY_UP)


func command(index: int) -> void:
	for attempt: int in range(screen.options().size()):
		if screen.selection == index: break
		await key(KEY_DOWN)
	check(screen.selection == index, "requested command is selectable")
	if screen.selection != index: return
	await key(KEY_E)


func _run() -> void:
	create_timer(100).timeout.connect(func() -> void: printerr("COMBAT_UI_FAIL watchdog"); quit(1))
	if "--combat-exit-probe" in OS.get_cmdline_user_args():
		var child: Node = load("res://game/tools/battle_lab/combat_lab.tscn").instantiate()
		root.add_child(child)
		await process_frame
		for index: int in range(3):
			await key(KEY_R)
			await key(KEY_E)
		await key(KEY_ESCAPE)
		print("COMBAT_EXIT_PROBE_CONFIRMING")
		await key(KEY_E) # Actual lab quit callback must terminate this process.
		await create_timer(2).timeout
		printerr("COMBAT_UI_FAIL quit callback did not exit"); quit(1); return
	captures = "--capture-combat" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	var session := root.get_node("GameSession")
	var before := JSON.stringify(session.state.to_dict())
	var context: StringName = root.get_node("App").current_context()
	lab = load("res://game/tools/battle_lab/combat_lab.tscn").instantiate()
	root.add_child(lab)
	screen = lab.screen
	screen.auto_ai = false
	await process_frame
	check(lab.startup_error.is_empty() and screen.mode == "command", "full lab starts")
	await capture("combat_start")
	var snapshot: Dictionary = lab.battle.snapshot()
	await key(KEY_E, true)
	check(screen.mode == "command" and lab.battle.snapshot() == snapshot, "echo ignored")
	await key(KEY_E)
	await key(KEY_RIGHT)
	await capture("combat_move")
	await key(KEY_E)
	check(screen.mode == "move_confirm" and lab.battle.snapshot() == snapshot, "movement requires confirmation")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(screen.mode == "command" and lab.battle.snapshot() == snapshot, "cancel preview preserves state")
	await key(KEY_E)
	await key(KEY_E)
	await key(KEY_E)
	check(lab.battle.moved and screen.mode == "command", "confirmed movement retains action menu")
	await key(KEY_F1)
	await capture("combat_help")
	await key(KEY_ESCAPE)
	await key(KEY_R)
	await key(KEY_ESCAPE)
	check(lab.battle.moved, "cancel retry keeps current state")
	await key(KEY_R)
	await key(KEY_E)
	check(not lab.battle.moved, "confirm retry restores state")
	# Visible enabled and disabled rows, including ultimate reasons, must fit.
	for index: int in range(screen.options().size()):
		await capture("combat_option_%d" % index)
		await key(KEY_DOWN)
	# Main character has an additional support skill: check the fullest menu.
	await command(3) # Breath for companion; main character acts next.
	await key(KEY_E)
	await key(KEY_E)
	await capture("combat_sword_menu")
	await key(KEY_R)
	await key(KEY_E)
	# Drive an entire real encounter using only keyboard menus and targets.
	var turns := 0
	while lab.battle.outcome == "ongoing" and turns < 80:
		turns += 1
		var actor: String = lab.battle.current_actor_id()
		if lab.battle.unit(actor)["team"] == "enemy":
			screen.auto_ai = true
			var revision: int = lab.battle.revision
			var deadline := Time.get_ticks_msec() + 4000
			while lab.battle.revision == revision and Time.get_ticks_msec() < deadline: await process_frame
			check(lab.battle.revision > revision, "actual view schedules enemy turn")
			screen.auto_ai = false
		else:
			var next: Dictionary = AI.plan(lab.battle, actor, true)
			if next["destination"] != Grid.cell_of(lab.battle.unit(actor)):
				await command(0)
				await cursor_to(next["destination"])
				await key(KEY_E)
				await key(KEY_E)
				check(screen.mode == "command", "keyboard movement commits")
			var ability_index: int = lab.battle.abilities(actor).find(next["skill_id"]) + 1
			await command(ability_index)
			await cursor_to(next["target"])
			await key(KEY_E)
			check(screen.mode == "action_confirm", "keyboard action preview")
			if turns < 5: await capture("combat_action_%d" % turns)
			var revision: int = lab.battle.revision
			await key(KEY_E)
			check(lab.battle.revision == revision+1, "exactly one action per confirm")
	check(lab.battle.outcome == "victory" and screen.mode == "result", "keyboard encounter reaches real victory")
	await capture("combat_victory")
	await key(KEY_E)
	await key(KEY_E)
	check(lab.battle.outcome == "ongoing" and lab.battle.round_number == 1, "result menu retry")
	await key(KEY_F2)
	await key(KEY_DOWN)
	await key(KEY_E)
	screen = lab.screen
	screen.auto_ai = false
	check(lab.battle.objective["kind"] == "escape" and lab.get_child_count() == 1, "scenario switch replaces view without duplicate nodes")
	await capture("combat_escape")
	if captures:
		root.size = Vector2i(1280,720)
		await process_frame
		check(root.size == Vector2i(1280,720), "1280 window size applied")
		await capture("combat_1280")
		root.size = Vector2i(960,540)
		await process_frame
		check(root.size == Vector2i(960,540), "960 window size applied")
		await capture("combat_960")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		await create_timer(0.4).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen applied")
		await capture("combat_fullscreen")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await key(KEY_F5)
	check(JSON.stringify(session.state.to_dict()) == before and root.get_node("App").current_context() == context, "full battle leaves persistent route/time/relationships/input context untouched")
	root.remove_child(lab)
	lab.queue_free()
	await process_frame
	for attempt: int in range(3):
		var output: Array = []
		var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://game/tests/test_combat_ui.gd", "--", "--combat-exit-probe"], output, true)
		var child_log := "\n".join(output)
		check(exit_code == 0 and "COMBAT_EXIT_PROBE_CONFIRMING" in child_log and not "ERROR:" in child_log, "separate process retries then exits through keyboard confirmation, run %d" % attempt)
	print("COMBAT_UI: %d checks, %d failures (injected keyboard and actual AI; not human playtest)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
