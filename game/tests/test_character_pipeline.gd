extends SceneTree
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const Board = preload("res://game/presentation/battle/battle_board.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
var checks := 0
var failures: Array[String] = []
var captures := false
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("CHARACTER_PIPELINE_FAIL ",label)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func capture(label: String) -> void:
	if not captures: return
	check(DisplayServer.get_name() != "headless","real renderer")
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("WUXIA_CAPTURE_DIR")
	if folder.is_empty(): folder = "res://builds/qa"
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder+"/week5_"+label+".png") == OK,"capture "+label)
func _run() -> void:
	await process_frame
	if "--require-pack" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"),"pack no source overlay")
	captures = "--capture-character" in OS.get_cmdline_user_args()
	var hero := Hero.new()
	root.add_child(hero)
	hero.set_process(false)
	check(hero.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"nearest filter")
	check(Hero.ATLAS.get_size() == Vector2(256,384),"runtime imported atlas")
	var shadow_bounds: Rect2 = Hero.SHADOW_ROWS[0]
	for row: Rect2 in Hero.SHADOW_ROWS:
		check(row.position == row.position.round() and row.size == row.size.round(),"shadow keeps integer pixel geometry")
		shadow_bounds = shadow_bounds.merge(row)
	check(shadow_bounds == Rect2(-8,-3,16,6),"fixed 16x6 shadow centered on feet")
	for direction: String in ["up","down","left","right"]:
		hero.facing = direction
		hero.walking = true
		hero.step_time = 0.0
		var first := hero.frame_number()
		hero._process(0.126)
		check(hero.frame_number() != first,"walk frame progression "+direction)
		hero.walking = false
		check(hero.clip_name() == "idle_"+direction,"stop keeps facing")
		for action: String in ["strike","thrust","slash","guard","hit"]:
			hero.play_action(action,direction)
			check(hero.clip_name() == action+"_"+direction,"play "+action+direction)
			hero._process(1.0)
			check(hero.clip_name() == "idle_"+direction,"one shot returns idle")
	hero.play_action("down","down")
	hero._process(10)
	check(hero.clip_name() == "down","down persists")
	hero.reset_pose()
	check(hero.clip_name() == "idle_down","retry clears down")
	hero.sprinting = true
	hero._process(0.1)
	check(is_equal_approx(hero.step_time,1.0/6.0),"sprint timing ratio")
	hero.queue_free()
	await process_frame
	var lab: Node = load("res://game/presentation/characters/character_lab.tscn").instantiate()
	root.add_child(lab)
	lab.set_process(false)
	await key(KEY_DOWN)
	check(lab.action_index == 2,"preview keyboard next action")
	await key(KEY_UP)
	check(lab.action_index == 1,"preview keyboard previous action")
	await key(KEY_1)
	check(lab.zoom == 1,"preview keyboard 1x")
	await key(KEY_2)
	check(lab.zoom == 2,"preview keyboard 2x")
	await key(KEY_3)
	check(lab.zoom == 3,"preview keyboard 3x")
	await key(KEY_SPACE)
	check(lab.paused,"preview keyboard pause")
	await key(KEY_SPACE)
	await key(KEY_SHIFT)
	check(not lab.paused and lab.sprint,"preview keyboard resume and sprint")
	await key(KEY_SHIFT)
	lab.elapsed = 0.0
	lab._update_figures()
	var neutral_frames: Array[int] = []
	for figure: Node in lab.figures: neutral_frames.append(figure.frame_number())
	await key(KEY_RIGHT)
	check(lab.paused and is_equal_approx(lab.elapsed,0.125),"single frame stepping pauses on next walk phase")
	for index: int in lab.figures.size(): check(lab.figures[index].frame_number() == neutral_frames[index]+1,"all directions step together")
	await key(KEY_LEFT)
	check(lab.elapsed == 0.0,"single frame previous returns neutral")
	await key(KEY_LEFT)
	check(is_equal_approx(lab.elapsed,0.375),"previous frame wraps without negative clip index")
	await key(KEY_SPACE)
	for zoom: int in [1,2,3]:
		lab.zoom = zoom
		lab.elapsed = 0.13
		lab._update_figures()
		lab.queue_redraw()
		await capture("walk_%dx" % zoom)
	for phase: int in 4:
		lab.elapsed = phase/8.0
		lab._update_figures()
		lab.queue_redraw()
		await capture("walk_phase_%d" % phase)
	for action: int in range(lab.ACTIONS.size()):
		lab.action_index = action
		lab.elapsed = 0.13
		lab._update_figures()
		lab.queue_redraw()
		for figure: Node in lab.figures: check(figure.frame_number() >= 0 and figure.frame_number() < 57,"preview valid frame")
		await capture(lab.ACTIONS[action])
	var before: float = lab.elapsed
	lab.paused = true
	lab._process(0.4)
	check(lab.elapsed == before,"preview pause")
	lab.queue_free()
	await process_frame
	await _combat()
	print("CHARACTER_PIPELINE: %d checks, %d failures (presentation and legal combat; not art approval)" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _combat() -> void:
	var setup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/graves_encounter.json"))
	setup["battle"]["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	var battle := CombatEncounter.new()
	var config_error := battle.configure(setup.battle)
	check(config_error.is_empty(),"real story battle configured: "+config_error)
	if not failures.is_empty(): return
	var board := Board.new()
	root.add_child(board)
	board.battle = battle
	board.sync_visuals()
	board.set_process(false)
	board.hero_visual.set_process(false)
	var hit_seen := false
	for turn: int in 180:
		if battle.outcome != "ongoing": break
		var actor := battle.current_actor_id()
		var unit := battle.unit(actor)
		var result: Dictionary
		if unit.team == "enemy": result = AI.take_turn(battle)
		else: result = battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(unit),battle.revision)
		check(result.ok,"legal passive battle action")
		board.animate_action(result.plan)
		board.sync_visuals()
		if board.hero_visual._action == "hit": hit_seen = true
	check(hit_seen,"actual damage triggers hit")
	check(battle.unit("CHAR_PROTAGONIST").hp == 0 and board.hero_visual.clip_name() == "down","real defeat triggers down")
	board.queue_redraw()
	await capture("battle_down")
	battle.retry()
	board.reset_presentation()
	check(board.hero_visual._action.is_empty() and board._motion.is_empty(),"retry removes death and motion")
	var snapshot := battle.snapshot()
	var other_id := ""
	for identifier: String in battle.unit_ids():
		if identifier != "CHAR_PROTAGONIST":
			other_id = identifier
			break
	check(not other_id.is_empty(),"occlusion test has another real actor")
	var other_feet: Vector2 = board._feet(Grid.cell_of(battle.unit(other_id)))
	board.hero_position = other_feet-Vector2(0,1)
	var order: Array[String] = board._sorted_actor_ids()
	check(order.find("CHAR_PROTAGONIST") < order.find(other_id),"moving hero behind actor uses visible feet not destination cell")
	board.hero_position = other_feet+Vector2(0,1)
	order = board._sorted_actor_ids()
	check(order.find("CHAR_PROTAGONIST") > order.find(other_id),"moving hero in front uses visible feet not destination cell")
	board.sync_visuals()
	# Mapping is a read-only presentation contract; legality is covered by the
	# confirmed keyboard commands in test_combat_ui, not fabricated successes.
	for mapping: Array in [["SK_FIST_BASIC","strike"],["SK_YUE_THRUST","thrust"],["ULT_SWORD","slash"],["SK_YUE_GUARD","guard"]]:
		board.animate_action({"actor":"CHAR_PROTAGONIST","skill_id":mapping[0],"target":Vector2i(2,3)})
		check(board.hero_visual._action == mapping[1],"presentation mapping "+mapping[0])
	board.animate_move("CHAR_PROTAGONIST",[Vector2i(1,3),Vector2i(2,3)])
	board._process(0.04)
	check(board.hero_visual.walking and board.hero_position == board.hero_position.round(),"pixel aligned interpolated path")
	board._process(0.05)
	check(not board.hero_visual.walking and board.hero_position == board._feet(Grid.cell_of(battle.unit("CHAR_PROTAGONIST"))),"visual settles at authoritative cell")
	check(battle.snapshot() == snapshot,"visual animation never mutates battle")
	board.queue_free()
