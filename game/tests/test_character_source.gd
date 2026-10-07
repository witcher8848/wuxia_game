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
		check(first.get_data() != Source.frame("walk",direction,3).get_data(),"alternating legs "+direction)
	var down := int(data.clips.down.cells[0])
	used.append(down)
	check(atlas.get_region(Rect2i(down%8*32,int(down/8)*48,32,48)).get_data() == Source.frame("down","down",0).get_data(),"down reproducible")
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
