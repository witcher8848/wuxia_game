extends SceneTree
## Immutable choice snapshots use only this test's isolated user://tests root.
const IO = preload("res://game/persistence/save_file_io.gd")
const NODE_ID := "CH01_FIRST_LEAD"
var checks := 0
var failures: Array[String] = []
var saves: Node
var session: Node
var content: Node
var fixture := ""
var base: Dictionary = {}
var sequence := 0


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CHOICE_ANCHORS_FAIL ", label)


func _run() -> void:
	await process_frame
	saves = root.get_node("SaveService")
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	fixture = "user://tests/choice_anchors_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	saves.test_root = fixture
	session.start_new_game()
	base = session.state.to_dict()
	_test_immutable_roundtrip()
	_test_identity_and_corruption()
	_test_identity_types_and_shape()
	_test_invalid_inputs()
	_test_interrupted_and_failed_writes()
	_test_combat_lock()
	saves.test_root = ""
	print("CHOICE_ANCHORS: %d checks, %d failures fixture=%s" % [checks, failures.size(), fixture])
	if failures.is_empty(): print("CHOICE_ANCHORS_PASS checks=%d" % checks)
	quit(0 if failures.is_empty() else 1)


func _fresh() -> GameState:
	sequence += 1
	var state := GameState.from_dict(base)
	state.route_id = "ROUTE_ANCHOR_%d" % sequence
	return state


static func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _test_immutable_roundtrip() -> void:
	var state := _fresh()
	state.player_state["position"] = {"x": 220.25, "y": 125.5}
	state.playtime_seconds = 31.125
	state.time_state = {"day": 2, "slot": 3}
	check(content.validate_persistent_state(state).is_empty(), "fixture satisfies complete content validation")
	for slot: String in ["quick", "auto_01", "auto_02", "auto_03"]:
		check(saves.save_game(slot, state) == OK, "ordinary slot fixture " + slot)
	var slot_hashes: Dictionary = {}
	for slot: String in saves.SLOTS:
		var path: String = saves.slot_path(slot)
		slot_hashes[slot] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var before := state.to_dict()
	var live_before: Dictionary = session.state.to_dict()
	var created: Dictionary = saves.save_choice_anchor(NODE_ID, state)
	if created["error"] != OK:
		printerr("CHOICE_ANCHORS_DIAGNOSTIC ", created)
	check(created["error"] == OK and created.get("created") == true, "first anchor publishes successfully")
	check(created.get("anchor_id") == state.route_id + ":" + NODE_ID, "stable anchor identity returned")
	check(created.get("source") == "choice_anchor", "explicit source, not auto slot")
	var path: String = saves.choice_anchor_path(state.route_id, NODE_ID)
	check(path.begins_with(fixture + "/saves/anchors/"), "anchor confined to isolated root")
	check(path.ends_with("/" + state.route_id.sha256_text() + "/" + NODE_ID + "/anchor.sav"), "case-safe hashed route and fixed node path")
	check(FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path.get_base_dir() + ".new")), "complete directory published, owned staging released")
	var original_hash := FileAccess.get_sha256(path)
	var loaded: Dictionary = saves.load_choice_anchor(state.route_id, NODE_ID)
	check(loaded["error"] == OK and _same(loaded["state"].to_dict(), before), "all persistent partitions round-trip exactly")
	if loaded["error"] != OK: return
	check(loaded["envelope"]["save_kind"] == "choice_anchor", "dedicated envelope kind")
	check(loaded["envelope"]["choice_anchor"]["route_id"] == state.route_id and loaded["envelope"]["choice_anchor"]["node_id"] == NODE_ID, "identity inside validated envelope")
	var repeated: Dictionary = saves.save_choice_anchor(NODE_ID, state)
	check(repeated["error"] == OK and repeated.get("created") == false, "identical snapshot is idempotent")
	check(FileAccess.get_sha256(path) == original_hash, "idempotency preserves original bytes and timestamp metadata")
	loaded["state"].player_state["hp"] = 1
	check(saves.load_choice_anchor(state.route_id, NODE_ID)["state"].player_state["hp"] == state.player_state["hp"], "read result cannot mutate persisted anchor")
	state.player_state["hp"] = 2
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_ALREADY_EXISTS, "different snapshot cannot replace the first")
	check(FileAccess.get_sha256(path) == original_hash, "refused replacement preserves committed bytes")
	check(session.state.to_dict() == live_before, "save and load never replace live session")
	for slot: String in saves.SLOTS:
		var ordinary_path: String = saves.slot_path(slot)
		var now: String = FileAccess.get_sha256(ordinary_path) if FileAccess.file_exists(ordinary_path) else ""
		check(now == slot_hashes[slot], "anchor operations never touch slot " + slot)
	var other := _fresh()
	check(saves.load_choice_anchor(other.route_id, NODE_ID)["error"] == ERR_FILE_NOT_FOUND, "missing route does not borrow another anchor or auto slot")
	check(saves.save_choice_anchor(NODE_ID, other)["error"] == OK, "independent route gets its own anchor")
	check(saves.choice_anchor_path(other.route_id, NODE_ID) != path, "separate route path")
	var lower := _fresh()
	lower.route_id = "ROUTE_case"
	var upper := _fresh()
	upper.route_id = "ROUTE_CASE"
	check(saves.choice_anchor_path(lower.route_id, NODE_ID).to_lower() != saves.choice_anchor_path(upper.route_id, NODE_ID).to_lower(), "case-sensitive identities cannot fold to same filesystem path")
	check(saves.save_choice_anchor(NODE_ID, lower)["error"] == OK and saves.save_choice_anchor(NODE_ID, upper)["error"] == OK, "case-distinct routes both persist")


func _test_identity_and_corruption() -> void:
	for mutation: String in ["damaged_json", "schema_future", "schema_huge", "anchor_future", "kind", "missing_identity", "route", "node", "anchor_id", "hash", "payload_route", "semantic_state"]:
		var state := _fresh()
		check(saves.save_choice_anchor(NODE_ID, state)["error"] == OK, "create corruption fixture " + mutation)
		var path: String = saves.choice_anchor_path(state.route_id, NODE_ID)
		if not FileAccess.file_exists(path): return
		var envelope: Dictionary = IO.read_envelope(path)["envelope"]
		var expected := ERR_INVALID_DATA
		match mutation:
			"damaged_json": expected = ERR_PARSE_ERROR
			"schema_future":
				envelope["schema_version"] = GameState.SCHEMA_VERSION + 1
				expected = ERR_UNAVAILABLE
			"schema_huge":
				envelope["schema_version"] = 1.0e30
				expected = ERR_UNAVAILABLE
			"anchor_future":
				envelope["choice_anchor"]["version"] = 1.0e30
				expected = ERR_UNAVAILABLE
			"kind": envelope["save_kind"] = "auto"
			"missing_identity": envelope.erase("choice_anchor")
			"route": envelope["choice_anchor"]["route_id"] = "ROUTE_OTHER"
			"node": envelope["choice_anchor"]["node_id"] = "CH01_OTHER"
			"anchor_id": envelope["choice_anchor"]["anchor_id"] = "FORGED"
			"hash": envelope["choice_anchor"]["snapshot_sha256"] = "FORGED"
			"payload_route": envelope["payload"]["route_id"] = "ROUTE_OTHER"
			"semantic_state":
				envelope["payload"]["world_flags"]["FACT_GRAVES_SAFE"] = "invalid"
		check(IO.write_text(path, "{broken" if mutation == "damaged_json" else JSON.stringify(envelope, "", true, true)) == OK, "write isolated bad fixture " + mutation)
		var bytes_hash := FileAccess.get_sha256(path)
		check(saves.load_choice_anchor(state.route_id, NODE_ID)["error"] == expected, "bad/future anchor refuses load " + mutation)
		check(saves.save_choice_anchor(NODE_ID, state)["error"] == expected, "bad/future anchor cannot be silently replaced " + mutation)
		check(FileAccess.get_sha256(path) == bytes_hash, "bad/future bytes preserved " + mutation)
	var source := _fresh()
	var destination := _fresh()
	check(saves.save_choice_anchor(NODE_ID, source)["error"] == OK, "source for copied-route fixture")
	var destination_path: String = saves.choice_anchor_path(destination.route_id, NODE_ID)
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_path.get_base_dir())) == OK, "isolated wrong-route target directory")
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(saves.choice_anchor_path(source.route_id, NODE_ID)), ProjectSettings.globalize_path(destination_path)) == OK, "copy valid envelope to another route's path")
	check(saves.load_choice_anchor(destination.route_id, NODE_ID)["error"] == ERR_INVALID_DATA, "path identity and payload route cross-check")
	check(saves.save_choice_anchor(NODE_ID, destination)["error"] == ERR_INVALID_DATA, "wrong-route file cannot be overwritten")


func _test_identity_types_and_shape() -> void:
	for field: String in ["route_id", "node_id", "anchor_id", "snapshot_sha256"]:
		for bad_value: Variant in [null, true, 1, [], {}]:
			var state := _fresh()
			check(saves.save_choice_anchor(NODE_ID, state)["error"] == OK, "create bad-type fixture " + field)
			var path: String = saves.choice_anchor_path(state.route_id, NODE_ID)
			var envelope: Dictionary = IO.read_envelope(path)["envelope"]
			envelope["choice_anchor"][field] = bad_value
			check(IO.write_text(path, JSON.stringify(envelope, "", true, true)) == OK, "write bad identity type " + field + " type=" + type_string(typeof(bad_value)))
			var bytes_hash := FileAccess.get_sha256(path)
			check(saves.load_choice_anchor(state.route_id, NODE_ID)["error"] == ERR_INVALID_DATA, "bad identity type refuses load without script errors " + field)
			check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_INVALID_DATA, "bad identity type cannot be overwritten " + field)
			check(FileAccess.get_sha256(path) == bytes_hash, "bad identity type preserves exact bytes " + field)
		var missing_state := _fresh()
		check(saves.save_choice_anchor(NODE_ID, missing_state)["error"] == OK, "create missing identity field fixture " + field)
		var missing_path: String = saves.choice_anchor_path(missing_state.route_id, NODE_ID)
		var missing_envelope: Dictionary = IO.read_envelope(missing_path)["envelope"]
		missing_envelope["choice_anchor"].erase(field)
		check(IO.write_text(missing_path, JSON.stringify(missing_envelope, "", true, true)) == OK, "write missing identity field " + field)
		var missing_hash := FileAccess.get_sha256(missing_path)
		check(saves.load_choice_anchor(missing_state.route_id, NODE_ID)["error"] == ERR_INVALID_DATA, "missing required identity field refused " + field)
		check(saves.save_choice_anchor(NODE_ID, missing_state)["error"] == ERR_INVALID_DATA and FileAccess.get_sha256(missing_path) == missing_hash, "missing field is not repaired or overwritten " + field)
	var compatible := _fresh()
	check(saves.save_choice_anchor(NODE_ID, compatible)["error"] == OK, "create compatible extra annotation fixture")
	var compatible_path: String = saves.choice_anchor_path(compatible.route_id, NODE_ID)
	var compatible_envelope: Dictionary = IO.read_envelope(compatible_path)["envelope"]
	compatible_envelope["choice_anchor"]["annotation"] = {"text": "ignored compatible annotation"}
	check(IO.write_text(compatible_path, JSON.stringify(compatible_envelope, "", true, true)) == OK, "write compatible extra annotation")
	var compatible_hash := FileAccess.get_sha256(compatible_path)
	check(saves.load_choice_anchor(compatible.route_id, NODE_ID)["error"] == OK, "unknown additive annotation accepted under current version")
	check(saves.save_choice_anchor(NODE_ID, compatible)["error"] == OK and FileAccess.get_sha256(compatible_path) == compatible_hash, "idempotent save preserves additive annotation bytes")


func _test_invalid_inputs() -> void:
	var state := _fresh()
	for route: String in ["", "../escape", "ROUTE/a", "user://route", "1_ROUTE", "ROUTE-1", "路线", "R".repeat(97)]:
		var malformed := GameState.from_dict(state.to_dict())
		malformed.route_id = route
		check(saves.choice_anchor_path(route, NODE_ID).is_empty(), "unsafe route has no path " + route)
		check(saves.save_choice_anchor(NODE_ID, malformed)["error"] == ERR_INVALID_PARAMETER, "unsafe route save refused " + route)
		check(saves.load_choice_anchor(route, NODE_ID)["error"] == ERR_INVALID_PARAMETER, "unsafe route read refused " + route)
	for node: String in ["", "../CH01_FIRST_LEAD", "CH01_SECOND_LEAD", "CH01_FIRST_LEAD.sav", "ch01_first_lead"]:
		check(saves.choice_anchor_path(state.route_id, node).is_empty(), "unregistered node has no path")
		check(saves.save_choice_anchor(node, state)["error"] == ERR_INVALID_PARAMETER, "unregistered node cannot write")
		check(saves.load_choice_anchor(state.route_id, node)["error"] == ERR_INVALID_PARAMETER, "unregistered node cannot load")
	for invalid_root: String in ["user://", "user://saves", "/tmp/anchors", "user://tests/../saves", "user://tests/valid/subdir"]:
		saves.test_root = invalid_root
		check(saves.choice_anchor_path(state.route_id, NODE_ID).is_empty(), "invalid test root has no anchor path")
		check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_INVALID_PARAMETER, "invalid test root cannot write anchors")
		check(saves.load_choice_anchor(state.route_id, NODE_ID)["error"] == ERR_INVALID_PARAMETER, "invalid test root cannot read anchors")
	saves.test_root = fixture
	check(saves.save_choice_anchor(NODE_ID, null)["error"] == ERR_INVALID_DATA, "null state rejected")
	state.player_state["hp"] = -1
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_INVALID_DATA, "invalid state rejected")
	check(not FileAccess.file_exists(saves.choice_anchor_path(state.route_id, NODE_ID)), "rejected state creates no anchor")
	state = _fresh()
	state.world_flags["FACT_GRAVES_SAFE"] = "invalid"
	check(state.validate().is_empty() and not content.validate_persistent_state(state).is_empty(), "semantic validation fixture exceeds generic schema")
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_INVALID_DATA, "complete content state validation on write")


func _test_interrupted_and_failed_writes() -> void:
	var state := _fresh()
	var target: String = saves.choice_anchor_path(state.route_id, NODE_ID)
	var staging: String = target.get_base_dir() + ".new"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging)) == OK, "simulate previous process claiming exclusive staging")
	var abandoned: String = staging.path_join("anchor.sav")
	check(IO.write_text(abandoned, "interrupted writer bytes") == OK, "interrupted fixture bytes")
	var abandoned_hash := FileAccess.get_sha256(abandoned)
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_BUSY, "concurrent or interrupted staging never stolen")
	check(FileAccess.get_sha256(abandoned) == abandoned_hash and not FileAccess.file_exists(target), "refusal preserves foreign staging and no partial target")
	check(saves.load_choice_anchor(state.route_id, NODE_ID)["error"] == ERR_FILE_NOT_FOUND, "reader never promotes incomplete staging")
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_BUSY, "repeated write still fails closed without cleanup")
	var second: Node = load("res://game/persistence/save_service.gd").new()
	second.test_root = fixture
	check(second.save_choice_anchor(NODE_ID, state)["error"] == ERR_BUSY, "separate service instance cannot steal existing staging")
	second.free()
	state = _fresh()
	target = saves.choice_anchor_path(state.route_id, NODE_ID)
	staging = target.get_base_dir() + ".new"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging.get_base_dir())) == OK, "foreign staging-file parent")
	check(IO.write_text(staging, "not a writable staging directory") == OK, "foreign staging file fixture")
	var staging_hash := FileAccess.get_sha256(staging)
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_BUSY, "preexisting staging file also fails closed")
	check(FileAccess.get_sha256(staging) == staging_hash, "foreign staging file never truncated or removed")
	state = _fresh()
	target = saves.choice_anchor_path(state.route_id, NODE_ID)
	state.inventory["anchor_size_probe"] = "x".repeat(IO.MAX_SAVE_BYTES + 1)
	check(state.validate().is_empty() and content.validate_persistent_state(state).is_empty(), "oversized JSON is generic/content-valid but exceeds file envelope limit")
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_INVALID_DATA, "post-write full envelope validation failure surfaced")
	check(not FileAccess.file_exists(target) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target.get_base_dir())), "failed validation publishes no final directory or partial anchor")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target.get_base_dir() + ".new")), "only this attempt's acquired staging reclaimed on failure")
	state.inventory.clear()
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == OK, "retry works after caller repairs oversized snapshot, without replaying an existing anchor")
	state = _fresh()
	target = saves.choice_anchor_path(state.route_id, NODE_ID)
	var blocked_parent := target.get_base_dir().get_base_dir()
	check(IO.write_text(blocked_parent, "file blocks route directory") == OK, "isolated parent path failure fixture")
	var blocker_hash := FileAccess.get_sha256(blocked_parent)
	var before := state.to_dict()
	check(saves.save_choice_anchor(NODE_ID, state)["error"] != OK, "parent creation failure surfaced")
	check(FileAccess.get_sha256(blocked_parent) == blocker_hash and state.to_dict() == before and not FileAccess.file_exists(target), "failed write preserves blocking file and exact caller state")
	state = _fresh()
	target = saves.choice_anchor_path(state.route_id, NODE_ID)
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir())) == OK, "isolated malformed committed directory")
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_FILE_NOT_FOUND, "existing incomplete final directory not overwritten")
	check(not FileAccess.file_exists(target), "no replacement written into malformed final directory")


func _test_combat_lock() -> void:
	var state := _fresh()
	var token: String = session.lock_martial_trial()
	check(not token.is_empty() and session.combat_active(), "real owned combat lock")
	var path: String = saves.choice_anchor_path(state.route_id, NODE_ID)
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == ERR_BUSY, "combat cannot create anchor")
	check(saves.load_choice_anchor(state.route_id, NODE_ID)["error"] == ERR_BUSY, "combat cannot read anchor for rewind")
	check(not FileAccess.file_exists(path), "combat refusal has no disk effect")
	session.unlock_martial_trial(token)
	check(saves.save_choice_anchor(NODE_ID, state)["error"] == OK, "anchor works after real combat ownership releases")
