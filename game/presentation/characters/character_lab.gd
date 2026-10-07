extends Node2D
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const ACTIONS := ["idle","walk","strike","thrust","slash","guard","hit","down"]
const NAMES := ["待机","行走／冲刺共用","短拳","直刺","横斩","护剑／守势","受击","倒地"]
const DIRECTIONS := ["down","left","right","up"]
var figures: Array[Node2D] = []
var action_index := 1
var zoom := 3
var paused := false
var sprint := false
var elapsed := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for _direction: String in DIRECTIONS:
		var figure := Hero.new()
		add_child(figure)
		figure.hide()
		figure.set_process(false)
		figures.append(figure)
	_update_figures()

func _process(delta: float) -> void:
	if not paused: elapsed += delta * (300.0/180.0 if sprint and ACTIONS[action_index] == "walk" else 1.0)
	_update_figures()
	queue_redraw()

func _update_figures() -> void:
	for index: int in figures.size():
		var figure := figures[index]
		figure.facing = DIRECTIONS[index]
		var action: String = ACTIONS[action_index]
		figure.walking = action == "walk"
		figure.sprinting = sprint and action == "walk"
		figure._action = "" if action in ["idle","walk"] else action
		var clip: Dictionary = Hero.data["clips"][figure.clip_name()]
		figure.step_time = elapsed
		figure._elapsed = fmod(elapsed,clip["cells"].size()/float(clip["fps"]))

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	match event.physical_keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_UP,KEY_W: action_index = posmod(action_index-1,ACTIONS.size()); elapsed = 0.0
		KEY_DOWN,KEY_S: action_index = posmod(action_index+1,ACTIONS.size()); elapsed = 0.0
		KEY_SPACE: paused = not paused
		KEY_SHIFT: sprint = not sprint
		KEY_1: zoom = 1
		KEY_2: zoom = 2
		KEY_3: zoom = 3
	_update_figures()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0,0,640,360),Color("#171820"))
	draw_string(FONT,Vector2(16,28),"第五周 · 主角动画样本（非正式人设定稿）",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#f1e6cf"))
	draw_string(FONT,Vector2(16,56),NAMES[action_index]+"  ·  %dx 最近邻" % zoom + (" · 暂停" if paused else " · 冲刺时序" if sprint else " · 播放"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("#d19a5c"))
	for index: int in figures.size():
		var x := 90+index*150
		draw_rect(Rect2(x-68,76,136,220),Color("#a9ada4") if index%2==0 else Color("#203934"))
		draw_string(FONT,Vector2(x-26,97),DIRECTIONS[index],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#171820") if index%2==0 else Color("#f1e6cf"))
		draw_line(Vector2(x-50,254),Vector2(x+50,254),Color("#d19a5c"))
		draw_set_transform(Vector2(x,254),0,Vector2(zoom,zoom))
		figures[index].draw_at(self,Vector2.ZERO)
		draw_set_transform(Vector2.ZERO)
		draw_string(FONT,Vector2(x-42,284),"帧 %02d" % figures[index].frame_number(),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#171820") if index%2==0 else Color("#f1e6cf"))
	draw_string(FONT,Vector2(16,322),"↑↓ / W S 动作 · 1/2/3 倍率 · 空格暂停 · Shift 切换时序",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#f1e6cf"))
	draw_string(FONT,Vector2(16,346),"32×48 · 脚底(16,44) · 文袋固定角色左侧 · Esc 退出",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#a9ada4"))
