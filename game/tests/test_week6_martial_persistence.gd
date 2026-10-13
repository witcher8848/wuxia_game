extends SceneTree
## Sequential writer/reader process phases. Only unique user://tests fixtures.
const IO = preload("res://game/persistence/save_file_io.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var saves: Node
var fixture := ""
var phase := ""


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("MARTIAL_PERSISTENCE_FAIL ", label)


func _run() -> void:
	var packed := "--require-pack" in OS.get_cmdline_user_args()
	if packed:
		check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported pack only; no source overlay")
		if not failures.is_empty(): quit(1); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
	if not fixture.begins_with("user://tests/martial_persistence_") or not fixture.trim_prefix("user://tests/").is_valid_identifier() or fixture.trim_prefix("user://tests/").length() > 96 or not phase in ["write","read"]:
		printerr("MARTIAL_PERSISTENCE_FAIL invalid isolated fixture/phase")
		quit(1)
		return
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	saves = root.get_node("SaveService")
	saves.test_root = fixture
	if phase == "write": _write()
	else: _read()
	check(IO.write_text(fixture.path_join(phase + "_receipt.json"),JSON.stringify({"pid":OS.get_process_id(),"phase":phase,"checks":checks,"failures":failures,"packed":packed})) == OK, "own process writes isolated receipt")
	saves.test_root = ""
	print("MARTIAL_PERSISTENCE_%s: %d checks, %d failures fixture=%s pid=%d" % [phase.to_upper(),checks,failures.size(),fixture,OS.get_process_id()])
	if failures.is_empty(): print("MARTIAL_PERSISTENCE_PHASE_PASS phase=%s pid=%d checks=%d packed=%s fixture=%s" % [phase,OS.get_process_id(),checks,str(packed),fixture])
	quit(0 if failures.is_empty() else 1)


func _write() -> void:
	session.start_new_game()
	var legacy: Dictionary = session.state.to_dict()
	check(saves.save_game("manual_01",session.state) == OK, "save exact schema1 legacy-empty state")
	var legacy_sha := FileAccess.get_sha256(saves.slot_path("manual_01"))
	var seed: Dictionary = session.martial_configuration()["state"]
	check(session.state.to_dict() == legacy, "read-only seed leaves legacy snapshot unchanged")
	check(session.set_martial_loadout(seed["loadout"]) == OK, "confirm default equipped configuration")
	var equipped: Dictionary = session.state.to_dict()
	check(saves.save_game("manual_02",session.state) == OK, "save configured slot")
	var custom: Dictionary = seed["loadout"].duplicate(true)
	custom["external"] = ["SK_TRIP_WRIST","SK_YUE_CROSSCUT"]
	custom["movement"] = ""
	custom["internal"] = ""
	check(session.set_martial_loadout(custom) == OK, "confirm genuinely alternate kit")
	var alternative: Dictionary = session.state.to_dict()
	check(saves.save_game("quick",session.state) == OK, "save alternate kit to quick")
	check(session.set_martial_loadout(seed["loadout"]) == OK and saves.save_game("quick",session.state) == OK, "overwrite quick with valid equipped kit and create alternate backup")
	check(IO.write_text(saves.slot_path("quick"),"{corrupt primary") == OK, "damage only this test's quick primary")
	var bad := equipped.duplicate(true)
	bad["martial_states"]["loadout"]["internal"] = "MISSING"
	var malformed := GameState.from_dict(bad)
	check(saves.save_game("manual_03",malformed) == ERR_INVALID_DATA, "writer cannot persist invalid reference")
	check(IO.write_text(saves.slot_path("manual_03"),JSON.stringify(saves._make_envelope("manual_03",malformed))) == OK, "inject own semantic-corrupt file for cold reader")
	var token: String = session.lock_martial_trial()
	check(not token.is_empty(), "transient trial token before writer shutdown")
	check(IO.write_text(fixture.path_join("expected.json"),JSON.stringify({"legacy":legacy,"legacy_sha":legacy_sha,"equipped":equipped,"alternative":alternative,"writer_pid":OS.get_process_id(),"old_trial_token":token})) == OK, "write independent expected snapshots")
	check(FileAccess.get_sha256(saves.slot_path("manual_01")) == legacy_sha, "all later writes leave legacy original bytes untouched")
	check(content.validate_persistent_state(GameState.from_dict(equipped)).is_empty(), "actual persisted kit semantically valid")


func _read() -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("expected.json")))
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("write_receipt.json")))
	check(expected is Dictionary and receipt is Dictionary, "writer emitted exact snapshots and receipt before fresh process")
	if not expected is Dictionary or not receipt is Dictionary: return
	check(int(expected["writer_pid"]) != OS.get_process_id() and int(receipt["pid"]) == int(expected["writer_pid"]) and receipt["failures"].is_empty(), "reader and successful writer are distinct process identities")
	check(not session.story_encounter_active() and not session.unlock_martial_trial(expected["old_trial_token"]), "transient combat/trial ownership does not survive process restart")
	var baseline: Dictionary = session.state.to_dict()
	var bad: Dictionary = saves.load_game("manual_03",false)
	check(bad["error"] == ERR_INVALID_DATA and session.state.to_dict() == baseline, "cold reader rejects bad martial references without defaults or live mutation")
	var recovered: Dictionary = saves.load_game("quick",false)
	check(recovered["error"] == OK and recovered["source"] == "backup", "cold reader recovers exact-slot genuine backup")
	if recovered["error"] != OK: return
	check(_same(recovered["state"].to_dict(),expected["alternative"]), "cold backup exact state, not writer's final in-memory equipped kit")
	check(session.replace_state(recovered["state"]) == OK and _same(session.state.to_dict(),expected["alternative"]), "actual session load restores alternative preparation")
	check(session.state.martial_states["loadout"]["internal"] == "" and session.state.martial_states["loadout"]["movement"] == "", "intentional empty slots not silently filled on reload")
	var restored: Dictionary = saves.load_game("manual_02",false)
	check(restored["error"] == OK and _same(restored["state"].to_dict(),expected["equipped"]), "independent equipped slot retains every field")
	check(session.replace_state(restored["state"]) == OK, "replace with actual restored equipped state")
	for field: String in ["martial_states","time_state","player_state","quest_states","evidence_states","relationships","route_id"]:
		check(_same(session.state.to_dict()[field],expected["equipped"][field]), "cold process exact " + field)
	var legacy: Dictionary = saves.load_game("manual_01",false)
	check(legacy["error"] == OK and _same(legacy["state"].to_dict(),expected["legacy"]), "legacy schema1 empty slot exact snapshot after restart")
	check(session.replace_state(legacy["state"]) == OK and session.state.martial_states == {"mastery":{},"loadout":{}}, "loading legacy keeps raw empty martial fields")
	var viewed: Dictionary = session.martial_configuration()
	check(viewed["error"].is_empty() and viewed["state"]["mastery"].size() == 6 and _same(session.state.to_dict(),expected["legacy"]), "compatibility preparation view remains read-only after cold load")
	check(FileAccess.get_sha256(saves.slot_path("manual_01")) == expected["legacy_sha"], "legacy file bytes not rewritten by either process")
	check(session.set_martial_loadout(viewed["state"]["loadout"]) == OK, "cold-loaded legacy can explicitly confirm actual new preparation")
	check(_same(saves.load_game("manual_02",false)["state"].to_dict(),expected["equipped"]), "continuing legacy does not mutate later slot")


static func _same(left: Variant, right: Variant) -> bool:
	# JSON numbers load as floats; compare all keys/values/array order without
	# dropping fields or pretending an engine int-vs-JSON-float tag is save loss.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))
