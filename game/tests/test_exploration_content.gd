extends SceneTree
## Real content/schema/state checks. No gameplay, hardware or usability claim.

const CONTENT = preload("res://game/core/services/content_db.gd")
const SESSION = preload("res://game/core/services/game_session.gd")
const SAVE = preload("res://game/persistence/save_service.gd")
const IO = preload("res://game/persistence/save_file_io.gd")
const EXPLORATION_PATH := "res://game/content/data/exploration.json"
const LOCALIZATION_PATH := "res://game/content/localization/exploration.csv"

var _checks: int = 0
var _failures: Array[String] = []
var _bootstrap: Dictionary = {}
var _exploration: Dictionary = {}
var _content: Node
var _isolated_root: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_isolated_root = "user://tests/exploration_content_%d" % Time.get_ticks_usec()
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_isolated_root)) == OK, "create isolated test directory")
	_bootstrap = _read_json(CONTENT.BOOTSTRAP_PATH)
	_exploration = _read_json(EXPLORATION_PATH)
	if _bootstrap.is_empty() or _exploration.is_empty():
		_finish()
		return
	_content = CONTENT.new()
	_check(_content.reload_content() == OK, "real bootstrap and exploration content load")
	if _content.content_version.is_empty():
		_finish()
		return
	_test_real_content()
	_test_bootstrap_validation()
	_test_region_validation()
	_test_transactional_file_reload()
	_test_session_and_save()
	_finish()


func _test_real_content() -> void:
	_check(_content.content_version == _bootstrap["content_version"], "content version comes from bootstrap")
	_check(_content.start_scene_id == "SCENE_TOWN_STREET" and _content.start_spawn_id == "SPAWN_START", "new game enters town start spawn")
	_check(_exploration["regions"].size() == 3, "week two has exactly three exploration regions")
	var npc_count: int = 0
	var kinds: Dictionary = {}
	var localized: Dictionary = _read_localization()
	for region: Dictionary in _exploration["regions"]:
		var scene_id: String = region["id"]
		_check(_content.get_exploration_region(scene_id) == region, "registered region matches source: " + scene_id)
		_check(ResourceLoader.exists(_content.get_scene_path(scene_id)), "region scene resource exists: " + scene_id)
		_check(localized.has(region["name_key"]), "region title is localized: " + scene_id)
		for spawn: String in region["spawns"]:
			var point: Vector2 = _content.get_spawn_position(scene_id, spawn)
			_check(_content.has_spawn(scene_id, spawn) and _content.is_safe_player_position(scene_id, point), "spawn has stable ID and safe feet: " + scene_id + "/" + spawn)
		for target: Dictionary in region["interactions"]:
			kinds[target["kind"]] = true
			_check(localized.has(target["name_key"]), "interaction name is localized: " + target["id"])
			if target["kind"] == "exit":
				_check(_content.has_spawn(target["target_scene"], target["target_spawn"]), "exit resolves registered destination: " + target["id"])
				_check(not _content.has_inspectable(target["id"]), "exit is not an inspected narrative fact: " + target["id"])
			else:
				_check(localized.has(target["text_key"]), "readable interaction text is localized: " + target["id"])
				_check(_content.has_inspectable(target["id"]), "readable target is registered: " + target["id"])
				if target["kind"] == "npc":
					npc_count += 1
		for obstacle: Dictionary in region["obstacles"]:
			if obstacle.has("label_key"):
				_check(localized.has(obstacle["label_key"]), "obstacle label is localized: " + obstacle["label_key"])
	_check(npc_count == 2 and kinds.size() == 3, "two NPC samples and NPC/document/exit interaction types")
	_check(_content.get_scene_path("SCENE_MISSING").is_empty(), "unknown scene has no path")
	_check(_content.get_exploration_region("SCENE_MISSING").is_empty(), "unknown region has no definition")
	_check(_content.get_spawn_position("SCENE_MISSING", "SPAWN_MISSING") == Vector2.INF, "unknown spawn is explicit nonfinite sentinel")
	_check(not _content.has_inspectable("NPC_MISSING"), "unknown inspection ID is rejected")
	_check(_content.get_spawn_position("SCENE_TEST_YARD", "SPAWN_START") == Vector2(320, 180), "legacy test-yard spawn still resolves")
	_check(not _content.is_walkable_position("SCENE_MISSING", Vector2.ZERO), "unknown region is never walkable")
	_check(not _content.is_safe_player_position("SCENE_MISSING", Vector2.ZERO), "unknown region never accepts player placement")
	_check(_content.is_walkable_position("SCENE_TOWN_STREET", Vector2(608, 352)) and not _content.is_safe_player_position("SCENE_TOWN_STREET", Vector2(608, 352)), "NPC interaction anchor is reachable but cannot contain player feet")
	_check(not _content.is_safe_player_position("SCENE_TOWN_STREET", Vector2(384, 352)), "document body cannot contain player feet")
	_check(_content.is_safe_player_position("SCENE_TOWN_STREET", Vector2(384, 192)), "exit trigger is not a physical blocker")
	_check(not _content.is_safe_player_position("SCENE_TOWN_STREET", Vector2.INF), "nonfinite player placement is rejected")
	for point: Vector2 in [Vector2.ZERO, Vector2(1280, 768), Vector2(100, 100), Vector2.INF, Vector2(NAN, 32)]:
		_check(not _content.is_walkable_position("SCENE_TOWN_STREET", point), "unsafe/nonfinite feet rejected: " + str(point))
	var copied: Dictionary = _content.get_exploration_region("SCENE_TOWN_STREET")
	copied["spawns"]["SPAWN_START"][0] = 0
	copied["interactions"][0]["text_key"] = "MUTATED"
	_check(_content.get_exploration_region("SCENE_TOWN_STREET") == _exploration["regions"][0], "region getter returns deep copy")
	var scene_copy: Dictionary = _content.get_scene_definition("SCENE_TOWN_STREET")
	scene_copy["spawn_ids"].clear()
	_check(_content.has_spawn("SCENE_TOWN_STREET", "SPAWN_START"), "scene getter returns deep copy")
	var source_bootstrap: Dictionary = _bootstrap.duplicate(true)
	var source_regions: Dictionary = _exploration.duplicate(true)
	_check(_content.load_definitions(source_bootstrap, source_regions) == OK, "explicit data registry loads")
	source_bootstrap["scenes"][1]["spawn_ids"].clear()
	source_regions["regions"][0]["spawns"]["SPAWN_START"][0] = 0
	_check(_content.has_spawn("SCENE_TOWN_STREET", "SPAWN_START") and _content.get_spawn_position("SCENE_TOWN_STREET", "SPAWN_START") == Vector2(512, 384), "published registry owns input dictionaries")


func _test_bootstrap_validation() -> void:
	for key: String in ["content_version", "start_scene_id", "start_spawn_id"]:
		var invalid: Dictionary = _bootstrap.duplicate(true)
		invalid[key] = " "
		_reject_bootstrap(invalid, "blank required bootstrap string: " + key)
	for scenes: Variant in [null, {}, [], [12]]:
		var invalid: Dictionary = _bootstrap.duplicate(true)
		invalid["scenes"] = scenes
		_reject_bootstrap(invalid, "malformed scene collection: " + str(scenes))
	var invalid: Dictionary = _bootstrap.duplicate(true)
	invalid["scenes"].append(invalid["scenes"][0].duplicate(true))
	_reject_bootstrap(invalid, "duplicate scene ID")
	for path: Variant in [null, "user://outside.tscn", "res://game/presentation/../outside.tscn", "res://game/presentation/missing.tscn", "res://game/presentation/main.gd"]:
		invalid = _bootstrap.duplicate(true)
		invalid["scenes"][0]["path"] = path
		_reject_bootstrap(invalid, "unsafe or absent scene path: " + str(path))
	for value: Variant in [[], ["SPAWN_START", "SPAWN_START"], ["wrong-prefix"], [null]]:
		invalid = _bootstrap.duplicate(true)
		invalid["scenes"][0]["spawn_ids"] = value
		_reject_bootstrap(invalid, "malformed registered spawn IDs")
	invalid = _bootstrap.duplicate(true)
	invalid["scenes"][0]["spawn_positions"] = {"SPAWN_MISSING": [32, 32]}
	_reject_bootstrap(invalid, "optional position for unknown spawn")
	invalid = _bootstrap.duplicate(true)
	invalid["scenes"][0]["name_key"] = " "
	_reject_bootstrap(invalid, "blank scene localization key")
	invalid = _bootstrap.duplicate(true)
	invalid["start_scene_id"] = "SCENE_MISSING"
	_reject_bootstrap(invalid, "missing start scene")
	invalid = _bootstrap.duplicate(true)
	invalid["start_spawn_id"] = "SPAWN_MISSING"
	_reject_bootstrap(invalid, "missing start spawn")
	invalid = _bootstrap.duplicate(true)
	invalid["editor_object"] = Vector2.ZERO
	_reject_bootstrap(invalid, "non-JSON object in bootstrap")
	for path: Variant in [12, "user://regions.json", "res://game/content/data/../outside.json", "res://game/content/data/missing.json", "res://game/content/data/bootstrap.txt"]:
		invalid = _bootstrap.duplicate(true)
		invalid["exploration_path"] = path
		_reject_bootstrap(invalid, "unsafe or absent exploration path: " + str(path))


func _test_region_validation() -> void:
	for malformed: Variant in [[], {"regions": []}, {"regions": {}}, {"regions": [false]}]:
		_reject_regions(malformed, "malformed region root: " + str(malformed))
	var invalid: Dictionary = _exploration.duplicate(true)
	invalid["regions"].append(invalid["regions"][0].duplicate(true))
	_reject_regions(invalid, "duplicate region")
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["id"] = "SCENE_UNKNOWN"
	_reject_regions(invalid, "unregistered region")
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["name_key"] = "WRONG_NAME_KEY"
	_reject_regions(invalid, "region name disagrees with scene registry")
	for size: Variant in [[639, 384], [640, 352], [641, 384], [8224, 384], [640, INF], [false, 384], [640]]:
		invalid = _exploration.duplicate(true)
		invalid["regions"][0]["size"] = size
		_reject_regions(invalid, "unsafe/non-grid region dimensions: " + str(size))
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["ground"] = "not-a-color"
	_reject_regions(invalid, "invalid ground color")
	for rectangle: Variant in [[0, 0, 0, 32], [0, 0, -32, 32], [0, 0, 31, 32], [-32, 0, 32, 32], [1280, 0, 32, 32], [32, 32, NAN, 32], [32, 32, 32], "invalid"]:
		invalid = _exploration.duplicate(true)
		invalid["regions"][0]["obstacles"][0]["rect"] = rectangle
		_reject_regions(invalid, "malformed/out-of-bounds obstacle: " + str(rectangle))
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["obstacles"][0]["kind"] = "trap"
	_reject_regions(invalid, "unknown obstacle kind")
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["spawns"].erase("SPAWN_START")
	_reject_regions(invalid, "missing registered spawn position")
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["spawns"]["SPAWN_UNREGISTERED"] = [512, 384]
	_reject_regions(invalid, "extra unregistered spawn")
	for point: Array in [[608, 352], [384, 352]]:
		invalid = _exploration.duplicate(true)
		invalid["regions"][0]["spawns"]["SPAWN_START"] = point
		_reject_regions(invalid, "spawn overlaps an NPC or document body")
	for point: Variant in [[128, 128], [0, 32], [513, 384], [32, NAN], [32, 32, 32], "invalid"]:
		invalid = _exploration.duplicate(true)
		invalid["regions"][0]["spawns"]["SPAWN_START"] = point
		_reject_regions(invalid, "blocked or malformed spawn position: " + str(point))
	invalid = _exploration.duplicate(true)
	invalid["regions"][1]["interactions"][0]["id"] = "NPC_STREET_VENDOR"
	_reject_regions(invalid, "duplicate interaction ID across maps")
	for field: String in ["id", "name_key", "text_key", "kind"]:
		invalid = _exploration.duplicate(true)
		invalid["regions"][0]["interactions"][0][field] = " "
		_reject_regions(invalid, "missing readable interaction field: " + field)
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["interactions"][0]["position"] = [128, 128]
	_reject_regions(invalid, "interaction point in building")
	for field: String in ["target_scene", "target_spawn"]:
		invalid = _exploration.duplicate(true)
		invalid["regions"][0]["interactions"][2][field] = "MISSING"
		_reject_regions(invalid, "broken exit destination: " + field)
	invalid = _exploration.duplicate(true)
	invalid["regions"][1]["interactions"].pop_back()
	_reject_regions(invalid, "one-way region with no route back")
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["interactions"].remove_at(2)
	_reject_regions(invalid, "region unreachable from start")
	invalid = _exploration.duplicate(true)
	# This wall leaves every individual point valid but separates the west exits
	# and document from the start. It therefore exercises flood-fill, not bounds.
	invalid["regions"][0]["obstacles"].append({"rect": [448, 0, 32, 768], "kind": "building"})
	_reject_regions(invalid, "valid individual points separated by impassable wall")
	invalid = _exploration.duplicate(true)
	# The sample NPC is surrounded by four other collision bodies on the
	# authored grid. Its center is geometrically reachable, but none of the
	# promised 32px standing points can actually accept the player's feet.
	for offset: Array in [[0, -32], [0, 32], [-32, 0], [32, 0]]:
		var blocker: Dictionary = invalid["regions"][0]["interactions"][0].duplicate(true)
		blocker["id"] = "NPC_APPROACH_BLOCKER_%d" % invalid["regions"][0]["interactions"].size()
		blocker["position"] = [608 + offset[0], 352 + offset[1]]
		invalid["regions"][0]["interactions"].append(blocker)
	_reject_regions(invalid, "readable target has no safe grid-aligned interaction approach")
	invalid = _exploration.duplicate(true)
	invalid["regions"][0]["runtime_object"] = Vector2.ONE
	_reject_regions(invalid, "runtime value cannot enter copied content registry")
	_check(_content.load_definitions(_bootstrap, _exploration) == OK and _content.last_error.is_empty(), "valid definitions recover after failures and clear diagnostic")


func _test_transactional_file_reload() -> void:
	var before: Dictionary = _snapshot()
	_check(_content.reload_content(_isolated_root.path_join("missing.json")) == ERR_FILE_CANT_OPEN, "missing bootstrap file fails explicitly")
	_check(_snapshot() == before and not _content.last_error.is_empty(), "missing file preserves active registry")
	var path: String = _isolated_root.path_join("invalid.json")
	for contents: String in ["{broken JSON", "[]", "{\"content_version\":\"mutated\"}"]:
		_check(IO.write_text(path, contents) == OK, "write isolated malformed bootstrap fixture")
		_check(_content.reload_content(path) != OK, "malformed bootstrap reload fails")
		_check(_snapshot() == before and not _content.last_error.is_empty(), "failed file reload preserves entire active registry")
	_check(_content.reload_content() == OK and _content.last_error.is_empty(), "production registry reload clears last error")


func _test_session_and_save() -> void:
	var content: Node = root.get_node("ContentDB")
	var session: Node = SESSION.new()
	var state: GameState = session.start_new_game()
	_check(state.validate().is_empty(), "new exploration game has valid serializable state")
	_check(state.scene_id == content.start_scene_id and state.spawn_id == content.start_spawn_id, "new game adopts configured scene and spawn")
	_check(_state_position(state) == content.get_spawn_position(state.scene_id, state.spawn_id), "new game starts at registered spawn coordinates")
	var first_route: String = state.route_id
	var original_time: Dictionary = state.time_state.duplicate(true)
	var original_partition: Dictionary = state.to_dict()
	for args: Array in [["SCENE_MISSING", "SPAWN_START"], ["SCENE_HOME_COURTYARD", "SPAWN_MISSING"], ["SCENE_TEST_YARD", "SPAWN_START"]]:
		_check(session.enter_region(args[0], args[1]) == ERR_INVALID_PARAMETER, "unusable exploration destination is refused")
		_check(session.state.to_dict() == original_partition, "failed region transition is transactional")
	for target: String in ["NPC_STREET_VENDOR", "DOC_STREET_NOTICE"]:
		_check(session.mark_inspected(target) == OK and session.is_inspected(target), "registered NPC/document inspection persists: " + target)
		var flags: Dictionary = state.world_flags.duplicate(true)
		_check(session.mark_inspected(target) == OK and state.world_flags == flags, "repeat inspection is idempotent: " + target)
	var before_invalid: Dictionary = state.to_dict()
	for target: String in ["EXIT_STREET_HOME", "NPC_UNKNOWN", "", "../../anything"]:
		_check(session.mark_inspected(target) == ERR_INVALID_PARAMETER and not session.is_inspected(target), "non-inspectable ID does not create world facts")
	_check(state.to_dict() == before_invalid, "invalid inspection leaves all state partitions unchanged")
	for trip in range(5):
		for destination: Array in [["SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN"], ["SCENE_TOWN_STREET", "SPAWN_FROM_HOME"], ["SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN"], ["SCENE_TOWN_STREET", "SPAWN_FROM_DOCK"]]:
			_check(session.enter_region(destination[0], destination[1]) == OK, "round trip %d resolves %s" % [trip + 1, destination[0]])
			_check(state.scene_id == destination[0] and state.spawn_id == destination[1] and _state_position(state) == content.get_spawn_position(destination[0], destination[1]), "region/spawn/position commit together")
	_check(state.time_state == original_time, "walking, reading and twenty transitions do not advance narrative time")
	_check(session.is_inspected("NPC_STREET_VENDOR") and session.is_inspected("DOC_STREET_NOTICE"), "inspected facts survive repeated region changes")
	_check(state.quest_states.is_empty() and state.evidence_states.is_empty() and state.relationships.is_empty(), "samples do not invent quest/evidence/relationship progress")
	_check(session.update_player_position(Vector2(800.5, 384.25)) == OK, "finite walking position can update")
	var safe_position: Dictionary = state.player_state["position"].duplicate(true)
	for point: Vector2 in [Vector2.INF, Vector2(NAN, 0)]:
		_check(session.update_player_position(point) == ERR_INVALID_PARAMETER and state.player_state["position"] == safe_position, "nonfinite position update leaves previous coordinates intact")
	state.player_state["facing"] = "left"
	var expected: Dictionary = state.to_dict()
	var saves: Node = SAVE.new()
	saves.test_root = _isolated_root
	_check(saves.save_game("manual_01", state) == OK, "exploration route writes through production save service")
	var loaded: Dictionary = saves.load_game("manual_01")
	_check(loaded["error"] == OK, "exploration save loads through envelope validation")
	if loaded["error"] == OK:
		_check(_same_json(loaded["state"].to_dict(), expected), "every exploration state partition survives JSON file round trip")
		_check(loaded["envelope"]["content_version"] == content.content_version, "save metadata records the currently loaded content version")
		var restored: Node = SESSION.new()
		_check(restored.replace_state(loaded["state"]) == OK, "fresh session restores saved exploration route")
		_check(restored.state.scene_id == state.scene_id and _state_position(restored.state) == _state_position(state) and restored.state.player_state["facing"] == "left", "restored route has exact region, fractional position and facing")
		_check(restored.is_inspected("DOC_STREET_NOTICE") and restored.is_inspected("NPC_STREET_VENDOR"), "fresh session restores inspected facts")
		loaded["state"].world_flags.clear()
		_check(restored.is_inspected("DOC_STREET_NOTICE"), "loaded snapshot cannot later mutate restored route")
		restored.free()
	state = session.start_new_game()
	_check(state.route_id != first_route and state.world_flags.is_empty(), "new game has new route and clears previous inspection flags")
	_check(state.scene_id == content.start_scene_id and _state_position(state) == content.get_spawn_position(content.start_scene_id, content.start_spawn_id), "new game after old save returns to configured start")
	saves.free()
	session.free()


func _snapshot() -> Dictionary:
	var scenes: Dictionary = {}
	var regions: Dictionary = {}
	for scene: Dictionary in _bootstrap["scenes"]:
		scenes[scene["id"]] = _content.get_scene_definition(scene["id"])
		regions[scene["id"]] = _content.get_exploration_region(scene["id"])
	return {"version": _content.content_version, "start": _content.start_scene_id, "spawn": _content.start_spawn_id, "scenes": scenes, "regions": regions}


func _reject_bootstrap(invalid: Dictionary, description: String) -> void:
	var before: Dictionary = _snapshot()
	_check(_content.load_definitions(invalid) == ERR_INVALID_DATA, "reject " + description)
	_check(_snapshot() == before and not _content.last_error.is_empty(), "preserve registry after " + description)


func _reject_regions(invalid: Variant, description: String) -> void:
	var before: Dictionary = _snapshot()
	_check(_content.load_definitions(_bootstrap, invalid) == ERR_INVALID_DATA, "reject " + description)
	_check(_snapshot() == before and not _content.last_error.is_empty(), "preserve registry after " + description)


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_check(file != null, "read fixture: " + path)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check(data is Dictionary, "fixture has object root: " + path)
	return data if data is Dictionary else {}


func _read_localization() -> Dictionary:
	var file: FileAccess = FileAccess.open(LOCALIZATION_PATH, FileAccess.READ)
	_check(file != null, "localization source opens")
	var result: Dictionary = {}
	if file == null:
		return result
	_check(file.get_csv_line() == PackedStringArray(["keys", "zh_CN", "en"]), "localization has key/Chinese/English header")
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		_check(row.size() == 3, "localization row has exact column count")
		if row.size() != 3:
			continue
		_check(not result.has(row[0]) and not row[0].is_empty() and not row[1].is_empty() and not row[2].is_empty(), "unique nonempty localized row: " + row[0])
		result[row[0]] = [row[1], row[2]]
	file.close()
	return result


func _state_position(state: GameState) -> Vector2:
	return Vector2(state.player_state["position"]["x"], state.player_state["position"]["y"])


func _same_json(left: Dictionary, right: Dictionary) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		printerr("EXPLORATION_CONTENT_FAIL ", description)


func _finish() -> void:
	if is_instance_valid(_content):
		_content.free()
	_remove_test_tree(_isolated_root)
	if _failures.is_empty():
		print("EXPLORATION_CONTENT_PASS checks=%d (real definitions, transactional validation and isolated save files)" % _checks)
	else:
		printerr("EXPLORATION_CONTENT_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _remove_test_tree(path: String) -> void:
	if path != _isolated_root and not path.begins_with(_isolated_root + "/"):
		_check(false, "cleanup refuses paths outside its exact isolated test root")
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_test_tree(path.path_join(child))
	for child: String in directory.get_files():
		_check(IO.remove_file(path.path_join(child)) == OK, "remove isolated fixture: " + child)
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "remove isolated test directory")
