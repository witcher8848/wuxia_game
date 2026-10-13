extends SceneTree
## Four complete originals; no cropping, bitmap edits, atlas writes or per-frame alignment.
## Run with -- --verify-only, -- --capture, or -- --movie-preview (4 seconds).
const SOURCES := [
	"res://docs/art_reference/protagonist_imagegen_walk_right_pose0_restored_20261010.png",
	"res://docs/art_reference/protagonist_imagegen_walk_right_pose1_restored_20261010.png",
	"res://docs/art_reference/protagonist_imagegen_walk_right_pose2_consistent_20261010.png",
	"res://docs/art_reference/protagonist_imagegen_walk_right_pose3_restored_20261010.png",
]
const PROTECTED := [
	"res://assets/source/characters/hero_pixel_source.gd",
	"res://assets/runtime/characters/chr_protagonist_atlas.png",
	"res://assets/runtime/characters/chr_protagonist_atlas.json",
	"res://game/presentation/exploration/player_controller.gd",
	"res://docs/art_reference/protagonist_imagegen_walk_right_20261010.png",
	"res://docs/art_reference/protagonist_imagegen_walk_right_20261010_v2.png",
]
const OUT := "res://docs/art_reference/hero_imagegen_walk_20261010/single_frames"
const ARMFIX_SOURCE := "res://docs/art_reference/protagonist_imagegen_walk_right_pose3_armfix_20261011.png"
const ARMFIX_OUT := "res://docs/art_reference/hero_imagegen_walk_20261010/single_frames_armfix_20261011"
const BAGFIX_SOURCE := "res://docs/art_reference/protagonist_imagegen_walk_right_pose3_bagfix_20261011.png"
const BAGFIX_OUT := "res://docs/art_reference/hero_imagegen_walk_20261010/single_frames_bagfix_20261011"
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const FPS := 8.0
const FRAME_COUNT := 4
const BOX := Vector2(48,72)
var checks := 0
var failures: Array[String] = []
var hashes: Dictionary = {}
var capture_dir := OUT

class Preview extends Node2D:
	var pictures: Array[Texture2D] = []
	var canvas_size := Vector2.ZERO
	var paused := false
	var light := true
	var contact_sheet := false
	var elapsed := 0.0
	var observed_frames: Dictionary = {}
	static func frame_at(time: float) -> int:
		return posmod(int(floor(time*FPS)),FRAME_COUNT)
	func _process(delta: float) -> void:
		if not paused: elapsed += delta
		observed_frames[frame_at(elapsed)] = true
		queue_redraw()
	func _unhandled_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo: return
		match event.physical_keycode:
			KEY_1: light = true
			KEY_2: light = false
			KEY_SPACE: paused = not paused
			KEY_LEFT: _step(-1)
			KEY_RIGHT: _step(1)
			KEY_ESCAPE: get_tree().quit()
			_: return
		get_viewport().set_input_as_handled()
		queue_redraw()
	func _step(delta: int) -> void:
		paused = true
		elapsed = posmod(frame_at(elapsed)+delta,FRAME_COUNT)/FPS
	func draw_pose(index: int, center_x: float, baseline: float, magnification: int, guide: Color) -> void:
		var box := BOX*magnification
		var fit := minf(box.x/canvas_size.x,box.y/canvas_size.y)
		var display_size := canvas_size*fit
		var slot := Rect2(Vector2(center_x-box.x/2.0,baseline-box.y),box)
		var destination := Rect2(Vector2(center_x-display_size.x/2.0,baseline-display_size.y),display_size)
		draw_rect(slot,guide,false,1.0)
		draw_line(Vector2(center_x-box.x/2.0-12,baseline+1),Vector2(center_x+box.x/2.0+12,baseline+1),guide)
		# One shared transform for all four equal-sized complete source canvases.
		draw_texture_rect(pictures[index],destination,false)
	func _draw() -> void:
		var background := Color("#d8d0be") if light else Color("#203934")
		var ink := Color("#242833") if light else Color("#f1e6cf")
		var guide := Color("#747b78") if light else Color("#7fa38d")
		draw_rect(Rect2(0,0,640,360),background)
		draw_string(FONT,Vector2(12,24),"单帧行走显示试验 · 非生产48×72原生精灵",HORIZONTAL_ALIGNMENT_LEFT,-1,18,ink)
		draw_string(FONT,Vector2(12,44),"完整原图等比显示 · 共用映射／最近邻 · 4帧 / 8 FPS",HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
		if contact_sheet:
			for index: int in FRAME_COUNT:
				var center := 88.0+index*155.0
				draw_string(FONT,Vector2(center-43,65),"帧 %d · 上1× 下2×" % index,HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
				draw_pose(index,center,147,1,guide)
				draw_pose(index,center,310,2,guide)
		else:
			var index := frame_at(elapsed)
			draw_string(FONT,Vector2(98,75),"1×显示 / 帧 %d" % index,HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
			draw_string(FONT,Vector2(346,75),"3×观察 / "+("暂停" if paused else "播放"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
			draw_pose(index,164,304,1,guide)
			draw_pose(index,420,304,3,guide)
		draw_string(FONT,Vector2(12,333),"Space暂停 · ←→暂停逐帧 · 1亮 / 2暗 · Esc退出",HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
		draw_string(FONT,Vector2(12,352),"原图未裁切／修位图；正式32×48角色、碰撞、旧条带未修改",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("SINGLE_WALK_FAIL ",label)
func _unchanged() -> void:
	for path: String in hashes: check(FileAccess.get_sha256(path) == hashes[path],"unchanged "+path)
func _finish(label: String) -> void:
	_unchanged()
	print("SINGLE_WALK_%s: %d checks, %d failures; engine contract only, NOT natural animation or art approval" % [label,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
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
func _capture(card: Preview, filename: String) -> void:
	card.queue_redraw()
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	check(screenshot != null and not screenshot.is_empty(),"real rendered pixels "+filename)
	if screenshot == null or screenshot.is_empty(): return
	check(screenshot.get_size() == Vector2i(640,360),"logical screenshot size "+filename)
	check(screenshot.save_png(capture_dir+"/"+filename+".png") == OK,"save "+filename)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var verify := "--verify-only" in args
	var capture := "--capture" in args
	var movie := "--movie-preview" in args
	var source_paths: Array = SOURCES.duplicate()
	var protected_paths: Array = PROTECTED.duplicate()
	var variant := "original"
	for argument: String in args:
		if argument.begins_with("--variant="):
			if argument not in ["--variant=armfix","--variant=bagfix"]:
				printerr("SINGLE_WALK_FAIL unsupported variant; omit or use --variant=armfix or --variant=bagfix")
				quit(1)
				return
			variant = argument.trim_prefix("--variant=")
			if variant == "armfix":
				source_paths[3] = ARMFIX_SOURCE
				capture_dir = ARMFIX_OUT
			else:
				source_paths[3] = BAGFIX_SOURCE
				capture_dir = BAGFIX_OUT
				# The bag-only trial must also preserve its armfix input.
				protected_paths.append(ARMFIX_SOURCE)
			# Both explicit variants preserve the original phase3.
			protected_paths.append(SOURCES[3])
	check(int(verify)+int(capture)+int(movie) <= 1,"select at most one run mode")
	if verify or capture or movie:
		create_timer(40).timeout.connect(func() -> void: printerr("SINGLE_WALK_FAIL watchdog"); quit(1))
	for path: String in source_paths+protected_paths:
		check(FileAccess.file_exists(path),"input exists "+path)
		hashes[path] = FileAccess.get_sha256(path)
	if not failures.is_empty(): quit(1); return
	var originals: Array[Image] = []
	for path: String in source_paths:
		var original := Image.new()
		check(original.load(path) == OK,"read whole original "+path)
		if original.is_empty(): quit(1); return
		check(original.get_width() > 0 and original.get_height() > 0,"valid source dimensions")
		originals.append(original)
		print("SINGLE_WALK_SOURCE ",path," size=",original.get_size()," sha256=",hashes[path])
	check(originals.size() == FRAME_COUNT and FPS == 8.0,"4 original frames at 8 FPS")
	for original: Image in originals:
		check(original.get_size() == originals[0].get_size(),"equal full canvases required for shared mapping")
	check(Preview.frame_at(0) == 0 and Preview.frame_at(0.125) == 1 and Preview.frame_at(0.25) == 2 and Preview.frame_at(0.375) == 3 and Preview.frame_at(0.5) == 0,"frame timing and 0.5-second loop")
	check(Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),ProjectSettings.get_setting("display/window/size/viewport_height")) == Vector2i(640,360),"existing logical viewport")
	if not failures.is_empty(): _finish("VERIFY"); return
	if verify: _finish("VERIFY"); return
	if DisplayServer.get_name() == "headless":
		printerr("SINGLE_WALK_UNSUPPORTED: no real renderer in headless mode; no screenshots written")
		quit(2)
		return
	var card := Preview.new()
	for original: Image in originals: card.pictures.append(ImageTexture.create_from_image(original))
	card.canvas_size = Vector2(originals[0].get_size())
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.title = "单帧行走显示试验（%s；非原生生产精灵）" % variant
	print("SINGLE_WALK_VARIANT ",variant," output=",capture_dir)
	root.add_child(card)
	if movie:
		await create_timer(4.0).timeout
		check(card.elapsed >= 3.9,"four seconds of engine playback time")
		check(card.observed_frames.size() == FRAME_COUNT,"all four frame indices observed in real renderer run")
		print("SINGLE_WALK_MOVIE renderer=",DisplayServer.get_name()," elapsed=",card.elapsed,"; script does not save video itself (engine --write-movie is separate); no perceptual naturalness claim")
		_finish("MOVIE")
		return
	if not capture: return
	card.set_process(false)
	card.elapsed = 0.0
	card._process(0.125)
	check(Preview.frame_at(card.elapsed) == 1,"playback advances at 8 FPS")
	await _key(KEY_SPACE)
	check(card.paused,"space pauses")
	var frozen := card.elapsed
	card._process(0.25)
	check(card.elapsed == frozen,"paused time frozen")
	await _key(KEY_RIGHT)
	check(card.paused and Preview.frame_at(card.elapsed) == 2,"right steps")
	await _key(KEY_LEFT)
	check(card.paused and Preview.frame_at(card.elapsed) == 1,"left steps")
	card.elapsed = 0.0
	await _key(KEY_LEFT)
	check(Preview.frame_at(card.elapsed) == 3,"left wraps")
	await _key(KEY_RIGHT)
	check(Preview.frame_at(card.elapsed) == 0,"right wraps")
	await _key(KEY_SPACE)
	check(not card.paused,"space resumes")
	card.paused = true
	check(DirAccess.make_dir_recursive_absolute(capture_dir) == OK,"capture output directory")
	for light: bool in [true,false]:
		await _key(KEY_1 if light else KEY_2)
		check(card.light == light,"background keyboard switch")
		var suffix := "light" if light else "dark"
		card.contact_sheet = true
		await _capture(card,"contact_sheet_"+suffix)
		card.contact_sheet = false
		for index: int in FRAME_COUNT:
			card.elapsed = index/FPS
			check(Preview.frame_at(card.elapsed) == index,"capture frame "+str(index))
			await _capture(card,"frame_%d_%s" % [index,suffix])
	print("SINGLE_WALK_RENDERER ",DisplayServer.get_name())
	_finish("CAPTURE")
