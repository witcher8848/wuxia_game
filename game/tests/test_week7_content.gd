extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK7_CONTENT_FAIL ", label)

func _run() -> void:
	await process_frame
	var packed := FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed, "pack without source overlay")
	var content: Node = load("res://game/core/services/content_db.gd").new()
	var bootstrap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/bootstrap.json"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/world_state.json"))
	check(content.load_definitions(bootstrap) == OK, "complete registered world loads")
	var saved: Dictionary = content.world_definitions()
	var state := GameState.new()
	state.scene_id = "SCENE_TOWN_STREET"
	state.spawn_id = "SPAWN_START"
	state.player_state["position"] = {"x":512.0,"y":384.0}
	var before := state.to_dict()
	var projection: Dictionary = content.exploration_view(state.scene_id, state)
	var bad_data: Array = []
	var bad := world.duplicate(true)
	bad["npcs"][0]["anchors"][1]["label"] = "WORLD_MISSING_TEXT"
	bad_data.append(bad)
	bad = world.duplicate(true)
	bad["npcs"][0]["anchors"][1]["position"] = [512,128]
	bad_data.append(bad)
	bad = world.duplicate(true)
	bad["npcs"][1]["schedule"][3] = 99
	bad_data.append(bad)
	bad_data.append([])
	for candidate: Variant in bad_data:
		check(content.load_definitions(bootstrap,null,null,null,null,candidate) == ERR_INVALID_DATA, "bad world reload fails atomically")
		check(content.world_definitions() == saved and content.exploration_view(state.scene_id,state) == projection, "failed reload retains world and exploration registry")
		check(not content.last_error.is_empty(), "failed reload has diagnostic")
		check(state.to_dict() == before, "registry validation changes no route")
	var bad_bootstrap := bootstrap.duplicate(true)
	bad_bootstrap["world_path"] = "res://game/content/data/../private.json"
	check(content.load_definitions(bad_bootstrap) == ERR_INVALID_DATA and content.world_definitions() == saved, "canonical world path enforced before publication")
	check(content.load_definitions(bootstrap) == OK and content.last_error.is_empty(), "valid reload clears diagnostic")
	for locale: String in ["zh_CN","en"]:
		TranslationServer.set_locale(locale)
		state.world_flags["INSPECTED_NPC_STREET_VENDOR"] = true
		for slot: int in 8:
			state.time_state["slot"] = slot
			var greeting: String = content.world_greeting(state,"NPC_STREET_VENDOR")
			check(not greeting.is_empty() and not greeting.contains("WORLD_"), "each time topic is translated "+locale+str(slot))
		check(content.people_entries(state).size() == 1 and not str(content.people_entries(state)).contains("WORLD_"), "people view is translated and acquaintance-only")
	var legacy := bootstrap.duplicate(true)
	legacy.erase("world_path")
	check(content.load_definitions(legacy) == OK and content.world_definitions().is_empty(), "old content registry need not declare a world")
	check(content.exploration_view(state.scene_id,state)["region"] == content.get_exploration_region(state.scene_id), "old content preserves static map behavior")
	check(content.prepare_world_action(state,"wait")["error"] == ERR_UNAVAILABLE, "old content cannot invent a time action")
	content.free()
	if failures.is_empty(): print("WEEK7_CONTENT_PASS checks=%d packed=%s" % [checks,str(packed)])
	else: printerr("WEEK7_CONTENT_FAILED ", failures)
	quit(0 if failures.is_empty() else 1)
