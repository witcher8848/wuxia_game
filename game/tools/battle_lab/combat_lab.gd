extends Node
const Combat = preload("res://game/domain/battle/combat_encounter.gd")
const Screen = preload("res://game/presentation/battle/battle_screen.gd")
var battle: CombatEncounter
var screen: Node2D
var startup_error := ""


func _ready() -> void:
	start_scenario("eliminate")


func start_scenario(kind: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/tools/battle_lab/combat_encounter.json"))
	data["skill_definitions"] = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
	if kind == "escape": data["objective"] = {"kind":"escape", "unit_id":"CHAR_PROTAGONIST", "cell":[9,7]}
	var candidate := Combat.new()
	startup_error = candidate.configure(data)
	if not startup_error.is_empty(): push_error(startup_error); return
	battle = candidate
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = Screen.new()
	screen.battle = battle
	screen.exit_requested.connect(func() -> void: get_tree().quit())
	screen.scenario_requested.connect(start_scenario)
	add_child(screen)
