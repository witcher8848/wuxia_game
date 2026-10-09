extends SceneTree
## Development-only native art comparison; no runtime atlas or save writes.
const Candidate = preload("res://assets/source/characters/hero_static_candidate_20261009.gd")
const Existing = preload("res://assets/source/characters/hero_pixel_source.gd")
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const OUT := "res://docs/art_reference/hero_static_20261009"
var checks := 0
var failures: Array[String] = []

class Comparison extends Node2D:
	var pictures: Array[Texture2D] = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,640,360),Color("#171820"))
		draw_string(FONT,Vector2(16,27),"主角静态候选 · 原生32×48 · 未替换动画",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#d8d0be"))
		var labels := ["旧版正面","候选正面","旧版左侧","候选左侧"]
		for index: int in pictures.size():
			var x := 80+index*160
			draw_string(FONT,Vector2(x-38,58),labels[index],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d19a5c"))
			draw_rect(Rect2(x-64,68,128,86),Color("#a9ada4"))
			draw_rect(Rect2(x-64,164,128,152),Color("#203934"))
			for scale_factor: int in [1,3]:
				var feet := Vector2(x,138 if scale_factor == 1 else 298)
				draw_set_transform(feet,0,Vector2(scale_factor,scale_factor))
				for row: Rect2 in Hero.SHADOW_ROWS: draw_rect(row,Color("#333b46"))
				draw_texture(pictures[index],Vector2(-16,-44))
				draw_set_transform(Vector2.ZERO)
		draw_string(FONT,Vector2(16,342),"上：1×亮底   下：3×暗底   同尺寸／同地面；外观待评审",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))

class StaticPose extends Node2D:
	var picture: Texture2D
	func _draw() -> void:
		for row: Rect2 in Hero.SHADOW_ROWS: draw_rect(row,Color("#333b46"))
		draw_texture(picture,Vector2(-16,-44))

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("HERO_STATIC_FAIL ",label)
func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+"/"+name+".png") == OK,"capture "+name)

func _run() -> void:
	create_timer(40).timeout.connect(func() -> void: printerr("HERO_STATIC_FAIL watchdog"); quit(1))
	check(DisplayServer.get_name() != "headless","real renderer required")
	if not failures.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(OUT)
	var atlas_before := FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.png")
	var metadata_before := FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.json")
	var textures: Array[Texture2D] = []
	for rows: Array in [Candidate.HEAD_FRONT,Candidate.HEAD_LEFT,Candidate.COAT_FRONT,Candidate.COAT_LEFT,Candidate.LEG,Candidate.SLEEVE,Candidate.POUCH]:
		for row: String in rows:
			for ink: String in row:
				check(ink == "." or Existing.PALETTE.has(ink),"source ink exists")
	for direction: String in ["down","left"]:
		var image: Image = Candidate.frame(direction)
		check(image.get_size() == Vector2i(32,48),direction+" exact native canvas")
		var allowed: Array[Color] = []
		for hex: String in Existing.PALETTE.values(): allowed.append(Color(hex))
		var valid_alpha := true
		var valid_color := true
		var bottom := -1
		for y: int in 48:
			for x: int in 32:
				var pixel := image.get_pixel(x,y)
				if pixel.a != 0 and pixel.a != 1: valid_alpha = false
				if pixel.a != 0:
					bottom = maxi(bottom,y)
					if not pixel in allowed: valid_color = false
		check(valid_alpha,direction+" binary transparency")
		check(valid_color,direction+" existing palette only")
		check(bottom == 43,direction+" fixed sole row43")
		check(image.get_data() != Existing.frame("walk",direction,0).get_data(),direction+" candidate not a copy of old pose")
		check(image.save_png(OUT+"/"+direction+"_32x48.png") == OK,direction+" saved native pose")
		textures.append(ImageTexture.create_from_image(Existing.frame("walk",direction,0)))
		textures.append(ImageTexture.create_from_image(image))
	var card := Comparison.new()
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.pictures = textures
	root.add_child(card)
	await _capture("comparison_1x_3x")
	card.queue_free()
	await process_frame
	var session := root.get_node("GameSession")
	session.start_new_game()
	root.get_node("App").reset_contexts()
	var region: Node = load("res://game/presentation/exploration/town_street.tscn").instantiate()
	root.add_child(region)
	await process_frame
	region.set_physics_process(false)
	region.player.set_physics_process(false)
	region.player.get_node("Visual").set_process(false)
	region.camera.set_physics_process(false)
	var snapshot: Dictionary = session.state.to_dict().duplicate(true)
	await _capture("town_old_front")
	var old_visual: Node2D = region.player.get_node("Visual")
	old_visual.hide()
	var pose := StaticPose.new()
	pose.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	region.player.add_child(pose)
	for direction: String in ["down","left"]:
		pose.picture = ImageTexture.create_from_image(Candidate.frame(direction))
		pose.queue_redraw()
		await _capture("town_candidate_"+direction)
	check(session.state.to_dict() == snapshot,"static preview changes no story state")
	check(FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.png") == atlas_before,"runtime atlas unchanged")
	check(FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.json") == metadata_before,"runtime metadata unchanged")
	region.queue_free()
	await process_frame
	print("HERO_STATIC_CANDIDATE: %d checks, %d failures (native poses and staged scene; not art approval)" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
