extends RefCounted
## Editable integer-pixel layers. This source is authored independently of AI
## concept PNGs: never resize or sample a generated illustration into the atlas.
const PALETTE := {"o":"171820", "d":"242833", "g":"333b46", "b":"335f79", "l":"5f899b", "c":"8fb0b4", "w":"d8d0be", "t":"5b3a30", "a":"d19a5c", "s":"bf7857", "h":"e2aa78"}
const DIRECTIONS := ["down", "left", "right", "up"]
const COUNTS := {"walk":4, "strike":2, "thrust":3, "slash":3, "guard":1, "hit":1}

static func rect(image: Image, x: int, y: int, w: int, h: int, ink: String) -> void:
	for iy: int in range(maxi(0,y),mini(48,y+h)):
		for ix: int in range(maxi(0,x),mini(32,x+w)):
			image.set_pixel(ix,iy,Color(PALETTE[ink]))

static func stamp(image: Image, x: int, y: int, rows: Array, inks := PALETTE) -> void:
	for iy: int in rows.size():
		for ix: int in rows[iy].length():
			var key: String = rows[iy][ix]
			if key != "." and x+ix >= 0 and x+ix < 32 and y+iy >= 0 and y+iy < 48:
				image.set_pixel(x+ix,y+iy,Color(inks[key]))

static func limb(image: Image, start: Vector2i, finish: Vector2i) -> void:
	var steps := maxi(absi(finish.x-start.x),absi(finish.y-start.y))
	for index: int in steps+1:
		var at := Vector2(start).lerp(Vector2(finish),float(index)/maxi(steps,1)).round()
		rect(image,int(at.x)-1,int(at.y)-1,5,5,"o")
	for index: int in steps+1:
		var at := Vector2(start).lerp(Vector2(finish),float(index)/maxi(steps,1)).round()
		rect(image,int(at.x),int(at.y),3,3,"b")

static func frame(action: String, direction: String, index: int) -> Image:
	var image := Image.create(32,48,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if action == "down":
		stamp(image,3,34,["......................", "...oooooo.............", "..oggggdooobbbbbboooo..", ".ogdddddossbbbbbbdddoo.", ".oddddddshhblbbbaaddoo.", "..oooooosssbbbbbbddoo..", "........oobbbbbboooo..", ".........ooooooo......"])
		return image
	var stride := (1 if index == 1 else -1 if index == 3 else 0) if action == "walk" else 0
	var bob := 1 if action == "walk" and index in [1,3] else 0
	var lean := (1 if direction == "right" else -1 if direction == "left" else 0) if action in ["thrust", "slash"] and index == 1 else 0
	if action == "hit": lean = -1 if direction == "right" else 1
	var side := direction in ["left", "right"]
	# Boots and trousers: feet stay on the baseline rather than bobbing the node.
	stamp(image,9,33,[".oddd..oddd.", ".odgd..odgd.", ".odgd..odgd.", ".oddd..oddd.", ".oddd..oddd.", ".oddd..oddd.", ".oddd..oddd.", "ooooo..ooooo", "ogddo..ogddo", "ooooo..ooooo"])
	if stride != 0:
		rect(image,8 if stride > 0 else 18,40,7,4,"o")
		rect(image,9 if stride > 0 else 19,41,5,1,"g")
	# Tunic, split hem, crossing collar: body silhouette is narrower than sleeves.
	stamp(image,7+lean,18+bob,["....oooooo........", "..oolllllboo......", ".olllwbbbwbbo.....", "olllblwbbwbbbo....", "olblbblwwbbbbo....", ".obbbbbwlbbbo.....", ".obbbbwlbbbbo.....", ".obbbwlbbbbbo.....", ".obbbwlbbbboo.....", ".oaaaaaaaaaao.....", ".otaaaattttto.....", ".obblbabbdbbo.....", ".obblbabbdbbo.....", ".obblbab.ddbbo....", ".obbbaa..ddbo.....", "..ooooo..oooo....."])
	if direction == "up":
		rect(image,10+lean,20+bob,11,7,"b")
		rect(image,11+lean,20+bob,2,6,"l")
	if side:
		rect(image,11+lean,20+bob,9,8,"b")
		rect(image,(11 if direction == "left" else 18)+lean,20+bob,2,8,"l")
	# Arms are separate layers, with a right-handed forward action.
	var arm_y := 21+bob
	var reach := index == 1 and action in ["strike", "thrust", "slash"]
	# Shoulder joins prevent detached sleeves at enlarged preview scale.
	rect(image,7+lean,21+bob,4,3,"b")
	rect(image,20+lean,21+bob,4,3,"b")
	for x: int in [6,22]:
		if action in ["strike","thrust","slash"] and x == (22 if direction in ["right","up"] else 6): continue
		var delta := stride if x == 6 else -stride
		stamp(image,x+lean,arm_y+delta,[".ooo", "oblo", "obbo", "obbo", "obbo", ".owo", ".oso", ".sho", "..oo"])
	if action == "guard":
		rect(image,10,24+bob-index,13,3,"g")
		rect(image,11,23+bob-index,3,3,"h")
		rect(image,7,17,1,12,"w")
		rect(image,8,17,1,12,"c")
		rect(image,5,28,6,1,"a")
		rect(image,7,27,3,3,"h")
		rect(image,9,25,4,3,"b")
	elif action in ["strike", "thrust", "slash"]:
		var hand := Vector2i(6,25)
		if direction == "right": hand = Vector2i(22 if reach else 20,24)
		elif direction == "left": hand = Vector2i(8 if reach else 10,24)
		elif direction == "down": hand = Vector2i(10,31 if reach else 24)
		else: hand = Vector2i(25,16 if reach else 22)
		var shoulder := Vector2i(20,21) if direction in ["right","up"] else Vector2i(9,21)
		limb(image,shoulder,hand)
		rect(image,hand.x,hand.y,3,3,"h")
		# Compact sword layer stays inside this fixed canvas. Longer reach is not
		# represented by changing the unit footprint or the domain attack range.
		var blade := 7 if reach else 4
		if side and action != "strike":
			var start := hand.x+2 if direction == "right" else hand.x-blade
			rect(image,start,hand.y,blade,1,"w")
			rect(image,start,hand.y+1,blade,1,"c")
		elif action != "strike":
			var start := hand.y+2 if direction == "down" else hand.y-blade
			rect(image,hand.x+1,start,1,blade,"w")
		if action == "slash" and index == 1:
			stamp(image,8,23,["...www...", "..w...w..", ".w.....w.", "w........"])
	# Head roughly 1/4 of the 40px body height; black topknot and light skin.
	stamp(image,9+lean,3+bob,["....oooo......", "...ogddo......", "...oaaao......", "..oodddooo....", ".ogggdddddo...", "ogggdddddddo..", "ogddssssdddo..", "odshhhhhsddo..", "odshhhhhsddo..", ".osohhhosso...", ".osshhhssso...", "..osssssso....", "...oshsso.....", "....osso......", "....owwo......"])
	if direction == "up":
		rect(image,10+lean,8+bob,12,9,"d")
		rect(image,11+lean,8+bob,3,6,"g")
		rect(image,14+lean,16+bob,3,7,"d")
	elif side:
		var back := 17 if direction == "left" else 10
		rect(image,back+lean,9+bob,5,8,"d")
		rect(image,(10 if direction == "left" else 21)+lean,12+bob,2,1,"h")
		rect(image,(12 if direction == "left" else 20)+lean,11+bob,1,1,"o")
	# The document pouch is ALWAYS anatomical left: viewer-right from front,
	# viewer-left from back, visible in left profile and hidden in right profile.
	if direction != "right":
		var pouch_x := 20 if direction == "down" else 7 if direction == "up" else 11
		stamp(image,pouch_x+lean,29+bob,[".ooooo", "otttto", "otaaao", "otatto", "otttto", ".oooo."])
	return image
