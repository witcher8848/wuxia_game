extends SceneTree
## A versus simplified static candidate. No save or runtime resource mutations.
const Candidate = preload("res://assets/source/characters/hero_simple_candidate_20261009.gd")
const Before = preload("res://assets/source/characters/hero_face_candidate_20261009.gd")
const Ink = preload("res://assets/source/characters/hero_pixel_source.gd")
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const OUT := "res://docs/art_reference/hero_simple_review_20261009"
var checks := 0
var failures: Array[String] = []

class Comparison extends Node2D:
	var pictures: Array[Texture2D] = []
	var shape_iteration := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,640,360),Color("#171820"))
		draw_string(FONT,Vector2(16,27),"主角简化候选 · 短颈／大色块／去褐边 · 未替换动画",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#d8d0be"))
		var labels := ["首轮正面","剪影收整正面","首轮左侧","剪影收整左侧"] if shape_iteration else ["已选 A 正面","简化版正面","已选 A 左侧","简化版左侧"]
		for index: int in pictures.size():
			var x := 80+index*160
			draw_string(FONT,Vector2(x-42,58),labels[index],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d19a5c"))
			draw_rect(Rect2(x-64,68,128,86),Color("#a9ada4"))
			draw_rect(Rect2(x-64,164,128,152),Color("#203934"))
			for scale_factor: int in [1,3]:
				var feet := Vector2(x,138 if scale_factor == 1 else 298)
				draw_set_transform(feet,0,Vector2(scale_factor,scale_factor))
				for row: Rect2 in Hero.SHADOW_ROWS: draw_rect(row,Color("#333b46"))
				draw_texture(pictures[index],Vector2(-16,-44))
				draw_set_transform(Vector2.ZERO)
		draw_string(FONT,Vector2(16,342),"上：1×亮底   下：3×暗底   相同32×48画布／脚底位置",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))

class DetailComparison extends Node2D:
	var pictures: Array[Texture2D] = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,640,360),Color("#171820"))
		draw_string(FONT,Vector2(16,27),"头颈与领口 · 8×最近邻诊断（非游戏显示尺寸）",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#d8d0be"))
		var labels := ["已选 A 正面","简化版正面","已选 A 左侧","简化版左侧"]
		for index: int in pictures.size():
			var x := 80+index*160
			draw_string(FONT,Vector2(x-42,61),labels[index],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d19a5c"))
			draw_rect(Rect2(x-60,77,120,182),Color("#203934"))
			draw_set_transform(Vector2(x-48,87),0,Vector2(8,8))
			draw_texture(pictures[index],Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)
		draw_string(FONT,Vector2(16,291),"简化：领口提高两行，裸颈三行→一行；保留 A 的单点眼。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))
		draw_string(FONT,Vector2(16,320),"肤色不用褐边；衣领／头发／裤腿／文袋减少色阶和碎点。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#d8d0be"))

class StaticPose extends Node2D:
	var picture: Texture2D
	func _draw() -> void:
		for row: Rect2 in Hero.SHADOW_ROWS: draw_rect(row,Color("#333b46"))
		draw_texture(picture,Vector2(-16,-44))

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("HERO_SIMPLE_FAIL ",label)
func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+"/"+name+".png") == OK,"capture "+name)

func _neck_rows(image: Image) -> int:
	var exposed := 0
	for y: int in range(Candidate.NECK_RECT.position.y,Candidate.NECK_RECT.end.y):
		var skin_on_row := false
		for x: int in range(Candidate.NECK_RECT.position.x,Candidate.NECK_RECT.end.x):
			if image.get_pixel(x,y) in [Color(Ink.PALETTE["h"]),Color(Ink.PALETTE["s"])]: skin_on_row = true
		if skin_on_row: exposed += 1
	return exposed

func _collar_top(image: Image) -> int:
	for y: int in range(13,20):
		for x: int in range(11,21):
			if image.get_pixel(x,y) == Color(Ink.PALETTE["w"]): return y
	return -1

func _brown_boundary_pixels(image: Image) -> int:
	var brown := [Color(Ink.PALETTE["s"]),Color(Ink.PALETTE["t"]),Color(Ink.PALETTE["a"])]
	var boundary_count := 0
	for y: int in 48:
		for x: int in 32:
			if not image.get_pixel(x,y) in brown: continue
			for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var neighbor := Vector2i(x,y)+offset
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= 32 or neighbor.y >= 48 or image.get_pixelv(neighbor).a == 0:
					boundary_count += 1
					break
	return boundary_count

func _run() -> void:
	create_timer(40).timeout.connect(func() -> void: printerr("HERO_SIMPLE_FAIL watchdog"); quit(1))
	check(DisplayServer.get_name() != "headless","real renderer required")
	if not failures.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(OUT)
	var atlas_before := FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.png")
	var metadata_before := FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.json")
	var base_before := FileAccess.get_sha256("res://assets/source/characters/hero_face_candidate_20261009.gd")
	var textures: Array[Texture2D] = []
	var details: Array[Texture2D] = []
	var first_textures: Array[Texture2D] = []
	var first_details: Array[Texture2D] = []
	var shape_textures: Array[Texture2D] = []
	for rows: Array in [Candidate.HEAD_FRONT,Candidate.HEAD_LEFT,Candidate.COAT_FRONT,Candidate.COAT_LEFT,Candidate.LEG,Candidate.SLEEVE,Candidate.SLEEVE_LEFT,Candidate.POUCH,Candidate.COAT_FRONT_FIRST,Candidate.COAT_LEFT_FIRST,Candidate.SLEEVE_FIRST]:
		for row: String in rows:
			for ink: String in row: check(ink == "." or Ink.PALETTE.has(ink),"source ink exists")
	for direction: String in ["down","left"]:
		var original: Image = Before.frame(direction,"a")
		var image: Image = Candidate.frame(direction)
		var first: Image = Candidate.frame(direction,"first")
		check(first.get_data() != image.get_data(),direction+" final silhouette differs from first iteration")
		check(first.get_region(Rect2i(0,0,32,16)).get_data() == image.get_region(Rect2i(0,0,32,16)).get_data(),direction+" refined silhouette preserves approved head and short neck")
		check(image.get_size() == Vector2i(32,48),direction+" exact native canvas")
		var allowed: Array[Color] = []
		for hex: String in Ink.PALETTE.values(): allowed.append(Color(hex))
		var used: Array[Color] = []
		var valid_alpha := true
		var valid_color := true
		var bottom := -1
		var top := 48
		for y: int in 48:
			for x: int in 32:
				var pixel := image.get_pixel(x,y)
				if pixel.a != 0 and pixel.a != 1: valid_alpha = false
				if pixel.a != 0:
					bottom = maxi(bottom,y)
					top = mini(top,y)
					if not pixel in used: used.append(pixel)
					if not pixel in allowed: valid_color = false
		check(valid_alpha,direction+" binary transparency")
		check(valid_color,direction+" existing palette only")
		check(used.size() <= 6,direction+" at most six used colors")
		check(bottom == 43,direction+" fixed sole row43")
		check(top == 4,direction+" same top row; not shorter through canvas crop")
		check(_neck_rows(original) == 3,direction+" before actually exposes three neck rows")
		check(_neck_rows(image) == 1,direction+" after actually exposes only one neck row")
		check(_collar_top(original) == 16,direction+" before collar starts y16")
		check(_collar_top(image) == 14,direction+" after collar actually raised to y14")
		check(_brown_boundary_pixels(original) > 0,direction+" before has brown silhouette pixels")
		check(_brown_boundary_pixels(image) == 0,direction+" no brown/gold silhouette pixels")
		if direction == "down":
			check(image.get_pixel(14,11) == Color(Ink.PALETTE["d"]) and image.get_pixel(17,11) == Color(Ink.PALETTE["d"]),"A front single-pixel eye positions preserved")
		else:
			check(image.get_pixel(12,10) == Color(Ink.PALETTE["d"]),"A left single-pixel eye position preserved")
		print("HERO_SIMPLE_DIFF ",direction,": neck ",_neck_rows(original),"->",_neck_rows(image)," rows, collar y",_collar_top(original),"->",_collar_top(image),", brown boundary ",_brown_boundary_pixels(original),"->",_brown_boundary_pixels(image),", colors ",used.size())
		check(image.save_png(OUT+"/"+direction+"_32x48.png") == OK,direction+" saved native pose")
		check(first.save_png(OUT+"/"+direction+"_first_32x48.png") == OK,direction+" preserved first simplified silhouette")
		for pose_image: Image in [original,image]:
			textures.append(ImageTexture.create_from_image(pose_image))
			details.append(ImageTexture.create_from_image(pose_image.get_region(Rect2i(10,4,12,20))))
		for pose_image: Image in [original,first]:
			first_textures.append(ImageTexture.create_from_image(pose_image))
			first_details.append(ImageTexture.create_from_image(pose_image.get_region(Rect2i(10,4,12,20))))
		for pose_image: Image in [first,image]: shape_textures.append(ImageTexture.create_from_image(pose_image))
	var card := Comparison.new()
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.pictures = textures
	root.add_child(card)
	await _capture("comparison_1x_3x")
	card.queue_free()
	await process_frame
	var first_card := Comparison.new()
	first_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	first_card.pictures = first_textures
	root.add_child(first_card)
	await _capture("comparison_first_1x_3x")
	first_card.queue_free()
	await process_frame
	var shape_card := Comparison.new()
	shape_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shape_card.pictures = shape_textures
	shape_card.shape_iteration = true
	root.add_child(shape_card)
	await _capture("shape_iteration_1x_3x")
	shape_card.queue_free()
	await process_frame
	var detail_card := DetailComparison.new()
	detail_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	detail_card.pictures = details
	root.add_child(detail_card)
	await _capture("head_neck_structure_8x")
	detail_card.queue_free()
	await process_frame
	var first_detail_card := DetailComparison.new()
	first_detail_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	first_detail_card.pictures = first_details
	root.add_child(first_detail_card)
	await _capture("head_neck_first_8x")
	first_detail_card.queue_free()
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
			pose.picture = ImageTexture.create_from_image(Before.frame(direction,"a") if variant == "before" else Candidate.frame(direction))
			pose.queue_redraw()
			await _capture("town_"+variant+"_"+direction)
	check(session.state.to_dict() == snapshot,"static preview changes no story state")
	check(FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.png") == atlas_before,"runtime atlas unchanged")
	check(FileAccess.get_sha256("res://assets/runtime/characters/chr_protagonist_atlas.json") == metadata_before,"runtime metadata unchanged")
	check(FileAccess.get_sha256("res://assets/source/characters/hero_face_candidate_20261009.gd") == base_before,"original A/B candidate preserved")
	region.queue_free()
	await process_frame
	print("HERO_SIMPLE_CANDIDATE: %d checks, %d failures (native proportions and staged scene; not art approval)" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
