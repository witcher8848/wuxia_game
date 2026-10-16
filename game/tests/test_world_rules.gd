extends SceneTree
## Pure world prototype: no session authority, frames, scenes or real-time clock.
const Rules = preload("res://game/domain/world/world_rules.gd")
const VENDOR := "NPC_STREET_VENDOR"
const DOCK := "NPC_DOCK_WORKER"
var checks := 0
var failures: Array[String] = []
var data: Dictionary
var regions: Dictionary = {}
var rules: WorldRules
var packed := false


func _initialize() -> void: _run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("WORLD_RULES_FAIL ",message)


func state(known := false) -> GameState:
	var result := GameState.new()
	result.scene_id = "SCENE_TOWN_STREET"
	result.player_state["position"] = {"x":512,"y":384}
	if known:
		result.world_flags["INSPECTED_"+VENDOR] = true
		result.world_flags["INSPECTED_"+DOCK] = true
	return result


func npc_definition(identifier: String) -> Dictionary:
	for npc: Dictionary in data["npcs"]:
		if npc["id"] == identifier: return npc.duplicate(true)
	return {}


func without_world_change(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	for field: String in ["time_state","character_states","relationships","world_flags"]: result.erase(field)
	return result


func _configuration() -> void:
	check(rules.configure(data,regions).is_empty(),"real world JSON and registered static regions validate")
	var source := JSON.stringify([data,regions])
	check(rules.definitions() == data,"definitions retain exact content data")
	var detached := rules.definitions()
	detached["npcs"][0]["schedule"].clear()
	check(rules.definitions() == data and JSON.stringify([data,regions]) == source,"published registry deeply owns copies")
	var bad_cases: Array = [null,[],"bad",{}, {"version":1}]
	for field: String in ["version","time_labels","reputation_flag","npcs"]:
		var bad := data.duplicate(true)
		bad.erase(field)
		bad_cases.append(bad)
	for change: Dictionary in [{"version":true},{"version":2},{"reputation_flag":true},{"reputation_flag":"OTHER"},{"time_labels":null},{"time_labels":["WORLD_TIME_0"]},{"npcs":null},{"npcs":[]},{"extra":1}]:
		var bad := data.duplicate(true)
		bad.merge(change,true)
		bad_cases.append(bad)
	for value: Variant in [null,true,1,"BAD_TIME"]:
		var bad := data.duplicate(true)
		bad["time_labels"][0] = value
		bad_cases.append(bad)
	for value: Variant in [null,"npc",{}, {"id":VENDOR}]:
		var bad := data.duplicate(true)
		bad["npcs"][0] = value
		bad_cases.append(bad)
	for change: Dictionary in [{"id":"MISSING"},{"id":DOCK},{"scene_id":"SCENE_MISSING"},{"scene_id":1},{"anchors":[]},{"anchors":null},{"schedule":[]},{"schedule":null},{"time_dialogue":null},{"time_dialogue":[]},{"extra":1}]:
		var bad := data.duplicate(true)
		bad["npcs"][0].merge(change,true)
		bad_cases.append(bad)
	for value: Variant in [null,true,-1,3,0.5,"1"]:
		var bad := data.duplicate(true)
		bad["npcs"][0]["schedule"][1] = value
		bad_cases.append(bad)
	for value: Variant in [null,true,1,"WORLD_VENDOR_CHAT_0","WORLD_DOCK_CHAT_1","WORLD_TIME_1"]:
		var bad := data.duplicate(true)
		bad["npcs"][0]["time_dialogue"][1] = value
		bad_cases.append(bad)
	var missing_dialogue := data.duplicate(true)
	missing_dialogue["npcs"][0].erase("time_dialogue")
	bad_cases.append(missing_dialogue)
	for position: Variant in [null,[],[608],[608,"352"],[610,352],[0,0],[512,128],[384,352],[864,512],[512,384],[608,352]]:
		var bad := data.duplicate(true)
		bad["npcs"][0]["anchors"][1]["position"] = position
		bad_cases.append(bad)
	for schedule: Array in [[1,0,1,2,0,1,2,0],[0,0,0,0,0,0,0,0]]:
		var bad := data.duplicate(true)
		bad["npcs"][0]["schedule"] = schedule
		bad_cases.append(bad)
	var duplicate := data.duplicate(true)
	duplicate["npcs"][1] = duplicate["npcs"][0].duplicate(true)
	bad_cases.append(duplicate)
	for index: int in range(bad_cases.size()):
		var bad: Variant = bad_cases[index]
		var before := JSON.stringify(bad)
		check(not rules.configure(bad,regions).is_empty(),"malformed world definition rejected "+str(index))
		check(rules.definitions() == data and JSON.stringify(bad) == before,"bad reload atomically preserves registry and caller data "+str(index))
	for patch: Dictionary in [{"obstacles":[{"rect":"bad"}]},{"interactions":[null]},{"spawns":[]},{"size":[1]},{"id":true}]:
		var bad := regions.duplicate(true)
		bad["SCENE_TOWN_STREET"].merge(patch,true)
		check(not rules.configure(data,bad).is_empty() and rules.definitions() == data,"malformed static geometry rejected before indexing")
	check(JSON.stringify([data,regions]) == source,"all validation leaves original JSON data unchanged")


func _queries_and_schedule() -> void:
	var original := state()
	var before := original.to_dict()
	check(rules.validate_state(original).is_empty() and rules.people_view(original)["people"].is_empty(),"unknown NPCs have no people-page identity/position leakage")
	check(rules.time_view(original) == {"day":1,"slot":0,"label":"WORLD_TIME_0"},"stable time localization key, no translated text in domain")
	for identifier: String in [VENDOR,DOCK]:
		var npc: Dictionary = rules.npc_view(original,identifier)["npc"]
		check(not npc["known"] and not npc["can_help_today"] and npc["last_known_scene"].is_empty(),"unmet NPC query does not invent last-known location")
		check(npc["position"] == npc_definition(identifier)["anchors"][0]["position"],"slot zero preserves original production placement")
	check(original.to_dict() == before,"queries do not seed any empty old container")
	var projections: Dictionary = {}
	for slot: int in range(8):
		var current := state(true)
		current.time_state["slot"] = slot
		var snapshot := current.to_dict()
		for identifier: String in [VENDOR,DOCK]:
			var npc: Dictionary = rules.npc_view(current,identifier)["npc"]
			var definition := npc_definition(identifier)
			var expected: int = int(definition["schedule"][slot])
			check(npc["anchor"] == expected and npc["position"] == definition["anchors"][expected]["position"],"full eight-slot schedule uses registered anchor "+identifier+str(slot))
			check(npc["dialogue_keys"][0] == definition["time_dialogue"][slot] and npc["dialogue_keys"][1] == definition["anchors"][expected]["label"],"NPC's real time dialogue changes independently of repeated anchor "+identifier+str(slot))
			var projected: Dictionary = rules.project_region(current,regions[npc["scene_id"]])
			check(projected["error"] == OK,"pure region projection is valid")
			var found := false
			for interaction: Dictionary in projected["region"]["interactions"]:
				if interaction["id"] == identifier:
					found = interaction["position"] == npc["position"] and interaction["character_id"] == identifier
			check(found,"projection preserves stable interaction ID and replaces real NPC body position")
			projected["region"]["interactions"].clear()
			check(not rules.project_region(current,regions[npc["scene_id"]])["region"]["interactions"].is_empty(),"caller cannot corrupt future projected interactions")
			if slot == 0: projections[identifier] = npc["position"]
			if slot == 1: check(npc["position"] != projections[identifier],"first advance physically changes each NPC anchor")
		check(current.to_dict() == snapshot,"all schedule and map queries are read-only "+str(slot))
	var known := state(true)
	var people: Dictionary = rules.people_view(known)
	check(people["people"].size() == 2 and people["reputation_label"] == "WORLD_REP_UNKNOWN","met NPCs and town reputation have visible read models")
	people["people"][0]["position"].clear()
	check(rules.people_view(known)["people"][0]["position"].size() == 2,"people read model does not alias state or registry")
	var bogus: Dictionary = regions["SCENE_TOWN_STREET"].duplicate(true)
	bogus["interactions"].clear()
	check(rules.project_region(known,bogus)["error"] == ERR_INVALID_DATA and rules.npc_view(known,"MISSING")["error"] == ERR_INVALID_PARAMETER,"projection cannot smuggle edited static content or unknown NPC IDs")


func _advance_and_services() -> void:
	var original := state()
	original.world_flags["FACT_LEGACY"] = true
	original.relationships["CHAR_PRISONER"] = {"trust":1}
	original.character_states["CHAR_OTHER"] = {"future":true}
	var before := original.to_dict()
	var waiting: Dictionary = rules.prepare_wait(original)
	check(waiting["error"] == OK and waiting["summary"]["action_id"] == "WORLD_WAIT_ONE" and waiting["summary"]["time_cost"] == 1,"waiting prepares exactly one explicit slot")
	check(waiting["state"].time_state == {"day":1,"slot":1} and original.to_dict() == before,"waiting prepares detached next state but does not commit")
	check(waiting["state"].world_flags == original.world_flags and waiting["state"].relationships == original.relationships,"waiting does not grant social reward or erase story facts")
	check(waiting["state"].character_states["CHAR_OTHER"] == {"future":true} and without_world_change(waiting["state"].to_dict()) == without_world_change(before),"world action preserves all unrelated legacy partitions")
	check(rules.prepare_wait(original)["state"].to_dict() == waiting["state"].to_dict(),"repeating a preview produces identical result, not hidden time increments")
	check(rules.prepare_help(original,VENDOR)["error"] == ERR_UNAVAILABLE and original.to_dict() == before,"unknown person cannot receive service rewards")
	check(rules.prepare_help(original,"MISSING")["error"] == ERR_INVALID_PARAMETER,"unknown service ID rejected")
	var current := state(true)
	var before_dialogue: Array = rules.npc_view(current,VENDOR)["npc"]["dialogue_keys"]
	var prepared: Dictionary = rules.prepare_help(current,VENDOR)
	check(prepared["error"] == OK and current.time_state["slot"] == 0 and current.relationships.is_empty(),"real service also remains an uncommitted candidate")
	current = prepared["state"]
	check(current.time_state == {"day":1,"slot":1} and current.relationships[VENDOR]["trust"] == 1 and current.world_flags["REP_TOWN"] == 1 and current.character_states[VENDOR]["last_help_day"] == 1,"help spends one slot and earns one personal trust plus one town reputation")
	check(prepared["summary"]["trust_delta"] == 1 and prepared["summary"]["reputation_delta"] == 1,"confirmation summary exposes actual social deltas")
	var npc: Dictionary = rules.npc_view(current,VENDOR)["npc"]
	check(npc["relationship_label"] == "WORLD_REL_FRIENDLY" and npc["dialogue_keys"] != before_dialogue and "WORLD_CHAT_FRIENDLY" in npc["dialogue_keys"] and "WORLD_CHAT_REP_POSITIVE" in npc["dialogue_keys"],"first legitimate service changes actual dialogue/relationship stage immediately")
	check("WORLD_CHAT_NEW" in rules.npc_view(current,DOCK)["npc"]["dialogue_keys"] and "WORLD_CHAT_REP_POSITIVE" in rules.npc_view(current,DOCK)["npc"]["dialogue_keys"],"town reputation affects another NPC without inventing personal trust")
	before = current.to_dict()
	check(not npc["can_help_today"] and rules.prepare_help(current,VENDOR)["error"] == ERR_ALREADY_EXISTS and current.to_dict() == before,"same NPC cannot be farmed twice that day")
	prepared = rules.prepare_help(current,DOCK)
	check(prepared["error"] == OK and prepared["state"].world_flags["REP_TOWN"] == 2,"second NPC has independent daily service allowance")
	current = prepared["state"]
	for _index in range(6): current = rules.prepare_wait(current)["state"]
	check(current.time_state == {"day":2,"slot":0} and rules.npc_view(current,VENDOR)["npc"]["can_help_today"],"eight technical slots roll to next day and refresh daily availability")
	prepared = rules.prepare_help(current,VENDOR)
	check(prepared["error"] == OK and prepared["state"].character_states[VENDOR]["last_help_day"] == 2 and prepared["state"].relationships[VENDOR]["trust"] == 2,"service can be earned again next day, not via repeated same-day dialogue")
	current.relationships[VENDOR]["trust"] = 100
	current.world_flags["REP_TOWN"] = 100
	prepared = rules.prepare_help(current,VENDOR)
	check(prepared["error"] == OK and prepared["summary"]["trust_delta"] == 0 and prepared["summary"]["reputation_delta"] == 0 and prepared["state"].relationships[VENDOR]["trust"] == 100,"capped rewards are reported honestly, not overflowing or falsely promising +1")
	var overflow := state()
	overflow.time_state = {"day":Rules.MAX_DAY,"slot":7}
	before = overflow.to_dict()
	check(rules.prepare_wait(overflow)["error"] == ERR_UNAVAILABLE and overflow.to_dict() == before,"bounded time cannot wrap integer range or partially mutate state")
	var historical := state()
	historical.time_state = {"day":1000000000000,"slot":7}
	check(rules.validate_state(historical).is_empty() and rules.time_view(historical)["day"] == 1000000000000,"old positive day beyond 1e9 remains readable without a new arbitrary cap")
	var historical_next: Dictionary = rules.prepare_wait(historical)
	var roundtrip := GameState.from_dict(JSON.parse_string(JSON.stringify(historical_next["state"].to_dict())))
	check(historical_next["error"] == OK and roundtrip != null and roundtrip.time_state["day"] == 1000000000001 and rules.validate_state(roundtrip).is_empty(),"large but safe old day advances and survives real JSON round-trip exactly")
	var edge := state()
	edge.time_state = {"day":Rules.MAX_DAY-1,"slot":7}
	var edge_next: Dictionary = rules.prepare_wait(edge)
	check(edge_next["error"] == OK and edge_next["state"].time_state["day"] == Rules.MAX_DAY,"last consecutive exact JSON day rolls over without narrowing compatibility")
	var extreme := state()
	extreme.time_state = {"day":9223372036854775807,"slot":0}
	check(rules.validate_state(extreme).is_empty() and rules.time_view(extreme)["day"] == 9223372036854775807,"int64 maximum legacy day remains queryable without float coercion")
	check(rules.prepare_wait(extreme)["error"] == OK and rules.prepare_wait(extreme)["state"].time_state["day"] == 9223372036854775807,"same-day slot advance need not add or wrap a huge legacy day")
	extreme.time_state["slot"] = 7
	check(rules.prepare_wait(extreme)["error"] == ERR_UNAVAILABLE,"unsafe cross-day advance is rejected even when old day remains readable")


func _safe_locations_and_persistence() -> void:
	for identifier: String in [VENDOR,DOCK]:
		var original := state(true)
		var definition := npc_definition(identifier)
		var target: Array = definition["anchors"][int(definition["schedule"][1])]["position"]
		original.scene_id = definition["scene_id"]
		original.player_state["position"] = {"x":target[0],"y":target[1]}
		var before := original.to_dict()
		# A query alone must not choose a fallback merely because the player is
		# here. Only the confirmed-action candidate can persist that decision.
		var no_cache := GameState.from_dict(before)
		no_cache.time_state["slot"] = 1
		check(rules.npc_view(no_cache,identifier)["npc"]["position"] == target and no_cache.character_states.is_empty(),"uncached projection is strict schedule, not frame-dependent avoidance")
		var prepared: Dictionary = rules.prepare_wait(original)
		check(prepared["error"] == OK and original.to_dict() == before,"overlap avoidance remains atomic and does not push player")
		var next: GameState = prepared["state"]
		var npc: Dictionary = rules.npc_view(next,identifier)["npc"]
		check(npc["position"] != target and next.player_state == original.player_state and next.character_states[identifier]["location"]["anchor"] == npc["anchor"],"transaction chooses and records a safe declared fallback, player stays exact")
		var stable: Array = npc["position"].duplicate()
		next.player_state["position"] = {"x":32,"y":32}
		check(rules.npc_view(next,identifier)["npc"]["position"] == stable,"walking away does not relocate cached NPC within same tick")
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(next.to_dict())))
		check(restored != null and rules.validate_state(restored).is_empty() and rules.npc_view(restored,identifier)["npc"]["position"] == stable,"JSON/schema1 round-trip restores the exact chosen safe anchor")
		var later: GameState = rules.prepare_wait(restored)["state"]
		check(rules.npc_view(later,identifier)["npc"]["anchor"] == int(definition["schedule"][2]),"next confirmed tick reevaluates schedule, not permanent random fallback")
	var current := state(true)
	current.time_state["slot"] = 4
	current.character_states[VENDOR] = {"location":{"day":1,"slot":1,"anchor":0}}
	check(rules.npc_view(current,VENDOR)["npc"]["anchor"] == int(npc_definition(VENDOR)["schedule"][4]),"legitimate past cached locations do not override a newer time")


func _state_validation_and_legacy() -> void:
	var cases: Array[GameState] = []
	for bad: Variant in [null,true,-101,101,0.5,"1"]:
		var invalid := state()
		invalid.world_flags["REP_TOWN"] = bad
		cases.append(invalid)
	for bad: Variant in [null,[],1,{"trust":true},{"trust":101},{"trust":0.5},{"unknown":0},{"alignment":-101}]:
		var invalid := state()
		invalid.relationships[VENDOR] = bad
		cases.append(invalid)
	for bad: Variant in [null,[],1,{"last_help_day":0},{"last_help_day":2},{"last_help_day":true},{"location":[]},{"location":{}},{"location":{"day":1,"slot":1,"anchor":0}},{"location":{"day":1,"slot":0,"anchor":3}},{"location":{"day":1,"slot":0,"anchor":true}},{"location":{"day":1,"slot":0,"anchor":0,"extra":1}},{"unknown":1}]:
		var invalid := state()
		invalid.character_states[VENDOR] = bad
		cases.append(invalid)
	var invalid := state()
	invalid.world_flags["INSPECTED_"+VENDOR] = 1
	cases.append(invalid)
	for candidate: GameState in cases:
		var before := candidate.to_dict()
		check(not rules.validate_state(candidate).is_empty(),"bad owned world value rejected rather than cleaned "+str(checks))
		check(rules.prepare_wait(candidate)["error"] == ERR_INVALID_DATA and rules.people_view(candidate)["error"] == ERR_INVALID_DATA and candidate.to_dict() == before,"bad state cannot be projected/advanced or partially replaced")
	var old := state()
	old.character_states[VENDOR] = {}
	old.relationships[VENDOR] = {}
	var before := old.to_dict()
	check(rules.validate_state(old).is_empty() and rules.npc_view(old,VENDOR)["npc"]["trust"] == 0 and old.to_dict() == before,"old empty owned records remain empty on read")
	var absent := Rules.new()
	check(absent.validate_state(old).is_empty() and absent.time_view(old)["label"] == "WORLD_TIME_0" and absent.people_view(old)["people"].is_empty(),"old content with no world_path keeps schema1/time compatibility")
	var projected: Dictionary = absent.project_region(old,regions["SCENE_TOWN_STREET"])
	check(projected["error"] == OK and projected["region"] == regions["SCENE_TOWN_STREET"] and old.to_dict() == before,"unconfigured world performs exact detached legacy projection")
	check(absent.prepare_wait(old)["error"] == ERR_UNAVAILABLE,"unconfigured old content cannot invent new time actions")


func _run() -> void:
	packed = FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot")
	if "--require-pack" in OS.get_cmdline_user_args():
		check(packed,"real exported pack, no source overlay")
		if not packed: quit(1); return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/world_state.json"))
	var exploration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/exploration.json"))
	for region: Dictionary in exploration["regions"]: regions[region["id"]] = region
	rules = Rules.new()
	_configuration()
	_queries_and_schedule()
	_advance_and_services()
	_safe_locations_and_persistence()
	_state_validation_and_legacy()
	print("WORLD_RULES: %d checks, %d failures; pure prototype, no human acceptance" % [checks,failures.size()])
	if failures.is_empty(): print("WORLD_RULES_PASS checks=%d packed=%s" % [checks,str(packed)])
	quit(0 if failures.is_empty() else 1)
