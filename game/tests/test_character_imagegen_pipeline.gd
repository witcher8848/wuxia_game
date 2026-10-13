extends SceneTree
## ACTIVE-PRODUCTION engineering checks, not anatomy/naturalness/user approval.
## Original character PNGs are read/hash-protected. Only viewport screenshots
## may be written, to WUXIA_CAPTURE_DIR; no source image is modified or exported.
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const Player = preload("res://game/presentation/exploration/player_controller.gd")
const Lab = preload("res://game/presentation/characters/character_lab.gd")
const Screen = preload("res://game/presentation/battle/battle_screen.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const ACTIVE := "res://assets/runtime/characters/chr_protagonist_imagegen_20261012.json"
const DIRECTIONS := ["down","left","right","up"]
const COUNTS := {"walk":4,"strike":2,"thrust":3,"slash":3,"guard":1,"hit":1,"idle":1}
const FPS := {"walk":8,"strike":10,"thrust":10,"slash":10,"guard":3,"hit":5,"idle":1}
const CAPTURES := ["walk_1x","walk_2x","walk_3x","walk_phase_0","walk_phase_1","walk_phase_2","walk_phase_3","thrust","slash","guard","hit","down","exploration","battle"]
const MOVE_ACTIONS := ["move_left","move_right","move_up","move_down","sprint"]
var checks := 0
var failures: Array[String] = []
var captures := false
var packed := false
var protected: Dictionary = {}
var images: Dictionary = {}
var captured: Array[String] = []
var manifest: Dictionary = {}
var app: Node
var session: Node

func _initialize() -> void:
	create_timer(110,true).timeout.connect(func() -> void: printerr("CHARACTER_IMAGEGEN_PIPELINE_FAIL watchdog"); quit(1))
	_run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CHARACTER_IMAGEGEN_PIPELINE_FAIL ",label)
	return ok

func _finish() -> void:
	for path: String in protected:
		check(FileAccess.get_sha256(path) == protected[path],"original/source bytes unchanged "+path)
	if captures: check(captured == CAPTURES,"complete ordered 14 actual-render captures")
	print("CHARACTER_IMAGEGEN_PIPELINE: %d checks, %d failures; active production, NOT semantic animation or human approval" % [checks,failures.size()])
	if failures.is_empty():
		print("CHARACTER_IMAGEGEN_PIPELINE_PASS checks=%d packed=%s captures=%d" % [checks,packed,captured.size()])
	quit(0 if failures.is_empty() else 1)

func _protect(path: String) -> void:
	if FileAccess.file_exists(path) and not protected.has(path): protected[path] = FileAccess.get_sha256(path)

func _advance(frames := 1) -> void:
	for _frame: int in frames:
		await physics_frame
		await process_frame

func _release() -> void:
	for action: String in MOVE_ACTIONS: Input.action_release(action)

func _key(code: Key,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _tap(code: Key) -> void:
	_key(code,true)
	await process_frame
	_key(code,false)
	await process_frame

func _capture(name: String) -> void:
	if not captures: return
	if not check(name in CAPTURES and name not in captured,"unique declared capture "+name): return
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	if not check(screenshot != null and not screenshot.is_empty() and screenshot.get_size() == Vector2i(640,360),"real 640x360 viewport "+name): return
	var folder := OS.get_environment("WUXIA_CAPTURE_DIR")
	if folder.is_empty(): folder = "res://builds/qa/week5_imagegen_pipeline"
	var absolute := ProjectSettings.globalize_path(folder)
	if not check(not absolute.begins_with(ProjectSettings.globalize_path("res://assets")) and not absolute.begins_with(ProjectSettings.globalize_path("res://docs/art_reference")),"screenshots never target source/character folders"): return
	if not check(DirAccess.make_dir_recursive_absolute(absolute) == OK,"capture directory "+name): return
	if check(screenshot.save_png(absolute.path_join(name+".png")) == OK,"write only viewport evidence "+name): captured.append(name)

func _sha(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

func _valid_sha(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character: String in value:
		if character not in "0123456789abcdef": return false
	return true

func _active(hero: Node,label: String) -> bool:
	return check(hero.default_manifest_error == OK and hero.manifest_path() == ACTIVE and hero.manifest_data() == manifest,"default active manifest, no opt-in fixture: "+label) and check(hero.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"nearest actual hero: "+label)

func _run() -> void:
	await process_frame
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	captures = "--capture-imagegen" in OS.get_cmdline_user_args()
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed,"real PCK only, no source overlay")
	if captures: check(DisplayServer.get_name() != "headless","real rendering required for --capture-imagegen")
	check(FileAccess.file_exists(ACTIVE),"production manifest exists; missing assets never fall back to legacy")
	check(Hero.ACTIVE_DATA_PATH == ACTIVE,"shared production default selects imagegen, not legacy DATA_PATH")
	if not failures.is_empty(): _finish(); return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACTIVE))
	if not check(parsed is Dictionary,"active JSON object"): _finish(); return
	manifest = parsed
	check(manifest.get("schema_version") == 2 and manifest.get("frame_count") == 57,"schema2 and 57 logical slots")
	check(manifest.get("frames") is Array and manifest.frames.size() == 57,"57 frame records")
	check(manifest.get("clips") is Dictionary and manifest.clips.size() == 29,"29 clips: four directions seven actions plus down")
	if not failures.is_empty(): _finish(); return
	app = root.get_node("App")
	session = root.get_node("GameSession")
	var original_state: Dictionary = session.state.to_dict().duplicate(true)
	var original_contexts: Array = app.contexts.duplicate()
	_protect(ACTIVE)
	for path: String in ["res://assets/source/characters/hero_pixel_source.gd",Hero.DATA_PATH,"res://assets/runtime/characters/chr_protagonist_atlas.png"]: _protect(path)
	var hero := Hero.new()
	root.add_child(hero)
	hero.set_process(false)
	if not _active(hero,"fresh shared Hero"):
		hero.queue_free(); _finish(); return
	_resources(hero)
	_playback(hero)
	hero.queue_free()
	await process_frame
	if not failures.is_empty(): _finish(); return
	await _controller(original_state)
	await _lab()
	await _exploration()
	await _battle()
	_release()
	app.contexts.assign(original_contexts)
	check(session.replace_state(GameState.from_dict(original_state)) == OK and session.state.to_dict() == original_state,"restore this test's in-memory session; no save writes")
	_finish()

func _resources(hero: Node) -> void:
	var slots: Array[int] = []
	for direction: String in DIRECTIONS:
		for action: String in COUNTS:
			var clip: Dictionary = manifest.clips.get(action+"_"+direction,{})
			if not check(clip.get("cells") is Array and clip.cells.size() == COUNTS[action],"clip count "+action+direction): continue
			check(clip.get("fps") == FPS[action] and clip.get("loop") == (action in ["walk","idle"]),"unchanged clip timing "+action+direction)
			if action != "idle":
				for cell: Variant in clip.cells: slots.append(int(cell))
		check(manifest.clips.get("idle_"+direction,{}).get("cells") == [manifest.clips.get("walk_"+direction,{}).get("cells",[-1])[0]],"idle reuses first walk "+direction)
	var down: Dictionary = manifest.clips.get("down",{})
	if check(down.get("cells") is Array and down.cells.size() == 1,"one persistent down slot"):
		slots.append(int(down.cells[0]))
	check(down.get("fps") == 1 and down.get("loop") == false,"existing down timing")
	slots.sort()
	check(slots == range(57),"all 57 non-idle slots exactly once")
	for index: int in 57:
		var record: Dictionary = manifest.frames[index]
		var geometry: Dictionary = hero.frame_geometry(index)
		if not check(not geometry.is_empty() and geometry.texture is Texture2D,"all geometry/texture loaded "+str(index)): continue
		var resource: String = record.texture
		check(resource.begins_with("res://assets/runtime/characters/") and resource.ends_with(".png") and ".." not in resource and "\\" not in resource,"runtime PNG scope "+str(index))
		check(_valid_sha(record.get("source_sha256")),"source SHA format "+str(index))
		var reference: Variant = record.get("source_reference")
		var reference_ok: bool = reference is String and reference.begins_with("docs/art_reference/") and reference.ends_with(".png") and ".." not in reference and "\\" not in reference and "//" not in reference
		check(reference_ok,"explicit canonical original reference "+str(index))
		var size: Variant = record.get("source_size")
		var size_ok: bool = size is Array and size.size() == 2
		if size_ok:
			for dimension: Variant in size:
				size_ok = size_ok and typeof(dimension) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(dimension)) and dimension > 0 and dimension == int(dimension)
		check(size_ok,"original PNG dimensions recorded "+str(index))
		if size_ok: check(geometry.texture.get_size() == Vector2(size[0],size[1]),"imported original texture dimensions "+str(index))
		check(geometry.region.size.x > 0 and geometry.region.size.y > 0 and Rect2(Vector2.ZERO,geometry.texture.get_size()).encloses(geometry.region),"region within original PNG "+str(index))
		check(is_equal_approx(geometry.display_size.x/geometry.region.size.x,geometry.display_size.y/geometry.region.size.y),"uniform GPU display scale "+str(index))
		check(geometry.anchor.x >= 0 and geometry.anchor.y >= 0 and geometry.anchor.x <= geometry.display_size.x and geometry.anchor.y <= geometry.display_size.y,"legal display foot anchor including boundary "+str(index))
		if not images.has(resource):
			var imported: Image = geometry.texture.get_image()
			if not check(imported != null and not imported.is_empty(),"texture fully decoded "+resource): continue
			imported.convert(Image.FORMAT_RGBA8) # In-memory readback only; never saved.
			images[resource] = imported
			check(imported.get_used_rect().has_area(),"nonempty imported original "+resource)
			var transparent := false
			var visible := false
			var pixels := imported.get_data()
			for offset: int in range(3,pixels.size(),4):
				transparent = transparent or pixels[offset] == 0
				visible = visible or pixels[offset] > 0
				if transparent and visible: break
			check(transparent and visible,"original alpha includes transparent background and visible art "+resource)
			if not packed and reference_ok:
				var source: String = "res://"+reference
				check(FileAccess.file_exists(source) and FileAccess.file_exists(resource),"source/raw runtime available "+resource)
				if FileAccess.file_exists(source) and FileAccess.file_exists(resource):
					_protect(source); _protect(resource)
					check(FileAccess.get_sha256(source) == record.source_sha256 and FileAccess.get_sha256(resource) == record.source_sha256,"original/raw runtime bytes match source SHA "+resource)
					var original := Image.new()
					if check(original.load_png_from_buffer(FileAccess.get_file_as_bytes(source)) == OK,"fully decode original PNG "+resource):
						original.convert(Image.FORMAT_RGBA8)
						check(original.get_size() == imported.get_size() and original.get_data() == imported.get_data(),"lossless imported RGBA preserves original alpha/RGB "+resource)
			else:
				print("IMAGEGEN_PACKED_TEXTURE_READBACK ",resource," source_sha256=",record.get("source_sha256")," raw/source parity verified by build preflight, not invented from compressed bytes")
		if images.has(resource): check(images[resource].get_region(Rect2i(geometry.region)).get_used_rect().has_area(),"nonempty selected pose "+str(index))
	for direction: String in DIRECTIONS:
		var hashes: Array[String] = []
		for cell: Variant in manifest.clips["walk_"+direction].cells:
			var geometry: Dictionary = hero.frame_geometry(int(cell))
			if not images.has(manifest.frames[int(cell)].texture): continue
			var region: Image = images[manifest.frames[int(cell)].texture].get_region(Rect2i(geometry.region))
			hashes.append(_sha(region.get_data()))
		var distinct: Dictionary = {}
		for digest: String in hashes: distinct[digest] = true
		check(hashes.size() == 4 and distinct.size() == 4,"four different actual decoded walk-region contents "+direction)
		print("IMAGEGEN_WALK_REGION_SHA ",direction," ",JSON.stringify(hashes),"; difference is NOT anatomical phase alternation or naturalness approval")

func _playback(hero: Node) -> void:
	for direction: String in DIRECTIONS:
		hero.reset_pose(); hero.facing = direction; hero.walking = true
		for phase: int in 4:
			hero.step_time = phase/8.0
			check(hero.frame_number() == int(manifest.clips["walk_"+direction].cells[phase]),"mapped walk phase "+direction+str(phase))
		hero.walking = false
		check(hero.clip_name() == "idle_"+direction,"stopping retains facing "+direction)
		for action: String in ["strike","thrust","slash","guard","hit"]:
			hero.play_action(action,direction)
			var clip: Dictionary = hero.clip_data()
			var duration: float = clip.cells.size()/float(clip.fps)
			hero._process(duration-0.001)
			check(hero._action == action and hero.frame_number() == int(clip.cells[-1]),"one-shot final frame "+action+direction)
			hero._process(0.002)
			check(hero.clip_name() == "idle_"+direction,"one-shot returns idle "+action+direction)
	hero.play_action("down","down"); hero._process(10)
	var elapsed: float = hero._elapsed
	hero._process(10)
	check(hero.clip_name() == "down" and hero.frame_number() == int(manifest.clips.down.cells[0]) and hero._elapsed == elapsed,"down holds terminal frame without unbounded clock")
	hero.reset_pose()
	check(hero._action.is_empty() and hero.step_time == 0,"retry pose resets down and walk time")

func _controller(original_state: Dictionary) -> void:
	app.reset_contexts()
	var world := Node2D.new()
	root.add_child(world)
	var player := Player.new()
	world.add_child(player)
	player.position = Vector2(100.25,100.25)
	await _advance(2)
	_active(player._visual,"real CharacterBody controller")
	check(player.get_node("FeetCollision").shape.size == Vector2(20,12),"unchanged 20x12 physical feet")
	check(Player.WALK_SPEED == 180 and Player.SPRINT_SPEED == 300,"unchanged walk/sprint speeds")
	for binding: Array in [[KEY_D,Vector2.RIGHT,"right"],[KEY_A,Vector2.LEFT,"left"],[KEY_W,Vector2.UP,"up"],[KEY_S,Vector2.DOWN,"down"]]:
		_release(); player.reset_input(); await _advance(2)
		var previous_phase := posmod(int(player._visual.step_time*8),4)
		var walk_advanced := false
		_key(binding[0],true)
		for _tick: int in 10:
			await _advance()
			walk_advanced = walk_advanced or player._visual.frame_number() != int(manifest.clips["walk_"+binding[2]].cells[previous_phase])
		check(player.velocity == binding[1]*180 and player.facing == binding[2] and player._visual.walking,"physical walk drives active facing/animation "+binding[2])
		check(walk_advanced,"physical movement advances actual mapped walk frame "+binding[2])
		check(player._visual.global_position == player.global_position.round() and player.position != player.position.round(),"integer drawing/fractional physics "+binding[2])
		_key(binding[0],false); await _advance(2)
		check(player.velocity == Vector2.ZERO and player._visual.clip_name() == "idle_"+binding[2],"physical release stops with facing "+binding[2])
	var sprint_clock: float = player._visual.step_time
	_key(KEY_D,true); _key(KEY_SHIFT,true); await _advance(3)
	check(player.velocity == Vector2(300,0) and player._visual.sprinting,"actual keyboard sprint drives fast active gait")
	check(player._visual.step_time-sprint_clock > 0.05,"actual sprint advances gait faster than normal three ticks")
	var stopped: Vector2 = player.position
	app.push_context(&"system_menu"); await _advance(3)
	check(player.position == stopped and not player._visual.walking,"pause context stops held input")
	app.pop_context(); await _advance(3)
	check(player.position == stopped,"resume rejects stale held input")
	_key(KEY_D,false); _key(KEY_SHIFT,false); _release(); await _advance(2)
	_key(KEY_D,true); await _advance(3)
	check(player.position.x > stopped.x,"fresh physical press after pause works")
	player.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	stopped = player.position; await _advance(3)
	check(player.position == stopped and player.velocity == Vector2.ZERO,"focus loss stops active player")
	player.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN); await _advance(3)
	check(player.position == stopped,"focus return rejects stale held input")
	_key(KEY_D,false); _release(); await _advance(2)
	_key(KEY_S,true); await _advance(3)
	check(player.position.y > stopped.y,"fresh press after focus return works")
	paused = true
	stopped = player.position
	await process_frame
	paused = false; await _advance(3)
	check(player.position == stopped,"actual SceneTree pause/resume resets held intent")
	_key(KEY_S,false); _release()
	check(session.state.to_dict() == original_state,"visual/controller never writes session state")
	world.queue_free(); await process_frame

func _lab_bounds(lab: Node,label: String) -> void:
	var visible := 0
	for index: int in 4:
		var bounds: Rect2 = lab.preview_draw_bounds(index)
		if not bounds.has_area(): continue
		visible += 1
		check(lab.preview_content_rect(index).encloses(bounds) and Rect2(0,34,640,296).encloses(bounds),"full region inside preview/title/footer "+label+str(index))
		check(bounds.size.is_equal_approx(lab.figures[index].presentation_bounds().size*lab.zoom),"no silent zoom reduction "+label+str(index))
	check(visible == (1 if lab.single_direction_mode() else 4),"all requested figures visible, not replaced by overflow warning "+label)

func _lab() -> void:
	var lab := Lab.new()
	root.add_child(lab)
	lab.set_process(false)
	for figure: Node in lab.figures: _active(figure,"normal character lab")
	await _tap(KEY_DOWN); check(lab.action_index == 2,"manual next action")
	await _tap(KEY_UP); check(lab.action_index == 1,"manual previous action")
	for zoom: int in [1,2,3]:
		await _tap(KEY_1 if zoom == 1 else KEY_2 if zoom == 2 else KEY_3)
		check(lab.zoom == zoom,"manual zoom "+str(zoom))
		lab.elapsed = 0.13; lab._update_figures(); _lab_bounds(lab,"walk "+str(zoom))
		lab.queue_redraw(); await _capture("walk_%dx" % zoom)
	if lab.single_direction_mode():
		await _tap(KEY_D); check(lab.direction_index == 1,"manual single direction next")
		await _tap(KEY_A); check(lab.direction_index == 0,"manual single direction previous")
		await _tap(KEY_A); check(lab.direction_index == 3,"manual direction wraps")
		await _tap(KEY_D)
	lab.elapsed = 0; lab._update_figures()
	await _tap(KEY_RIGHT)
	check(lab.paused and is_equal_approx(lab.elapsed,0.125),"manual step pauses at next actual walk frame")
	for index: int in 4: check(lab.figures[index].frame_number() == int(manifest.clips["walk_"+DIRECTIONS[index]].cells[1]),"manual all directions advance "+str(index))
	await _tap(KEY_LEFT); check(lab.elapsed == 0,"manual step backward")
	await _tap(KEY_LEFT); check(is_equal_approx(lab.elapsed,0.375),"manual backward wraps")
	await _tap(KEY_SPACE); check(not lab.paused,"manual resume")
	await _tap(KEY_SHIFT)
	var before: float = lab.elapsed
	lab._process(0.1)
	check(is_equal_approx(lab.elapsed-before,0.1*300/180),"manual sprint timing ratio")
	await _tap(KEY_SHIFT); await _tap(KEY_SPACE)
	before = lab.elapsed; lab._process(0.3)
	check(lab.elapsed == before,"manual pause freezes active sample")
	lab.zoom = 1
	for phase: int in 4:
		lab.elapsed = phase/8.0; lab._update_figures(); _lab_bounds(lab,"phase "+str(phase))
		lab.queue_redraw(); await _capture("walk_phase_%d" % phase)
	for action: int in Lab.ACTIONS.size():
		lab.action_index = action; lab.elapsed = 0.1; lab._update_figures()
		for zoom: int in [1,2,3]:
			lab.zoom = zoom
			_lab_bounds(lab,Lab.ACTIONS[action]+str(zoom))
		lab.zoom = 1; lab.queue_redraw()
		if Lab.ACTIONS[action] in ["thrust","slash","guard","hit","down"]: await _capture(Lab.ACTIONS[action])
	lab.queue_free(); await process_frame

func _exploration() -> void:
	var main: Node = load("res://game/presentation/main.tscn").instantiate()
	root.add_child(main)
	await _advance(2)
	session.start_new_game()
	if not check(main._enter_yard() == OK,"actual root main enters real content exploration"):
		main.queue_free(); await process_frame; return
	await _advance(3)
	var host: Node = main.get_node("SceneHost")
	if not check(host.get_child_count() == 1,"one actual exploration region"):
		main.queue_free(); await process_frame; return
	var region: Node = host.get_child(0)
	_active(region.player._visual,"actual root exploration player")
	check(region.player.get_node("FeetCollision").shape.size == Vector2(20,12),"actual exploration still 20x12 feet")
	var stable_time: Dictionary = session.state.time_state.duplicate(true)
	var start_position: Vector2 = region.player.position
	_key(KEY_D,true); await _advance(3)
	check(region.player.position.x > start_position.x and region.player._visual.walking and region.player.facing == "right","actual root exploration keyboard physically moves active walk")
	_key(KEY_D,false); _release(); await _advance(2)
	check(session.state.time_state == stable_time,"walking/animation spend no story time")
	await _capture("exploration")
	main.queue_free(); await process_frame
	root.canvas_transform = Transform2D.IDENTITY

func _choose_skill(screen: Node,skill: String) -> bool:
	var index: int = screen.battle.abilities(screen.battle.current_actor_id()).find(skill)+1
	if not check(index > 0,"actual command exists "+skill): return false
	for _attempt: int in screen.options().size():
		if screen.selection == index: break
		await _tap(KEY_DOWN)
	if not check(screen.selection == index,"actual keyboard selects "+skill): return false
	await _tap(KEY_E)
	return check(screen.mode == "target","actual command enters target preview "+skill)

func _battle() -> void:
	app.reset_contexts(); app.push_context(&"battle")
	var setup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/graves_encounter.json"))
	setup.battle["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	var battle := CombatEncounter.new()
	if not check(battle.configure(setup.battle).is_empty(),"actual production encounter configured"): return
	var screen := Screen.new()
	screen.battle = battle; screen.auto_ai = false
	root.add_child(screen)
	screen.set_process(false); screen.board.set_process(false); screen.board.hero_visual.set_process(false)
	await process_frame
	_active(screen.board.hero_visual,"real battle screen/Board default")
	var before: Dictionary = session.state.to_dict().duplicate(true)
	var initial: Dictionary = battle.snapshot()
	# Original encounter order starts with the companion. Pass through her legal
	# keyboard command rather than changing agility/queue or fabricating success.
	if battle.current_actor_id() == "CHAR_COMPANION" and await _choose_skill(screen,"ACT_BREATH"):
		await _tap(KEY_E); await _tap(KEY_E)
	if not check(battle.current_actor_id() == "CHAR_PROTAGONIST","legal companion action reaches hero turn"):
		screen.queue_free(); await process_frame; return
	var snapshot: Dictionary = battle.snapshot()
	await _tap(KEY_E); await _tap(KEY_RIGHT); await _tap(KEY_E)
	check(screen.mode == "move_confirm" and battle.snapshot() == snapshot,"real movement preview has no state mutation")
	await _tap(KEY_ESCAPE); await _tap(KEY_ESCAPE)
	check(screen.mode == "command" and battle.snapshot() == snapshot and screen.board._motion.is_empty() and screen.board.hero_visual._action.is_empty(),"real cancel never moves or animates hero")
	if await _choose_skill(screen,"SK_YUE_GUARD"):
		await _tap(KEY_E)
		check(screen.mode == "action_confirm" and battle.snapshot() == snapshot and screen.board.hero_visual._action.is_empty(),"real guard preview does not animate or mutate")
		await _tap(KEY_ESCAPE); await _tap(KEY_ESCAPE)
		check(battle.snapshot() == snapshot and screen.board.hero_visual._action.is_empty(),"real action cancellation leaves snapshot/presentation unchanged")
		if await _choose_skill(screen,"SK_YUE_GUARD"):
			await _tap(KEY_E); await _tap(KEY_E)
			check(battle.revision == int(snapshot.revision)+1 and screen.board.hero_visual._action == "guard","actual confirmed legal guard triggers active pose exactly once")
	await _capture("battle")
	var hit_seen := false
	for _turn: int in 180:
		if battle.outcome != "ongoing": break
		var actor: String = battle.current_actor_id()
		var unit: Dictionary = battle.unit(actor)
		var result: Dictionary = AI.take_turn(battle) if unit.team == "enemy" else battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(unit),battle.revision)
		if not check(result.get("ok",false),"legal passive encounter damage turn"): break
		screen.board.animate_action(result.plan)
		screen.actor_changed()
		if screen.board.hero_visual._action == "hit": hit_seen = true
	check(hit_seen,"actual resolved damage triggers active hit")
	check(battle.unit("CHAR_PROTAGONIST").hp == 0 and screen.board.hero_visual._action == "down","actual defeat triggers persistent active down")
	snapshot = battle.snapshot()
	screen.board.hero_visual._process(10)
	var down_elapsed: float = screen.board.hero_visual._elapsed
	for _repeat: int in 4: screen.board.sync_visuals()
	check(screen.board.hero_visual._action == "down" and screen.board.hero_visual._elapsed == down_elapsed and battle.snapshot() == snapshot,"repeated down sync/visual timing never restarts or changes battle")
	var discarded_revision: int = battle.revision
	await _tap(KEY_R); await _tap(KEY_E)
	var restored: Dictionary = battle.snapshot()
	var original_retry_state: Dictionary = initial.duplicate(true)
	# Retry intentionally increments the revision to invalidate old previews;
	# all other authoritative fields must exactly match the real initial state.
	restored.erase("revision"); original_retry_state.erase("revision")
	check(restored == original_retry_state and battle.revision == discarded_revision+1 and screen.board.hero_visual._action.is_empty() and screen.board._motion.is_empty(),"actual confirmed retry restores original state, invalidates stale previews and clears active pose")
	if battle.current_actor_id() == "CHAR_COMPANION" and await _choose_skill(screen,"ACT_BREATH"):
		await _tap(KEY_E); await _tap(KEY_E)
	await _tap(KEY_E); await _tap(KEY_RIGHT); await _tap(KEY_E); await _tap(KEY_E)
	check(battle.moved and screen.board._motion.size() == 2,"actual confirmed move drives shared active walk path")
	snapshot = battle.snapshot()
	screen.board._process(0.04)
	check(screen.board.hero_visual.walking and screen.board.hero_position == screen.board.hero_position.round(),"actual interpolated active movement keeps integer display feet")
	screen.board._process(0.05)
	check(not screen.board.hero_visual.walking and screen.board.hero_position == screen.board._feet(Grid.cell_of(battle.unit("CHAR_PROTAGONIST"))),"active visual settles at authoritative physical cell")
	check(battle.snapshot() == snapshot and session.state.to_dict() == before,"visual animation never decides combat or permanent story state")
	screen.queue_free(); await process_frame
