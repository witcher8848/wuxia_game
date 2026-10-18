extends SceneTree
## Persistent automatic rotation. Every fixture stays under its own test root.
const IO = preload("res://game/persistence/save_file_io.gd")
const SaveScript = preload("res://game/persistence/save_service.gd")
const AUTO: Array[String] = ["auto_01", "auto_02", "auto_03"]
var checks := 0
var failures: Array[String] = []
var saves: Node
var session: Node
var content: Node
var fixture := ""
var base: Dictionary = {}


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("AUTOMATIC_SAVES_FAIL ", label)


func _run() -> void:
	await process_frame
	saves = root.get_node("SaveService")
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	if not String(content.last_error).is_empty():
		check(false, "content must finish loading before persistence tests: " + String(content.last_error))
		quit(1)
		return
	fixture = "user://tests/automatic_saves_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	session.start_new_game()
	base = session.state.to_dict()
	var phase := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
	if not phase.is_empty():
		if not phase in ["write", "read"] or not fixture.begins_with("user://tests/automatic_saves_cold_") or not fixture.trim_prefix("user://tests/").is_valid_identifier():
			check(false, "cold process fixture and phase are explicitly isolated")
		else:
			_test_cold_process(phase)
	else:
		_test_rotation_and_cold_service()
		_test_legacy_compatibility()
		_test_protected_copies()
		_test_metadata_shapes()
		_test_corrupt_primary_and_backup()
		_test_invalid_state_and_failure()
		_test_sequence_limit()
		_test_sequences_from_backup_and_rollback()
		_test_latest_fallback()
	saves.test_root = ""
	print("AUTOMATIC_SAVES: %d checks, %d failures fixture=%s" % [checks, failures.size(), fixture])
	if failures.is_empty(): print("AUTOMATIC_SAVES_PASS checks=%d" % checks)
	if failures.is_empty() and not phase.is_empty():
		print("AUTOMATIC_SAVES_PHASE_PASS phase=%s pid=%d checks=%d fixture=%s" % [phase, OS.get_process_id(), checks, fixture])
	quit(0 if failures.is_empty() else 1)


func _test_cold_process(phase: String) -> void:
	saves.test_root = fixture
	var state := GameState.from_dict(base)
	state.route_id = "ROUTE_AUTOMATIC_COLD"
	if phase == "write":
		for index: int in range(1, 5):
			state.playtime_seconds = float(index)
			var result: Dictionary = saves.save_automatic(state)
			check(result["error"] == OK and result["sequence"] == index and result["slot"] == AUTO[(index - 1) % 3], "cold writer genuine rotation %d" % index)
		check(IO.write_text(fixture.path_join("writer.json"), JSON.stringify({"writer_pid": OS.get_process_id(), "state": state.to_dict()})) == OK, "cold writer exact snapshot and process receipt")
	else:
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("writer.json")))
		check(int(receipt["writer_pid"]) != OS.get_process_id(), "cold reader runs in a different OS process")
		var prior: Dictionary = _read("auto_01")
		check(prior["error"] == OK and prior["envelope"]["auto_sequence"] == 4 and _same(prior["state"].to_dict(), receipt["state"]), "cold reader restores complete persisted fourth snapshot")
		state = GameState.from_dict(receipt["state"])
		state.playtime_seconds = 5.0
		var continued: Dictionary = saves.save_automatic(state)
		check(continued["error"] == OK and continued["slot"] == "auto_02" and continued["sequence"] == 5, "fresh OS process continues automatic sequence rather than resetting")
		check(_read("auto_01")["envelope"]["auto_sequence"] == 4 and _read("auto_03")["envelope"]["auto_sequence"] == 3, "cold continuation rotates only the oldest slot")


func _case(label: String) -> GameState:
	saves.test_root = fixture + "_" + label
	return GameState.from_dict(base)


func _test_latest_fallback() -> void:
	var state := _case("latest_fallback")
	for index: int in range(1,4):
		state.playtime_seconds = index
		check(saves.save_automatic(state)["error"] == OK,"rapid real fallback snapshot %d" % index)
	var recovered: Dictionary = saves.load_game("quick",true)
	check(recovered["error"] == OK and recovered["source"] == "auto_03" and recovered["state"].playtime_seconds == 3,"rapid fallback selects sequence three rather than first equal-mtime slot")
	var envelope: Dictionary = _read("auto_02")["envelope"]
	envelope["auto_sequence"] = 8
	check(IO.write_text(saves.backup_path("auto_02"),JSON.stringify(envelope)) == OK,"higher sequence backup for fallback")
	check(saves.load_game("quick",true).get("source") == "auto_02_backup","fallback compares backup sequence even when primary is valid")
	envelope["auto_sequence"] = 9
	check(IO.write_text(saves.slot_path("auto_01")+".old",JSON.stringify(envelope)) == OK,"higher sequence rollback for fallback")
	check(saves.load_game("quick",true).get("source") == "auto_01_rollback","fallback includes validated rollback and reports its source")
	envelope["auto_sequence_version"] = 2
	envelope["auto_sequence"] = 999
	check(IO.write_text(saves.slot_path("auto_03"),JSON.stringify(envelope)) == OK,"future automatic metadata for fallback")
	check(saves.load_game("quick",true).get("source") == "auto_01_rollback","unsupported automatic metadata never wins recovery")
	# Controlled timestamps exercise legacy compatibility without OS-specific
	# touch commands, clock sleeps, or depending on filesystem time resolution.
	var candidates: Array[Dictionary] = [
		{"sequence":4,"modified":10,"result":{"source":"newest_sequence"}},
		{"sequence":2,"modified":12,"result":{"source":"newer_mtime"}},
		{"sequence":0,"modified":12,"result":{"source":"legacy"}},
	]
	check(saves._select_latest_auto(candidates)["source"] == "newest_sequence","sequence beats mtime; equal-time legacy does not erase receipt ordering")
	candidates[2]["modified"] = 13
	check(saves._select_latest_auto(candidates)["source"] == "legacy","strictly newer legacy automatic remains recoverable")
	candidates.reverse()
	check(saves._select_latest_auto(candidates)["source"] == "legacy","mixed legacy comparison is independent of traversal order")
	candidates.remove_at(0)
	check(saves._select_latest_auto(candidates)["source"] == "newest_sequence","sequenced comparison independent of traversal order")


func _hashes() -> Dictionary:
	var result: Dictionary = {}
	for slot: String in saves.SLOTS:
		for path: String in [saves.slot_path(slot), saves.slot_path(slot) + ".old", saves.backup_path(slot)]:
			result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	return result


func _read(slot: String) -> Dictionary:
	return IO.read_envelope(saves.slot_path(slot))


func _seed(slot: String, state: GameState, sequence: int = 0) -> void:
	check(saves.save_game(slot, state) == OK, "seed ordinary slot " + slot)
	if sequence > 0:
		var envelope: Dictionary = _read(slot)["envelope"]
		envelope["auto_sequence"] = sequence
		envelope["auto_sequence_version"] = 1
		check(IO.write_text(saves.slot_path(slot), JSON.stringify(envelope)) == OK, "seed automatic sequence " + slot)


func _test_rotation_and_cold_service() -> void:
	var state := _case("rotation")
	for slot: String in ["manual_01", "manual_02", "manual_03", "manual_04", "manual_05", "quick"]:
		_seed(slot, state)
	check(saves.save_choice_anchor("CH01_FIRST_LEAD", state)["error"] == OK, "immutable anchor fixture before rotation")
	var anchor_path: String = saves.choice_anchor_path(state.route_id, "CH01_FIRST_LEAD")
	var anchor_hash := FileAccess.get_sha256(anchor_path)
	var ordinary: Dictionary = _hashes()
	var live_before: Dictionary = session.state.to_dict()
	for index: int in range(1, 11):
		state.playtime_seconds = float(index)
		var before := state.to_dict()
		var result: Dictionary = saves.save_automatic(state)
		var expected := AUTO[(index - 1) % 3]
		check(result["error"] == OK and result.get("slot") == expected and result.get("sequence") == index, "deterministic rapid rotation %d -> %s" % [index, expected])
		if result["error"] != OK: return
		var loaded: Dictionary = _read(expected)
		check(loaded["error"] == OK and loaded["envelope"]["auto_sequence"] == index and loaded["envelope"]["auto_sequence_version"] == 1, "sequence atomically included in valid envelope %d" % index)
		check(_same(loaded["state"].to_dict(), before), "exact state round-trip for automatic write %d" % index)
		check(state.to_dict() == before and session.state.to_dict() == live_before, "automatic persistence never publishes or mutates runtime %d" % index)
		if index == 3:
			# Same timestamps cannot choose the next slot. The API does not read mtime.
			for slot: String in AUTO:
				var same_second: Dictionary = _read(slot)["envelope"]
				same_second["created_at_utc"] = "2026-10-17T00:00:00Z"
				check(IO.write_text(saves.slot_path(slot), JSON.stringify(same_second)) == OK, "same-second metadata fixture " + slot)
	var cold: Node = SaveScript.new()
	cold.name = "AutomaticColdService"
	root.add_child(cold)
	cold.test_root = saves.test_root
	var continued: Dictionary = cold.save_automatic(state)
	check(continued["error"] == OK and continued["slot"] == "auto_02" and continued["sequence"] == 11, "new cold service continues persisted sequence, not auto_01")
	root.remove_child(cold)
	cold.free()
	check(FileAccess.get_sha256(anchor_path) == anchor_hash, "automatic rotation cannot overwrite choice anchor")
	var after := _hashes()
	for path: String in ordinary:
		if not path.contains("/auto_"):
			check(after[path] == ordinary[path], "automatic rotation leaves manual/quick files untouched " + path.get_file())


func _test_legacy_compatibility() -> void:
	var state := _case("legacy")
	_seed("auto_01", state)
	_seed("auto_02", state)
	check(not _read("auto_01")["envelope"].has("auto_sequence"), "ordinary save_game auto behavior unchanged")
	for expected: String in ["auto_03", "auto_01", "auto_02", "auto_03"]:
		var result: Dictionary = saves.save_automatic(state)
		check(result["error"] == OK and result["slot"] == expected, "empty then legacy then oldest sequenced slot " + expected)
	check(_read("auto_01")["envelope"]["auto_sequence"] == 2 and _read("auto_02")["envelope"]["auto_sequence"] == 3 and _read("auto_03")["envelope"]["auto_sequence"] == 4, "legacy upgrade keeps monotonic persisted order")
	var backup: Dictionary = IO.read_envelope(saves.backup_path("auto_01"))
	check(backup["error"] == OK and not backup["envelope"].has("auto_sequence"), "legacy old backup remains readable without rewrite")


func _test_protected_copies() -> void:
	var state := _case("protected")
	_seed("auto_01", state, 1)
	var primary: Dictionary = _read("auto_01")["envelope"]
	primary["schema_version"] = GameState.SCHEMA_VERSION + 1
	check(IO.write_text(saves.slot_path("auto_01"), JSON.stringify(primary)) == OK, "future primary fixture")
	var future_primary_hash := FileAccess.get_sha256(saves.slot_path("auto_01"))
	var second: Dictionary = saves.save_automatic(state)
	check(second["error"] == OK and second["slot"] == "auto_02", "future primary slot skipped")
	check(FileAccess.get_sha256(saves.slot_path("auto_01")) == future_primary_hash, "future primary preserved byte-for-byte")
	var future_backup: Dictionary = _read("auto_02")["envelope"]
	future_backup["auto_sequence_version"] = 1.0e30
	check(IO.write_text(saves.backup_path("auto_02"), JSON.stringify(future_backup)) == OK, "future metadata backup fixture")
	var future_backup_hash := FileAccess.get_sha256(saves.backup_path("auto_02"))
	var third: Dictionary = saves.save_automatic(state)
	check(third["error"] == OK and third["slot"] == "auto_03" and third["sequence"] == 2, "future backup protects whole slot while valid primary sequence counts")
	check(FileAccess.get_sha256(saves.backup_path("auto_02")) == future_backup_hash, "future backup not replaced")
	var rollback: Dictionary = _read("auto_03")["envelope"]
	rollback["auto_sequence"] = {}
	check(IO.write_text(saves.slot_path("auto_03") + ".old", JSON.stringify(rollback)) == OK, "bad metadata rollback fixture")
	var before := _hashes()
	var rejected: Dictionary = saves.save_automatic(state)
	check(rejected["error"] == ERR_UNAVAILABLE and rejected["slot"] == "", "all protected slots fail explicitly")
	check(_hashes() == before, "all protected failure cannot alter any primary/backup/rollback")


func _test_metadata_shapes() -> void:
	var case_index := 0
	for field: String in ["auto_sequence", "auto_sequence_version"]:
		for value: Variant in [null, true, "1", [], {}, 0, -1, 1.25, 1.0e30]:
			case_index += 1
			var state := _case("metadata_%d" % case_index)
			_seed("auto_01", state, 1)
			var envelope: Dictionary = _read("auto_01")["envelope"]
			envelope[field] = value
			check(IO.write_text(saves.slot_path("auto_01"), JSON.stringify(envelope)) == OK, "bad metadata type fixture " + field + " " + type_string(typeof(value)))
			var original_hash := FileAccess.get_sha256(saves.slot_path("auto_01"))
			var result: Dictionary = saves.save_automatic(state)
			check(result["error"] == OK and result["slot"] == "auto_02", "invalid/future metadata slot skipped without script error " + field)
			check(FileAccess.get_sha256(saves.slot_path("auto_01")) == original_hash, "bad metadata file preserved " + field)
	for missing: String in ["auto_sequence", "auto_sequence_version"]:
		case_index += 1
		var state := _case("metadata_%d" % case_index)
		_seed("auto_01", state, 1)
		var envelope: Dictionary = _read("auto_01")["envelope"]
		envelope.erase(missing)
		check(IO.write_text(saves.slot_path("auto_01"), JSON.stringify(envelope)) == OK, "partial metadata fixture " + missing)
		var original_hash := FileAccess.get_sha256(saves.slot_path("auto_01"))
		var result: Dictionary = saves.save_automatic(state)
		check(result["error"] == OK and result["slot"] == "auto_02", "partial sequence metadata is not treated as legacy")
		check(FileAccess.get_sha256(saves.slot_path("auto_01")) == original_hash, "partial metadata remains unchanged")
	var wrong_kind := _case("wrongkind")
	_seed("auto_01", wrong_kind, 1)
	var wrong_envelope: Dictionary = _read("auto_01")["envelope"]
	wrong_envelope["save_kind"] = "manual"
	check(IO.write_text(saves.slot_path("auto_01"), JSON.stringify(wrong_envelope)) == OK, "wrong kind automatic slot fixture")
	check(saves.save_automatic(wrong_kind)["slot"] == "auto_02", "wrong kind metadata protected")


func _test_corrupt_primary_and_backup() -> void:
	var state := _case("corruption")
	for index: int in range(1, 5):
		check(saves.save_automatic(state)["error"] == OK, "seed rotation before corruption %d" % index)
	var backup_hash := FileAccess.get_sha256(saves.backup_path("auto_01"))
	check(IO.write_text(saves.slot_path("auto_01"), "{damaged") == OK, "damage primary but retain earlier sequenced backup")
	var result: Dictionary = saves.save_automatic(state)
	check(result["error"] == OK and result["slot"] == "auto_01" and result["sequence"] == 4, "valid backup controls corrupted slot age; valid global maximum controls sequence")
	check(FileAccess.get_sha256(saves.backup_path("auto_01")) == backup_hash, "damaged primary never copied over good backup")
	check(_read("auto_01")["error"] == OK, "corrupt primary replaced by validated full envelope")
	var legacy_state := _case("corrupt_no_backup")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.slot_path("auto_01").get_base_dir())) == OK, "corrupt-only directory fixture")
	check(IO.write_text(saves.slot_path("auto_01"), "{broken") == OK, "corrupt-only primary fixture")
	var empty: Dictionary = saves.save_automatic(legacy_state)
	check(empty["error"] == OK and empty["slot"] == "auto_02", "empty slot preferred to damaged occupied slot")


func _test_invalid_state_and_failure() -> void:
	var state := _case("invalid_state")
	check(saves.save_automatic(state)["error"] == OK, "valid save before refusal probes")
	var before := _hashes()
	check(saves.save_automatic(null)["error"] == ERR_INVALID_DATA, "null cannot save automatically")
	state.player_state["hp"] = -1
	check(saves.save_automatic(state)["error"] == ERR_INVALID_DATA, "invalid generic state refused")
	state = GameState.from_dict(base)
	state.world_flags["FACT_GRAVES_SAFE"] = "bad"
	check(saves.save_automatic(state)["error"] == ERR_INVALID_DATA, "invalid semantic state refused before write")
	check(_hashes() == before, "invalid states leave all slots untouched")
	state = GameState.from_dict(base)
	var token: String = session.lock_martial_trial()
	check(not token.is_empty(), "real combat lock for automatic save")
	check(saves.save_automatic(state)["error"] == ERR_BUSY and _hashes() == before, "combat auto-save refused without changes")
	session.unlock_martial_trial(token)
	for invalid_root: String in ["user://", "user://tests/../saves", "/tmp/saves", "user://tests/x/y"]:
		saves.test_root = invalid_root
		check(saves.save_automatic(state)["error"] == ERR_INVALID_PARAMETER, "invalid isolated root refused " + invalid_root)
	state = _case("io_failure")
	var blocked_temporary: String = saves.slot_path("auto_01") + ".tmp"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_temporary)) == OK, "IO failure fixture blocks only temporary file path")
	var blocker := blocked_temporary.path_join("owned_test_marker.txt")
	check(IO.write_text(blocker, "block temporary file") == OK, "IO failure blocker marker")
	var blocker_hash := FileAccess.get_sha256(blocker)
	var snapshot := state.to_dict()
	var failed: Dictionary = saves.save_automatic(state)
	check(failed["error"] != OK and failed["slot"] == "", "write failure returned with no successful slot")
	check(FileAccess.get_sha256(blocker) == blocker_hash and state.to_dict() == snapshot and not FileAccess.file_exists(saves.slot_path("auto_01")), "write failure does not change blocker, publish a slot, or mutate caller state")


func _test_sequence_limit() -> void:
	var state := _case("limit")
	_seed("auto_01", state, SaveScript.MAX_AUTOMATIC_SEQUENCE - 1)
	var last: Dictionary = saves.save_automatic(state)
	check(last["error"] == OK and last["slot"] == "auto_02" and last["sequence"] == SaveScript.MAX_AUTOMATIC_SEQUENCE, "last safe JSON integer persisted exactly")
	check(_read("auto_02")["envelope"]["auto_sequence"] == SaveScript.MAX_AUTOMATIC_SEQUENCE, "last sequence exact after JSON read")
	var before := _hashes()
	var rejected: Dictionary = saves.save_automatic(state)
	check(rejected["error"] == ERR_UNAVAILABLE and rejected["slot"] == "", "sequence overflow refused explicitly")
	check(_hashes() == before, "overflow never wraps/restarts or overwrites a slot")


func _test_sequences_from_backup_and_rollback() -> void:
	var state := _case("backup_order")
	_seed("auto_01", state, 5)
	var backup: Dictionary = _read("auto_01")["envelope"]
	backup["auto_sequence"] = 40
	check(IO.write_text(saves.backup_path("auto_01"), JSON.stringify(backup)) == OK, "valid high-sequence backup fixture")
	var next: Dictionary = saves.save_automatic(state)
	check(next["error"] == OK and next["slot"] == "auto_02" and next["sequence"] == 41, "global sequence includes valid backup even while primary exists")
	var rollback: Dictionary = _read("auto_02")["envelope"]
	rollback["auto_sequence"] = 60
	check(IO.write_text(saves.slot_path("auto_02") + ".old", JSON.stringify(rollback)) == OK, "valid high-sequence rollback fixture")
	next = saves.save_automatic(state)
	check(next["error"] == OK and next["slot"] == "auto_03" and next["sequence"] == 61, "global sequence includes valid interrupted rollback copy")
	state = _case("rollback_restore")
	_seed("auto_01", state, 8)
	check(IO.rename_file(saves.slot_path("auto_01"), saves.slot_path("auto_01") + ".old") == OK, "interrupted rollback without primary fixture")
	next = saves.save_automatic(state)
	check(next["error"] == OK and next["slot"] == "auto_02" and next["sequence"] == 9, "rollback-only slot counts as occupied and preserves sequence")


static func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))
