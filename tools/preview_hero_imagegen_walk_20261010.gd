extends SceneTree
## Isolated display experiment. Reads original four-column image unchanged.
## Interactive: ./tools/godot.sh --path . --script res://tools/preview_hero_imagegen_walk_20261010.gd
## Add -- --capture for real-renderer evidence or -- --verify-only for read-only checks.
## Add --variant=v2 after -- to use the known v2 source and separate v2 evidence directory.
const SOURCE := "res://docs/art_reference/protagonist_imagegen_walk_right_20261010.png"
const SOURCE_V2 := "res://docs/art_reference/protagonist_imagegen_walk_right_20261010_v2.png"
const OUT := "res://docs/art_reference/hero_imagegen_walk_20261010"
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const FRAME_COUNT := 4
const FPS := 8.0
const DISPLAY_BOX := Vector2(48,72)
const PROTECTED := [SOURCE,"res://assets/source/characters/hero_pixel_source.gd","res://assets/runtime/characters/chr_protagonist_atlas.png","res://assets/runtime/characters/chr_protagonist_atlas.json","res://game/presentation/exploration/player_controller.gd"]
var checks := 0
var failures: Array[String] = []
var hashes: Dictionary = {}
var source_path := SOURCE
var output_directory := OUT
var protected_paths: Array = PROTECTED.duplicate()

class WalkPreview extends Node2D:
	var picture: Texture2D
	var regions: Array[Rect2] = []
	var light := true
	var paused := false
	var contact_sheet := false
	var elapsed := 0.0
	static func frame_at(time: float) -> int:
		return posmod(int(floor(time*FPS)),FRAME_COUNT)

	func _process(delta: float) -> void:
		if not paused: elapsed += delta
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
		var box := DISPLAY_BOX*magnification
		var slot := Rect2(Vector2(center_x-box.x/2.0,baseline-box.y),box)
		var region: Rect2 = regions[index]
		var fit := minf(box.x/region.size.x,box.y/region.size.y)
		var display_size := region.size*fit
		var destination := Rect2(Vector2(center_x-display_size.x/2.0,baseline-display_size.y),display_size)
		draw_rect(slot,guide,false,1.0)
		draw_line(Vector2(center_x-box.x/2.0-12,baseline+1),Vector2(center_x+box.x/2.0+12,baseline+1),guide)
		draw_texture_rect_region(picture,destination,region)

	func _draw() -> void:
		var background := Color("#d8d0be") if light else Color("#203934")
		var text_ink := Color("#242833") if light else Color("#f1e6cf")
		var guide := Color("#747b78") if light else Color("#7fa38d")
		draw_rect(Rect2(0,0,640,360),background)
		draw_string(FONT,Vector2(12,24),"朝右行走 · 仅显示试验，非原生图集",HORIZONTAL_ALIGNMENT_LEFT,-1,18,text_ink)
		draw_string(FONT,Vector2(12,44),"48×72显示框 · 原图四分区 · 最近邻 · 4帧 / 8 FPS",HORIZONTAL_ALIGNMENT_LEFT,-1,13,text_ink)
		if contact_sheet:
			for index: int in FRAME_COUNT:
				var center_x := 88.0+index*155.0
				draw_string(FONT,Vector2(center_x-43,65),"帧 %d · 上1× 下2×" % index,HORIZONTAL_ALIGNMENT_LEFT,-1,12,text_ink)
				draw_pose(index,center_x,147,1,guide)
				draw_pose(index,center_x,310,2,guide)
		else:
			var index := frame_at(elapsed)
			draw_string(FONT,Vector2(98,75),"1×显示 / 帧 %d" % index,HORIZONTAL_ALIGNMENT_LEFT,-1,14,text_ink)
			draw_string(FONT,Vector2(346,75),"3×观察 / "+("暂停" if paused else "播放"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,text_ink)
			draw_pose(index,164,304,1,guide)
			draw_pose(index,420,304,3,guide)
		draw_string(FONT,Vector2(12,333),"Space 暂停 · ←→暂停逐帧 · 1亮 / 2暗 · Esc退出",HORIZONTAL_ALIGNMENT_LEFT,-1,13,text_ink)
		draw_string(FONT,Vector2(12,352),"原图未裁切或重采样；正式32×48角色、碰撞与数值未改变",HORIZONTAL_ALIGNMENT_LEFT,-1,12,text_ink)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("HERO_IMAGEGEN_WALK_FAIL ",label)

func _unchanged() -> void:
	for path: String in protected_paths:
		check(FileAccess.get_sha256(path) == hashes[path],"unchanged "+path)

func _report_boundary_ink(source: Image) -> void:
	# Diagnostic only: never shift windows or edit pixels to hide bad source layout.
	for divider: int in range(1,FRAME_COUNT):
		var boundary := int(floor(divider*source.get_width()/float(FRAME_COUNT)))
		var occupied := 0
		for x: int in range(maxi(0,boundary-2),mini(source.get_width(),boundary+3)):
			for y: int in source.get_height():
				if roundi(source.get_pixel(x,y).a*255.0) > 127: occupied += 1
		if occupied > 0:
			print("SOURCE_CONTENT_WARNING boundary_x=%d band=[%d,%d] alpha_gt_127=%d; possible cross-cell clipping; engine checks do not approve art" % [boundary,boundary-2,boundary+2,occupied])
		else:
			print("SOURCE_BOUNDARY_CLEAR boundary_x=%d band=[%d,%d] alpha_gt_127=0" % [boundary,boundary-2,boundary+2])

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

func _capture(card: WalkPreview, filename: String) -> void:
	card.queue_redraw()
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	check(screenshot != null and not screenshot.is_empty(),"rendered pixels "+filename)
	if screenshot == null or screenshot.is_empty(): return
	check(screenshot.get_size() == Vector2i(640,360),"logical capture size "+filename)
	check(screenshot.save_png(output_directory+"/"+filename+".png") == OK,"capture "+filename)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			if argument != "--variant=v2":
				printerr("HERO_IMAGEGEN_WALK_FAIL unknown variant; omit for v1 or use --variant=v2")
				quit(1)
				return
			source_path = SOURCE_V2
			output_directory = OUT+"/v2"
			protected_paths[0] = source_path
	print("HERO_IMAGEGEN_WALK_INPUT ",source_path,"; output=",output_directory)
	var capture := "--capture" in OS.get_cmdline_user_args()
	var verify_only := "--verify-only" in OS.get_cmdline_user_args()
	if capture or verify_only:
		create_timer(40).timeout.connect(func() -> void: printerr("HERO_IMAGEGEN_WALK_FAIL watchdog"); quit(1))
	for path: String in protected_paths:
		check(FileAccess.file_exists(path),"input exists "+path)
		hashes[path] = FileAccess.get_sha256(path)
	if not failures.is_empty(): quit(1); return
	var source := Image.new()
	check(source.load(source_path) == OK,"read untouched source PNG")
	if not failures.is_empty(): quit(1); return
	check(source.get_width() >= FRAME_COUNT and source.get_height() > 0,"valid source dimensions")
	check(FRAME_COUNT == 4 and FPS == 8.0,"4 frames at 8 FPS")
	check(WalkPreview.frame_at(0.0) == 0 and WalkPreview.frame_at(0.125) == 1 and WalkPreview.frame_at(0.375) == 3 and WalkPreview.frame_at(0.5) == 0,"exact progression and loop")
	check(Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),ProjectSettings.get_setting("display/window/size/viewport_height")) == Vector2i(640,360),"project logical viewport")
	var regions: Array[Rect2] = []
	for column: int in FRAME_COUNT:
		var left := int(floor(column*source.get_width()/float(FRAME_COUNT)))
		var right := int(floor((column+1)*source.get_width()/float(FRAME_COUNT)))
		var region := Rect2(left,0,right-left,source.get_height())
		regions.append(region)
		check(region.size.x > 0 and region.end.x <= source.get_width(),"region bounds "+str(column))
		if column > 0: check(regions[column-1].end.x == region.position.x,"adjacent source windows "+str(column))
		print("HERO_IMAGEGEN_WALK_REGION ",column," ",region)
	check(regions.size() == 4 and regions[3].end.x == source.get_width(),"four windows cover whole source")
	_report_boundary_ink(source)
	if verify_only:
		_unchanged()
		print("HERO_IMAGEGEN_WALK_VERIFY: %d checks, %d failures; no render or PNG writes; engine contract only, NOT art approval" % [checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	if DisplayServer.get_name() == "headless":
		printerr("HERO_IMAGEGEN_WALK_UNSUPPORTED: headless has no real renderer here; no screenshot written. Remove --headless and use -- --capture.")
		quit(2)
		return
	var card := WalkPreview.new()
	card.picture = ImageTexture.create_from_image(source)
	card.regions = regions
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.title = "朝右行走显示试验（非原生图集）"
	root.add_child(card)
	if not capture: return
	card.set_process(false)
	card.elapsed = 0.0
	card._process(0.125)
	check(WalkPreview.frame_at(card.elapsed) == 1,"playback advances at 8 FPS")
	await _key(KEY_SPACE)
	check(card.paused,"space pauses")
	var frozen := card.elapsed
	card._process(0.25)
	check(card.elapsed == frozen,"pause freezes playback")
	await _key(KEY_RIGHT)
	check(card.paused and WalkPreview.frame_at(card.elapsed) == 2,"right steps paused")
	await _key(KEY_LEFT)
	check(card.paused and WalkPreview.frame_at(card.elapsed) == 1,"left steps paused")
	await _key(KEY_SPACE)
	check(not card.paused,"space resumes")
	card.paused = true
	check(DirAccess.make_dir_recursive_absolute(output_directory) == OK,"capture directory")
	for light: bool in [true,false]:
		await _key(KEY_1 if light else KEY_2)
		check(card.light == light,"background keyboard "+str(light))
		var suffix := "light" if light else "dark"
		card.contact_sheet = true
		await _capture(card,"contact_sheet_"+suffix)
		card.contact_sheet = false
		for index: int in FRAME_COUNT:
			card.elapsed = index/FPS
			check(WalkPreview.frame_at(card.elapsed) == index,"capture frame index "+str(index))
			await _capture(card,"frame_%d_%s" % [index,suffix])
	_unchanged()
	print("HERO_IMAGEGEN_WALK_CAPTURE: %d checks, %d failures; renderer=%s; engine contract only, NOT art approval" % [checks,failures.size(),DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
