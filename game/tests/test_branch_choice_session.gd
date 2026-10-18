extends SceneTree
## Week8 foundation: actual service/capability/anchor integration, not a playable
## new quest, 30-minute measurement, human test or packaged/native verification.
const IO = preload("res://game/persistence/save_file_io.gd")
const RECORD := "CHOICE_CH01_FIRST_LEAD"
var checks := 0
var failures: Array[String] = []
var session: Node
var saves: Node
var content: Node
var fixture := ""
var phase := ""
var choice := "home"


func _initialize() -> void:
	create_timer(55).timeout.connect(func() -> void: printerr("BRANCH_CHOICE_SESSION_FAIL watchdog"); quit(124))
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("BRANCH_CHOICE_SESSION_FAIL ", label)
	return ok


static func same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))


func denied(result: Dictionary, before: Dictionary, label: String) -> void:
	check(typeof(result.get("error")) == TYPE_INT and result["error"] != OK, label+" rejects")
	check(not result.has("token"),label+" issues no replacement capability")
	check(same(session.state.to_dict(), before), label+" preserves complete state")


func seed_search() -> void:
	session.start_new_game()
	check(session.apply_investigation_step("STEP_RECEIVE_INDEX")["error"] == OK, "receive real index")
	check(session.apply_investigation_step("STEP_ACCEPT_SEARCH")["error"] == OK, "accept real search")


func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	saves = root.get_node("SaveService")
	content = root.get_node("ContentDB")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--choice="): choice = argument.trim_prefix("--choice=")
	if fixture.is_empty(): fixture = "user://tests/branch_session_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	if not check(fixture.begins_with("user://tests/branch_session_") and fixture.trim_prefix("user://tests/").is_valid_identifier() and fixture.trim_prefix("user://tests/").length() <= 96, "strict isolated fixture"):
		quit(1); return
	saves.test_root = fixture
	if phase == "write":
		_write()
	elif phase == "read":
		_read()
	elif phase.is_empty():
		_security()
	else:
		check(false,"unknown phase")
	check(choice in ["home","dock"],"known route parameter")
	saves.test_root = ""
	print("BRANCH_CHOICE_SESSION: %d checks, %d failures; engineering foundation only" % [checks,failures.size()])
	if not phase.is_empty() and failures.is_empty():
		print("BRANCH_CHOICE_SESSION_PHASE_PASS phase=%s choice=%s pid=%d checks=%d packed=false fixture=%s" % [phase,choice,OS.get_process_id(),checks,fixture])
	quit(0 if failures.is_empty() else 1)


func _security() -> void:
	session.start_new_game()
	var before: Dictionary = session.state.to_dict()
	check(not session.state.world_flags.has(RECORD),"ordinary new game does not enable unfinished route")
	denied(session.preview_branch_choice("home"),before,"no active investigation")
	denied(session.confirm_branch_choice(""),before,"empty capability")
	denied(session.confirm_branch_choice("BRANCH_FORGED"),before,"invented capability")
	seed_search()
	before = session.state.to_dict()
	denied(session.preview_branch_choice("other"),before,"unknown choice")
	var preview: Dictionary = session.preview_branch_choice("home")
	if not check(preview.get("error") == OK,"first preview creates verified immutable anchor"): return
	check(not preview.has("state") and same(session.state.to_dict(),before),"preview exposes no mutable candidate")
	var anchor_path: String = saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")
	var first_hash: String = FileAccess.get_sha256(anchor_path)
	check(not first_hash.is_empty(),"anchor actually exists on disk")
	var anchor: Dictionary = saves.load_choice_anchor(session.state.route_id,"CH01_FIRST_LEAD")
	check(anchor.get("error") == OK and same(anchor["state"].to_dict(),before),"anchor is exact complete before-state")
	preview["summary"]["choice"] = "dock"
	session.cancel_branch_choice("wrong")
	var token: String = preview["token"]
	session.cancel_branch_choice(token)
	denied(session.confirm_branch_choice(token),before,"cancelled capability")
	check(FileAccess.get_sha256(anchor_path) == first_hash,"cancel retains first anchor")
	check(session.update_player_position(Vector2(321,181)) == OK,"move after cancelling")
	before = session.state.to_dict()
	preview = session.preview_branch_choice("dock")
	check(preview.get("error") == OK,"reopen after movement reuses first anchor without softlock")
	check(preview.get("anchor_id") == session.state.route_id+":CH01_FIRST_LEAD","reopen returns same nonempty verified anchor identity")
	check(FileAccess.get_sha256(anchor_path) == first_hash,"reopen never overwrites first anchor")
	var older: String = preview.get("token","")
	preview = session.preview_branch_choice("home")
	denied(session.confirm_branch_choice(older),before,"superseded capability")
	if preview.get("error") == OK:
		preview["summary"]["choice"] = "dock"
		var result: Dictionary = session.confirm_branch_choice(preview["token"])
		check(result.get("error") == OK and result.get("requires_save") == true and result.get("saved") == false,"confirmation reports unpersisted result honestly")
		check(session.state.world_flags.get(RECORD,{}).get("choice") == "home","original summary mutation cannot change actual choice")
		var expected := before.duplicate(true)
		expected["world_flags"][RECORD] = session.state.world_flags[RECORD].duplicate(true)
		check(same(session.state.to_dict(),expected),"commit only adds immutable choice record, no hidden facts/time/rewards")
		before = session.state.to_dict()
		denied(session.confirm_branch_choice(preview["token"]),before,"double confirm")
		denied(session.preview_branch_choice("dock"),before,"opposite choice after commit")
		denied(session.apply_investigation_step("STEP_TAKE_FERRY_TOKEN"),before,"opposite full acquisition guarded")
		check(saves.save_game("quick",session.state) == OK,"choice state is persistable via ordinary explicit save")
		var loaded: Dictionary = saves.load_game("quick",false)
		check(loaded.get("error") == OK and same(loaded["state"].to_dict(),before),"same-process roundtrip preserves choice, not cold restart")
	for invalidation: String in ["movement","inspection","replace","new_game","reload","combat","world"]:
		seed_search()
		preview = session.preview_branch_choice("dock")
		if not check(preview.get("error") == OK,"invalidation preview "+invalidation): continue
		var combat_token := ""
		match invalidation:
			"movement": session.update_player_position(Vector2(322,180))
			"inspection": session.mark_inspected("DOC_STREET_NOTICE")
			"replace": session.replace_state(GameState.from_dict(session.state.to_dict()))
			"new_game": session.start_new_game()
			"reload": check(content.reload_content() == OK,"successful content reload changes generation")
			"combat": combat_token = session.lock_martial_trial()
			"world":
				var world: Dictionary = session.preview_world_action("wait")
				check(world.get("error") == OK and session.confirm_world_action(world["token"])["error"] == OK,"real world action invalidates previous state")
		before = session.state.to_dict()
		denied(session.confirm_branch_choice(preview["token"]),before,"stale after "+invalidation)
		if not combat_token.is_empty():
			denied(session.preview_branch_choice("home"),before,"preview during trial")
			session.unlock_martial_trial(combat_token)
	seed_search()
	preview = session.preview_branch_choice("dock")
	if check(preview.get("error") == OK,"damaged anchor fixture previews"):
		anchor_path = saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")
		check(IO.write_text(anchor_path,"{damaged") == OK,"damage only isolated owned anchor")
		before = session.state.to_dict()
		denied(session.confirm_branch_choice(preview["token"]),before,"damaged anchor at confirmation")
		denied(session.preview_branch_choice("home"),before,"damaged existing anchor never overwritten")
	seed_search()
	preview = session.preview_branch_choice("home")
	if check(preview.get("error") == OK,"validly rewritten anchor fixture previews"):
		anchor_path = saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")
		anchor = saves.load_choice_anchor(session.state.route_id,"CH01_FIRST_LEAD")
		var envelope: Dictionary = anchor["envelope"]
		envelope["payload"]["player_state"]["hp"] = 19
		var different: GameState = GameState.from_dict(envelope["payload"])
		envelope["choice_anchor"]["snapshot_sha256"] = saves._anchor_snapshot_hash(different)
		check(IO.write_text(anchor_path,JSON.stringify(envelope,"",true,true)) == OK,"rewrite only owned test anchor with coherent metadata")
		check(saves.load_choice_anchor(session.state.route_id,"CH01_FIRST_LEAD")["error"] == OK,"rewritten anchor remains individually well-formed")
		before = session.state.to_dict()
		denied(session.confirm_branch_choice(preview["token"]),before,"confirmation rejects a different well-formed snapshot")
	seed_search()
	anchor_path = saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(anchor_path.get_base_dir()+".new")) == OK,"real interrupted-writer fixture owns only isolated directory")
	before = session.state.to_dict()
	denied(session.preview_branch_choice("home"),before,"real interrupted anchor write never issues token")
	seed_search()
	var good_root: String = saves.test_root
	saves.test_root = "user://unsafe_path"
	before = session.state.to_dict()
	denied(session.preview_branch_choice("home"),before,"anchor persistence rejected before issuing token")
	saves.test_root = good_root
	check(same(session.state.to_dict(),before),"failed anchor save never changes live state")
	seed_search()
	check(session.apply_investigation_step("STEP_INSPECT_BLANK")["error"] == OK,"legacy progress fixture acquires actual original")
	before = session.state.to_dict()
	denied(session.preview_branch_choice("home"),before,"existing old investigation not retroactively committed")
	check(saves.save_game("manual_02",session.state) == OK,"legacy state still saves")
	var malformed := GameState.from_dict(session.state.to_dict())
	malformed.world_flags[RECORD] = {"choice":"home"}
	denied({"error":session.replace_state(malformed)},before,"malformed choice blocked in Session replacement")
	check(saves.save_game("manual_03",malformed) != OK,"malformed choice blocked at SaveService boundary")
	check(not FileAccess.file_exists(saves.slot_path("manual_03")),"invalid choice never creates a save")
	_alias_commands()
	for slot: String in ["auto_01","auto_02","auto_03"]:
		check(not FileAccess.file_exists(saves.slot_path(slot)),"foundation does not claim automatic trigger "+slot)


func _alias_commands() -> void:
	var bootstrap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/bootstrap.json"))
	for route: String in ["home","dock"]:
		seed_search()
		var preview: Dictionary = session.preview_branch_choice(route)
		if not check(preview.get("error") == OK and session.confirm_branch_choice(preview["token"])["error"] == OK,"alias guard actual choice "+route): continue
		var data: Dictionary = content.get_investigation_definitions()
		var evidence := "EV_FERRY_TOKEN_01" if route == "home" else "EV_BLANK_DEATH_01"
		var fact := "FACT_FERRY_ROUTE" if route == "home" else "FACT_YAMEN_FORMATION"
		data["steps"].append({"id":"STEP_ALIAS_TAKE","feedback_key":"INV_TOKEN_FOUND","requires":[],"effects":[{"op":"discover","id":evidence}]})
		data["steps"].append({"id":"STEP_ALIAS_MULTI","feedback_key":"INV_TOKEN_FOUND","requires":[],"effects":[{"op":"set_fact","id":"FACT_WEST_GRAVES"},{"op":"discover","id":evidence}]})
		data["steps"].append({"id":"STEP_ALIAS_ADVANTAGE","feedback_key":"INV_TOKEN_FOUND","requires":[],"effects":[{"op":"set_fact","id":fact}]})
		check(content.load_definitions(bootstrap,null,data) == OK,"registered renamed commands are legitimate data")
		var before: Dictionary = session.state.to_dict()
		for identifier: String in ["STEP_ALIAS_TAKE","STEP_ALIAS_MULTI","STEP_ALIAS_ADVANTAGE"]:
			denied(session.apply_investigation_step(identifier),before,"effect-based opposite opportunity guard "+route+" "+identifier)
			check(content.prepare_investigation_step(session.state,identifier)["error"] != OK,"ContentDB also guards direct candidate "+identifier)
		# Positive control: first acquire this route's actual materials and prove
		# that the ordinary inquiry succeeds. Otherwise an unknown proof could
		# reject before the new guard, making the security assertion vacuous.
		var inquiry := "INQ_INDEX" if route == "home" else "INQ_BOATMAN"
		var selected: Array = ["EV_INDEX_01","EV_BLANK_DEATH_01"] if route == "home" else ["EV_FERRY_TOKEN_01"]
		var acquire: Array = ["STEP_INSPECT_BLANK"] if route == "home" else ["STEP_RECORD_BOATMAN","STEP_TAKE_FERRY_TOKEN"]
		for identifier: String in acquire:
			check(session.apply_investigation_step(identifier)["error"] == OK,"inquiry control acquires real source "+identifier)
		before = session.state.to_dict()
		check(content.prepare_inquiry(session.state,inquiry,selected)["error"] == OK,"ordinary inquiry succeeds before alias guard "+route)
		check(same(session.state.to_dict(),before),"positive candidate control never commits")
		for entry: Dictionary in data["inquiries"]:
			if entry["id"] == inquiry: entry["step_id"] = "STEP_ALIAS_TAKE"
		check(content.load_definitions(bootstrap,null,data) == OK,"inquiry alias is valid authored content")
		denied(session.resolve_inquiry(inquiry,selected),before,"inquiry alias cannot bypass guard "+route)
		check(content.reload_content() == OK,"restore real content after alias guard")


func _write() -> void:
	seed_search()
	var before: Dictionary = session.state.to_dict()
	check(saves.save_game("manual_01",session.state) == OK,"cold writer stores pre-choice ordinary slot")
	var preview: Dictionary = session.preview_branch_choice(choice)
	if not check(preview.get("error") == OK,"cold writer previews actual route"): return
	var path: String = saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")
	check(session.confirm_branch_choice(preview["token"])["error"] == OK,"cold writer commits through Session")
	check(saves.save_game("quick",session.state) == OK,"cold writer persists complete chosen state")
	check(IO.write_text(fixture.path_join("receipt.json"),JSON.stringify({"writer_pid":OS.get_process_id(),"before":before,"after":session.state.to_dict(),"anchor_hash":FileAccess.get_sha256(path),"token":preview["token"],"choice":choice})) == OK,"cold writer receipt records actual complete states")


func _read() -> void:
	var path := fixture.path_join("receipt.json")
	if not check(FileAccess.file_exists(path),"cold reader requires writer receipt"): return
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not check(receipt is Dictionary and receipt.get("choice") == choice and receipt.get("writer_pid") != OS.get_process_id(),"reader matches actual other-process writer and route"): return
	var loaded: Dictionary = saves.load_game("quick",false)
	if not check(loaded.get("error") == OK,"reader exact-slot restores choice"): return
	check(same(loaded["state"].to_dict(),receipt["after"]),"cold reader recovers every field")
	check(session.replace_state(loaded["state"]) == OK,"restored chosen state accepted by real Session")
	var after: Dictionary = session.state.to_dict()
	denied(session.confirm_branch_choice(receipt["token"]),after,"previous process token not resurrected")
	denied(session.preview_branch_choice("dock" if choice == "home" else "home"),after,"cold choice cannot be repeated on another route")
	var anchor: Dictionary = saves.load_choice_anchor(session.state.route_id,"CH01_FIRST_LEAD")
	check(anchor.get("error") == OK and same(anchor["state"].to_dict(),receipt["before"]),"anchor retains exact complete pre-choice state")
	check(FileAccess.get_sha256(saves.choice_anchor_path(session.state.route_id,"CH01_FIRST_LEAD")) == receipt["anchor_hash"],"cold anchor bytes unchanged")
	loaded = saves.load_game("manual_01",false)
	check(loaded.get("error") == OK and session.replace_state(loaded["state"]) == OK,"ordinary early save remains freely loadable")
	check(same(session.state.to_dict(),receipt["before"]),"early slot has no later-route bleed")
	loaded = saves.load_game("quick",false)
	check(loaded.get("error") == OK and session.replace_state(loaded["state"]) == OK and same(session.state.to_dict(),receipt["after"]),"late slot restores original chosen route independently")
