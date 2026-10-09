extends RefCounted
## Two native static poses for art approval. Not an animation replacement.
const Existing = preload("res://assets/source/characters/hero_pixel_source.gd")
const HEAD_FRONT := [
	"....ddd.....", "....dad.....", "...dggddd...", "..dgdddddd..",
	".dgdddddddd.", ".ddshhhssdd.", ".dshhhhhhsd.", ".dshghhghsd.",
	"..shhhshhs..", "...shhhss...", "....shhs....", "....shhs....",
]
const HEAD_LEFT := [
	"....ddd.....", "....dad.....", "...dggddd...", "..dgdddddd..",
	".dgdddddddd.", ".shhhdddddd.", ".hhhhhdddd..", "shghhhdddd..",
	".hhhhhddd...", "..shhssdd...", "...shhsd....", "....shhs....",
]
const COAT_FRONT := [
	".....wwssww......", "...llbwbbwbdb....", "..llbbwbbwbddb...", "..lbbbbwwbbddb...",
	"..lbbbbwbbbddb...", "...bbbwbbbbddb...", "...bbwbbbbdddb...", "...bbbbbbbdddb...",
	"...bbbbbbbdddb...", "...bbbbbbbdddb...", "...ttttttttttd...", "...aaaattttttd...",
	"...lbbbbbbdddb...", "...lbbbbbbdddb...", "...bbbbbbbdddb...", "...bbbbbbbdddb...",
	"...bbbbbb.bddb...", "...bbbbb..bdb....", "....bbb....d.....",
]
const COAT_LEFT := [
	"...wwssbbb..", "..lwbbbbbdd.", ".llbwbbbbdd.", ".lbbbwbbbdd.",
	".lbbbwbbbdd.", "..bbbwbbbdd.", "..bbbbbbbdd.", "..bbbbbbbdd.",
	"..bbbbbbbdd.", "..bbbbbbbdd.", "..ttttttttd.", "..aaatttttd.",
	"..lbbbbbddd.", "..lbbbbbddd.", "..bbbbbbddd.", "..bbbbbbddd.",
	"...bbbbbddd.", "...bbbbbdd..", "....bbbbd...",
]
const LEG := ["gggdd", "gggdd", "gggdd", ".ggdd", ".ggdd", ".ggdd", ".ggdd", ".ggdd", ".gddd", "gdddd", "ddddd"]
const SLEEVE := [".lbb", "llbb", "lbbb", "bbbb", "bbbd", "bbbd", ".bbd", ".bbw", ".whs", "..hs"]
const POUCH := [".tttt", "taaad", "taatd", "ttttd", "ttttd", ".ddd."]

static func frame(direction: String) -> Image:
	assert(direction in ["down","left"], "Static art candidate has only front and left poses")
	var image := Image.create(32,48,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if direction == "down":
		Existing.stamp(image,10,33,LEG)
		Existing.stamp(image,18,33,LEG)
		Existing.stamp(image,8,16,COAT_FRONT)
		Existing.stamp(image,7,18,SLEEVE)
		Existing.stamp(image,22,18,SLEEVE,true)
		Existing.stamp(image,10,4,HEAD_FRONT)
		Existing.stamp(image,22,27,POUCH)
	else:
		Existing.stamp(image,16,33,LEG)
		Existing.stamp(image,12,33,LEG)
		Existing.stamp(image,10,16,COAT_LEFT)
		Existing.stamp(image,15,18,SLEEVE)
		Existing.stamp(image,10,4,HEAD_LEFT)
		Existing.stamp(image,12,27,POUCH)
	return image
