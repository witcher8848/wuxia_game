extends SceneTree
## Face-only art review. Original static candidate and runtime files remain intact.
const Candidate = preload("res://assets/source/characters/hero_face_candidate_20261009.gd")
const Base = preload("res://assets/source/characters/hero_static_candidate_20261009.gd")
const Ink = preload("res://assets/source/characters/hero_pixel_source.gd")
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const OUT := "res://docs/art_reference/hero_face_review_20261009"
var checks := 0
var failures: Array[String] = []

class Comparison extends Node2D:
	var pictures: Array[Texture2D] = []
	var iteration := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,640,360),Color("#171820"))
		draw_string(FONT,Vector2(16,27),"主角五官专项 · 同身体／同头发 · 未替换动画",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#d8d0be"))
		var labels := ["A 正面／单点眼","B 正面／眼角","A 左侧／单点眼","B 左侧／眼角"] if iteration else ["原候选正面","五官 B 正面","原候选左侧","五官 B 左侧"]
		for index: int in pictures.size():
			var x := 80+index*160
			draw_string(FONT,Vector2(x-48,58),labels[index],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d19a5c"))
			draw_rect(Rect2(x-64,68,128,86),Color("#a9ada4"))
			draw_rect(Rect2(x-64,164,128,152),Color("#203934"))
			for scale_factor: int in [1,3]:
				var feet := Vector2(x,138 if scale_factor == 1 else 298)
				draw_set_transform(feet,0,Vector2(scale_factor,scale_factor))
				for row: Rect2 in Hero.SHADOW_ROWS: draw_rect(row,Color("#333b46"))
				draw_texture(pictures[index],Vector2(-16,-44))
				draw_set_transform(Vector2.ZERO)
		draw_string(FONT,Vector2(16,342),"上：1×亮底   下：3×暗底   只改五官；审美效果待用户确认",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))

class HeadComparison extends Node2D:
	var pictures: Array[Texture2D] = []
	var iteration := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,640,360),Color("#171820"))
		draw_string(FONT,Vector2(16,27),"五官像素结构诊断 · 8×最近邻（非游戏显示尺寸）",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#d8d0be"))
		var labels := ["A 正面／单点眼","B 正面／眼角","A 左侧／单点眼","B 左侧／眼角"] if iteration else ["原候选正面","五官 B 正面","原候选左侧","五官 B 左侧"]
		for index: int in pictures.size():
			var x := 80+index*160
			draw_string(FONT,Vector2(x-48,67),labels[index],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d19a5c"))
			draw_rect(Rect2(x-60,83,120,178),Color("#203934"))
			draw_set_transform(Vector2(x-48,97),0,Vector2(8,8))
			draw_texture(pictures[index],Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)
		draw_string(FONT,Vector2(16,293),"正面 B：低对比外眼角／深内眼，鼻部暗点删除，下颌减碎影。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))
		draw_string(FONT,Vector2(16,320),"侧面：眼睛与鼻尖错层，鼻尖靠轮廓表达，减少内侧碎点。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))

class StaticPose extends Node2D:
	var picture: Texture2D
	func _draw() -> void:
		for row: Rect2 in Hero.SHADOW_ROWS: draw_rect(row,Color("#333b46"))
		draw_texture(picture,Vector2(-16,-44))

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("HERO_FACE_FAIL ",label)
func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+"/"+name+".png") == OK,"capture "+name)

func _run() -> void:
	create_timer(40).timeout.connect(func() -> void: printerr("HERO_FACE_FAIL watchdog"); quit(1))
	check(DisplayServer.get_name() != "headless","real renderer required")
	if not failures.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(OUT)
	var atlas_before := FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.png")
	var metadata_before := FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.json")
	var base_before := FileAccess.get_sha256("res://assets/source/characters/hero_static_candidate_20261009.gd")
	var textures: Array[Texture2D] = []
	var heads: Array[Texture2D] = []
	var iteration_textures: Array[Texture2D] = []
	var iteration_heads: Array[Texture2D] = []
	for rows: Array in [Candidate.FACE_FRONT_A,Candidate.FACE_LEFT_A,Candidate.FACE_FRONT_B,Candidate.FACE_LEFT_B]:
		check(rows.size() == Candidate.FACE_RECT.size.y,"face template height")
		for row: String in rows:
			check(row.length() == Candidate.FACE_RECT.size.x,"face template width")
			for ink: String in row:
				check(ink == "." or Ink.PALETTE.has(ink),"source ink exists")
	for direction: String in ["down","left"]:
		var original: Image = Base.frame(direction)
		var image: Image = Candidate.frame(direction)
		check(image.get_size() == Vector2i(32,48),direction+" exact native canvas")
		var allowed: Array[Color] = []
		for hex: String in Ink.PALETTE.values(): allowed.append(Color(hex))
		var valid_alpha := true
		var valid_color := true
		var outside_unchanged := true
		var hair_unchanged := true
		var bottom := -1
		var changed := 0
		for y: int in 48:
			for x: int in 32:
				var pixel := image.get_pixel(x,y)
				var original_pixel := original.get_pixel(x,y)
				if pixel != original_pixel:
					changed += 1
					if not Candidate.FACE_RECT.has_point(Vector2i(x,y)): outside_unchanged = false
				# Original dark hair clusters are immutable; gray eye pixels are not hair.
				if original_pixel == Color(Ink.PALETTE["d"]) and pixel != original_pixel: hair_unchanged = false
				if pixel.a != 0 and pixel.a != 1: valid_alpha = false
				if pixel.a != 0:
					bottom = maxi(bottom,y)
					if not pixel in allowed: valid_color = false
		check(valid_alpha,direction+" binary transparency")
		check(valid_color,direction+" existing palette only")
		check(outside_unchanged,direction+" every pixel outside face unchanged")
		check(hair_unchanged,direction+" existing dark hair clusters unchanged")
		check(bottom == 43,direction+" fixed sole row43")
		check(changed > 0,direction+" face changed")
		print("HERO_FACE_DIFF ",direction,": ",changed," pixels; face region only")
		check(image.save_png(OUT+"/"+direction+"_32x48.png") == OK,direction+" saved native pose")
		check(Candidate.frame(direction,"a").save_png(OUT+"/"+direction+"_a_32x48.png") == OK,direction+" preserved first iteration")
		for pose_image: Image in [original,image]:
			textures.append(ImageTexture.create_from_image(pose_image))
			heads.append(ImageTexture.create_from_image(pose_image.get_region(Rect2i(10,4,12,16))))
		for pose_image: Image in [Candidate.frame(direction,"a"),image]:
			iteration_textures.append(ImageTexture.create_from_image(pose_image))
			iteration_heads.append(ImageTexture.create_from_image(pose_image.get_region(Rect2i(10,4,12,16))))
	var card := Comparison.new()
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.pictures = textures
	root.add_child(card)
	await _capture("comparison_1x_3x")
	card.queue_free()
	await process_frame
	var iteration_card := Comparison.new()
	iteration_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	iteration_card.pictures = iteration_textures
	iteration_card.iteration = true
	root.add_child(iteration_card)
	await _capture("iteration_a_b_1x_3x")
	iteration_card.queue_free()
	await process_frame
	var head_card := HeadComparison.new()
	head_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head_card.pictures = heads
	root.add_child(head_card)
	await _capture("face_structure_8x")
	head_card.queue_free()
	await process_frame
	var iteration_head_card := HeadComparison.new()
	iteration_head_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	iteration_head_card.pictures = iteration_heads
	iteration_head_card.iteration = true
	root.add_child(iteration_head_card)
	await _capture("iteration_a_b_8x")
	iteration_head_card.queue_free()
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
	region.player.get_node("Visual").hide()
	var snapshot: Dictionary = session.state.to_dict().duplicate(true)
	var pose := StaticPose.new()
	pose.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	region.player.add_child(pose)
	for direction: String in ["down","left"]:
		for variant: String in ["before","after"]:
			pose.picture = ImageTexture.create_from_image(Base.frame(direction) if variant == "before" else Candidate.frame(direction))
			pose.queue_redraw()
			await _capture("town_"+variant+"_"+direction)
	check(session.state.to_dict() == snapshot,"static preview changes no story state")
	check(FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.png") == atlas_before,"runtime atlas unchanged")
	check(FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.json") == metadata_before,"runtime metadata unchanged")
	check(FileAccess.get_sha256("res://assets/source/characters/hero_static_candidate_20261009.gd") == base_before,"original static candidate preserved")
	region.queue_free()
	await process_frame
	print("HERO_FACE_CANDIDATE: %d checks, %d failures (native face masks and staged scene; not art approval)" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
