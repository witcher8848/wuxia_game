extends SceneTree
const Source = preload("res://assets/source/characters/hero_pixel_source.gd")
func _initialize() -> void:
	var atlas := Image.create(256,384,false,Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var clips: Dictionary = {}
	var count := 0
	for direction: String in Source.DIRECTIONS:
		for action: String in Source.COUNTS:
			var cells: Array = []
			for index: int in Source.COUNTS[action]:
				var image: Image = Source.frame(action,direction,index)
				var at := Vector2i((count % 8)*32,int(count/8)*48)
				atlas.blit_rect(image,Rect2i(0,0,32,48),at)
				cells.append(count)
				count += 1
			var fps := 8 if action == "walk" else 3 if action == "guard" else 5 if action == "hit" else 10
			clips[action+"_"+direction] = {"cells":cells,"fps":fps,"loop":action == "walk"}
		clips["idle_"+direction] = {"cells":[clips["walk_"+direction]["cells"][0]],"fps":1,"loop":true}
	atlas.blit_rect(Source.frame("down","down",0),Rect2i(0,0,32,48),Vector2i((count%8)*32,int(count/8)*48))
	clips["down"] = {"cells":[count],"fps":1,"loop":false}
	var folder := "res://assets/runtime/characters"
	DirAccess.make_dir_recursive_absolute(folder)
	if atlas.save_png(folder+"/chr_protagonist_atlas.png") != OK: quit(1); return
	var file := FileAccess.open(folder+"/chr_protagonist_atlas.json",FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify({"frame_size":[32,48],"anchor":[16,44],"columns":8,"frame_count":count+1,"palette":Source.PALETTE.values(),"clips":clips},"\t")+"\n")
	file.close()
	print("HERO_ART_EXPORT_PASS frames=",count+1)
	quit()
