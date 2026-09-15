extends Node

const CONTEXTS := [&"exploration", &"dialogue", &"codex", &"battle", &"system_menu"]
var contexts: Array[StringName] = [&"exploration"]
var debug_enabled: bool = false

func _ready() -> void:
	debug_enabled = OS.is_debug_build() and "--dev" in OS.get_cmdline_user_args()
	# Control nodes consume the standard UI actions, independent of gameplay context.
	for mapping in [["ui_up", "move_up"], ["ui_down", "move_down"], ["ui_left", "move_left"], ["ui_right", "move_right"], ["ui_accept", "confirm"], ["ui_cancel", "cancel"]]:
		InputMap.action_erase_events(mapping[0])
		for event in InputMap.action_get_events(mapping[1]):
			if event is not InputEventMouseButton:
				InputMap.action_add_event(mapping[0], event)

func current_context() -> StringName:
	return contexts.back()

func push_context(context: StringName) -> void:
	if context in CONTEXTS:
		contexts.append(context)

func pop_context() -> void:
	if contexts.size() > 1:
		contexts.pop_back()

func reset_contexts() -> void:
	contexts.assign([&"exploration"])
