extends SceneTree
## Battle-only size/occlusion regressions. Original PNGs are read/hash-protected;
## only native viewport evidence may be written. No combat/session state is
## decided by the renderer, and the default exploration/lab size is unchanged.
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Screen = preload("res://game/presentation/battle/battle_screen.gd")
const Board = preload("res://game/presentation/battle/battle_board.gd")
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const Actions = preload("res://game/domain/battle/battle_actions.gd")
const A := "CHAR_PROTAGONIST"
const C := "CHAR_COMPANION"
const B := "ENEMY_BLADE"
const ACTIVE_SHA := "ed5a342f06b62191a718551521020c5159ffc2f5a5b97f9bf582bc5385098561"
const CAPTURES := ["battle_26px", "battle_28px", "adjacent_enemy", "adjacent_ally", "adjacent_obstacle", "move_preview", "move_confirmed", "attack_info_layer", "threat_overlay"]
var checks := 0
var failures: Array[String] = []
var screen: Node2D
var fixture: Dictionary
var captures := false
var packed := false
var capture_folder := ""
var captured: Array[String] = []
var protected: Dictionary = {}
var original_session: Dictionary


func _initialize() -> void:
	create_timer(100).timeout.connect(func() -> void: printerr("BOARD_VISIBILITY_FAIL watchdog"); quit(1))
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("BOARD_VISIBILITY_FAIL ", label)
	return ok


func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Board.ORIGIN+Vector2(cell)*Board.CELL,Vector2(Board.CELL,Board.CELL))


func geometry_checks() -> void:
	var visual: Node2D = screen.board.hero_visual
	check(visual.manifest_path() == Hero.ACTIVE_DATA_PATH and visual.default_manifest_error == OK, "battle reuses the unchanged active original textures")
	check(is_equal_approx(screen.board.hero_draw_scale,0.4), "default battle-only scale is 0.4, about 27px body height")
	var at: Vector2 = screen.board._feet(Vector2i(3,3))
	var own := cell_rect(Vector2i(3,3))
	var before: Dictionary = screen.battle.snapshot()
	var before_manifest: Dictionary = visual.manifest_data().duplicate(true)
	for direction: String in ["down","left","right","up"]:
		for action: String in ["idle","walk"]:
			for frame: int in visual.clip_data(action+"_"+direction)["cells"]:
				var geometry: Dictionary = visual.frame_geometry(frame)
				var unscaled: Rect2 = visual.frame_draw_rectangle(frame,at)
				check(unscaled == Rect2(at-geometry["anchor"],geometry["display_size"]), "default exploration/lab rectangle remains unchanged")
				check(unscaled.position.y < own.position.y, "original tall body genuinely crossed the preceding row")
				for scale: float in [0.38,Board.HERO_DRAW_SCALE]:
					var rectangle: Rect2 = visual.frame_draw_rectangle(frame,at,scale)
					check(own.encloses(rectangle), "every standing/walking frame remains inside its own battle cell")
					check(rectangle.size.y <= 29 and rectangle.size.y >= 25, "actual compact frame height is 25–29px")
					check(rectangle.position+geometry["anchor"]*scale == at, "GPU size change preserves the exact physical feet anchor")
	check(not visual.frame_draw_rectangle(0,at,0).has_area() and not visual.frame_draw_rectangle(0,at,-1).has_area(), "invalid presentation scale draws nothing rather than moving the anchor")
	check(screen.battle.snapshot() == before and visual.manifest_data() == before_manifest, "geometry queries change neither domain snapshot nor manifest")


func setup(kind: String) -> Dictionary:
	var definition := fixture.duplicate(true)
	definition["blocked"] = [[4,2]]
	for unit: Dictionary in definition["units"]:
		match unit["id"]:
			A:
				unit["cell"] = [3,3]
				unit["agility"] = 15
				unit["hp"] = 12
			C:
				unit["cell"] = [3,2] if kind == "ally" else [4,1] if kind == "threat" else [2,2]
				unit["agility"] = 20 if kind == "ally" else 5
				unit["hp"] = 10
			B:
				unit["cell"] = [3,2] if kind == "enemy" else [4,2] if kind == "threat" else [6,3]
				unit["agility"] = 20 if kind in ["enemy","threat"] else 2
				unit["hp"] = 6
			"ENEMY_BOW": unit["cell"] = [7,1]
			"ENEMY_CATCHER": unit["cell"] = [8,6]
	if kind == "obstacle": definition["blocked"].append([3,2])
	if kind == "threat": definition["blocked"] = [[6,4]]
	return definition


func install(kind: String) -> void:
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
		await process_frame
	var battle := Combat.new()
	check(battle.configure(setup(kind)).is_empty(), "adjacent "+kind+" fixture configured through actual combat authority")
	# An actual breath creates the status marker on the preceding-row actor;
	# no status/turn/snapshot is fabricated by the board.
	for _turn: int in range(8):
		if battle.current_actor_id() == A: break
		var actor: String = battle.current_actor_id()
		check(battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(battle.unit(actor)),battle.revision)["ok"], "legal prior actor action reaches protagonist")
	check(battle.current_actor_id() == A, "protagonist owns real keyboard turn")
	screen = Screen.new()
	screen.battle = battle
	screen.auto_ai = false
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	screen.board.set_process(false)
	screen.board.hero_visual.set_process(false)
	check(screen.board.hero_position == screen.board._feet(Vector2i(3,3)), "initial visible feet match actual cell without physical offsets")


func native_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Image = root.get_texture().get_image()
	check(result != null and result.get_size() == Vector2i(640,360), "actual native 640x360 render")
	return result


func same_region(left: Image, right: Image, rectangle: Rect2) -> bool:
	for y: int in range(int(rectangle.position.y),int(rectangle.end.y)):
		for x: int in range(int(rectangle.position.x),int(rectangle.end.x)):
			if left.get_pixel(x,y) != right.get_pixel(x,y): return false
	return true


func pixel_is(image: Image, at: Vector2, color: Color) -> bool:
	var actual := image.get_pixel(int(at.x),int(at.y))
	return absf(actual.r-color.r) < 0.01 and absf(actual.g-color.g) < 0.01 and absf(actual.b-color.b) < 0.01


func above_cell_visible(kind: String) -> void:
	if not captures: return
	var before: Dictionary = screen.battle.snapshot()
	var scale: float = screen.board.hero_draw_scale
	# Reference is a read-only GPU comparison, never a final gameplay capture.
	screen.board.hero_draw_scale = 0.0
	screen.board.queue_redraw()
	var reference: Image = await native_image()
	screen.board.hero_draw_scale = scale
	screen.board.queue_redraw()
	var actual: Image = await native_image()
	var rectangle := cell_rect(Vector2i(3,2))
	check(same_region(reference,actual,rectangle), "visible compact hero changes zero pixels in the entire preceding-row "+kind+" cell")
	if kind == "obstacle":
		check(pixel_is(actual,rectangle.position+Vector2(16,16),Color("#796f5c")), "preceding obstacle remains visibly brown")
	else:
		var identifier := B if kind == "enemy" else C
		check(screen.battle.unit_at(Vector2i(3,2)) == identifier, "real adjacent unit is present")
		# Sample clear body paint, not the Chinese unit glyph inside the rectangle.
		check(pixel_is(actual,rectangle.position+Vector2(9,6),Color("#dd876e") if kind == "enemy" else Color("#69bfd5")), "preceding-row "+kind+" unit body remains readable")
		check(pixel_is(actual,rectangle.position+Vector2(5,28),Color("#95c979")), "preceding-row HP remains visible above hero")
		check(pixel_is(actual,rectangle.position+Vector2(27,28),Color("#17232b")), "preceding-row missing HP remains distinguishable")
		check(pixel_is(actual,rectangle.position+Vector2(27,5),Color("#d9bd68")), "preceding-row real status marker remains visible")
	check(screen.battle.snapshot() == before, "GPU size/reference comparison is strictly domain read-only")


func capture(name: String) -> void:
	if not captures: return
	check(name in CAPTURES and name not in captured, "unique declared viewport evidence "+name)
	var image: Image = await native_image()
	if check(image.save_png(capture_folder.path_join(name+".png")) == OK, "native evidence saved "+name): captured.append(name)


func choose_skill(identifier: String) -> void:
	var index: int = screen.battle.abilities(A).find(identifier)+1
	check(index > 0, "actual available keyboard ability "+identifier)
	for _step: int in range(32):
		if screen.selection == index: break
		await key(KEY_DOWN)
	check(screen.selection == index, "keyboard focus reaches "+identifier)
	await key(KEY_E)
	check(screen.mode == "target", "actual command enters target selection")


func keyboard_visibility() -> void:
	await install("enemy")
	var before: Dictionary = screen.battle.snapshot()
	await key(KEY_E)
	await key(KEY_RIGHT)
	check(screen.mode == "move" and not screen.board.enemy_reach.is_empty() and not screen.board.highlights.is_empty(), "real keyboard movement shows enemy and ally ranges")
	check(screen.cursor == Vector2i(4,3) and screen.board.cursor == screen.cursor, "actual keyboard drives top-layer cursor")
	check(screen.battle.snapshot() == before, "movement cursor/range previews do not alter authority")
	await capture("move_preview")
	if captures:
		var actual: Image = await native_image()
		# Godot's one-pixel outline is centred on the edge: its painted left
		# pixel is x-1, not the interior cell at x. Keep the exact colour check.
		check(pixel_is(actual,cell_rect(screen.cursor).position+Vector2(-1,10),Color.WHITE), "real cursor outline is on top of the rendered board")
		var range_visible := false
		for cell: Vector2i in screen.board.enemy_reach:
			if cell == screen.cursor: continue
			if pixel_is(actual,cell_rect(cell).position+Vector2(2,10),Color("#b78bc9")): range_visible = true; break
		check(range_visible, "actual enemy reachable border survives the actor rendering pass")
	await key(KEY_E)
	check(screen.mode == "move_confirm" and screen.battle.snapshot() == before, "real move requires confirmation")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(screen.mode == "command" and screen.battle.snapshot() == before, "real cancellation changes neither turn nor position")
	await key(KEY_E)
	await key(KEY_RIGHT)
	await key(KEY_E)
	await key(KEY_E)
	check(screen.battle.moved and Grid.cell_of(screen.battle.unit(A)) == Vector2i(4,3), "actual confirmed keyboard move changes only legal battle location")
	var committed: Dictionary = screen.battle.snapshot()
	screen.board._process(0.04)
	check(screen.board.hero_visual.walking and screen.board.hero_position == screen.board.hero_position.round(), "actual confirmed movement animates compact original walk with integer feet")
	var bounds: Rect2 = screen.board.hero_visual.frame_draw_rectangle(screen.board.hero_visual.frame_number(),screen.board.hero_position,screen.board.hero_draw_scale)
	check(bounds.position.y >= cell_rect(Vector2i(3,3)).position.y, "horizontal interpolated body never reaches the preceding row")
	await capture("move_confirmed")
	screen.board._process(0.05)
	check(screen.board.hero_position == screen.board._feet(Vector2i(4,3)) and not screen.board.hero_visual.walking, "visual movement settles at the unchanged physical grid anchor")
	check(screen.battle.snapshot() == committed, "visual interpolation cannot change damage/resources/turns")
	await install("enemy")
	before = screen.battle.snapshot()
	await choose_skill("SK_YUE_THRUST")
	await key(KEY_UP)
	await key(KEY_E)
	check(screen.mode == "action_confirm" and screen.battle.snapshot() == before, "adjacent upper enemy actual attack preview is read-only")
	await key(KEY_E)
	check(screen.board.hero_visual._action == "thrust" and screen.board.hero_visual.facing == "up", "real confirmed attack plays original upward weapon animation at compact size")
	check(screen.battle.unit(B)["hp"] > 0 and screen.battle.unit(B)["hp"] < before["units"][B]["hp"], "actual preceding-row target damage remains authoritative")
	await capture("attack_info_layer")
	if captures:
		var actual: Image = await native_image()
		check(pixel_is(actual,cell_rect(Vector2i(3,2)).position+Vector2(5,28),Color("#95c979")), "upward attack cannot cover preceding-row health information")
		check(pixel_is(actual,cell_rect(Vector2i(3,2)).position+Vector2(27,28),Color("#17232b")), "upward attack cannot cover missing-health information")


func danger_overlay() -> void:
	await install("threat")
	var before: Dictionary = screen.battle.snapshot()
	await key(KEY_E)
	await key(KEY_RIGHT)
	var overlap := Vector2i(4,3)
	check(overlap in screen.board.highlights and overlap in screen.board.enemy_reach, "actual movement fixture contains a shared ally/enemy reachable cell")
	check(overlap in Actions.target_cells(screen.battle,B,"SK_FIST_BASIC"), "danger sample is in an actual current-position enemy attack shape, not a guessed future AI plan")
	var occupied := Grid.cell_of(screen.battle.unit(C))
	check(occupied in Actions.target_cells(screen.battle,B,"SK_FIST_BASIC"), "actual adjacent companion occupies a current attack-danger cell")
	var reference: Image
	if captures: reference = await native_image()
	# Explicit marker-layer probe: the real movement/attack geometry is retained,
	# and added target/affected view lists must coexist without mutating combat.
	screen.board.enemy_attack_cells = [overlap,occupied]
	screen.board.valid_targets = [overlap]
	screen.board.affected = [overlap]
	screen.board.queue_redraw()
	await capture("threat_overlay")
	if captures:
		var image: Image = await native_image()
		var at := cell_rect(overlap).position
		check(pixel_is(image,at+Vector2(14,12),Color("#315a65")), "danger hatch does not replace cyan movement fill")
		check(pixel_is(image,at+Vector2(2,10),Color("#b78bc9")), "purple movement frame coexists with danger and affected outlines")
		check(pixel_is(image,at+Vector2(3,10),Color("#a5dfeb")), "bright selectable frame keeps its independent meaning")
		check(pixel_is(image,at+Vector2(6,10),Color("#cd6864")), "red inner current-attack danger frame remains visible")
		check(pixel_is(image,at+Vector2(0,10),Color("#e88e77")), "orange affected outline retains its independent meaning")
		check(pixel_is(image,at+Vector2(-1,10),Color.WHITE), "white keyboard cursor remains above all combined range markers")
		var ally_at := cell_rect(occupied).position
		check(pixel_is(image,ally_at+Vector2(6,10),Color("#cd6864")), "danger frame is visible when an ally body occupies the cell")
		check(same_region(reference,image,Rect2(ally_at+Vector2(8,8),Vector2(15,15))), "danger frame never erases or replaces the unit-name inner region")
		check(same_region(reference,image,Rect2(ally_at+Vector2(4,28),Vector2(24,2))), "occupied-danger ally health remains identical to the unmarked view")
	check(screen.battle.snapshot() == before, "current danger/target/affected presentation adds no turn, damage or saved state")


func _run() -> void:
	await process_frame
	root.size = Vector2i(640,360)
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	captures = "--capture-board-visibility" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed, "PCK runtime only, no source project overlay")
	if captures: check(DisplayServer.get_name() != "headless", "real renderer required for viewport evidence")
	capture_folder = OS.get_environment("WUXIA_CAPTURE_DIR")
	if capture_folder.is_empty(): capture_folder = "res://builds/qa/board_visibility"
	capture_folder = ProjectSettings.globalize_path(capture_folder)
	if captures:
		check(not capture_folder.begins_with(ProjectSettings.globalize_path("res://assets/")) and not capture_folder.begins_with(ProjectSettings.globalize_path("res://docs/art_reference/")), "screenshots cannot target original art")
		check(DirAccess.make_dir_recursive_absolute(capture_folder) == OK, "native evidence directory created")
	check(FileAccess.get_sha256(Hero.ACTIVE_DATA_PATH) == ACTIVE_SHA, "active original manifest bytes retain exact protected SHA")
	protected[Hero.ACTIVE_DATA_PATH] = ACTIVE_SHA
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Hero.ACTIVE_DATA_PATH))
	for frame: Dictionary in manifest["frames"]:
		if FileAccess.file_exists(frame["texture"]):
			check(FileAccess.get_sha256(frame["texture"]) == frame["source_sha256"], "raw original PNG parity where available")
			protected[frame["texture"]] = frame["source_sha256"]
	if not packed: check(protected.size() == 16, "all fifteen raw PNGs and manifest are protected in source")
	else: print("BOARD_VISIBILITY_PACKED_SOURCE_PARITY raw PNG SHA parity requires export preflight; imported textures are not raw PNG bytes")
	original_session = root.get_node("GameSession").state.to_dict().duplicate(true)
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/week6_ai_test_encounter.json"))
	fixture["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	fixture["ai_profiles"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_ai_profiles.json"))
	await install("enemy")
	geometry_checks()
	var before: Dictionary = screen.battle.snapshot()
	screen.board.hero_draw_scale = 0.38
	screen.board.queue_redraw()
	await above_cell_visible("enemy")
	await capture("battle_26px")
	screen.board.hero_draw_scale = Board.HERO_DRAW_SCALE
	screen.board.queue_redraw()
	await above_cell_visible("enemy")
	await capture("battle_28px")
	check(screen.battle.snapshot() == before, "both size candidates leave the exact battle snapshot unchanged")
	for kind: String in ["enemy","ally","obstacle"]:
		await install(kind)
		await above_cell_visible(kind)
		await capture("adjacent_"+kind)
	await keyboard_visibility()
	await danger_overlay()
	check(root.get_node("GameSession").state.to_dict() == original_session, "all visual and keyboard battle checks preserve persistent gameplay state")
	for path: String in protected: check(FileAccess.get_sha256(path) == protected[path], "original PNG/manifest bytes unchanged after the whole test")
	if captures: check(captured == CAPTURES, "exactly nine ordered native viewport captures produced")
	if is_instance_valid(screen): screen.queue_free(); await process_frame
	print("BOARD_VISIBILITY: %d checks, %d failures; geometry/keyboard/render evidence, not human aesthetic acceptance" % [checks,failures.size()])
	if failures.is_empty(): print("BOARD_VISIBILITY_PASS checks=%d packed=%s captures=%d" % [checks,packed,captured.size()])
	quit(0 if failures.is_empty() else 1)
