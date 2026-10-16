extends Node

var menu: PanelContainer
var status: Label
var debug_label: Label
var _automation := false
var ui_theme: Theme
var reading_panel: PanelContainer
var region_label: Label
var interaction_hint: Label
var transition_cover: ColorRect
var controls_backdrop: ColorRect
var transitioning := false
var _reading_target: Dictionary = {}
var _menu_kind: StringName = &"title"
var _slot_origin: StringName = &"title"
var _slot_page: int = 0
var _pending_slot: String = ""
var slot_buttons: Array[Button] = []
var slot_entries: Array[Dictionary] = []
const SLOT_PAGE_SIZE: int = 3
const DialoguePanel = preload("res://game/presentation/investigation/dialogue_panel.gd")
const ActivityPanel = preload("res://game/presentation/investigation/activity_panel.gd")
const ProloguePanel = preload("res://game/presentation/investigation/prologue_panel.gd")
const ObjectiveGuide = preload("res://game/presentation/investigation/objective_guide.gd")
var objective_label: Label
var activity_panel: PanelContainer
var _activity_from_dialogue := false
var _activity_initial_state: Dictionary = {}
const StoryBattleScreen = preload("res://game/presentation/battle/story_battle_screen.gd")
const MartialPanel = preload("res://game/presentation/battle/martial_preparation_panel.gd")
const WorldPanel = preload("res://game/presentation/world/world_panel.gd")
const SocialDialoguePanel = preload("res://game/presentation/world/social_dialogue_panel.gd")
const ExplorationRegion = preload("res://game/presentation/exploration/exploration_region.gd")
var world_panel: PanelContainer
var _world_from_dialogue := false
var martial_panel: PanelContainer
var story_battle_screen: Node2D
var _story_layer: CanvasLayer
var _story_token := ""
var _combat_v1_screen: Node
var _combat_v1_layer: CanvasLayer

func _ready() -> void:
	_automation = OS.is_debug_build() and ("--smoke-test" in OS.get_cmdline_user_args() or "--capture-week1" in OS.get_cmdline_user_args())
	ui_theme = Theme.new()
	ui_theme.default_font = preload("res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf")
	ui_theme.default_font_size = 16
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#171820")
	panel_style.border_color = Color("#747b78")
	panel_style.set_border_width_all(1)
	ui_theme.set_stylebox("panel", "PanelContainer", panel_style)
	_build_ui()
	_show_title()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if _automation:
		get_tree().create_timer(20).timeout.connect(func() -> void:
			push_error("Exploration smoke watchdog expired")
			get_tree().quit(1))
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
	region_label = Label.new()
	region_label.theme = ui_theme
	region_label.position = Vector2(12, 8)
	region_label.size = Vector2(616, 24)
	region_label.add_theme_font_size_override("font_size", 15)
	region_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	region_label.add_theme_color_override("font_color", Color("#f1e6cf"))
	region_label.add_theme_color_override("font_shadow_color", Color("#171820"))
	region_label.add_theme_constant_override("shadow_outline_size", 4)
	$UIRoot.add_child(region_label)
	objective_label = Label.new()
	objective_label.theme = ui_theme
	objective_label.position = Vector2(12, 35)
	objective_label.size = Vector2(616, 46)
	objective_label.add_theme_font_size_override("font_size", 13)
	objective_label.add_theme_color_override("font_shadow_color", Color("#171820"))
	objective_label.add_theme_constant_override("shadow_outline_size", 5)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UIRoot.add_child(objective_label)
	interaction_hint = Label.new()
	interaction_hint.theme = ui_theme
	interaction_hint.position = Vector2(16, 286)
	interaction_hint.add_theme_color_override("font_color", Color("#f1e6cf"))
	interaction_hint.add_theme_color_override("font_shadow_color", Color("#171820"))
	interaction_hint.add_theme_constant_override("shadow_outline_size", 4)
	$UIRoot.add_child(interaction_hint)
	var footer := ColorRect.new()
	controls_backdrop = footer
	footer.color = Color("#171820")
	footer.position = Vector2(0, 310)
	footer.size = Vector2(640, 50)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UIRoot.add_child(footer)
	$UIRoot.move_child(footer, status.get_index())
	status.position = Vector2(12, 315)
	status.size = Vector2(616, 40)
	debug_label.position = Vector2(12, 32)
	transition_cover = ColorRect.new()
	transition_cover.color = Color("#171820")
	transition_cover.size = Vector2(640, 360)
	transition_cover.modulate.a = 0.0
	transition_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TransitionLayer.add_child(transition_cover)

func _new_menu(title: String) -> VBoxContainer:
	slot_buttons.clear()
	if is_instance_valid(menu):
		menu.hide()
		$UIRoot.remove_child(menu)
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
	button.pressed.connect(func() -> void:
		get_viewport().set_input_as_handled()
		callback.call())
	if focus:
		_focus_later(button)
	return button

func _focus_later(button: Button) -> void:
	# A second menu can replace this one before the deferred layout pass.
	# Keep an instance ID rather than a potentially freed typed node reference.
	var identifier: int = button.get_instance_id()
	(func() -> void:
		var target: Object = instance_from_id(identifier)
		if target is Button and target.is_inside_tree() and target.is_visible_in_tree() and is_instance_valid(menu) and menu.is_ancestor_of(target):
			target.grab_focus()).call_deferred()

func _show_title() -> void:
	_menu_kind = &"title"
	_pending_slot = ""
	region_label.text = ""
	interaction_hint.text = ""
	status.text = tr("UI_CONTROLS")
	App.reset_contexts()
	App.push_context(&"system_menu")
	var box := _new_menu(tr("UI_TITLE"))
	_button(box, tr("UI_ENTER_YARD"), _start_game, true)
	_button(box, tr("UI_LOAD"), _show_load_slots)
	_button(box, tr("UI_QUIT"), func() -> void: get_tree().quit())
	_button(box, "战斗V1演武（测试）", _open_combat_v1)
	box.add_theme_constant_override("separation", 5)
	menu.size.y = 218

func _open_combat_v1() -> void:
	if GameSession.combat_active() or transitioning: return
	var packed: PackedScene = load("res://game/presentation/battle/combat_v1_trial.tscn")
	if packed == null: return
	_combat_v1_screen = packed.instantiate()
	_combat_v1_layer = CanvasLayer.new()
	_combat_v1_layer.layer = 4
	add_child(_combat_v1_layer)
	$UIRoot.hide()
	$SceneHost.hide()
	$SceneHost.process_mode = Node.PROCESS_MODE_DISABLED
	_combat_v1_screen.exit_requested.connect(_close_combat_v1)
	_combat_v1_layer.add_child(_combat_v1_screen)

func _close_combat_v1() -> void:
	if not is_instance_valid(_combat_v1_layer): return
	_combat_v1_layer.hide()
	_combat_v1_layer.process_mode = Node.PROCESS_MODE_DISABLED
	# Exit the trial synchronously before rebuilding title input contexts.
	remove_child(_combat_v1_layer)
	_combat_v1_layer.queue_free()
	_combat_v1_screen = null
	$SceneHost.process_mode = Node.PROCESS_MODE_INHERIT
	$SceneHost.show()
	$UIRoot.show()
	_show_title()

func _start_game() -> void:
	GameSession.start_new_game()
	if _enter_yard() != OK: return
	App.push_context(&"dialogue")
	_reset_movement()
	if is_instance_valid(reading_panel): reading_panel.queue_free()
	reading_panel = ProloguePanel.new()
	reading_panel.theme = ui_theme
	reading_panel.activity_requested.connect(_open_activity)
	reading_panel.departed.connect(_finish_prologue)
	$UIRoot.add_child(reading_panel)

func _finish_prologue(lead: String) -> void:
	if not reading_panel is ProloguePanel or reading_panel.page != 6: return
	var accepted: Dictionary = GameSession.apply_investigation_step("STEP_ACCEPT_SEARCH")
	if accepted["error"] not in [OK, ERR_ALREADY_EXISTS]: return
	var chosen: Dictionary = GameSession.apply_investigation_step("STEP_FIRST_DOCK" if lead == "dock" else "STEP_FIRST_HOME")
	if chosen["error"] != OK: return
	_close_reading()

func _prepare_region(scene_id: String) -> Node:
	var path: String = ContentDB.get_scene_path(scene_id)
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return null
	var packed: Resource = load(path)
	if not packed is PackedScene or not packed.can_instantiate():
		return null
	var candidate: Node = packed.instantiate()
	if not candidate is Node2D:
		candidate.free()
		return null
	if not ContentDB.get_exploration_region(scene_id).is_empty():
		if not candidate.has_method("choose_target") or candidate.get("scene_id") != scene_id:
			candidate.free()
			return null
	return candidate

func _enter_yard(prepared: Node = null) -> Error:
	# Kept as a compatibility entry point; current content starts in the town.
	var recovered := false
	var next_state: GameState = GameState.from_dict(GameSession.state.to_dict())
	if next_state == null:
		status.text = tr("UI_INVALID_SCENE")
		if prepared != null:
			prepared.free()
		return ERR_INVALID_DATA
	if ContentDB.get_scene_path(next_state.scene_id).is_empty() or not ContentDB.has_spawn(next_state.scene_id, next_state.spawn_id):
		next_state.scene_id = ContentDB.start_scene_id
		next_state.spawn_id = ContentDB.start_spawn_id
		var start: Vector2 = ContentDB.get_spawn_position(next_state.scene_id, next_state.spawn_id)
		next_state.player_state["position"] = {"x": start.x, "y": start.y}
		recovered = true
	var definition: Dictionary = ContentDB.get_exploration_region(next_state.scene_id)
	if not definition.is_empty():
		var saved: Dictionary = next_state.player_state["position"]
		if not ContentDB.is_safe_world_position(next_state.scene_id, Vector2(saved["x"], saved["y"]), next_state):
			var spawn: Vector2 = ContentDB.get_spawn_position(next_state.scene_id, next_state.spawn_id)
			# An NPC's new scheduled anchor may overlap an older save. Move only
			# the minimum safe distance, not all the way back to the entrance.
			if ContentDB.is_walkable_position(next_state.scene_id, Vector2(saved["x"], saved["y"])):
				var projection: Dictionary = ContentDB.exploration_view(next_state.scene_id, next_state)
				if projection["error"].is_empty(): spawn = ExplorationRegion.nearest_safe_position(projection["region"], Vector2(saved["x"], saved["y"]))
			if not ContentDB.is_safe_world_position(next_state.scene_id, spawn, next_state):
				status.text = tr("UI_INVALID_SCENE")
				if prepared != null:
					prepared.free()
				return ERR_INVALID_DATA
			next_state.player_state["position"] = {"x": spawn.x, "y": spawn.y}
			recovered = true
	var region: Node = prepared if prepared != null else _prepare_region(next_state.scene_id)
	if region == null:
		status.text = tr("UI_INVALID_SCENE")
		return ERR_CANT_OPEN
	var previous: GameState = GameSession.state
	if GameSession.replace_state(next_state) != OK:
		region.free()
		status.text = tr("UI_INVALID_SCENE")
		return ERR_INVALID_DATA
	if region.has_signal("interaction_requested"):
		region.interaction_requested.connect(_on_interaction)
	$SceneHost.add_child(region)
	if not definition.is_empty() and not is_instance_valid(region.get("player")):
		$SceneHost.remove_child(region)
		region.queue_free()
		GameSession.replace_state(previous)
		status.text = tr("UI_INVALID_SCENE")
		return ERR_CANT_CREATE
	for child in $SceneHost.get_children():
		if child != region:
			$SceneHost.remove_child(child)
			child.queue_free()
	$UIRoot/Backdrop.hide()
	if is_instance_valid(menu):
		menu.hide()
	_menu_kind = &""
	_pending_slot = ""
	App.reset_contexts()
	region_label.text = tr(ContentDB.get_scene_definition(GameSession.state.scene_id)["name_key"]) + " · " + tr("UI_GREYBOX")
	status.text = tr("UI_SPAWN_RECOVERED") if recovered else tr("UI_EXPLORATION_CONTROLS")
	_reset_movement()
	return OK

func _reset_movement() -> void:
	if $SceneHost.get_child_count() == 1:
		var region: Node = $SceneHost.get_child(0)
		if region.get("player") is CharacterBody2D:
			region.player.reset_input()

func _on_interaction(target: Dictionary) -> void:
	if transitioning or App.current_context() != &"exploration" or $SceneHost.get_child_count() != 1:
		return
	var region: Node = $SceneHost.get_child(0)
	if not region.has_method("choose_target") or region.choose_target().get("id", "") != target.get("id", ""):
		return
	if target.get("kind") == "exit":
		_transition_to(target["target_scene"], target["target_spawn"])
		return
	if GameSession.mark_inspected(target["id"]) != OK:
		return
	_reading_target = target.duplicate(true)
	_reset_movement()
	App.push_context(&"dialogue")
	if is_instance_valid(reading_panel):
		reading_panel.queue_free()
	if target["kind"] == "npc" and ContentDB.dialogue_entry(target["id"], GameSession.state).is_empty() and ContentDB.world_npc(GameSession.state, target["id"]).get("error", ERR_INVALID_DATA) == OK:
		reading_panel = SocialDialoguePanel.new()
		reading_panel.name = "ReadingPanel"
		reading_panel.theme = ui_theme
		reading_panel.target_id = target["id"]
		reading_panel.close_requested.connect(_close_reading)
		$UIRoot.add_child(reading_panel)
		interaction_hint.text = ""
		return
	if not ContentDB.dialogue_entry(target["id"], GameSession.state).is_empty():
		reading_panel = DialoguePanel.new()
		reading_panel.name = "ReadingPanel"
		reading_panel.theme = ui_theme
		reading_panel.target_id = target["id"]
		reading_panel.close_requested.connect(_close_reading)
		reading_panel.activity_requested.connect(_open_activity)
		$UIRoot.add_child(reading_panel)
		interaction_hint.text = ""
		return
	reading_panel = PanelContainer.new()
	reading_panel.name = "ReadingPanel"
	reading_panel.theme = ui_theme
	reading_panel.position = Vector2(12, 172)
	reading_panel.size = Vector2(616, 176)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	reading_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = tr(target["name_key"])
	heading.add_theme_font_size_override("font_size", 18)
	box.add_child(heading)
	var body := Label.new()
	body.text = tr(target["text_key"])
	body.custom_minimum_size = Vector2(580, 72)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	box.add_child(body)
	var hint := Label.new()
	hint.text = tr("UI_CLOSE_READING")
	hint.add_theme_font_size_override("font_size", 14)
	box.add_child(hint)
	$UIRoot.add_child(reading_panel)
	interaction_hint.text = ""

func _close_reading() -> void:
	if not is_instance_valid(reading_panel) or not reading_panel.visible:
		return
	reading_panel.hide()
	_reading_target.clear()
	if App.current_context() == &"dialogue":
		App.pop_context()
	_reset_movement()

func _open_activity(activity: String) -> void:
	if transitioning or App.current_context() not in [&"exploration", &"dialogue"]:
		return
	if not activity in DialogueCatalog.ACTIVITIES:
		return
	if activity == "@battle":
		_start_story_battle()
		return
	_activity_from_dialogue = App.current_context() == &"dialogue"
	_activity_initial_state = GameSession.state.to_dict()
	if _activity_from_dialogue:
		reading_panel.hide()
	_reset_movement()
	App.push_context(&"codex")
	if is_instance_valid(activity_panel): activity_panel.queue_free()
	activity_panel = ActivityPanel.new()
	activity_panel.theme = ui_theme
	activity_panel.activity = activity
	activity_panel.onboarding = reading_panel is ProloguePanel and _activity_from_dialogue
	activity_panel.close_requested.connect(_close_activity)
	$UIRoot.add_child(activity_panel)

func _close_activity() -> void:
	if not is_instance_valid(activity_panel) or not activity_panel.visible: return
	GameSession.cancel_original_handover(activity_panel.handover_preview.get("token", ""))
	activity_panel.hide()
	if App.current_context() == &"codex": App.pop_context()
	if _activity_from_dialogue and is_instance_valid(reading_panel):
		reading_panel.show()
		if _activity_initial_state != GameSession.state.to_dict():
			reading_panel.go_to("@entry")
		else: reading_panel.refresh()
	_activity_from_dialogue = false
	_reset_movement()

func _open_martial() -> void:
	if transitioning or App.current_context() != &"exploration" or GameSession.combat_active(): return
	var configuration: Dictionary = GameSession.martial_configuration()
	if not configuration["error"].is_empty():
		status.text = "武学数据无效；未改变当前配置。"
		return
	_reset_movement()
	App.push_context(&"codex")
	if is_instance_valid(martial_panel): martial_panel.queue_free()
	martial_panel = MartialPanel.new()
	martial_panel.configure(configuration["state"], ContentDB.martial_definitions())
	martial_panel.closed.connect(_close_martial)
	martial_panel.loadout_submitted.connect(func(loadout: Dictionary) -> void:
		var error: Error = GameSession.set_martial_loadout(loadout)
		martial_panel.set_message("已应用；退出后F5存档。" if error == OK else "无法应用；当前战斗或熟练状态已改变。"))
	$UIRoot.add_child(martial_panel)

func _close_martial() -> void:
	if not is_instance_valid(martial_panel) or not martial_panel.visible: return
	martial_panel.hide()
	if App.current_context() == &"codex": App.pop_context()
	_reset_movement()

func _open_world(npc_id: String = "") -> void:
	if transitioning or GameSession.combat_active() or App.current_context() not in [&"exploration", &"dialogue"]: return
	if App.current_context() == &"dialogue" and (not reading_panel is DialoguePanel or npc_id.is_empty()): return
	if not npc_id.is_empty() and not ContentDB.can_reach_world_npc(GameSession.state, npc_id): return
	if $SceneHost.get_child_count() != 1: return
	_reset_movement()
	var region: Node = $SceneHost.get_child(0)
	GameSession.update_player_position(region.player_position)
	GameSession.state.player_state["facing"] = region.player.facing
	_world_from_dialogue = App.current_context() == &"dialogue"
	if _world_from_dialogue: reading_panel.hide()
	App.push_context(&"codex")
	if is_instance_valid(world_panel): world_panel.queue_free()
	world_panel = WorldPanel.new()
	world_panel.theme = ui_theme
	world_panel.npc_id = npc_id
	world_panel.closed.connect(_close_world)
	$UIRoot.add_child(world_panel)

func _close_world() -> void:
	if not is_instance_valid(world_panel) or not world_panel.visible: return
	GameSession.cancel_world_action(world_panel.preview.get("token", ""))
	world_panel.hide()
	if App.current_context() == &"codex": App.pop_context()
	if _world_from_dialogue and is_instance_valid(reading_panel):
		reading_panel.show()
		if not ContentDB.can_reach_world_npc(GameSession.state, world_panel.npc_id): _close_reading()
		else: reading_panel.refresh()
	_world_from_dialogue = false
	_reset_movement()

func _start_story_battle() -> void:
	if App.current_context() != &"dialogue" or $SceneHost.get_child_count() != 1: return
	var region: Node = $SceneHost.get_child(0)
	GameSession.update_player_position(region.player_position)
	GameSession.state.player_state["facing"] = region.player.facing
	var prepared: Dictionary = GameSession.begin_story_encounter()
	if prepared["error"] != OK:
		reading_panel.feedback.text = tr("INV_COMMAND_FAILED")
		return
	_story_token = prepared["token"]
	_close_reading()
	App.push_context(&"battle")
	$SceneHost.process_mode = Node.PROCESS_MODE_DISABLED
	$SceneHost.hide()
	$UIRoot.hide()
	_story_layer = CanvasLayer.new()
	_story_layer.layer = 3
	add_child(_story_layer)
	story_battle_screen = StoryBattleScreen.new()
	story_battle_screen.battle = prepared["battle"]
	story_battle_screen.reveal_intent = prepared["reveal"]
	story_battle_screen.ferry_deployment = prepared["ferry"]
	story_battle_screen.message = tr("INV_RESCUE_CHANGED")
	story_battle_screen.settlement_requested.connect(_settle_story_battle)
	story_battle_screen.retry_requested.connect(_retry_story_battle)
	story_battle_screen.exit_requested.connect(_abort_story_battle)
	_story_layer.add_child(story_battle_screen)

func _settle_story_battle() -> void:
	var result: Dictionary = GameSession.finish_story_encounter(_story_token)
	if result["error"] == OK: _close_story_battle()
	else: story_battle_screen.message = tr("INV_COMMAND_FAILED")

func _retry_story_battle() -> void:
	if GameSession.retry_story_encounter(_story_token) == OK:
		story_battle_screen.board.reset_presentation()
		story_battle_screen.actor_changed()
	else: story_battle_screen.message = tr("INV_COMMAND_FAILED")

func _abort_story_battle() -> void:
	if GameSession.abort_story_encounter(_story_token) == OK: _close_story_battle()
	else: story_battle_screen.message = tr("INV_COMMAND_FAILED")

func _close_story_battle() -> void:
	_story_layer.hide()
	_story_layer.process_mode = Node.PROCESS_MODE_DISABLED
	_story_layer.queue_free()
	_story_token = ""
	$SceneHost.process_mode = Node.PROCESS_MODE_INHERIT
	$SceneHost.show()
	$UIRoot.show()
	App.reset_contexts()
	_reset_movement()
	if is_instance_valid(reading_panel) and reading_panel is DialoguePanel and ContentDB.can_reach_world_npc(GameSession.state, reading_panel.target_id):
		_reading_target = {"id":reading_panel.target_id}
		App.push_context(&"dialogue")
		reading_panel.show()
		reading_panel.go_to("@entry")
	else:
		status.text = tr("WORLD_STORY_RETURN")

func _transition_to(scene_id: String, spawn_id: String) -> void:
	if transitioning:
		return
	var spawn: Vector2 = ContentDB.get_spawn_position(scene_id, spawn_id)
	if not ContentDB.has_spawn(scene_id, spawn_id) or not ContentDB.is_safe_world_position(scene_id, spawn, GameSession.state):
		status.text = tr("UI_EXIT_INVALID")
		_reset_movement()
		return
	var candidate: Node = _prepare_region(scene_id)
	if candidate == null:
		status.text = tr("UI_EXIT_INVALID")
		return
	var previous: GameState = GameState.from_dict(GameSession.state.to_dict())
	transitioning = true
	_reset_movement()
	App.push_context(&"system_menu")
	interaction_hint.text = ""
	var fade := create_tween()
	fade.tween_property(transition_cover, "modulate:a", 1.0, 0.12)
	await fade.finished
	# Stop old region processing before changing the authoritative location.
	for child in $SceneHost.get_children():
		child.set_physics_process(false)
	var result: Error = GameSession.enter_region(scene_id, spawn_id)
	if result == OK:
		result = _enter_yard(candidate)
	else:
		candidate.free()
	if result != OK:
		GameSession.replace_state(previous)
		status.text = tr("UI_EXIT_INVALID")
		for child in $SceneHost.get_children():
			child.set_physics_process(true)
			if child.get("camera") is Camera2D:
				child.camera.make_current()
	else:
		App.push_context(&"system_menu")
	fade = create_tween()
	fade.tween_property(transition_cover, "modulate:a", 0.0, 0.12)
	await fade.finished
	if App.current_context() == &"system_menu":
		App.pop_context()
	transitioning = false
	_reset_movement()

func _show_pause() -> void:
	if transitioning or App.current_context() != &"exploration":
		return
	_reset_movement()
	App.push_context(&"system_menu")
	_render_pause()

func _render_pause() -> void:
	_menu_kind = &"pause"
	_pending_slot = ""
	var box := _new_menu(tr("UI_PAUSED"))
	menu.position.y = 22
	box.add_theme_constant_override("separation", 4)
	_button(box, tr("UI_RESUME"), _resume, true)
	_button(box, tr("UI_SAVE"), _save_game)
	_button(box, tr("UI_MANUAL_SAVE"), _show_save_slots)
	_button(box, tr("UI_LOAD"), _show_load_slots)
	_button(box, tr("UI_FULLSCREEN"), _toggle_fullscreen)
	_button(box, tr("UI_TITLE_RETURN"), _return_to_title)

func _return_to_title() -> void:
	_close_reading()
	for child in $SceneHost.get_children():
		$SceneHost.remove_child(child)
		child.queue_free()
	$UIRoot/Backdrop.show()
	_show_title()

func _resume() -> void:
	menu.hide()
	_menu_kind = &""
	_pending_slot = ""
	App.pop_context()
	_reset_movement()

func _save_game(slot: String = "quick") -> Error:
	if transitioning or App.current_context() not in [&"exploration", &"system_menu"] or $SceneHost.get_child_count() != 1:
		return ERR_UNAVAILABLE
	# A future-version backup is data too: the UI must not overwrite its slot.
	if not SaveService.slot_summary(slot).get("can_overwrite", false):
		status.text = tr("UI_SLOT_NEWER")
		return ERR_UNAVAILABLE
	if $SceneHost.get_child_count() == 1:
		GameSession.update_player_position($SceneHost.get_child(0).player_position)
		var region: Node = $SceneHost.get_child(0)
		if region.get("player") is CharacterBody2D:
			GameSession.state.player_state["facing"] = region.player.facing
	var result := SaveService.save_game(slot, GameSession.state)
	status.text = tr("UI_SAVE_SLOT_OK") % _slot_name(slot) if result == OK else tr("UI_SAVE_FAILED") % error_string(result)
	return result

func _load_game(slot: String = "quick") -> void:
	if GameSession.story_encounter_active(): return
	if transitioning:
		return
	# Explicit UI selection may recover this slot's backup, never another slot.
	var result := SaveService.load_game(slot, false)
	if result.get("error", FAILED) == OK:
		var loaded: GameState = result["state"]
		if not ContentDB.has_spawn(loaded.scene_id, loaded.spawn_id):
			status.text = tr("UI_INVALID_SCENE")
			return
		var candidate: Node = _prepare_region(loaded.scene_id)
		if candidate == null:
			status.text = tr("UI_INVALID_SCENE")
			return
		var previous: GameState = GameSession.state
		if GameSession.replace_state(loaded) != OK:
			candidate.free()
			status.text = tr("UI_INVALID_SCENE")
			return
		_close_reading()
		if _enter_yard(candidate) != OK:
			GameSession.replace_state(previous)
			return
		var recovered_position: bool = status.text == tr("UI_SPAWN_RECOVERED")
		status.text = tr("UI_LOAD_SLOT_OK") % [_slot_name(slot), _source_name(str(result.get("source", "primary")))]
		if recovered_position:
			status.text += " · " + tr("UI_POSITION_RECOVERED_SHORT")
	else:
		status.text = tr("UI_SLOT_LOAD_FAILED") % [_slot_name(slot), _slot_error(result["error"])]

func _slot_name(slot: String) -> String:
	if slot == "quick":
		return tr("UI_QUICK_SLOT")
	if slot.begins_with("manual_"):
		return tr("UI_MANUAL_SLOT") % int(slot.trim_prefix("manual_"))
	return tr("UI_AUTO_SLOT") % int(slot.trim_prefix("auto_"))

func _source_name(source: String) -> String:
	match source:
		"primary": return tr("UI_SOURCE_PRIMARY")
		"rollback": return tr("UI_SOURCE_ROLLBACK")
		"backup": return tr("UI_SOURCE_BACKUP")
		_: return source

func _slot_error(error: int) -> String:
	match error:
		ERR_FILE_NOT_FOUND: return tr("UI_SLOT_EMPTY")
		ERR_UNAVAILABLE: return tr("UI_SLOT_NEWER")
		_: return tr("UI_SLOT_DAMAGED")

func _slot_caption(summary: Dictionary, for_save: bool = false) -> String:
	var name: String = _slot_name(summary["slot"])
	if for_save and not summary.get("can_overwrite", false):
		return name + " · " + tr("UI_SLOT_NEWER")
	if not summary["exists"]:
		return name + " · " + tr("UI_SLOT_EMPTY")
	if not summary["can_load"]:
		return name + " · " + _slot_error(summary["error"])
	var definition: Dictionary = ContentDB.get_scene_definition(summary["scene_id"])
	var location: String = tr(definition["name_key"]) if not definition.is_empty() else tr("UI_UNKNOWN_LOCATION")
	var stamp: String = str(summary["created_at_utc"]).replace("T", " ").replace("\n", " ").left(16)
	var recovered: String = " · " + _source_name(summary["source"]) if summary["source"] != "primary" else ""
	return name + recovered + "\n" + stamp + " UTC · " + location.left(16)

func _show_save_slots() -> void:
	if $SceneHost.get_child_count() != 1 or App.current_context() != &"system_menu":
		return
	_slot_origin = &"pause"
	_show_slot_list(&"save_slots")

func _show_load_slots() -> void:
	if App.current_context() != &"system_menu":
		return
	_slot_origin = &"pause" if $SceneHost.get_child_count() == 1 else &"title"
	_show_slot_list(&"load_slots")

func _show_slot_list(kind: StringName, page: int = 0, focus_slot: String = "", notice: String = "") -> void:
	_menu_kind = kind
	_pending_slot = ""
	slot_entries.clear()
	slot_buttons.clear()
	var summaries: Array[Dictionary] = SaveService.list_slot_summaries()
	if kind == &"load_slots":
		for summary: Dictionary in summaries:
			if summary["slot"] == "quick":
				slot_entries.append(summary)
	for summary: Dictionary in summaries:
		if summary["slot"].begins_with("manual_") or (kind == &"load_slots" and summary["slot"].begins_with("auto_") and summary["exists"]):
			slot_entries.append(summary)
	var pages: int = maxi(1, ceili(float(slot_entries.size()) / SLOT_PAGE_SIZE))
	_slot_page = clampi(page, 0, pages - 1)
	var box := _new_menu(tr("UI_MANUAL_SAVE") if kind == &"save_slots" else tr("UI_LOAD"))
	menu.position = Vector2(16, 8)
	menu.size = Vector2(608, 296)
	var margin: MarginContainer = box.get_parent()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	box.add_theme_constant_override("separation", 4)
	var hint := Label.new()
	hint.text = tr("UI_SLOT_PAGE_HINT") % [_slot_page + 1, pages]
	hint.add_theme_font_size_override("font_size", 14)
	box.add_child(hint)
	var preferred: Button
	for index in range(_slot_page * SLOT_PAGE_SIZE, mini((_slot_page + 1) * SLOT_PAGE_SIZE, slot_entries.size())):
		var summary: Dictionary = slot_entries[index]
		var slot: String = summary["slot"]
		var callback: Callable = _request_save_slot.bind(slot) if kind == &"save_slots" else _load_game.bind(slot)
		var button := _button(box, _slot_caption(summary, kind == &"save_slots"), callback)
		button.name = "Slot_" + slot
		button.set_meta("slot", slot)
		button.add_theme_font_size_override("font_size", 14)
		button.custom_minimum_size.y = 40
		button.clip_text = true
		button.disabled = not summary["can_overwrite"] if kind == &"save_slots" else not summary["can_load"]
		slot_buttons.append(button)
		if not button.disabled and (preferred == null or slot == focus_slot):
			preferred = button
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	box.add_child(navigation)
	var previous := Button.new()
	previous.name = "SlotPrevious"
	previous.text = tr("UI_PREVIOUS_PAGE")
	previous.disabled = _slot_page == 0
	previous.pressed.connect(func() -> void:
		get_viewport().set_input_as_handled()
		_show_slot_list(kind, _slot_page - 1))
	navigation.add_child(previous)
	var next := Button.new()
	next.name = "SlotNext"
	next.text = tr("UI_NEXT_PAGE")
	next.disabled = _slot_page + 1 >= pages
	next.pressed.connect(func() -> void:
		get_viewport().set_input_as_handled()
		_show_slot_list(kind, _slot_page + 1))
	navigation.add_child(next)
	var back := Button.new()
	back.name = "SlotBack"
	back.text = tr("UI_BACK")
	back.pressed.connect(_menu_back)
	navigation.add_child(back)
	if preferred == null:
		preferred = next if not next.disabled else back
	_focus_later(preferred)
	status.text = notice if not notice.is_empty() else tr("UI_SLOT_SAVE_HELP" if kind == &"save_slots" else "UI_SLOT_LOAD_HELP")

func _request_save_slot(slot: String) -> void:
	if _menu_kind != &"save_slots" or not slot.begins_with("manual_") or not SaveService.is_valid_slot(slot):
		return
	var summary: Dictionary = SaveService.slot_summary(slot)
	if not summary["can_overwrite"]:
		status.text = tr("UI_SLOT_NEWER")
		return
	if not summary["exists"]:
		_save_game(slot)
		_show_slot_list(&"save_slots", _slot_page, slot, status.text)
		return
	_pending_slot = slot
	_menu_kind = &"overwrite"
	var box := _new_menu(tr("UI_OVERWRITE_TITLE") % _slot_name(slot))
	menu.position = Vector2(60, 62)
	menu.size = Vector2(520, 208)
	var explanation := Label.new()
	explanation.text = tr("UI_OVERWRITE_HELP") + "\n" + _slot_caption(summary)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size.x = 480
	explanation.add_theme_font_size_override("font_size", 14)
	box.add_child(explanation)
	var cancel := _button(box, tr("UI_CANCEL"), _menu_back, true)
	cancel.name = "OverwriteCancel"
	var confirm := _button(box, tr("UI_OVERWRITE_CONFIRM"), _confirm_overwrite)
	confirm.name = "OverwriteConfirm"

func _confirm_overwrite() -> void:
	if _menu_kind != &"overwrite" or _pending_slot.is_empty():
		return
	var slot: String = _pending_slot
	_save_game(slot)
	_show_slot_list(&"save_slots", _slot_page, slot, status.text)

func _menu_back() -> void:
	get_viewport().set_input_as_handled()
	match _menu_kind:
		&"overwrite":
			_show_slot_list(&"save_slots", _slot_page, _pending_slot, tr("UI_OVERWRITE_CANCELLED"))
		&"save_slots", &"load_slots":
			if _slot_origin == &"title":
				_show_title()
			else:
				_render_pause()
		&"pause":
			_resume()

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _input(event: InputEvent) -> void:
	if transitioning:
		get_viewport().set_input_as_handled()
		return
	if App.current_context() == &"codex" and is_instance_valid(world_panel) and world_panel.visible:
		world_panel.handle_input(event)
		return
	if event.is_action_pressed("open_world") and not event.is_echo() and App.current_context() == &"dialogue" and reading_panel is DialoguePanel:
		get_viewport().set_input_as_handled()
		_open_world(reading_panel.target_id)
		return
	if App.current_context() == &"codex" and is_instance_valid(martial_panel) and martial_panel.visible:
		get_viewport().set_input_as_handled()
		martial_panel.handle_input(event)
		return
	if App.current_context() == &"codex" and is_instance_valid(activity_panel) and activity_panel.visible:
		activity_panel.handle_input(event)
		return
	if App.current_context() == &"system_menu" and is_instance_valid(menu) and menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			if not event.is_echo():
				_menu_back()
			return
		if event.is_echo() and event.is_action_pressed("confirm", true):
			get_viewport().set_input_as_handled()
			return
	if App.current_context() == &"dialogue" and is_instance_valid(reading_panel) and reading_panel.visible:
		if reading_panel.has_method("handle_input"):
			reading_panel.handle_input(event)
			return
		if event.is_action_pressed("confirm") or event.is_action_pressed("cancel") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			if not event.is_echo():
				_close_reading()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or transitioning or App.current_context() == &"battle":
		return
	if event.is_action_pressed("open_world") and App.current_context() == &"exploration":
		get_viewport().set_input_as_handled()
		_open_world()
		return
	if event.is_action_pressed("open_martial") and App.current_context() == &"exploration":
		get_viewport().set_input_as_handled()
		_open_martial()
		return
	if event.is_action_pressed("open_codex") and App.current_context() == &"exploration":
		get_viewport().set_input_as_handled()
		_open_activity("@journal")
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("cancel"):
		if App.current_context() == &"exploration":
			_show_pause()
		elif App.current_context() == &"system_menu" and $SceneHost.get_child_count() > 0:
			_resume()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_save") and App.current_context() == &"exploration":
		_save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dev_toggle") and OS.is_debug_build():
		App.debug_enabled = not App.debug_enabled
		debug_label.visible = App.debug_enabled

func _process(_delta: float) -> void:
	var controls_at_top := false
	objective_label.visible = App.current_context() == &"exploration"
	region_label.visible = App.current_context() == &"exploration"
	if App.current_context() == &"exploration" and $SceneHost.get_child_count() == 1:
		var region: Node = $SceneHost.get_child(0)
		var clock: Dictionary = ContentDB.world_time(GameSession.state)
		region_label.text = tr(ContentDB.get_scene_definition(GameSession.state.scene_id)["name_key"]) + " · " + tr("WORLD_CLOCK") % [clock.get("day", 1), tr(clock.get("label", "WORLD_TIME_0"))] + " · H " + tr("WORLD_TITLE")
		var guidance: Dictionary = ObjectiveGuide.project(GameSession.state)
		objective_label.text = tr(guidance["key"]) + "  ·  J " + tr("INV_CODEX_TITLE") + " · M武学"
		for destination: Dictionary in region.definition.get("interactions", []):
			if destination["id"] != guidance["target"]: continue
			var offset: Vector2 = Vector2(destination["position"][0], destination["position"][1]) - region.player_position
			var direction := "GUIDE_NEAR" if offset.length() < 58 else ("GUIDE_EAST" if offset.x > 0 else "GUIDE_WEST") if absf(offset.x) > absf(offset.y) else ("GUIDE_SOUTH" if offset.y > 0 else "GUIDE_NORTH")
			objective_label.text += "\n" + tr(direction) + " · " + tr(destination["name_key"]) + " · " + tr("GUIDE_FREE")
		var target: Variant = region.get("selected_target")
		interaction_hint.text = tr("UI_INTERACT_PROMPT") % tr(target["name_key"]) if target is Dictionary and not target.is_empty() else ""
		if region.get("player") is CharacterBody2D:
			var screen_position: Vector2 = region.player.get_global_transform_with_canvas().origin
			controls_at_top = screen_position.y > 278
	else:
		interaction_hint.text = ""
	# Keep the avatar and its feet visible even at the map's lower camera limit.
	controls_backdrop.position.y = 48 if controls_at_top else 310
	status.position.y = 53 if controls_at_top else 315
	interaction_hint.position.y = 104 if controls_at_top else 286
	objective_label.position.y = 235 if controls_at_top else 35
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
	# This smoke covers movement; the separate onboarding test covers New Game.
	GameSession.start_new_game()
	_enter_yard()
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().physics_frame
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
	print("EXPLORATION_SMOKE_PASS scene=", GameSession.state.scene_id, " movement=ok platform=offline connected_pads=", Input.get_connected_joypads().size())
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
