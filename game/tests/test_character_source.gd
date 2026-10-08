extends SceneTree
const Source = preload("res://assets/source/characters/hero_pixel_source.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("CHARACTER_SOURCE_FAIL ",label)
func _initialize() -> void:
	var atlas := Image.new()
	check(atlas.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/runtime/characters/chr_protagonist_atlas.png")) == OK,"read exported source PNG")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/runtime/characters/chr_protagonist_atlas.json"))
	check(atlas.get_size() == Vector2i(256,384),"atlas dimensions")
	check(Vector2i(data.frame_size[0],data.frame_size[1]) == Vector2i(32,48) and Vector2i(data.anchor[0],data.anchor[1]) == Vector2i(16,44),"fixed canvas and foot anchor")
	check(data.frame_count == 57 and data.columns == 8,"57 slots, not 57 unique paintings")
	var used: Array[int] = []
	for direction: String in Source.DIRECTIONS:
		for action: String in Source.COUNTS:
			var clip: Dictionary = data.clips[action+"_"+direction]
			check(clip.cells.size() == Source.COUNTS[action],"clip count "+action+direction)
			var expected_fps := 8 if action == "walk" else 3 if action == "guard" else 5 if action == "hit" else 10
			check(clip.fps == expected_fps and clip.loop == (action == "walk"),"clip timing "+action+direction)
			for index: int in clip.cells.size():
				var cell := int(clip.cells[index])
				used.append(cell)
				var source := Source.frame(action,direction,index)
				var actual := atlas.get_region(Rect2i(cell%8*32,int(cell/8)*48,32,48))
				check(actual.get_data() == source.get_data(),"reproducible layered source "+action+direction+str(index))
				check(source.get_used_rect().has_area(),"nonempty frame")
		check(data.clips["idle_"+direction].cells == [data.clips["walk_"+direction].cells[0]],"idle reuses neutral")
		var first := Source.frame("walk",direction,1)
		var other := Source.frame("walk",direction,3)
		check(first.get_region(Rect2i(0,36,32,8)).get_data() != other.get_region(Rect2i(0,36,32,8)).get_data(),"feet alternate independently of head and arms "+direction)
		for index: int in 4:
			var walk := Source.frame("walk",direction,index)
			check(walk.get_used_rect().end.y == 44,"planted foot retains sole baseline "+direction+str(index))
		# These are readability regressions, not an automated attractiveness vote.
		# Count only the head area; warm cuffs/hands cannot make a dark face pass.
		var face := Source.frame("walk",direction,0).get_region(Rect2i(7,9,18,10))
		var bright := ink_count(face,"h")
		var shadow := ink_count(face,"s")
		if direction == "up": check(bright == 0 and shadow == 0,"rear head is hair, not an invented face")
		else:
			check(bright >= (35 if direction == "down" else 24),"bright face area "+direction)
			check(bright > shadow,"face light skin dominates edge shadow "+direction)
			check(largest_skin_cluster(face) >= (45 if direction == "down" else 30),"skin forms a connected face instead of isolated bright dots "+direction)
	check(ink_count(Source.frame("walk","left",0).get_region(Rect2i(7,9,18,10)),"h") == ink_count(Source.frame("walk","right",0).get_region(Rect2i(7,9,18,10)),"h"),"profiles have equal skin area; no dark rectangle on one side")
	var down := int(data.clips.down.cells[0])
	used.append(down)
	check(atlas.get_region(Rect2i(down%8*32,int(down/8)*48,32,48)).get_data() == Source.frame("down","down",0).get_data(),"down reproducible")
	check(Source.frame("down","down",0).get_used_rect().end.y == 44,"fallen pose grounded on the same baseline")
	used.sort()
	check(used == range(57),"all slots exactly once")
	var colors: Array[String] = []
	var binary_alpha := true
	for y: int in atlas.get_height():
		for x: int in atlas.get_width():
			var pixel := atlas.get_pixel(x,y)
			if pixel.a != 0.0 and pixel.a != 1.0: binary_alpha = false
			if pixel.a == 1.0 and pixel.to_html(false) not in colors: colors.append(pixel.to_html(false))
	check(binary_alpha,"no antialias or translucent edge pixels")
	for color: String in colors: check(color in Source.PALETTE.values(),"palette "+color)
	var config := ConfigFile.new()
	check(config.load("res://assets/runtime/characters/chr_protagonist_atlas.png.import") == OK,"import config")
	check(config.get_value("params","compress/mode") == 0 and not config.get_value("params","mipmaps/generate"),"lossless no mipmaps")
	# Anatomical left is NOT a horizontal mirror: front-right, back-left,
	# left profile visible, right profile hidden. Probe the pouch flap ink.
	for spec: Array in [["down",22],["up",9],["left",13]]:
		check(Source.frame("walk",spec[0],0).get_pixel(spec[1],31) == Color(Source.PALETTE.a),"pouch "+spec[0])
	check(Source.frame("walk","right",0).get_region(Rect2i(11,29,6,6)).get_data() != Source.frame("walk","left",0).get_region(Rect2i(11,29,6,6)).get_data(),"far-side silhouette not mirrored pouch")
	print("CHARACTER_SOURCE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func ink_count(image: Image, ink: String) -> int:
	var count := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x,y) == Color(Source.PALETTE[ink]): count += 1
	return count

func largest_skin_cluster(image: Image) -> int:
	var visited: Dictionary = {}
	var largest := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var seed := Vector2i(x,y)
			if visited.has(seed) or image.get_pixel(x,y) not in [Color(Source.PALETTE.h),Color(Source.PALETTE.s)]: continue
			var queue: Array[Vector2i] = [seed]
			visited[seed] = true
			var cursor := 0
			while cursor < queue.size():
				var at := queue[cursor]
				cursor += 1
				for delta: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var next := at+delta
					if next.x < 0 or next.y < 0 or next.x >= image.get_width() or next.y >= image.get_height() or visited.has(next): continue
					if image.get_pixel(next.x,next.y) not in [Color(Source.PALETTE.h),Color(Source.PALETTE.s)]: continue
					visited[next] = true
					queue.append(next)
			largest = maxi(largest,queue.size())
	return largest
