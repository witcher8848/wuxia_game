extends SceneTree
## Engineering fixtures use ONLY regions of the existing legacy atlas.
## No new character pixels/art are created, approved, or promoted by this test.
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const Board = preload("res://game/presentation/battle/battle_board.gd")
const Lab = preload("res://game/presentation/characters/character_lab.gd")
const Player = preload("res://game/presentation/exploration/player_controller.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")
const AI = preload("res://game/domain/battle/battle_ai.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const ATLAS_PATH := "res://assets/runtime/characters/chr_protagonist_atlas.png"
const PROTECTED := [ATLAS_PATH,Hero.DATA_PATH,"res://assets/source/characters/hero_pixel_source.gd"]
var checks := 0
var failures: Array[String] = []
var captures := false
var fixture_path := ""
var hashes: Dictionary = {}

class FixtureLabel extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,640,34),Color("#171820"))
		draw_string(FONT,Vector2(12,24),"工程夹具：旧图集分区 · 不是新美术或动画验收",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#f1e6cf"))

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CHARACTER_MANIFEST_RENDERER_FAIL ",label)

func _write_fixture(manifest: Dictionary) -> void:
	var file := FileAccess.open(fixture_path,FileAccess.WRITE)
	check(file != null,"temporary metadata writable")
	if file == null: return
	file.store_string(JSON.stringify(manifest))
	file.close()

func _fixture() -> Dictionary:
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Hero.DATA_PATH))
	var frames: Array = []
	for index: int in int(legacy.frame_count):
		frames.append({
			"texture":ATLAS_PATH,
			"region":[(index%8)*32,int(index/8)*48,32,48],
			"display_size":[48,72],"anchor":[24,66],
			"source_sha256":hashes[ATLAS_PATH],
		})
	var clips: Dictionary = legacy.clips.duplicate(true)
	clips.walk_right.cells = [28,31,29,30]
	# Deliberately reuse unrelated legacy regions to exercise multi-frame timing,
	# not to pretend these three poses are finished falling animation artwork.
	clips.down = {"cells":[56,13,12],"fps":5,"loop":false}
	return {"schema_version":2,"frame_count":frames.size(),"nominal_display_size":[48,72],"frames":frames,"clips":clips}

func _invalid(hero: Node, manifest: Dictionary, label: String) -> void:
	var before: Dictionary = hero.manifest_data().duplicate(true)
	var path: String = hero.manifest_path()
	var action: String = hero._action
	var elapsed: float = hero._elapsed
	var frame: int = hero.frame_number()
	var geometry: Dictionary = hero.frame_geometry(frame)
	var bounds: Rect2 = hero.presentation_bounds()
	_write_fixture(manifest)
	check(hero.configure_manifest(fixture_path) != OK,"reject "+label)
	check(hero.manifest_data() == before and hero._action == action and hero._elapsed == elapsed and hero.frame_number() == frame,"failed configuration preserves state: "+label)
	check(hero.manifest_path() == path and hero.frame_geometry(frame) == geometry and hero.presentation_bounds() == bounds,"failed configuration preserves geometry/bounds/source: "+label)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _capture(label: String) -> void:
	if not captures: return
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	check(screenshot != null and not screenshot.is_empty() and screenshot.get_size() == Vector2i(640,360),"real renderer capture "+label)
	if screenshot == null or screenshot.is_empty(): return
	var folder := OS.get_environment("WUXIA_CAPTURE_DIR")
	if folder.is_empty(): folder = "res://builds/qa/character_manifest_renderer_fixture"
	check(DirAccess.make_dir_recursive_absolute(folder) == OK,"fixture screenshot directory")
	check(screenshot.save_png(folder+"/engineering_fixture_"+label+".png") == OK,"save engineering-only screenshot "+label)

func _check_lab_bounds(lab: Node, label: String) -> void:
	var visible := 0
	for index: int in lab.figures.size():
		var bounds: Rect2 = lab.preview_draw_bounds(index)
		if not bounds.has_area(): continue
		visible += 1
		var content: Rect2 = lab.preview_content_rect(index)
		check(content.encloses(bounds),"preview lies inside content: "+label+str(index))
		check(bounds.position.y >= 34 and bounds.end.y <= 330 and bounds.position.x >= 0 and bounds.end.x <= 640,"preview avoids title/footer: "+label+str(index))
		var local: Rect2 = lab.figures[index].presentation_bounds()
		check(bounds.size == local.size*lab.zoom,"preview does not silently scale: "+label+str(index))
	check(visible == (1 if lab.single_direction_mode() else 4),"expected visible directions: "+label)

func _run() -> void:
	await process_frame
	captures = "--capture-manifest-renderer" in OS.get_cmdline_user_args()
	if captures and DisplayServer.get_name() == "headless":
		printerr("CHARACTER_MANIFEST_RENDERER_UNSUPPORTED headless has no real capture; no images written")
		quit(2)
		return
	create_timer(30).timeout.connect(func() -> void: printerr("CHARACTER_MANIFEST_RENDERER_FAIL watchdog"); quit(1))
	fixture_path = "user://character_manifest_renderer_fixture_%d.json" % OS.get_process_id()
	check(not FileAccess.file_exists(fixture_path),"unique temporary metadata path")
	if not failures.is_empty(): quit(1); return
	for path: String in PROTECTED: hashes[path] = FileAccess.get_sha256(path)
	var hero := Hero.new()
	root.add_child(hero)
	hero.set_process(false)
	var default_hero := Hero.new()
	root.add_child(default_hero)
	default_hero.set_process(false)
	var default_data: Dictionary = Hero.data.duplicate(true)
	check(default_hero.default_manifest_error == OK and default_hero.manifest_path() == Hero.ACTIVE_DATA_PATH,"unconfigured Hero selects the unified active default")
	var active_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Hero.ACTIVE_DATA_PATH))
	check(default_hero.manifest_data() == active_data,"active default really loads its metadata, not the legacy static data")
	check(Hero.IMAGEGEN_DATA_PATH == "res://assets/runtime/characters/chr_protagonist_imagegen_20261012.json","planned imagegen promotion path is explicit")
	# Native regression fixtures opt into the old contract regardless of activation.
	check(default_hero.configure_manifest(Hero.DATA_PATH) == OK,"native fixture explicitly selects legacy metadata")
	var fixture := _fixture()
	_write_fixture(fixture)
	var preconfigured_hero := Hero.new()
	check(preconfigured_hero.configure_manifest(fixture_path) == OK,"fixture configures before entering the tree")
	root.add_child(preconfigured_hero)
	preconfigured_hero.set_process(false)
	check(preconfigured_hero.manifest_path() == fixture_path and preconfigured_hero.display_size() == Vector2(48,72),"ready does not overwrite deliberate pre-tree configuration")
	var player := Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	player._visual.set_process(false)
	check(player._visual.default_manifest_error == OK and player._visual.manifest_path() == Hero.ACTIVE_DATA_PATH,"exploration subclass inherits the same active resource selection")
	player.queue_free()
	preconfigured_hero.queue_free()
	check(hero.configure_manifest(fixture_path) == OK,"explicit v2 configuration")
	check(hero.frame_count() == 57 and hero.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"v2 frame count and nearest")
	check(default_hero.manifest_data() == default_data and Hero.data == default_data,"v2 instance does not mutate static default manifest")
	check(default_hero.display_size() == Vector2(32,48) and hero.display_size() == Vector2(48,72),"instances retain different display sizes")
	var geometry: Dictionary = hero.frame_geometry(31)
	check(geometry.region == Rect2(224,144,32,48),"region indexes original texture without new atlas")
	check(geometry.display_size == Vector2(48,72) and geometry.anchor == Vector2(24,66),"metadata display size and logical anchor")
	check(geometry.texture == hero.frame_geometry(28).texture and geometry.texture == Hero.ATLAS,"ResourceLoader shares cached source texture")
	check(hero._geometry_cache.size() == 57,"successful metadata builds all cached frame geometry")
	geometry.anchor = Vector2.ZERO
	check(hero.frame_geometry(31).anchor == Vector2(24,66),"returned geometry cannot mutate the cached frame")
	check(hero.frame_geometry(-1).is_empty() and hero.frame_geometry(57).is_empty(),"out-of-range frame access is safe")
	hero.facing = "right"; hero.walking = true
	check(hero.presentation_bounds() == Rect2(-24,-66,48,72),"bounds merge all mapped cells in display-anchor space")
	var changed: Dictionary = fixture.duplicate(true)
	changed.frames[31].display_size = [96,144]; changed.frames[31].anchor = [48,132]
	_write_fixture(changed)
	check(hero.configure_manifest(fixture_path) == OK,"valid reconfiguration replaces cached metadata")
	hero.walking = true
	check(hero.frame_geometry(31).display_size == Vector2(96,144) and hero.presentation_bounds() == Rect2(-48,-132,96,144),"success invalidates both frame and clip-bounds caches")
	_write_fixture(fixture)
	check(hero.configure_manifest(fixture_path) == OK,"restore original fixture after cache checks")
	hero.facing = "right"
	hero.walking = true
	for phase: int in 4:
		hero.step_time = phase/8.0
		check(hero.frame_number() == fixture.clips.walk_right.cells[phase],"non-contiguous cell mapping phase "+str(phase))
	hero.step_time = 0.5
	check(hero.frame_number() == 28,"walk loop wraps to mapped first cell")
	hero.walking = false
	check(hero.frame_number() == 28 and hero.clip_name() == "idle_right","idle remains facing-specific")
	for direction: String in ["up","down","left","right"]:
		for action: String in ["strike","thrust","slash","guard","hit"]:
			hero.play_action(action,direction)
			var clip: Dictionary = hero.clip_data()
			var duration: float = clip.cells.size()/float(clip.fps)
			hero._process(duration-0.001)
			check(hero._action == action and hero.frame_number() == int(clip.cells[-1]),"one-shot last frame "+action+direction)
			hero._process(0.002)
			check(hero.clip_name() == "idle_"+direction,"one-shot returns idle "+action+direction)
	hero.play_action("down","down")
	hero._process(0.21)
	check(hero.frame_number() == 13,"multi-frame down advances")
	hero._process(10.0)
	check(hero.frame_number() == 12 and hero._action == "down","down holds last frame")
	var down_elapsed: float = hero._elapsed
	hero._process(10.0)
	check(hero.frame_number() == 12 and hero._elapsed == down_elapsed,"down clock stays clamped")
	var bad: Dictionary
	for invalid_version: Variant in [2.8,"2",0,3]:
		bad = fixture.duplicate(true); bad.schema_version = invalid_version
		_invalid(hero,bad,"schema "+str(invalid_version))
	for invalid_count: Variant in [57.5,"57",0,-1,58]:
		bad = fixture.duplicate(true); bad.frame_count = invalid_count
		_invalid(hero,bad,"count "+str(invalid_count))
	bad = fixture.duplicate(true); bad.clips.erase("walk_left")
	_invalid(hero,bad,"missing API clip")
	bad = fixture.duplicate(true); bad.frames[0].region = [240,0,32,48]
	_invalid(hero,bad,"out-of-texture region")
	bad = fixture.duplicate(true); bad.frames[0].region = [0.5,0,32,48]
	_invalid(hero,bad,"fractional source region")
	bad = fixture.duplicate(true); bad.frames[0].display_size = [49,72]
	_invalid(hero,bad,"nonuniform scale")
	bad = fixture.duplicate(true); bad.frames[0].anchor = [-1,66]
	_invalid(hero,bad,"negative anchor")
	bad = fixture.duplicate(true); bad.frames[0].anchor = [24,73]
	_invalid(hero,bad,"anchor outside displayed frame")
	bad = fixture.duplicate(true); bad.frames[0].texture = "res://assets/runtime/characters/nonexistent_fixture.png"
	_invalid(hero,bad,"missing texture")
	bad = fixture.duplicate(true); bad.frames[0].texture = "res://assets/runtime/characters/../characters/chr_protagonist_atlas.png"
	_invalid(hero,bad,"noncanonical texture path")
	bad = fixture.duplicate(true); bad.frames[0].source_sha256 = "not-a-source-hash"
	_invalid(hero,bad,"invalid source hash")
	bad = fixture.duplicate(true); bad.clips.walk_right.cells = [28,57]
	_invalid(hero,bad,"unknown frame cell")
	bad = fixture.duplicate(true); bad.clips.walk_right.cells = [28,31.5]
	_invalid(hero,bad,"fractional frame cell")
	bad = fixture.duplicate(true); bad.clips.walk_right.fps = 0
	_invalid(hero,bad,"zero fps")
	bad = fixture.duplicate(true); bad.clips.walk_right.loop = "true"
	_invalid(hero,bad,"nonboolean loop")
	bad = fixture.duplicate(true); bad.clips.walk_right.cells = []
	_invalid(hero,bad,"empty clip")
	bad = fixture.duplicate(true); bad.clips.down.loop = true
	_invalid(hero,bad,"looping defeat would not hold the final frame")
	bad = fixture.duplicate(true); bad.frame_count = INF
	check(hero._validate_manifest(bad) != OK,"non-finite count rejected before integer conversion")
	bad = fixture.duplicate(true); bad.clips.walk_right.cells = [INF]
	check(hero._validate_manifest(bad) != OK,"non-finite cell rejected before integer conversion")
	var legacy: Dictionary = default_data.duplicate(true)
	legacy.columns = INF
	check(hero._validate_manifest(legacy) != OK,"non-finite legacy columns rejected")
	check(hero.configure_manifest("user://missing_character_manifest_fixture.json") == ERR_FILE_NOT_FOUND and hero._action == "down","missing metadata preserves active state")
	check(default_hero.configure_manifest(Hero.DATA_PATH) == OK and default_hero.display_size() == Vector2(32,48),"legacy manifest remains explicitly configurable")
	hero.reset_pose()
	check(hero.clip_name() == "idle_down" and hero._elapsed == 0 and hero.step_time == 0,"reset clears persistent down")
	hero.hide(); default_hero.hide()
	_write_fixture(fixture)
	await _board(fixture)
	await _lab(fixture)
	check(Hero.data == default_data,"all opt-in tests leave static default intact")
	for path: String in hashes: check(FileAccess.get_sha256(path) == hashes[path],"production source bytes unchanged "+path)
	check(DirAccess.remove_absolute(fixture_path) == OK,"remove only this process's temporary metadata")
	hero.queue_free(); default_hero.queue_free()
	print("CHARACTER_MANIFEST_RENDERER: %d checks, %d failures; engineering legacy-region fixtures only, NOT new art or animation approval" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _board(_fixture_data: Dictionary) -> void:
	var setup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/graves_encounter.json"))
	setup["battle"]["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	var battle := CombatEncounter.new()
	var configuration_error := battle.configure(setup["battle"])
	check(configuration_error.is_empty(),"real story battle configured: "+configuration_error)
	if not configuration_error.is_empty(): return
	var board := Board.new()
	root.add_child(board)
	board.set_process(false)
	board.hero_visual.set_process(false)
	check(board.hero_visual.default_manifest_error == OK and board.hero_visual.manifest_path() == Hero.ACTIVE_DATA_PATH,"battle board inherits the unified active default")
	board.battle = battle
	check(board.hero_visual.configure_manifest(fixture_path) == OK,"board opts into fixture per instance")
	board.sync_visuals()
	for turn: int in 180:
		if battle.outcome != "ongoing": break
		var actor := battle.current_actor_id()
		var unit := battle.unit(actor)
		var result: Dictionary = AI.take_turn(battle) if unit.team == "enemy" else battle.perform_action(actor,"ACT_BREATH",Grid.cell_of(unit),battle.revision)
		check(result.ok,"legal passive defeat action")
		board.animate_action(result.plan)
		board.sync_visuals()
	check(battle.unit("CHAR_PROTAGONIST").hp == 0 and board.hero_visual._action == "down","real defeat starts falling fixture")
	var snapshot := battle.snapshot()
	board.hero_visual._process(0.21)
	var elapsed: float = board.hero_visual._elapsed
	for repeat: int in 5: board.sync_visuals()
	check(board.hero_visual._elapsed == elapsed and board.hero_visual.frame_number() == 13,"repeated battle synchronization does not restart down")
	board.hero_visual._process(10)
	board.sync_visuals()
	check(board.hero_visual.frame_number() == 12 and board.hero_visual._action == "down","board preserves down last frame")
	check(battle.snapshot() == snapshot,"renderer and repeated synchronization never mutate battle")
	battle.retry()
	board.reset_presentation()
	check(board.hero_visual._action.is_empty() and board.hero_visual._elapsed == 0,"battle retry resets persistent down")
	board.queue_free()
	await process_frame

func _lab(fixture: Dictionary) -> void:
	var lab := Lab.new()
	root.add_child(lab)
	lab.set_process(false)
	for figure: Node in lab.figures:
		check(figure.default_manifest_error == OK and figure.manifest_path() == Hero.ACTIVE_DATA_PATH,"lab figure inherits unified active default")
	check(lab.configure_manifest(Hero.DATA_PATH) == OK,"legacy lab layout fixture explicitly selects old metadata")
	for scale: int in [1,2,3]:
		lab.zoom = scale
		check(not lab.dynamic_layout() and not lab.single_direction_mode(),"legacy preview retains four-column mode "+str(scale))
		for index: int in 4:
			check(lab.preview_draw_bounds(index) == Rect2(Vector2(90+index*150,254)+Vector2(-16,-44)*scale,Vector2(32,48)*scale),"legacy preview placement unchanged "+str(scale)+str(index))
	check(lab.configure_manifest(fixture_path) == OK,"lab explicit v2 configuration")
	var label := FixtureLabel.new()
	lab.add_child(label)
	for action: int in lab.ACTIONS.size():
		lab.action_index = action
		lab._update_figures()
		for scale: int in [1,2,3]:
			lab.zoom = scale
			check(lab.single_direction_mode() == (scale == 3),"48x72 layout mode "+str(action)+str(scale))
			_check_lab_bounds(lab,"48x72 "+str(action)+str(scale))
			if action == 1:
				lab.queue_redraw()
				await _capture("48x72_walk_%dx" % scale)
	lab.action_index = lab.ACTIONS.find("down")
	lab.elapsed = 10.0
	lab._update_figures()
	for figure: Node in lab.figures:
		check(figure._action == "down" and figure.frame_number() == 12,"lab also holds the final multi-frame defeat pose")
	lab.elapsed = 0.0
	lab._update_figures()
	lab.zoom = 3
	await _key(KEY_D)
	check(lab.direction_index == 1,"D selects next single-preview direction")
	await _key(KEY_A)
	check(lab.direction_index == 0,"A selects previous single-preview direction")
	await _key(KEY_A)
	check(lab.direction_index == 3,"A wraps direction backward")
	await _key(KEY_D)
	check(lab.direction_index == 0,"D wraps direction forward")
	var larger: Dictionary = fixture.duplicate(true)
	for record: Dictionary in larger.frames:
		record.display_size = [64,96]; record.anchor = [32,88]
	_write_fixture(larger)
	check(lab.configure_manifest(fixture_path) == OK,"64x96 engineering fixture")
	for scale: int in [1,2,3]:
		lab.zoom = scale
		_check_lab_bounds(lab,"64x96 "+str(scale))
	var wide: Dictionary = fixture.duplicate(true)
	for record: Dictionary in wide.frames:
		record.region = [0,0,128,96]; record.display_size = [96,72]; record.anchor = [48,66]
	_write_fixture(wide)
	check(lab.configure_manifest(fixture_path) == OK,"wide and tall legacy-region engineering fixture")
	for scale: int in [1,2,3]:
		lab.zoom = scale
		check(lab.single_direction_mode() == (scale >= 2),"wide tall layout does not force overflowing 2x2 "+str(scale))
		_check_lab_bounds(lab,"wide tall "+str(scale))
	var band: Dictionary = fixture.duplicate(true)
	for record: Dictionary in band.frames:
		record.region = [0,0,128,48]; record.display_size = [96,36]; record.anchor = [48,33]
	_write_fixture(band)
	check(lab.configure_manifest(fixture_path) == OK,"wide short legacy-region engineering fixture")
	lab.zoom = 2
	check(not lab.single_direction_mode() and lab._overview_layout() == 1,"2x2 overview requires both dimensions to fit")
	_check_lab_bounds(lab,"wide short 2x2")
	_write_fixture(fixture)
	lab.queue_free()
	await process_frame
