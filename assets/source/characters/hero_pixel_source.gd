extends RefCounted
## Editable native 32x48 pixel layers, authored from the character brief.
## Concept images guide shapes only; this source never reads or samples them.
const PALETTE := {"o":"171820", "d":"242833", "g":"333b46", "b":"335f79", "l":"5f899b", "c":"8fb0b4", "w":"d8d0be", "t":"5b3a30", "a":"d19a5c", "s":"bf7857", "h":"e2aa78"}
const DIRECTIONS := ["down", "left", "right", "up"]
const COUNTS := {"walk":4, "strike":2, "thrust":3, "slash":3, "guard":1, "hit":1}

# Front, profile and rear heads have separate geometry. Only the symmetric
# profile head is reflected; body layers and pouch retain handedness.
const HEAD_FRONT := [
	".....oooo.....", "....ogdddo....", "....ogdddo....", "....oaaaao....",
	"...ogdddddo...", "..ogggdddddo..", ".ogggdddddddo.", ".ogddshhsdddo.",
	".odshhhhhhsdo.", ".odhhhhhhhhdo.", ".oshghhhghhso.", ".oshhhhhhhhso.",
	"..shhhshhhhs..", "...shhhhhss...", "....shhhss....", ".....shhs.....",
]
const HEAD_PROFILE := [
	".....oooo.....", "....ogdddo....", "....ogdddo....", "....oaaaao....",
	"...ogdddddoo..", "..ogggddddddo.", ".oogggdddddoo.", ".oshhhddddddo.",
	"..hhhhhdddddo.", ".shghhhdddddo.", ".shhhhshdddo..", "..hhhhshdddo..",
	"..shhhssdddo..", "...shhssddo...", "....shssdo....", ".....shhs.....",
]
const HEAD_BACK := [
	".....oooo.....", "....ogdddo....", "....ogdddo....", "....oaaaao....",
	"...ogdddddo...", "..ogggdddddo..", ".ogggdddddddo.", ".ogggdddddddo.",
	".odggdddddddo.", ".odggdddddddo.", ".oddgdddddddo.", "..oddddddddo..",
	"...oddddddo...", "....oddgdo....", "....oddgdo....", ".....oddo.....",
]
const TUNIC_FRONT := [
	"....owhhwboo....", "..olbwbbwbblbo..", ".olllbwbbwbblbo.", ".ollbbbwwbbblbo.",
	".olbbbbwlbbblbo.", ".olbbbwlbbbdbbo.", ".obbbwlbbbbdbbo.", ".obbbwlbbbbdbbo.",
	".otaaaaaaaaatto.", ".otaaaattatttto.", ".obllbabbdbbbbo.", ".obllbabbddbbbo.",
	".obllbabbdddbbo.", "..ollbabb.ddbo..", "..obbbab..dbo..", "...oaa....oo...",
]
const TUNIC_PROFILE := [
	"....owwboo..", "..olwbbdbbo.", ".ollwbbdbbo.", ".ollbwbbbbo.",
	".olbbwbbbbo.", ".olbbwbbdbo.", ".obbbwbbdbo.", ".obbbwbbdbo.",
	".otaaaaaato.", ".otaattttto.", ".oblbabddbo.", ".oblbabddbo.",
	".oblbabddbo.", "..obbabdbo..", "..obba.dbo..", "...oo...o...",
]
const TUNIC_BACK := [
	"....obbbbbo.....", "..ollllbbbdbbo..", ".olllllbbbddbbo.", ".olllblbbbddbbo.",
	".ollbblbbbddbbo.", ".olbbblbbbddbbo.", ".obbbblbbbddbbo.", ".obbbblbbbddbbo.",
	".otaaaaaaaaatto.", ".otttttttttttto.", ".obllbbbbddbbbo.", ".obllbbbbddbbbo.",
	".obllbbbbdddbbo.", "..ollbbb.dddbo..", "..obbbbb..dbo..", "...ooo....oo...",
]
const LEG_FRONT := [
	".ogggdo", "oggggdo", "oggggdo", ".ogggdo", "..oddo.", "..owto.",
	"..oddo.", "..oddo.", ".ogddoo", "ogddddo", ".ooooo.",
]
const LEG_PROFILE := [
	".ogddo", "ogggdo", "ogggdo", ".oggdo", ".odddo", "..odo.",
	"..owo.", "..odo.", ".ogdo.", "ogddo.", "ooooo.",
]
const LEG_FAR := [
	".odddo", "oddddo", "oddddo", ".odddo", ".odddo", "..odo.",
	"..oto.", "..odo.", ".oddo.", "odddo.", "ooooo.",
]
const SLEEVE := [
	".olbbo", "ollbbo", "obbbbo", "obbbbo", "owwwwo", ".shhso", ".hhho.", ".shho.", "..oo..",
]

static func rect(image: Image, x: int, y: int, w: int, h: int, ink: String) -> void:
	for iy: int in range(maxi(0,y),mini(48,y+h)):
		for ix: int in range(maxi(0,x),mini(32,x+w)):
			image.set_pixel(ix,iy,Color(PALETTE[ink]))

static func stamp(image: Image, x: int, y: int, rows: Array, mirror := false) -> void:
	for iy: int in rows.size():
		for ix: int in rows[iy].length():
			var key: String = rows[iy][ix]
			var px: int = x+(rows[iy].length()-1-ix if mirror else ix)
			if key != "." and px >= 0 and px < 32 and y+iy >= 0 and y+iy < 48:
				image.set_pixel(px,y+iy,Color(PALETTE[key]))

static func line(image: Image, start: Vector2i, finish: Vector2i, ink: String, width := 1) -> void:
	var steps := maxi(absi(finish.x-start.x),absi(finish.y-start.y))
	for index: int in steps+1:
		var at := Vector2(start).lerp(Vector2(finish),float(index)/maxi(steps,1)).round()
		rect(image,int(at.x),int(at.y),width,width,ink)

static func limb(image: Image, start: Vector2i, finish: Vector2i) -> void:
	line(image,start-Vector2i.ONE,finish-Vector2i.ONE,"o",5)
	line(image,start,finish,"b",3)
	line(image,start,finish,"l")
	rect(image,finish.x,finish.y,3,3,"s")
	rect(image,finish.x,finish.y,2,2,"h")

static func legs(image: Image, direction: String, stride: int) -> void:
	if direction in ["left","right"]:
		var right := direction == "right"
		var sign_x := 1 if right else -1
		var near_x := (14 if right else 12)+stride*sign_x*3
		var far_x := (11 if right else 15)-stride*sign_x*3
		stamp(image,far_x,32 if stride != 0 else 33,LEG_FAR,right)
		stamp(image,near_x,33,LEG_PROFILE,right)
	else:
		# The lifted foot is one pixel higher; the planted foot ends at row43.
		# Motion stays local to the pose, retaining the fixed anchor(16,44).
		stamp(image,9-stride,32 if stride < 0 else 33,LEG_FRONT)
		stamp(image,17+stride,32 if stride > 0 else 33,LEG_FRONT)

static func arms(image: Image, direction: String, action: String, stride: int, bob: int, lean: int) -> void:
	var attack := action in ["strike","thrust","slash"]
	if direction in ["left","right"]:
		var x := 15 if direction == "left" else 11
		if not attack or direction == "left":
			stamp(image,x+lean,21+bob-stride,SLEEVE,direction == "right")
	else:
		if not attack or direction == "up": stamp(image,5+lean,21+bob+stride,SLEEVE)
		if not attack or direction == "down": stamp(image,21+lean,21+bob-stride,SLEEVE,true)

static func attack_layer(image: Image, action: String, direction: String, index: int, bob: int) -> void:
	var reach := index == 1
	var hand := Vector2i(9,25)
	var shoulder := Vector2i(9,21+bob)
	var tip := Vector2i(10,32)
	match direction:
		"down":
			hand = Vector2i(8,32 if reach else 25)
			tip = Vector2i(9,43 if reach else 32)
		"left":
			shoulder = Vector2i(14,21+bob)
			hand = Vector2i(7 if reach else 12,25)
			tip = Vector2i(1 if reach else 7,26)
		"right":
			shoulder = Vector2i(17,21+bob)
			hand = Vector2i(23 if reach else 18,25)
			tip = Vector2i(30 if reach else 25,26)
		"up":
			shoulder = Vector2i(20,21+bob)
			hand = Vector2i(22,13 if reach else 20)
			tip = Vector2i(23,5 if reach else 14)
	if action == "slash":
		if direction == "down": tip = Vector2i(24,24) if reach else Vector2i(4,19)
		elif direction == "up": tip = Vector2i(7,10) if reach else Vector2i(27,10)
		elif direction == "left": tip = Vector2i(3,18) if reach else Vector2i(9,16)
		else: tip = Vector2i(29,18) if reach else Vector2i(22,16)
	limb(image,shoulder,hand)
	if action != "strike":
		var start := hand+Vector2i(1,1)
		line(image,start,tip,"c",2)
		line(image,start,tip,"w")
		# Short crossguard reads as a sword within the fixed canvas.
		if direction in ["left","right"]: rect(image,start.x,start.y-2,1,5,"a")
		else: rect(image,start.x-2,start.y,5,1,"a")
		rect(image,hand.x,hand.y,2,2,"h")

static func guard_layer(image: Image, direction: String, bob: int) -> void:
	var blade_x := 22 if direction in ["right","up"] else 9
	var shoulder := Vector2i(19,22+bob) if direction in ["right","up"] else Vector2i(9,22+bob)
	var hand := Vector2i(blade_x-1,27)
	limb(image,shoulder,hand)
	line(image,Vector2i(blade_x,15),Vector2i(blade_x,26),"c",2)
	line(image,Vector2i(blade_x,15),Vector2i(blade_x,26),"w")
	rect(image,blade_x-2,26,5,1,"a")
	rect(image,hand.x,hand.y,3,2,"h")

static func fallen(image: Image) -> void:
	# Dedicated collapsed pose, retaining the warm face, tunic and pouch.
	stamp(image,11,37,[".ooolbbboooo.......", "olllwbbbbdddoooo...", "obllwbbbbddgggddoo.", "obbbbbbaaddggddddo.", ".obbbbbttddggdddoo.", "..ooobbbbddddddoo..", ".....oooooooooo..."])
	stamp(image,2,35,["...ooo......", "..ogddo.....", "..oaadoooo..", ".ogggdddddo.", "ogddshhhhsdo", "oddshhghhhso", ".oshhhhhhs..", "..sshhhss...", "....sss....."])
	stamp(image,10,41,["olbbwo....", ".obbwhhhs.", "..oo.sss.."])
	stamp(image,19,38,[".ooo.", "otaao", "otato", ".ooo."])

static func frame(action: String, direction: String, index: int) -> Image:
	var image := Image.create(32,48,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if action == "down":
		fallen(image)
		return image
	var stride := (1 if index == 1 else -1 if index == 3 else 0) if action == "walk" else 0
	var bob := 1 if action == "walk" and index in [1,3] else 0
	var lean := (1 if direction == "right" else -1 if direction == "left" else 0) if action in ["thrust","slash"] and index == 1 else 0
	if action == "hit": lean = -1 if direction == "right" else 1
	legs(image,direction,stride)
	if direction == "up": stamp(image,8+lean,19+bob,TUNIC_BACK)
	elif direction in ["left","right"]: stamp(image,10+lean,19+bob,TUNIC_PROFILE,direction == "right")
	else: stamp(image,8+lean,19+bob,TUNIC_FRONT)
	arms(image,direction,action,stride,bob,lean)
	if action == "guard": guard_layer(image,direction,bob)
	elif action in ["strike","thrust","slash"]: attack_layer(image,action,direction,index,bob)
	if direction == "up": stamp(image,9+lean,3+bob,HEAD_BACK)
	elif direction in ["left","right"]: stamp(image,9+lean,3+bob,HEAD_PROFILE,direction == "right")
	else: stamp(image,9+lean,3+bob,HEAD_FRONT)
	# Anatomical left: front-right, back-left, near left profile, hidden right.
	if direction != "right":
		var pouch_x := 20 if direction == "down" else 7 if direction == "up" else 11
		stamp(image,pouch_x+lean,29+bob,[".ooooo", "otttto", "otaaao", "otatto", "otttto", ".oooo."])
	return image
