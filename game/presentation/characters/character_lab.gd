extends Node2D
const Hero = preload("res://game/presentation/characters/hero_visual.gd")
const FONT = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
const ACTIONS := ["idle","walk","strike","thrust","slash","guard","hit","down"]
const NAMES := ["待机","行走／冲刺共用","短拳","直刺","横斩","护剑／守势","受击","倒地"]
const DIRECTIONS := ["down","left","right","up"]
const TITLE := "主角动画样本（非正式人设定稿）"
var figures: Array[Node2D] = []
var action_index := 1
var zoom := 3
var paused := false
var sprint := false
var elapsed := 0.0
var direction_index := 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for _direction: String in DIRECTIONS:
		var figure := Hero.new()
		add_child(figure)
		figure.hide()
		figure.set_process(false)
		figures.append(figure)
	_update_figures()

## Optional fixture/preview override. Normal entry uses Hero.ACTIVE_DATA_PATH,
## exactly like the exploration player and battle board.
func configure_manifest(path: String) -> Error:
	if figures.is_empty(): return ERR_UNCONFIGURED
	for figure: Node in figures:
		var error: Error = figure.configure_manifest(path)
		if error != OK: return error
	elapsed = 0.0
	_update_figures()
	queue_redraw()
	return OK

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
		var clip: Dictionary = figure.clip_data()
		figure.step_time = elapsed
		var duration: float = clip["cells"].size()/float(clip["fps"]) if not clip.is_empty() else 0.0
		figure._elapsed = minf(elapsed,duration) if action == "down" else fmod(elapsed,duration) if duration > 0 else 0.0

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
		KEY_A: direction_index = posmod(direction_index-1,DIRECTIONS.size())
		KEY_D: direction_index = posmod(direction_index+1,DIRECTIONS.size())
		KEY_LEFT: _step_frame(-1)
		KEY_RIGHT: _step_frame(1)
	_update_figures()
	queue_redraw()

func _step_frame(step: int) -> void:
	paused = true
	var clip: Dictionary = figures[direction_index if single_direction_mode() else 0].clip_data()
	if clip.is_empty(): return
	elapsed = posmod(int(floor(elapsed*clip.fps))+step,clip.cells.size())/float(clip.fps)

func dynamic_layout() -> bool:
	for figure: Node in figures:
		var bounds: Rect2 = figure.presentation_bounds()
		if bounds.size.x > 32 or bounds.size.y > 48: return true
	return false

func single_direction_mode() -> bool:
	return dynamic_layout() and _overview_layout() == 2

func status_ink() -> Color:
	if single_direction_mode():
		return Color("#171820") if direction_index%2 == 0 else Color("#f1e6cf")
	return Color("#d19a5c")

func status_lines() -> PackedStringArray:
	var state := "暂停" if paused else "冲刺时序" if sprint else "播放"
	if single_direction_mode():
		return [NAMES[action_index], "%dx · %s" % [zoom,state]]
	return [NAMES[action_index]+" · %dx · " % zoom+state]

func _overview_layout() -> int:
	var columns_fit := true
	var grid_fit := true
	for figure: Node in figures:
		var bounds: Rect2 = figure.presentation_bounds()
		var size := bounds.size*zoom
		columns_fit = columns_fit and size.x <= 132 and size.y <= 204
		grid_fit = grid_fit and size.x <= 292 and size.y <= 88
	return 0 if columns_fit else 1 if grid_fit else 2

func preview_panel(index: int) -> Rect2:
	if single_direction_mode(): return Rect2(16,36,608,294)
	if dynamic_layout() and _overview_layout() == 1:
		return Rect2(16+(index%2)*312,76+int(index/2)*120,296,112)
	return Rect2(22+index*150,76,136,232)

func preview_content_rect(index: int) -> Rect2:
	if single_direction_mode(): return Rect2(208,38,410,290)
	var panel := preview_panel(index)
	return Rect2(panel.position+Vector2(2,2),panel.size-Vector2(4,28 if _overview_layout() == 0 else 24))

func preview_draw_bounds(index: int) -> Rect2:
	if figures.is_empty() or index < 0 or index >= figures.size(): return Rect2()
	var bounds: Rect2 = figures[index].presentation_bounds()
	if not dynamic_layout():
		return Rect2(Vector2(90+index*150,254)+bounds.position*zoom,bounds.size*zoom)
	if single_direction_mode() and index != direction_index: return Rect2()
	var content := preview_content_rect(index)
	var size := bounds.size*zoom
	if size.x > content.size.x or size.y > content.size.y: return Rect2()
	return Rect2(content.get_center()-size/2.0,size)

func _draw_dynamic_figure(index: int) -> void:
	var figure: Node = figures[index]
	var panel := preview_panel(index)
	var single := single_direction_mode()
	var bounds: Rect2 = figure.presentation_bounds()
	var draw_bounds := preview_draw_bounds(index)
	var light := index%2 == 0
	var ink := Color("#171820") if light else Color("#f1e6cf")
	draw_rect(panel,Color("#a9ada4") if light else Color("#203934"))
	if draw_bounds.has_area():
		var origin := draw_bounds.position-bounds.position*zoom
		draw_line(Vector2(origin.x-50,origin.y),Vector2(origin.x+50,origin.y),Color("#d19a5c"))
		draw_set_transform(origin,0,Vector2(zoom,zoom))
		figure.draw_at(self,Vector2.ZERO)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_string(FONT,preview_content_rect(index).position+Vector2(12,24),"此倍率超出显示区域；请选较小倍率",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
	var label: String = DIRECTIONS[index]+" · 帧 %02d" % figure.frame_number()
	draw_string(FONT,panel.position+Vector2(12,24) if single else Vector2(panel.position.x+10,panel.end.y-9),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
	if single:
		draw_string(FONT,panel.position+Vector2(12,46),"A / D 切方向",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)

func _draw_dynamic_figures() -> void:
	if single_direction_mode():
		# Side labels leave the entire height available for the enlarged sprite.
		_draw_dynamic_figure(direction_index)
		return
	for index: int in figures.size():
		_draw_dynamic_figure(index)

func _draw() -> void:
	draw_rect(Rect2(0,0,640,360),Color("#171820"))
	draw_string(FONT,Vector2(16,28),TITLE,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#f1e6cf"))
	if dynamic_layout():
		_draw_dynamic_figures()
		var lines := status_lines()
		for index: int in lines.size():
			var at := Vector2(28,96+index*20) if single_direction_mode() else Vector2(16,56)
			draw_string(FONT,at,lines[index],HORIZONTAL_ALIGNMENT_LEFT,180 if single_direction_mode() else -1,14,status_ink())
		draw_string(FONT,Vector2(16,344),"↑↓动作 · 1/2/3倍率 · Space暂停 · Shift步频 · ←→逐帧 · A/D方向",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#f1e6cf"))
		return
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
	draw_string(FONT,Vector2(16,322),"↑↓ 动作 · 1/2/3 倍率 · 空格暂停 · Shift 步频 · ←→逐帧",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#f1e6cf"))
	draw_string(FONT,Vector2(16,346),"32×48 · 脚底(16,44) · 文袋固定角色左侧 · Esc 退出",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("#a9ada4"))
