extends Node

var menu: PanelContainer
var status: Label
var debug_label: Label
var _automation := false
var ui_theme: Theme

func _ready() -> void:
	_automation = OS.is_debug_build() and ("--smoke-test" in OS.get_cmdline_user_args() or "--capture-week1" in OS.get_cmdline_user_args())
	ui_theme = Theme.new()
	ui_theme.default_font = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
	ui_theme.default_font_size = 16
	_build_ui()
	_show_title()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if _automation:
		_run_smoke.call_deferred()

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("#171820")
	backdrop.size = Vector2(640, 360)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UIRoot.add_child(backdrop)
	backdrop.name = "Backdrop"
	status = Label.new()
	status.position = Vector2(16, 312)
	status.size = Vector2(608, 40)
	status.add_theme_font_size_override("font_size", 14)
	status.theme = ui_theme
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = tr("UI_CONTROLS")
	$UIRoot.add_child(status)
	debug_label = Label.new()
	debug_label.position = Vector2(16, 16)
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.theme = ui_theme
	debug_label.visible = App.debug_enabled
	$UIRoot.add_child(debug_label)

func _new_menu(title: String) -> VBoxContainer:
	if is_instance_valid(menu):
		menu.queue_free()
	menu = PanelContainer.new()
	menu.theme = ui_theme
	menu.position = Vector2(148, 58)
	menu.size = Vector2(344, 198)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	menu.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 22)
	box.add_child(heading)
	$UIRoot.add_child(menu)
	return box

func _button(box: VBoxContainer, caption: String, callback: Callable, focus: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 28
	box.add_child(button)
	button.pressed.connect(callback)
	if focus:
		button.grab_focus.call_deferred()
	return button

func _show_title() -> void:
	App.reset_contexts()
	App.push_context(&"system_menu")
	var box := _new_menu(tr("UI_TITLE"))
	_button(box, tr("UI_ENTER_YARD"), _start_game, true)
	_button(box, tr("UI_LOAD"), _load_game)
	_button(box, tr("UI_QUIT"), func() -> void: get_tree().quit())

func _start_game() -> void:
	GameSession.start_new_game()
	_enter_yard()

func _enter_yard() -> void:
	for child in $SceneHost.get_children():
		$SceneHost.remove_child(child)
		child.queue_free()
	var scene_path: String = ContentDB.get_scene_path(GameSession.state.scene_id)
	if scene_path.is_empty() or not ContentDB.has_spawn(GameSession.state.scene_id, GameSession.state.spawn_id):
		status.text = tr("UI_INVALID_SCENE")
		return
	$SceneHost.add_child((load(scene_path) as PackedScene).instantiate())
	$UIRoot/Backdrop.hide()
	menu.hide()
	App.reset_contexts()
	status.text = tr("UI_YARD_CONTROLS")

func _show_pause() -> void:
	App.push_context(&"system_menu")
	var box := _new_menu(tr("UI_PAUSED"))
	menu.position.y = 22
	box.add_theme_constant_override("separation", 4)
	_button(box, tr("UI_RESUME"), _resume, true)
	_button(box, tr("UI_SAVE"), _save_game)
	_button(box, tr("UI_LOAD"), _load_game)
	_button(box, tr("UI_FULLSCREEN"), _toggle_fullscreen)
	_button(box, tr("UI_TITLE_RETURN"), _return_to_title)

func _return_to_title() -> void:
	for child in $SceneHost.get_children():
		$SceneHost.remove_child(child)
		child.queue_free()
	$UIRoot/Backdrop.show()
	_show_title()

func _resume() -> void:
	menu.hide()
	App.pop_context()

func _save_game() -> void:
	var result := SaveService.save_game("quick", GameSession.state)
	status.text = tr("UI_SAVE_OK") if result == OK else tr("UI_SAVE_FAILED") % error_string(result)

func _load_game() -> void:
	var result := SaveService.load_game("quick")
	if result.get("error", FAILED) == OK:
		var loaded: GameState = result["state"]
		if not ContentDB.has_spawn(loaded.scene_id, loaded.spawn_id) or GameSession.replace_state(loaded) != OK:
			status.text = tr("UI_INVALID_SCENE")
			return
		_enter_yard()
		status.text = tr("UI_LOAD_OK") % str(result.get("source", "quick"))
	else:
		status.text = tr("UI_LOAD_FAILED") + str(result.get("message", ""))

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("cancel"):
		if App.current_context() == &"exploration":
			_show_pause()
		elif $SceneHost.get_child_count() > 0:
			_resume()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_save") and App.current_context() == &"exploration":
		_save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_toggle") and OS.is_debug_build():
		App.debug_enabled = not App.debug_enabled
		debug_label.visible = App.debug_enabled

func _process(_delta: float) -> void:
	if debug_label.visible:
		debug_label.text = "DEV | FPS %d | %s | pads %d" % [Engine.get_frames_per_second(), App.current_context(), Input.get_connected_joypads().size()]

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if not connected and App.current_context() == &"exploration":
		_show_pause()
		status.text = tr("UI_PAD_DISCONNECTED")

func _run_smoke() -> void:
	await get_tree().process_frame
	if "--capture-week1" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture("title")
	_start_game()
	await get_tree().process_frame
	if $SceneHost.get_child_count() != 1 or App.current_context() != &"exploration":
		push_error("Main scene did not enter test yard")
		get_tree().quit(1)
		return
	var yard: Node2D = $SceneHost.get_child(0)
	var before: Vector2 = yard.player_position
	Input.action_press("move_right")
	for _frame in range(6):
		await get_tree().physics_frame
	Input.action_release("move_right")
	if yard.player_position.x <= before.x:
		push_error("Test yard did not respond to InputMap")
		get_tree().quit(1)
		return
	print("WEEK1_SMOKE_PASS scene=SCENE_TEST_YARD movement=ok platform=offline connected_pads=", Input.get_connected_joypads().size())
	if "--capture-week1" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture("test_yard")
		_show_pause()
		await _capture("pause")
	get_tree().quit()

func _capture(stage: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/qa")
	var capture_error := get_viewport().get_texture().get_image().save_png("res://builds/qa/week1_%s.png" % stage)
	if capture_error != OK:
		push_error("Screenshot capture failed")
		get_tree().quit(1)
