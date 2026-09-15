extends SceneTree
## Run with: godot --headless --path . --script res://game/tests/test_state_services.gd
## Real failures return exit 1 in debug and release builds; no assert() dependency.

const SaveScript = preload("res://game/persistence/save_service.gd")
const SessionScript = preload("res://game/core/services/game_session.gd")
const ContentScript = preload("res://game/core/services/content_db.gd")
const PlatformScript = preload("res://game/platform/offline/offline_platform_service.gd")
const IO = preload("res://game/persistence/save_file_io.gd")

var _failures: Array[String] = []
var _checks: int = 0
var _isolated_root: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_isolated_root = "user://tests/state_services_%d" % Time.get_ticks_usec()
	var saves: Node = SaveScript.new()
	saves.test_root = _isolated_root
	_test_state_and_session()
	_test_roundtrip_and_backup(saves)
	_test_future_schema(saves)
	_test_invalid_paths_and_state(saves)
	_test_rollback_and_auto(saves)
	_test_content()
	_test_offline_platform()
	saves.free()
	_remove_test_tree(_isolated_root)
	for failure: String in _failures:
		printerr("FAIL: " + failure)
	print("STATE_SERVICES: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_state_and_session() -> void:
	var state: GameState = GameState.new()
	_check(state.validate().is_empty(), "Default GameState validates")
	var data: Dictionary = state.to_dict()
	data["player_state"]["position"]["x"] = 999.0
	_check(state.player_state["position"]["x"] == 320.0, "Snapshot dictionaries are deep copies")
	data["time_state"]["slot"] = -1
	_check(GameState.from_dict(data) == null, "Invalid time is rejected")
	data["time_state"]["slot"] = 8
	_check(GameState.from_dict(data) == null, "Only the eight defined time slots are accepted")
	data = state.to_dict()
	data["player_state"]["hp"] = "twenty"
	_check(GameState.from_dict(data) == null, "Malformed player field is rejected")
	var session: Node = SessionScript.new()
	var first: GameState = session.start_new_game()
	var first_route: String = first.route_id
	var second: GameState = session.start_new_game()
	_check(first_route != second.route_id, "Each new game has a separate route ID")
	_check(session.replace_state(first) == OK, "A valid loaded route can replace the session")
	first.player_state["hp"] = 1
	_check(session.state.player_state["hp"] == 20, "Session owns its loaded state copy")
	_check(session.replace_state(null) == ERR_INVALID_DATA, "Null state cannot erase the route")
	session.free()


func _test_roundtrip_and_backup(saves: Node) -> void:
	var first: GameState = GameState.new()
	first.player_state["position"] = {"x": 111.0, "y": 77.0}
	first.world_flags["FACT_TEST_DOCUMENT"] = true
	first.quest_states["QUEST_TEST"] = {"status": "active"}
	first.evidence_states["EV_TEST"] = {"knowledge_state": "discovered", "holder_id": "CHAR_PROTAGONIST"}
	first.relationships["CHAR_TEST"] = {"trust": 3, "alignment": -1}
	first.playtime_seconds = 12.5
	_check(saves.save_game("manual_01", first) == OK, "First save writes a validated JSON file")
	var loaded: Dictionary = saves.load_game("manual_01")
	_check(loaded["error"] == OK and loaded["source"] == "primary", "Primary save loads")
	if loaded["error"] == OK:
		var restored: GameState = loaded["state"]
		_check(_same_json_data(restored.to_dict(), first.to_dict()), "All persistent partitions round-trip exactly")
	_check(String(saves.slot_path("manual_01")).begins_with(_isolated_root + "/"), "Tests write only their isolated root")
	var second: GameState = GameState.from_dict(first.to_dict())
	second.player_state["position"]["x"] = 222.0
	second.evidence_states["EV_TEST"]["holder_id"] = "CHAR_TEST"
	_check(saves.save_game("manual_01", second) == OK, "Second save retains the previous revision")
	_check(FileAccess.file_exists(saves.backup_path("manual_01")), "Per-slot .bak exists")
	_check(not FileAccess.file_exists(saves.slot_path("manual_01") + ".old"), "Committed write removes rollback file")
	_check(IO.write_text(saves.slot_path("manual_01"), "{broken json") == OK, "Corrupt-primary fixture is written")
	loaded = saves.load_game("manual_01")
	_check(loaded["error"] == OK and loaded["source"] == "backup", "Damaged primary explicitly falls back to backup")
	if loaded["error"] == OK:
		_check(_same_json_data(loaded["state"].to_dict(), first.to_dict()), "Recovery restores previous state, not a new blank game")
	_check(saves.save_game("manual_01", second) == OK, "Saving after corruption succeeds")
	var backup: Dictionary = IO.read_envelope(saves.backup_path("manual_01"))
	_check(backup["error"] == OK, "Damaged primary never replaces the good backup")


func _test_future_schema(saves: Node) -> void:
	var path: String = saves.slot_path("manual_01")
	var current: Dictionary = IO.read_envelope(path)
	if current["error"] != OK:
		_check(false, "Future-schema fixture requires an existing valid save")
		return
	var envelope: Dictionary = current["envelope"]
	envelope["schema_version"] = 999
	_check(IO.write_text(path, JSON.stringify(envelope)) == OK, "Future-schema fixture is written")
	var original_hash: String = FileAccess.get_sha256(path)
	_check(saves.load_game("manual_01")["error"] == ERR_UNAVAILABLE, "Newer schema is refused even with a valid old backup")
	_check(saves.save_game("manual_01", GameState.new()) == ERR_UNAVAILABLE, "Newer schema cannot be overwritten")
	_check(FileAccess.get_sha256(path) == original_hash, "Refused save preserves the newer file byte for byte")
	envelope["schema_version"] = 1.0e30
	_check(IO.write_text(path, JSON.stringify(envelope)) == OK, "Oversized future-schema fixture is written")
	_check(saves.load_game("manual_01")["error"] == ERR_UNAVAILABLE, "Oversized future schema cannot wrap around to an old version")


func _test_invalid_paths_and_state(saves: Node) -> void:
	for slot: String in ["../escape", "manual_01/../../escape", "user://escape", "manual_06", "", "manual_01.sav"]:
		_check(saves.save_game(slot, GameState.new()) == ERR_INVALID_PARAMETER, "Unsafe or unknown slot rejected: " + slot)
		_check(saves.load_game(slot)["error"] == ERR_INVALID_PARAMETER, "Unsafe slot load rejected: " + slot)
		_check(saves.slot_path(slot).is_empty(), "Unsafe slot has no resolved path: " + slot)
	for invalid_root: String in ["user://", "user://saves", "user://tests/../saves", "/tmp/save", "user://tests/a/b"]:
		saves.test_root = invalid_root
		_check(saves.save_game("quick", GameState.new()) == ERR_INVALID_PARAMETER, "Unsafe test root rejected: " + invalid_root)
	saves.test_root = _isolated_root
	var bad_state: GameState = GameState.new()
	bad_state.world_flags["BAD_RUNTIME_OBJECT"] = Vector2.ONE
	_check(saves.save_game("quick", bad_state) == ERR_INVALID_DATA, "Runtime objects cannot enter JSON saves")
	_check(saves.save_game("quick", null) == ERR_INVALID_DATA, "Null state save is rejected")
	_check(not FileAccess.file_exists(saves.slot_path("quick")), "Rejected saves do not create a primary file")


func _test_rollback_and_auto(saves: Node) -> void:
	var state: GameState = GameState.new()
	state.player_state["position"]["x"] = 333.0
	_check(saves.save_game("manual_02", state) == OK, "Rollback fixture saves")
	var path: String = saves.slot_path("manual_02")
	_check(IO.rename_file(path, path + ".old") == OK, "Interrupted commit fixture moves primary to .old")
	var restored: Dictionary = saves.load_game("manual_02")
	_check(restored["error"] == OK and restored["source"] == "rollback", "Interrupted commit recovers the rollback file")
	_check(saves.save_game("manual_02", state) == OK, "Next save repairs an interrupted commit")
	_check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".old"), "Repair leaves a validated primary")
	_check(saves.save_game("auto_01", state) == OK, "Automatic slot saves independently")
	var fallback: Dictionary = saves.load_game("manual_05")
	_check(fallback["error"] == OK and fallback["source"] == "auto_01", "Missing slot can recover with an explicitly named automatic slot")
	_check(not FileAccess.file_exists(saves.slot_path("manual_05")), "Automatic recovery does not silently overwrite manual slots")


func _test_content() -> void:
	var content: Node = ContentScript.new()
	_check(content.reload_content() == OK, "Bootstrap definitions and scene references validate")
	_check(content.get_scene_path("SCENE_TEST_YARD") == "res://game/presentation/exploration/test_yard.tscn", "Stable scene ID resolves to its resource")
	_check(content.has_spawn("SCENE_TEST_YARD", "SPAWN_START"), "Known spawn resolves")
	_check(not content.has_spawn("SCENE_TEST_YARD", "SPAWN_MISSING"), "Unknown spawn does not resolve")
	var file: FileAccess = FileAccess.open(ContentScript.BOOTSTRAP_PATH, FileAccess.READ)
	if file != null:
		var data: Dictionary = JSON.parse_string(file.get_as_text())
		file.close()
		var duplicate: Dictionary = data.duplicate(true)
		duplicate["scenes"].append(duplicate["scenes"][0].duplicate(true))
		_check(content.load_definitions(duplicate) == ERR_INVALID_DATA, "Duplicate scene IDs fail validation")
		var missing: Dictionary = data.duplicate(true)
		missing["start_spawn_id"] = "SPAWN_MISSING"
		_check(content.load_definitions(missing) == ERR_INVALID_DATA, "Missing spawn reference fails validation")
		_check(content.has_spawn("SCENE_TEST_YARD", "SPAWN_START"), "Failed reload preserves the last valid content registry")
	content.free()


func _test_offline_platform() -> void:
	var platform: Node = PlatformScript.new()
	var capabilities: Dictionary = platform.initialize()
	for capability: String in ["achievements", "stats", "overlay", "cloud"]:
		_check(capabilities[capability] == false, "Offline capability unavailable: " + capability)
	_check(not platform.is_available(), "Offline adapter never claims Steam availability")
	platform.unlock_achievement("ACH_TEST")
	platform.set_stat("STAT_TEST", 1.0)
	platform.store_stats()
	platform.open_store_page()
	platform.shutdown()
	platform.free()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _same_json_data(left: Dictionary, right: Dictionary) -> bool:
	# JSON has one number type: Godot decodes integers as floats. Compare every
	# nested field after the same encoding/decoding step, not Variant type tags.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _remove_test_tree(path: String) -> void:
	# Cleanup is restricted to the unique directory this test created.
	if path != _isolated_root and not path.begins_with(_isolated_root + "/"):
		_check(false, "Test cleanup refused a path outside its own directory")
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_test_tree(path.path_join(child))
	for child: String in directory.get_files():
		IO.remove_file(path.path_join(child))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
