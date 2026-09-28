extends SceneTree
## External script: execute real exported main scene and rules, not source fixtures.
const AI = preload("res://game/domain/battle/battle_ai.gd")
const Grid = preload("res://game/domain/battle/battle_grid.gd")


func _initialize() -> void: _run.call_deferred()


func _run() -> void:
	if not FileAccess.file_exists("res://project.binary"):
		printerr("COMBAT_PACK_FAIL exported pack required"); quit(1); return
	var lab: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(lab)
	lab.screen.auto_ai = false
	await process_frame
	var turns := 0
	while lab.battle.outcome == "ongoing" and turns < 100:
		turns += 1
		var actor: String = lab.battle.current_actor_id()
		var plan: Dictionary = AI.plan(lab.battle, actor, lab.battle.unit(actor)["team"] == "ally")
		if plan["destination"] != Grid.cell_of(lab.battle.unit(actor)):
			if not lab.battle.move_actor(actor, plan["destination"], lab.battle.revision)["ok"]:
				printerr("COMBAT_PACK_FAIL movement"); quit(1); return
		if not lab.battle.perform_action(actor, plan["skill_id"], plan["target"], lab.battle.revision)["ok"]:
			printerr("COMBAT_PACK_FAIL action"); quit(1); return
	if lab.battle.outcome != "victory" or not lab.battle.retry():
		printerr("COMBAT_PACK_FAIL victory/retry"); quit(1); return
	lab.start_scenario("escape")
	if lab.battle.objective["kind"] != "escape":
		printerr("COMBAT_PACK_FAIL alternative objective"); quit(1); return
	print("COMBAT_PACK_PASS victory_turns=", turns, " retry=ok escape_setup=ok platform=macOS-host (not Windows hardware)")
	root.remove_child(lab)
	lab.queue_free()
	await process_frame
	quit(0)
