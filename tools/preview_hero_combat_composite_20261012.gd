extends SceneTree
## Read-only originals plus real-engine screenshots, never edited sprite PNGs.
## -- --verify-only; -- --capture; default interactive 1/light, 2/dark, Esc.
const SOURCES := [
	"res://docs/art_reference/protagonist_imagegen_combat_down_sheet_20261011.png",
	"res://docs/art_reference/protagonist_imagegen_combat_left_sheet_20261011.png",
	"res://docs/art_reference/protagonist_imagegen_combat_right_sheet_20261011_v3.png",
	"res://docs/art_reference/protagonist_imagegen_combat_up_sheet_20261011.png",
]
const LABELS := ["正面 / down","左向 / left","右向 / right","背面 / up"]
const PROTECTED := [
	"res://assets/source/characters/hero_pixel_source.gd",
	"res://assets/runtime/characters/chr_protagonist_atlas.png",
	"res://assets/runtime/characters/chr_protagonist_atlas.json",
	"res://docs/art_reference/protagonist_imagegen_combat_right_edge_trial_20261011.png",
]
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const OUT := "res://docs/art_reference/hero_combat_composite_20261012"
const LIGHT := Color("#d8d0be")
const DARK := Color("#203934")
const DRAW_SIZE := Vector2(128,192)
var checks := 0
var failures: Array[String] = []
var hashes: Dictionary = {}
var originals: Array[Image] = []

class Card extends Node2D:
	var pictures: Array[Texture2D] = []
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
		var bg := LIGHT if light else DARK
		var ink := Color("#242833") if light else Color("#f1e6cf")
		draw_rect(Rect2(0,0,640,360),bg)
		draw_string(FONT,Vector2(12,24),"四向战斗候选 · 原图透明合成核查",HORIZONTAL_ALIGNMENT_LEFT,-1,18,ink)
		draw_string(FONT,Vector2(12,44),"整图最近邻显示 / 未取帧接入 / 不是完整57槽或正式像素规格",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
		for i: int in pictures.size():
			draw_string(FONT,Vector2(16+i*160,70),LABELS[i],HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
			draw_texture_rect(pictures[i],Rect2(Vector2(16+i*160,80),DRAW_SIZE),false)
		draw_string(FONT,Vector2(12,299),"等格可能裁掉鞋或剑；本页保留完整原图，不能据此判独立取格通过。",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
		draw_string(FONT,Vector2(12,320),"alpha=0隐藏RGB不应产生光晕；弱半透明边缘另行评估。",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
		draw_string(FONT,Vector2(12,346),"1亮底 / 2暗底 / Esc退出 · 不改原PNG、正式角色、碰撞或存档",HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("COMBAT_COMPOSITE_FAIL ",label)
func unchanged() -> void:
	for path: String in hashes:
		check(FileAccess.get_sha256(path) == hashes[path],"unchanged "+path)
func finish(label: String) -> void:
	unchanged()
	print("COMBAT_COMPOSITE_%s: %d checks, %d failures; alpha/display evidence only, NOT art, frame-sheet or integration approval" % [label,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func capture(card: Card, light: bool) -> PackedByteArray:
	card.light = light
	card.queue_redraw()
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	check(shot != null and not shot.is_empty(),"real rendered image")
	if shot == null or shot.is_empty(): return PackedByteArray()
	check(shot.get_size() == Vector2i(640,360),"640x360 captured viewport")
	var bg := LIGHT if light else DARK
	for i: int in originals.size():
		var transparent_samples := 0
		var opaque_samples := 0
		var transparent_mismatches := 0
		var visible_samples := 0
		for y: int in int(DRAW_SIZE.y):
			for x: int in int(DRAW_SIZE.x):
				# Nearest sampling at each destination pixel center, 1:8 whole-source mapping.
				var source := originals[i].get_pixel(x*8+4,y*8+4)
				var actual := shot.get_pixel(16+i*160+x,80+y)
				var difference := maxf(absf(actual.r-bg.r),maxf(absf(actual.g-bg.g),absf(actual.b-bg.b)))
				if source.a == 0.0:
					transparent_samples += 1
					if difference > 2.0/255.0: transparent_mismatches += 1
				elif source.a > 0.95:
					opaque_samples += 1
					if difference > 2.0/255.0: visible_samples += 1
		check(transparent_samples > 1000,"many actual zero-alpha sample positions "+LABELS[i])
		check(transparent_mismatches == 0,"zero-alpha hidden RGB leaves background unchanged "+LABELS[i])
		check(opaque_samples > 1000 and visible_samples > 900,"real figure pixels remain visible "+LABELS[i])
		print("COMBAT_COMPOSITE_ALPHA ",LABELS[i]," light=",light," alpha0_samples=",transparent_samples," mismatches=",transparent_mismatches," alpha>0.95=",opaque_samples," visible=",visible_samples)
	check(shot.save_png(OUT+("/light_640x360.png" if light else "/dark_640x360.png")) == OK,"save actual screenshot")
	return shot.get_data()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var verify := "--verify-only" in args
	var recording := "--capture" in args
	check(not (verify and recording),"at most one run mode")
	if verify or recording:
		create_timer(35).timeout.connect(func() -> void: printerr("COMBAT_COMPOSITE_FAIL watchdog"); quit(1))
	for path: String in SOURCES+PROTECTED:
		check(FileAccess.file_exists(path),"input exists "+path)
		hashes[path] = FileAccess.get_sha256(path)
	if not failures.is_empty(): finish("VERIFY"); return
	for path: String in SOURCES:
		var original := Image.new()
		check(original.load(path) == OK,"decode whole original "+path)
		check(original.get_size() == Vector2i(1024,1536) and original.get_format() == Image.FORMAT_RGBA8,"unmodified source dimensions/format")
		originals.append(original)
	check(Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),ProjectSettings.get_setting("display/window/size/viewport_height")) == Vector2i(640,360),"existing viewport")
	if not failures.is_empty() or verify: finish("VERIFY"); return
	if DisplayServer.get_name() == "headless":
		printerr("COMBAT_COMPOSITE_UNSUPPORTED headless has no real capture")
		quit(2)
		return
	var card := Card.new()
	for original: Image in originals:
		card.pictures.append(ImageTexture.create_from_image(original))
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.title = "四向战斗原图透明合成（非接入验收）"
	root.add_child(card)
	if not recording: return
	check(DirAccess.make_dir_recursive_absolute(OUT) == OK,"capture directory")
	var light_pixels := await capture(card,true)
	var dark_pixels := await capture(card,false)
	check(not light_pixels.is_empty() and light_pixels != dark_pixels,"different actual backgrounds")
	print("COMBAT_COMPOSITE_RENDERER ",DisplayServer.get_name())
	finish("CAPTURE")

