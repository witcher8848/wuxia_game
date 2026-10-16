extends SceneTree
## Actual ContentDB/GameSession/SaveService world workflow. Default mode is a
## same-process save/load regression, NOT cold-restart evidence. --phase=write
## and --phase=read require two independently launched OS processes and receipts.
const IO = preload("res://game/persistence/save_file_io.gd")
const NPCS := ["NPC_STREET_VENDOR","NPC_DOCK_WORKER"]
const SCENES := ["SCENE_TOWN_STREET","SCENE_HOME_COURTYARD","SCENE_RIVER_DOCK"]
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var saves: Node
var fixture := ""
var phase := ""
var packed := false


func _initialize() -> void:
	create_timer(100).timeout.connect(func() -> void: printerr("WEEK7_WORLD_SESSION_FAIL watchdog"); quit(124))
	_run.call_deferred()


func check(ok: bool,label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WEEK7_WORLD_SESSION_FAIL ",label)
	return ok


static func same(left: Variant,right: Variant) -> bool:
	# JSON restores whole numbers as floats. Preserve every key/value/array item;
	# do not mistake only that numeric tag difference for a lost persistent field.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func denied(result: Dictionary,before: Dictionary,label: String) -> void:
	check(typeof(result.get("error")) == TYPE_INT,label+" reports a typed error code")
	check(result.get("error",OK) != OK,label+" is rejected")
	check(session.state.to_dict() == before,label+" changes no live field")


func projections() -> Dictionary:
	var before: Dictionary = session.state.to_dict()
	var result := {"clock":content.world_time(session.state),"people":content.people_entries(session.state),"npcs":{},"regions":{}}
	check(not str(result["clock"].get("label","")).is_empty(),"world time has a human-readable period label")
	for identifier: String in NPCS:
		var npc: Dictionary = content.world_npc(session.state,identifier)
		check(npc.get("error",ERR_INVALID_DATA) == OK and not npc.get("npc",{}).is_empty(),"registered NPC has a real current world projection "+identifier)
		result["npcs"][identifier] = npc
	for identifier: String in SCENES:
		var view: Dictionary = content.exploration_view(identifier,session.state)
		check(view.get("error","missing").is_empty() and not view.get("region",{}).is_empty(),"registered region has a current world projection "+identifier)
		result["regions"][identifier] = view
	check(session.state.to_dict() == before,"clock/NPC/map/people queries are completely read-only")
	return result


func npc_target(identifier: String) -> Dictionary:
	var found: Dictionary = {}
	var count := 0
	for scene_id: String in SCENES:
		var view: Dictionary = content.exploration_view(scene_id,session.state)
		if not view.get("error","missing").is_empty(): continue
		for target: Dictionary in view["region"].get("interactions",[]):
			if target.get("id") == identifier:
				found = {"scene":scene_id,"region":view["region"],"target":target}
				count += 1
	check(count == 1,"scheduled NPC appears exactly once across real maps "+identifier)
	return found


func enter_scene(identifier: String) -> bool:
	var definition: Dictionary = content.get_exploration_region(identifier)
	for spawn_id: String in definition.get("spawns",{}):
		if session.enter_region(identifier,spawn_id) == OK: return true
	return check(false,"registered spawn can enter "+identifier)


func approach(identifier: String) -> bool:
	var target := npc_target(identifier)
	if target.is_empty() or not enter_scene(target["scene"]): return false
	var position: Array = target["target"]["position"]
	var at := Vector2(position[0],position[1])
	# Use legal public movement updates and real safe geometry, not injected NPC
	# positions or modified content. Physical keyboard walking has its own suite.
	for offset: Vector2 in [Vector2(32,0),Vector2(-32,0),Vector2(0,32),Vector2(0,-32)]:
		var candidate := at+offset
		if not content.is_safe_world_position(target["scene"],candidate,session.state): continue
		if session.update_player_position(candidate) != OK: continue
		check(candidate.distance_to(at) <= 58,"help approach is actually within the registered interaction radius")
		return true
	return check(false,"scheduled NPC has a safe adjacent interaction point "+identifier)


func wait_once(label: String) -> bool:
	var before: Dictionary = session.state.to_dict()
	var proposal: Dictionary = session.preview_world_action("wait")
	if not check(proposal.get("error",ERR_INVALID_DATA) == OK and not proposal.get("token","").is_empty(),label+" offers a real wait token"): return false
	check(session.state.to_dict() == before,label+" preview does not spend time")
	var result: Dictionary = session.confirm_world_action(proposal["token"])
	if not check(result.get("error",ERR_INVALID_DATA) == OK,label+" confirmation succeeds"): return false
	check(result.get("summary") is Dictionary,label+" returns the authoritative world-change summary")
	var slot: int = int(before["time_state"]["slot"])+1
	check(session.state.time_state == {"day":int(before["time_state"]["day"])+int(slot/8),"slot":slot%8},label+" advances exactly one compatible technical slot")
	for field: String in ["route_id","scene_id","spawn_id","player_state","quest_states","evidence_states","martial_states","inventory","relationships"]:
		check(same(session.state.to_dict()[field],before[field]),label+" leaves non-time field unchanged "+field)
	check(session.state.world_flags.get("REP_TOWN",0) == before["world_flags"].get("REP_TOWN",0),label+" waiting grants no free reputation")
	var after: Dictionary = session.state.to_dict()
	denied(session.confirm_world_action(proposal["token"]),after,label+" consumed token replay")
	return true


func help_once(identifier: String,label: String) -> bool:
	if not approach(identifier): return false
	check(session.mark_inspected(identifier) == OK,label+" records the real registered NPC inspection")
	var before: Dictionary = session.state.to_dict()
	var trust: int = int(before["relationships"].get(identifier,{}).get("trust",0))
	var reputation: int = int(before["world_flags"].get("REP_TOWN",0))
	var proposal: Dictionary = session.preview_world_action("help",identifier)
	if not check(proposal.get("error",ERR_INVALID_DATA) == OK and not proposal.get("token","").is_empty(),label+" offers an authorized help token"): return false
	check(session.state.to_dict() == before,label+" preview cannot award trust/reputation")
	var result: Dictionary = session.confirm_world_action(proposal["token"])
	if not check(result.get("error",ERR_INVALID_DATA) == OK,label+" confirmation succeeds"): return false
	check(result.get("summary") is Dictionary,label+" returns the authoritative help summary")
	check(session.state.relationships.get(identifier,{}).get("trust") == trust+1,label+" awards exactly one trust")
	check(session.state.world_flags.get("REP_TOWN") == reputation+1,label+" awards exactly one town reputation")
	check(session.state.character_states.get(identifier,{}).get("last_help_day") == before["time_state"]["day"],label+" records which day was helped")
	var location: Dictionary = session.state.character_states.get(identifier,{}).get("location",{})
	check(location.has("day") and location.has("slot") and GameState.is_whole_number(location.get("anchor")) and location["anchor"] >= 0 and location["anchor"] <= 2,label+" stores a real day/slot/integer-anchor location receipt")
	var npc_after: Dictionary = content.world_npc(session.state,identifier)
	check(npc_after.get("error",ERR_INVALID_DATA) == OK and npc_after.get("npc",{}).get("anchor") == location.get("anchor"),label+" persisted anchor is the actual post-action projected position")
	var slot: int = int(before["time_state"]["slot"])+1
	check(session.state.time_state == {"day":int(before["time_state"]["day"])+int(slot/8),"slot":slot%8},label+" costs precisely one compatible technical slot")
	for field: String in ["route_id","scene_id","spawn_id","player_state","quest_states","evidence_states","martial_states","inventory"]:
		check(same(session.state.to_dict()[field],before[field]),label+" preserves unrelated persistent field "+field)
	for identifier_before: String in before["relationships"]:
		if identifier_before != identifier: check(same(session.state.relationships.get(identifier_before),before["relationships"][identifier_before]),label+" preserves other existing relationships")
	for flag: String in before["world_flags"]:
		if flag != "REP_TOWN": check(same(session.state.world_flags.get(flag),before["world_flags"][flag]),label+" preserves existing investigation/world flag "+flag)
	var after: Dictionary = session.state.to_dict()
	denied(session.confirm_world_action(proposal["token"]),after,label+" help replay")
	return true


func command_security() -> void:
	session.start_new_game()
	var before: Dictionary = session.state.to_dict()
	for kind: String in ["", "WAIT", "unknown"]: denied(session.preview_world_action(kind),before,"invalid action kind "+kind)
	denied(session.preview_world_action("help","MISSING_NPC"),before,"unknown NPC")
	denied(session.confirm_world_action(""),before,"empty token")
	denied(session.confirm_world_action("WORLD_FORGED"),before,"invented token")
	var proposal: Dictionary = session.preview_world_action("wait")
	if not check(proposal.get("error",ERR_INVALID_DATA) == OK,"cancel fixture previews wait"): return
	session.cancel_world_action("not_the_owned_token")
	check(session.state.to_dict() == before,"wrong-token cancel has no side effects")
	session.cancel_world_action(proposal["token"])
	denied(session.confirm_world_action(proposal["token"]),before,"cancelled token")
	var older: Dictionary = session.preview_world_action("wait")
	var current: Dictionary = session.preview_world_action("wait")
	if not check(older.get("error",ERR_INVALID_DATA) == OK and current.get("error",ERR_INVALID_DATA) == OK,"replacement preview offers two real proposals"): return
	check(older["token"] != current["token"],"replacement preview cannot reuse the same capability")
	denied(session.confirm_world_action(older["token"]),before,"superseded token")
	session.cancel_world_action(current["token"])
	proposal = session.preview_world_action("wait")
	check(session.mark_inspected("DOC_STREET_NOTICE") == OK,"real public state change can invalidate a pending proposal")
	before = session.state.to_dict()
	denied(session.confirm_world_action(proposal["token"]),before,"proposal with changed world snapshot")
	proposal = session.preview_world_action("wait")
	check(session.replace_state(GameState.from_dict(session.state.to_dict())) == OK,"actual session replace establishes a new ownership boundary")
	before = session.state.to_dict()
	denied(session.confirm_world_action(proposal["token"]),before,"token from replaced session state")
	wait_once("first authorized wait")


func help_requirements() -> void:
	session.start_new_game()
	if not approach(NPCS[0]): return
	var before: Dictionary = session.state.to_dict()
	denied(session.preview_world_action("help",NPCS[0]),before,"help before inspecting NPC")
	check(session.mark_inspected(NPCS[0]) == OK,"registered inspection unlocks prerequisite")
	var target := npc_target(NPCS[0])
	for scene_id: String in SCENES:
		if scene_id != target["scene"] and enter_scene(scene_id): break
	before = session.state.to_dict()
	denied(session.preview_world_action("help",NPCS[0]),before,"help from wrong scene")
	if not enter_scene(target["scene"]): return
	var point: Array = target["target"]["position"]
	var at := Vector2(point[0],point[1])
	var current: Dictionary = session.state.player_state["position"]
	check(Vector2(current["x"],current["y"]).distance_to(at) > 58,"real registered spawn is out of help range")
	before = session.state.to_dict()
	denied(session.preview_world_action("help",NPCS[0]),before,"remote NPC help")
	if not approach(NPCS[0]): return
	var proposal: Dictionary = session.preview_world_action("help",NPCS[0])
	if not check(proposal.get("error",ERR_INVALID_DATA) == OK,"near inspected NPC offers real help"): return
	before = session.state.to_dict()
	session.cancel_world_action(proposal["token"])
	denied(session.confirm_world_action(proposal["token"]),before,"cancelled real NPC help")
	proposal = session.preview_world_action("help",NPCS[0])
	check(session.update_player_position(Vector2(current["x"],current["y"])) == OK,"public movement can leave a pending help location")
	before = session.state.to_dict()
	denied(session.confirm_world_action(proposal["token"]),before,"help after moving away from preview location")


func combat_locks() -> void:
	session.start_new_game()
	var proposal: Dictionary = session.preview_world_action("wait")
	var token: String = session.lock_martial_trial()
	if not check(not token.is_empty(),"actual production trial lock acquired"): return
	var before: Dictionary = session.state.to_dict()
	denied(session.preview_world_action("wait"),before,"wait during trial")
	denied(session.preview_world_action("help",NPCS[0]),before,"help during trial")
	denied(session.confirm_world_action(proposal.get("token","")),before,"pending world confirmation during trial")
	check(saves.save_game("manual_05",session.state) == ERR_BUSY,"actual SaveService cannot overwrite a route during trial")
	check(session.unlock_martial_trial(token),"owned trial lock releases normally")
	session.cancel_world_action(proposal.get("token",""))
	for step_id: String in ["STEP_RECEIVE_INDEX","STEP_ACCEPT_SEARCH","STEP_INSPECT_BLANK"]:
		check(session.apply_investigation_step(step_id)["error"] == OK,"public investigation unlock "+step_id)
	check(session.resolve_inquiry("INQ_INDEX",["EV_INDEX_01","EV_BLANK_DEATH_01"])["error"] == OK,"actual inquiry unlocks the original story battle")
	for _period: int in range(8):
		var boatman := npc_target(NPCS[1])
		if boatman.get("scene") == "SCENE_RIVER_DOCK": break
		if not wait_once("find the scheduled boatman"): return
	if not approach(NPCS[1]): return
	check(session.state.scene_id == "SCENE_RIVER_DOCK","scheduled story boatman is at the production dock")
	check(session.mark_inspected(NPCS[1]) == OK,"actual dock NPC has been inspected")
	proposal = session.preview_world_action("wait")
	var opened: Dictionary = session.begin_story_encounter()
	if not check(opened.get("error",ERR_INVALID_DATA) == OK and session.story_encounter_active(),"real owned story battle starts"): return
	before = session.state.to_dict()
	denied(session.preview_world_action("wait"),before,"wait during owned story")
	denied(session.preview_world_action("help",NPCS[1]),before,"help during owned story")
	denied(session.confirm_world_action(proposal.get("token","")),before,"pending world confirmation during story")
	check(saves.save_game("manual_05",session.state) == ERR_BUSY,"actual SaveService cannot overwrite a route during story")
	check(session.abort_story_encounter(opened["token"]) == OK and not session.combat_active(),"normal owned story abort releases world actions")
	session.cancel_world_action(proposal.get("token",""))


func write_flow() -> Dictionary:
	session.start_new_game()
	var legacy: Dictionary = session.state.to_dict()
	check(legacy["character_states"].is_empty() and legacy["relationships"].is_empty() and legacy["world_flags"].is_empty(),"legacy route starts with genuinely empty world/social containers")
	var legacy_projection := projections()
	check(saves.save_game("manual_01",session.state) == OK,"real SaveService persists exact legacy empty route")
	var legacy_sha := FileAccess.get_sha256(saves.slot_path("manual_01"))
	command_security()
	help_requirements()
	combat_locks()
	if session.combat_active(): check(false,"all owned test combat must be released"); return {}
	session.start_new_game()
	if not help_once(NPCS[0],"first vendor help"): return {}
	if not approach(NPCS[0]): return {}
	var before: Dictionary = session.state.to_dict()
	denied(session.preview_world_action("help",NPCS[0]),before,"same NPC cannot be helped twice on the same day at its new position")
	if not help_once(NPCS[1],"independent boatman help"): return {}
	check(session.state.relationships[NPCS[0]]["trust"] == 1 and session.state.relationships[NPCS[1]]["trust"] == 1 and session.state.world_flags["REP_TOWN"] == 2,"daily limit belongs to each NPC, not a global one-help cap")
	for _period: int in range(8):
		if int(session.state.time_state["day"]) == 2: break
		if not wait_once("next-day technical boundary"): return {}
	check(session.state.time_state == {"day":2,"slot":0},"eight technical slots roll over to next prototype day, not final story-calendar claims")
	if not help_once(NPCS[0],"next-day vendor help"): return {}
	check(session.state.relationships[NPCS[0]]["trust"] == 2 and session.state.relationships[NPCS[1]]["trust"] == 1 and session.state.world_flags["REP_TOWN"] == 3,"next day allows exactly one additional confirmed relationship/reputation reward")
	var world: Dictionary = session.state.to_dict()
	var projection := projections()
	check(saves.save_game("manual_02",session.state) == OK and saves.save_game("quick",session.state) == OK,"actual world/social route is persisted in independent exact slots")
	var world_sha := FileAccess.get_sha256(saves.slot_path("manual_02"))
	if not wait_once("backup distinct time"): return {}
	check(saves.save_game("quick",session.state) == OK,"genuine second save creates a prior-world exact-slot backup")
	check(IO.write_text(saves.slot_path("quick"),"{test-owned corrupt primary") == OK,"damage only this isolated fixture quick primary for real backup recovery")
	var malformed := GameState.from_dict(world)
	if not check(malformed != null,"real saved world can be copied into an isolated invalid-save fixture"): return {}
	malformed.world_flags["REP_TOWN"] = "not a reputation number"
	var untouched: Dictionary = session.state.to_dict()
	check(saves.save_game("manual_03",malformed) == ERR_INVALID_DATA,"real SaveService rejects semantically malformed world reputation")
	check(session.state.to_dict() == untouched,"rejected external save payload cannot mutate live world state")
	check(not FileAccess.file_exists(saves.slot_path("manual_03")),"rejected world save created no slot")
	check(IO.write_text(saves.slot_path("manual_03"),JSON.stringify(saves._make_envelope("manual_03",malformed))) == OK,"write only an isolated malformed semantic envelope for cold-reader refusal")
	check(FileAccess.get_sha256(saves.slot_path("manual_01")) == legacy_sha and FileAccess.get_sha256(saves.slot_path("manual_02")) == world_sha,"all later world commands leave both earlier actual slot bytes untouched")
	var pending: Dictionary = session.preview_world_action("wait")
	check(pending.get("error",ERR_INVALID_DATA) == OK,"pending world capability exists before writer shutdown")
	var expected := {"legacy":legacy,"legacy_projection":legacy_projection,"legacy_sha":legacy_sha,"world":world,"projection":projection,"world_sha":world_sha,"writer_pid":OS.get_process_id(),"pending_token":pending.get("token","")}
	check(IO.write_text(fixture.path_join("expected.json"),JSON.stringify(expected)) == OK,"writer emits exact world/social/projection snapshots, not a fabricated read result")
	return expected


func read_flow(expected: Dictionary,cold: bool) -> void:
	if cold:
		var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("write_receipt.json")))
		# Godot's is_process_running is for processes launched by that Godot
		# instance and emits an engine error for an already reaped non-child.
		# Validate identities here; check_world_persistence.py proves exit order
		# by synchronously reaping the successful writer before reader launch.
		if not check(receipt is Dictionary and receipt.get("failures",["missing"]).is_empty() and int(receipt.get("pid",0)) > 0 and int(receipt.get("pid",0)) == int(expected.get("writer_pid",0)) and int(expected.get("writer_pid",0)) != OS.get_process_id(),"successful writer receipt belongs to a distinct OS process; orchestrator proves exit order"): return
	session.start_new_game()
	var baseline: Dictionary = session.state.to_dict()
	denied(session.confirm_world_action(expected["pending_token"]),baseline,"world proposal ownership cannot revive after route/process reset")
	var bad: Dictionary = saves.load_game("manual_03",false)
	check(bad["error"] == ERR_INVALID_DATA and session.state.to_dict() == baseline,"real reader rejects malformed world semantics without replacing live state")
	var restored: Dictionary = saves.load_game("manual_02",false)
	if not check(restored["error"] == OK and same(restored["state"].to_dict(),expected["world"]),"reader restores every saved world/social/time/NPC field"): return
	check(session.replace_state(restored["state"]) == OK,"actual Session owns the restored validated world state")
	check(same(projections(),expected["projection"]),"NPC location/topic, map interactions, clock and people projections reproduce after real load")
	var owned: Dictionary = session.state.to_dict()
	restored["state"].relationships[NPCS[0]]["trust"] = 77
	check(session.state.to_dict() == owned,"mutating returned load object cannot corrupt owned live social/world state")
	var backup: Dictionary = saves.load_game("quick",false)
	check(backup["error"] == OK and backup.get("source") == "backup" and same(backup["state"].to_dict(),expected["world"]),"damaged quick recovers genuine prior-world backup, not writer's latest in-memory time")
	var legacy: Dictionary = saves.load_game("manual_01",false)
	if not check(legacy["error"] == OK and same(legacy["state"].to_dict(),expected["legacy"]),"legacy empty world/social schema1 route loads exactly"): return
	check(session.replace_state(legacy["state"]) == OK,"actual Session accepts valid legacy-empty world state")
	check(same(projections(),expected["legacy_projection"]) and same(session.state.to_dict(),expected["legacy"]),"viewing legacy schedules/people does not silently fill persistent containers")
	check(FileAccess.get_sha256(saves.slot_path("manual_01")) == expected["legacy_sha"] and FileAccess.get_sha256(saves.slot_path("manual_02")) == expected["world_sha"],"neither independent reader nor projection queries rewrites original saved bytes")


func _finish() -> void:
	if not phase.is_empty():
		check(IO.write_text(fixture.path_join(phase+"_receipt.json"),JSON.stringify({"pid":OS.get_process_id(),"phase":phase,"checks":checks,"failures":failures,"packed":packed})) == OK,"own isolated process receipt written")
	print("WEEK7_WORLD_SESSION: %d checks, %d failures; actual services; default is not cold restart" % [checks,failures.size()])
	if failures.is_empty():
		if phase.is_empty(): print("WEEK7_WORLD_SESSION_PASS checks=%d packed=%s" % [checks,str(packed)])
		else: print("WEEK7_WORLD_SESSION_PHASE_PASS phase=%s pid=%d checks=%d packed=%s fixture=%s" % [phase,OS.get_process_id(),checks,str(packed),fixture])
	saves.test_root = ""
	quit(0 if failures.is_empty() else 1)


func _run() -> void:
	await process_frame
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args(): check(packed,"real PCK only, no source project overlay")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="): fixture = argument.trim_prefix("--fixture=")
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
	if fixture.is_empty() and phase.is_empty(): fixture = "user://tests/world_session_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	if not fixture.begins_with("user://tests/world_session_") or not fixture.trim_prefix("user://tests/").is_valid_identifier() or fixture.trim_prefix("user://tests/").length() > 96 or not phase in ["","write","read"]:
		printerr("WEEK7_WORLD_SESSION_FAIL invalid isolated fixture/phase"); quit(1); return
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	saves = root.get_node("SaveService")
	saves.test_root = fixture
	for method: String in ["preview_world_action","confirm_world_action","cancel_world_action"]: check(session.has_method(method),"required actual Session API "+method)
	for method: String in ["world_time","world_npc","exploration_view","people_entries","is_safe_world_position"]: check(content.has_method(method),"required actual ContentDB API "+method)
	if not failures.is_empty(): _finish(); return
	if phase == "read":
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture.path_join("expected.json")))
		if check(expected is Dictionary and not expected.is_empty(),"cold reader has actual successful writer snapshot"): read_flow(expected,true)
	else:
		var expected := write_flow()
		if phase.is_empty() and not expected.is_empty(): read_flow(expected,false)
	_finish()
