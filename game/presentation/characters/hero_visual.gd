extends Node2D
## Presentation-only shared atlas. No damage, action or save state is decided here.
const ATLAS = preload("res://assets/runtime/characters/chr_protagonist_atlas.png")
const DATA_PATH := "res://assets/runtime/characters/chr_protagonist_atlas.json"
static var data: Dictionary = {}
var facing := "down"
var walking := false
var sprinting := false
var step_time := 0.0
var external_clock := false
var _action := ""
var _elapsed := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if data.is_empty(): data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	queue_redraw()

func play_action(action: String, direction: String) -> void:
	if direction in ["up","down","left","right"]: facing = direction
	if action not in ["strike","thrust","slash","guard","hit","down"]: return
	_action = action
	_elapsed = 0.0
	walking = false
	queue_redraw()

func reset_pose() -> void:
	_action = ""
	_elapsed = 0.0
	walking = false
	step_time = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not external_clock: step_time += delta * (300.0/180.0 if sprinting else 1.0)
	if not _action.is_empty() and _action != "down":
		_elapsed += delta
		var clip: Dictionary = data["clips"][clip_name()]
		if _elapsed >= clip["cells"].size()/float(clip["fps"]): _action = ""
	queue_redraw()

func clip_name() -> String:
	if _action == "down": return "down"
	return (_action if not _action.is_empty() else "walk" if walking else "idle") + "_" + facing

func frame_number() -> int:
	if data.is_empty(): return 0
	var clip: Dictionary = data["clips"][clip_name()]
	var elapsed := step_time if _action.is_empty() else _elapsed
	var index := int(elapsed*clip["fps"])
	index = index % clip["cells"].size() if clip["loop"] else mini(index,clip["cells"].size()-1)
	return int(clip["cells"][index])

func _draw() -> void:
	draw_at(self,Vector2.ZERO)

func draw_at(canvas: CanvasItem, at: Vector2) -> void:
	if data.is_empty(): return
	var frame := frame_number()
	# Separate fixed pixel shadow; anchor always follows physics feet exactly.
	canvas.draw_rect(Rect2(at+Vector2(-7,-1),Vector2(14,3)),Color("#333b46"))
	canvas.draw_rect(Rect2(at+Vector2(-5,-2),Vector2(10,5)),Color("#333b46"))
	var source := Rect2((frame % 8)*32,int(frame/8)*48,32,48)
	canvas.draw_texture_rect_region(ATLAS,Rect2(at+Vector2(-16,-44),Vector2(32,48)),source)
	if sprinting and walking:
		var behind := Vector2.UP if facing == "down" else Vector2.DOWN if facing == "up" else Vector2.LEFT if facing == "right" else Vector2.RIGHT
		canvas.draw_rect(Rect2(at+(behind*14).round(),Vector2(3,2)),Color("#d19a5c"))
		canvas.draw_rect(Rect2(at+(behind*19+Vector2(3,1)).round(),Vector2(2,1)),Color("#a9ada4"))
