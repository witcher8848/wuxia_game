extends SceneTree
## Display-only experiment: reads the original PNG; never resizes/crops/saves it.
## Interactive: ./tools/godot.sh --path . --script res://tools/preview_hero_imagegen_size_20261010.gd
## Capture: append -- --capture (requires a real renderer; headless exits 2).
## Read-only headless verification: append -- --verify-only.
## Side-occlusion candidate: append -- --variant=sidefix; default v2 stays unchanged.
const SOURCE := "res://docs/art_reference/protagonist_imagegen_turnaround_20261010_v2.png"
const OUT := "res://docs/art_reference/hero_imagegen_size_20261010"
const SIDEFIX_SOURCE := "res://docs/art_reference/protagonist_imagegen_turnaround_20261011_v3.png"
const SIDEFIX_OUT := "res://docs/art_reference/hero_imagegen_size_20261011_sidefix"
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const BOXES := [Vector2(32,48),Vector2(48,72),Vector2(64,96)]
const BASELINES := [123.0,213.0,325.0]
const LABELS := ["正面 / down","左侧 / left","背面 / up","右侧 / right"]
const PROTECTED := [SOURCE,SIDEFIX_SOURCE,"res://assets/source/characters/hero_pixel_source.gd","res://assets/runtime/characters/chr_protagonist_atlas.png","res://assets/runtime/characters/chr_protagonist_atlas.json"]
var checks := 0
var failures: Array[String] = []
var hashes: Dictionary = {}
var source_path := SOURCE
var output_path := OUT

class SizePreview extends Node2D:
	var picture: Texture2D
	var regions: Array[Rect2] = []
	var light := true
	func _unhandled_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo: return
		match event.physical_keycode:
			KEY_1: light = true
			KEY_2: light = false
			KEY_ESCAPE: get_tree().quit()
			_: return
		get_viewport().set_input_as_handled()
		queue_redraw()

	func _draw() -> void:
		var background := Color("#d8d0be") if light else Color("#203934")
		var text_ink := Color("#242833") if light else Color("#f1e6cf")
		var guide := Color("#747b78") if light else Color("#7fa38d")
		draw_rect(Rect2(0,0,640,360),background)
		draw_string(FONT,Vector2(12,24),"显示缩放试验，非生产精灵",HORIZONTAL_ALIGNMENT_LEFT,-1,18,text_ink)
		draw_string(FONT,Vector2(12,43),"640×360逻辑视口 · 原图分区等比显示 · 最近邻",HORIZONTAL_ALIGNMENT_LEFT,-1,13,text_ink)
		for column: int in regions.size():
			var center_x := 155.0+column*135.0
			draw_string(FONT,Vector2(center_x-40,64),LABELS[column],HORIZONTAL_ALIGNMENT_LEFT,-1,12,text_ink)
			for row: int in BOXES.size():
				var box: Vector2 = BOXES[row]
				var slot := Rect2(Vector2(center_x-box.x/2.0,BASELINES[row]-box.y),box)
				var region: Rect2 = regions[column]
				var fit := minf(box.x/region.size.x,box.y/region.size.y)
				var display_size := region.size*fit
				var destination := Rect2(Vector2(center_x-display_size.x/2.0,BASELINES[row]-display_size.y),display_size)
				draw_rect(slot,guide,false,1.0)
				draw_line(Vector2(center_x-40,BASELINES[row]+1),Vector2(center_x+40,BASELINES[row]+1),guide)
				draw_texture_rect_region(picture,destination,region)
		for row: int in BOXES.size():
			draw_string(FONT,Vector2(12,BASELINES[row]-BOXES[row].y/2.0),"%d×%d框" % [BOXES[row].x,BOXES[row].y],HORIZONTAL_ALIGNMENT_LEFT,-1,14,text_ink)
		draw_string(FONT,Vector2(12,348),"1 亮底 / 2 暗底 · Esc 退出 · 仅显示缩放，不修改32×48生产规格",HORIZONTAL_ALIGNMENT_LEFT,-1,13,text_ink)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("HERO_IMAGEGEN_SIZE_FAIL ",label)

func _unchanged() -> void:
	for path: String in PROTECTED:
		check(FileAccess.get_sha256(path) == hashes[path],"unchanged "+path)

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

func _capture(card: SizePreview, light: bool, filename: String) -> PackedByteArray:
	await _key(KEY_1 if light else KEY_2)
	check(card.light == light,"keyboard background "+filename)
	card.queue_redraw()
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	check(screenshot != null and not screenshot.is_empty(),"real rendered pixels "+filename)
	if screenshot == null or screenshot.is_empty(): return PackedByteArray()
	check(screenshot.get_size() == Vector2i(640,360),"logical capture size "+filename)
	check(screenshot.save_png(output_path+"/"+filename+".png") == OK,"capture "+filename)
	return screenshot.get_data()

func _run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	var verify_only := "--verify-only" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--variant="): continue
		if argument == "--variant=sidefix":
			source_path = SIDEFIX_SOURCE
			output_path = SIDEFIX_OUT
		elif argument != "--variant=default":
			printerr("HERO_IMAGEGEN_SIZE_FAIL unknown variant ",argument)
			quit(2)
			return
	if capture or verify_only:
		create_timer(30).timeout.connect(func() -> void: printerr("HERO_IMAGEGEN_SIZE_FAIL watchdog"); quit(1))
	for path: String in PROTECTED:
		check(FileAccess.file_exists(path),"input exists "+path)
		hashes[path] = FileAccess.get_sha256(path)
	if not failures.is_empty(): quit(1); return
	var source := Image.new()
	check(source.load(source_path) == OK,"load untouched original PNG")
	if not failures.is_empty(): quit(1); return
	check(source.get_width() >= 4 and source.get_height() > 0,"valid source dimensions")
	check(Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),ProjectSettings.get_setting("display/window/size/viewport_height")) == Vector2i(640,360),"project logical viewport")
	var regions: Array[Rect2] = []
	# Four full-height quarter windows, in source order down/left/up/right.
	# No cropped Image or resized asset is created; all original margins remain.
	for column: int in 4:
		var left := int(floor(column*source.get_width()/4.0))
		var right := int(floor((column+1)*source.get_width()/4.0))
		var region := Rect2(left,0,right-left,source.get_height())
		regions.append(region)
		check(region.size.x > 0 and region.end.x <= source.get_width(),"region "+str(column))
		print("HERO_IMAGEGEN_SIZE_REGION ",LABELS[column]," ",region)
	if verify_only:
		print("HERO_IMAGEGEN_SIZE_SOURCE ",source_path)
		_unchanged()
		print("HERO_IMAGEGEN_SIZE_VERIFY: %d checks, %d failures; no render or PNG writes" % [checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	if DisplayServer.get_name() == "headless":
		printerr("HERO_IMAGEGEN_SIZE_UNSUPPORTED: headless has no real renderer here; no screenshot written. Remove --headless and use -- --capture.")
		quit(2)
		return
	var card := SizePreview.new()
	card.picture = ImageTexture.create_from_image(source)
	card.regions = regions
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.title = "主角显示缩放试验（非生产精灵）"
	root.add_child(card)
	if not capture: return
	check(DirAccess.make_dir_recursive_absolute(output_path) == OK,"capture directory")
	var light_pixels := await _capture(card,true,"size_light_640x360")
	var dark_pixels := await _capture(card,false,"size_dark_640x360")
	check(not light_pixels.is_empty() and light_pixels != dark_pixels,"background captures differ")
	_unchanged()
	print("HERO_IMAGEGEN_SIZE_CAPTURE: %d checks, %d failures; real renderer=%s; display experiment only" % [checks,failures.size(),DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
