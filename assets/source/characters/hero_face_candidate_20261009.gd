extends RefCounted
## Face-only revision of the unapproved static candidate. Never used by runtime.
const Base = preload("res://assets/source/characters/hero_static_candidate_20261009.gd")
const Ink = preload("res://assets/source/characters/hero_pixel_source.gd")
## Original hair/bun rows 4..8, neck row15 and every body pixel stay unchanged.
const FACE_RECT := Rect2i(10,9,12,6)
const FACE_FRONT_A := [
	".ddshhhhsdd.",
	".dshhhhhhsd.",
	".dshdhhdhsd.",
	"..shhhhhhs..",
	"...shhhss...",
	"....shhs....",
]
const FACE_LEFT_A := [
	".shhhdddddd.",
	".hdhhhdddd..",
	"hhhhhsdddd..",
	".hhhhsddd...",
	"..shhssdd...",
	"...shhsd....",
]

## B: paired one-row eye clusters, with softer outer corners rather than brows
## stacked above eyes. Jaw lighting is one coherent rim, not isolated mouth dots.
const FACE_FRONT_B := [
	".ddshhhhsdd.",
	".dshhhhhhsd.",
	".dsgdhhdgsd.",
	"..shhhhhhs..",
	"...shhhhs...",
	"....shhs....",
]
const FACE_LEFT_B := [
	".shhhdddddd.",
	".hdghhdddd..",
	"hhhhhsdddd..",
	".hhhhsddd...",
	"..shhssdd...",
	"...shhsd....",
]

static func frame(direction: String, variant := "b") -> Image:
	assert(direction in ["down","left"], "Face candidate only has front and left poses")
	assert(variant in ["a","b"], "Face candidate variant must be a or b")
	var image: Image = Base.frame(direction)
	image.fill_rect(FACE_RECT,Color.TRANSPARENT)
	var rows: Array = (FACE_FRONT_A if direction == "down" else FACE_LEFT_A) if variant == "a" else (FACE_FRONT_B if direction == "down" else FACE_LEFT_B)
	Ink.stamp(image,FACE_RECT.position.x,FACE_RECT.position.y,rows)
	return image
