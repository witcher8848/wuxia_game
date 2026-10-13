extends RefCounted
## Simplified native static character. User selected the A single-pixel eyes.
## The collar is raised two rows; there is only one exposed neck row (y14).
## Brown/gold may appear inside belt/pouch, never on the transparent silhouette.
const Ink = preload("res://assets/source/characters/hero_pixel_source.gd")
const NECK_RECT := Rect2i(14,14,4,3)
const HEAD_FRONT := [
	"....ddd.....", "....ddd.....", "...dddddd...", "..dddddddd..",
	".dddddddddd.", ".ddhhhhhhdd.", ".dhhhhhhhhd.", ".dhhdhhdhhd.",
	"..dhhhhhhd..", "...dhhhhd...",
]
const HEAD_LEFT := [
	"....ddd.....", "....ddd.....", "...dddddd...", "..dddddddd..",
	".dddddddddd.", ".hhhhdddddd.", ".hdhhhdddd..", "hhhhhhdddd..",
	".dhhhdddd...", "..dhhdddd...",
]
const COAT_FRONT_FIRST := [
	"...wwhhww...", "..dbwwwwbd..", ".dbbbwwbbbd.", ".dbbwbbbbbd.",
	".dbwbbbbbbd.", ".dbbbbbbbbd.", ".dbbbbbbbbd.", ".dbbbbbbbbd.",
	".dbbbbbbbbd.", ".dbbbbbbbbd.", ".daaaaaaaad.", ".dbbbbbbbbd.",
	".dbbbbbbbbd.", ".dbbbbbbbbd.", ".dbbbbbbbbd.", ".dbbbbbbbbd.",
	".dbbbddbbbd.", ".dbbd..dbbd.", "..dd....dd..",
]
const COAT_LEFT_FIRST := [
	"..wwhhbbdd..", ".dbwwbbbdd..", ".dbbwbbbdd..", ".dbwbbbbdd..",
	".dbbbbbbdd..", ".dbbbbbbdd..", ".dbbbbbbdd..", ".dbbbbbbdd..",
	".dbbbbbbdd..", ".dbbbbbbdd..", ".daaaaaadd..", ".dbbbbbbdd..",
	".dbbbbbbdd..", ".dbbbbbbdd..", ".dbbbbbbdd..", ".dbbbbbbdd..",
	"..dbbbbddd..", "..dbbbbddd..", "...dddddd...",
]
const LEG := ["gggd", "gggd", "gggd", "gggd", ".ggd", ".ggd", ".ggd", ".ddd", ".ddd", "dddd", "dddd"]
const SLEEVE_FIRST := [".dbbd", "dbbbd", "dbbbd", "dbbbd", "dbbbd", ".dbbd", ".dwwd", "..hh.", "..hh."]
## A slight waist taper and robe flare replace the straight shirt box. Upper
## sleeves join the shoulder as one blue mass; no extra highlights or creases.
const COAT_FRONT := [
	"...wwhhww...", "..dbwwwwbd..", ".bbbbwwbbbb.", ".bbbwbbbbbb.",
	".bbwbbbbbbb.", ".dbbbbbbbbd.", "..dbbbbbbd..", "..dbbbbbbd..",
	"..dbbbbbbd..", "..dbbbbbbd..", "..daaaaaad..", "..dbbbbbbd..",
	".dbbbbbbbbd.", ".dbbbbbbbbd.", ".dbbbbbbbbd.", "dbbbbbbbbbbd",
	"dbbbbddbbbbd", ".dbbd..dbbd.", "..dd....dd..",
]
const COAT_LEFT := [
	"..wwhhbbdd..", ".dbwwbbbdd..", ".dbbwbbbdd..", ".dbwbbbbdd..",
	".dbbbbbbdd..", ".dbbbbbbdd..", "..dbbbbddd..", "..dbbbbddd..",
	"..dbbbbddd..", "..dbbbbddd..", "..daaaaddd..", "..dbbbbddd..",
	".dbbbbbddd..", ".dbbbbbddd..", ".dbbbbbddd..", ".dbbbbbbdd..",
	"..dbbbbddd..", "..dbbbbddd..", "...dddddd...",
]
const SLEEVE := ["..dbb", ".dbbb", "dbbbb", "dbbbd", ".dbbd", ".dwwd", "..hh.", "..hh."]
const SLEEVE_LEFT := [".dbbd", ".dbbd", "dbbbd", "dbbbd", ".dbbd", ".dwwd", "..hh.", "..hh."]
const POUCH := [".dd.", "daad", "daad", "daad", ".dd."]

static func frame(direction: String, variant := "final") -> Image:
	assert(direction in ["down","left"], "Simple candidate has front and left static poses only")
	assert(variant in ["first","final"], "Simple candidate retains its first silhouette for comparison")
	var image := Image.create(32,48,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if direction == "down":
		Ink.stamp(image,10,33,LEG)
		Ink.stamp(image,18,33,LEG)
		Ink.stamp(image,10,14,COAT_FRONT_FIRST if variant == "first" else COAT_FRONT)
		Ink.stamp(image,7,16,SLEEVE_FIRST if variant == "first" else SLEEVE)
		Ink.stamp(image,21,16,SLEEVE_FIRST if variant == "first" else SLEEVE,true)
		Ink.stamp(image,10,4,HEAD_FRONT)
		Ink.stamp(image,21,26,POUCH)
	else:
		Ink.stamp(image,16,33,LEG)
		Ink.stamp(image,12,33,LEG)
		Ink.stamp(image,10,14,COAT_LEFT_FIRST if variant == "first" else COAT_LEFT)
		Ink.stamp(image,15,16,SLEEVE_FIRST if variant == "first" else SLEEVE_LEFT)
		Ink.stamp(image,10,4,HEAD_LEFT)
		Ink.stamp(image,12,26,POUCH)
	return image
