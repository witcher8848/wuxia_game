class_name WorldRules
extends RefCounted
## Pure eight-slots-per-day prototype. Queries never seed old state; only a
## prepared, detached world action contains new time/social/location records.
const NPC_IDS := ["NPC_STREET_VENDOR","NPC_DOCK_WORKER"]
const REP_FLAG := "REP_TOWN"
# The clock may read old days anywhere in the positive int64 range. Only a
# rollover needs the next day to round-trip exactly through JSON's float parser.
const MAX_DAY := 9007199254740992 # 2^53; no exact consecutive JSON integer after it.
const FEET := Vector2(20,12)
var _data: Dictionary = {}
var _regions: Dictionary = {}
var _npcs: Dictionary = {}
var _interactions: Dictionary = {}


func configure(data: Variant, regions: Dictionary) -> String:
	if not data is Dictionary or not GameState.is_json_value(data) or not GameState.is_json_value(regions) or not _fields(data,["version","time_labels","reputation_flag","npcs"]): return "World definitions require finite supported fields."
	if not _integer(data["version"],1,1) or not data["reputation_flag"] is String or data["reputation_flag"] != REP_FLAG or not data["time_labels"] is Array or data["time_labels"].size() != 8 or not data["npcs"] is Array or data["npcs"].size() != NPC_IDS.size(): return "World version, reputation, eight labels and two NPCs are required."
	for index: int in range(8):
		if not data["time_labels"][index] is String or data["time_labels"][index] != "WORLD_TIME_%d" % index: return "World time labels must use WORLD_TIME_0 through 7."
	var npcs: Dictionary = {}
	var interactions: Dictionary = {}
	var reserved_anchors: Dictionary = {}
	for npc: Variant in data["npcs"]:
		if not npc is Dictionary or not _fields(npc,["id","scene_id","anchors","schedule","time_dialogue"]) or not npc.get("id") is String or not npc["id"] in NPC_IDS or npcs.has(npc["id"]) or not npc.get("scene_id") is String or not regions.has(npc["scene_id"]): return "Unknown, duplicate or malformed scheduled NPC."
		var region: Variant = regions[npc["scene_id"]]
		if not _valid_region(region,npc["scene_id"]): return "Scheduled NPC needs a valid static region."
		var base: Dictionary = {}
		for interaction: Dictionary in region["interactions"]:
			if interaction["id"] == npc["id"]:
				if not base.is_empty() or interaction["kind"] != "npc": return "Scheduled NPC must have one original interaction."
				base = interaction
		if base.is_empty() or not base.get("name_key") is String or not base.get("text_key") is String: return "Scheduled NPC must reference a named, readable existing interaction."
		if not npc["anchors"] is Array or npc["anchors"].size() != 3 or not npc["schedule"] is Array or npc["schedule"].size() != 8 or not npc["time_dialogue"] is Array or npc["time_dialogue"].size() != 8: return "Each NPC needs three anchors, eight schedule entries and eight dialogue keys."
		var dialogue_prefix := "WORLD_VENDOR_CHAT_" if npc["id"] == "NPC_STREET_VENDOR" else "WORLD_DOCK_CHAT_"
		for index: int in range(8):
			if not npc["time_dialogue"][index] is String or npc["time_dialogue"][index] != dialogue_prefix+str(index): return "Each NPC needs its eight ordered time-dialogue keys."
		for index: int in range(3):
			var anchor: Variant = npc["anchors"][index]
			if not anchor is Dictionary or not _fields(anchor,["position","label"]) or not _pair(anchor["position"]) or not anchor["label"] is String or not anchor["label"].is_valid_identifier() or not anchor["label"].begins_with("WORLD_"): return "Invalid world anchor geometry or localization key."
			var position := _point(anchor["position"])
			if fmod(position.x,32) != 0 or fmod(position.y,32) != 0 or not _anchor_safe(region,position,npc["id"]): return "World anchor overlaps geometry, a readable, an exit or a spawn."
			var location_key: String = npc["scene_id"]+":"+str(position)
			if reserved_anchors.has(location_key): return "World anchors must be unique within each scene."
			reserved_anchors[location_key] = true
		for index: Variant in npc["schedule"]:
			if not _integer(index,0,2): return "Unknown schedule anchor."
		if npc["schedule"][0] != 0 or _point(npc["anchors"][0]["position"]) != _point(base["position"]): return "Slot zero must preserve the original NPC position."
		for index: int in range(3):
			var used := false
			for entry: Variant in npc["schedule"]:
				if int(entry) == index: used = true
			if not used: return "Every declared anchor must be used by the schedule."
		npcs[npc["id"]] = npc.duplicate(true)
		interactions[npc["id"]] = base.duplicate(true)
	# Publish together, never partially replace a previously valid registry.
	_data = data.duplicate(true)
	_regions = regions.duplicate(true)
	_npcs = npcs
	_interactions = interactions
	return ""


func definitions() -> Dictionary:
	return _data.duplicate(true)


func validate_state(state: GameState) -> String:
	if state == null or not state.validate().is_empty(): return "Invalid world state."
	if _data.is_empty(): return "" # Old registries without world_path stay valid.
	if not _day(state.time_state.get("day")) or not _integer(state.time_state.get("slot"),0,7): return "Invalid prototype world time."
	if state.world_flags.has(REP_FLAG) and not _integer(state.world_flags[REP_FLAG],-100,100): return "Invalid town reputation."
	for identifier: String in NPC_IDS:
		var seen := "INSPECTED_"+identifier
		if state.world_flags.has(seen) and not state.world_flags[seen] is bool: return "Invalid scheduled-NPC knowledge marker."
		if state.relationships.has(identifier):
			var relationship: Variant = state.relationships[identifier]
			if not relationship is Dictionary: return "NPC relationship must be a dictionary."
			for field: Variant in relationship:
				if not field in ["trust","alignment"] or not _integer(relationship[field],-100,100): return "Invalid owned NPC relationship field."
		if not state.character_states.has(identifier): continue
		var character: Variant = state.character_states[identifier]
		if not character is Dictionary: return "Scheduled character state must be a dictionary."
		for field: Variant in character:
			if not field in ["last_help_day","location"]: return "Unknown scheduled-character state field."
		if character.has("last_help_day") and (not _day(character["last_help_day"]) or character["last_help_day"] > state.time_state["day"]): return "Invalid last-help day."
		if character.has("location"):
			var location: Variant = character["location"]
			if not location is Dictionary or not _fields(location,["day","slot","anchor"]) or not _day(location["day"]) or location["day"] > state.time_state["day"] or not _integer(location["slot"],0,7) or not _integer(location["anchor"],0,2): return "Invalid cached NPC location."
			if location["day"] == state.time_state["day"] and location["slot"] > state.time_state["slot"]: return "NPC location cannot come from a future tick."
	return ""


func time_view(state: GameState) -> Dictionary:
	if not validate_state(state).is_empty(): return {}
	return _time_view(state.time_state)


func npc_view(state: GameState, npc_id: String) -> Dictionary:
	if not validate_state(state).is_empty(): return {"error":ERR_INVALID_DATA,"npc":{}}
	if not _npcs.has(npc_id): return {"error":ERR_INVALID_PARAMETER,"npc":{}}
	return {"error":OK,"npc":_npc_view(state,npc_id)}


func people_view(state: GameState) -> Dictionary:
	if not validate_state(state).is_empty(): return {"error":ERR_INVALID_DATA,"people":[],"reputation":0,"reputation_label":"WORLD_REP_UNKNOWN"}
	if _data.is_empty(): return {"error":OK,"people":[],"reputation":0,"reputation_label":"WORLD_REP_UNKNOWN"}
	var people: Array[Dictionary] = []
	for identifier: String in NPC_IDS:
		var person := _npc_view(state,identifier)
		if not person["known"]: continue
		people.append(person)
	var reputation: int = int(state.world_flags.get(REP_FLAG,0))
	return {"error":OK,"people":people,"reputation":reputation,"reputation_label":_reputation_label(reputation)}


func project_region(state: GameState, region: Dictionary) -> Dictionary:
	if not validate_state(state).is_empty(): return {"error":ERR_INVALID_DATA,"region":{}}
	if _data.is_empty(): return {"error":OK,"region":region.duplicate(true)} if GameState.is_json_value(region) else {"error":ERR_INVALID_DATA,"region":{}}
	var scene: Variant = region.get("id")
	if not scene is String or not _regions.has(scene) or region != _regions[scene]: return {"error":ERR_INVALID_DATA,"region":{}}
	var projected := region.duplicate(true)
	for interaction: Dictionary in projected["interactions"]:
		if not _npcs.has(interaction["id"]): continue
		var npc := _npc_view(state,interaction["id"])
		interaction["position"] = npc["position"].duplicate()
		interaction["character_id"] = npc["id"]
	return {"error":OK,"region":projected}


func prepare_wait(state: GameState) -> Dictionary:
	return _prepare(state,"")


func prepare_help(state: GameState, npc_id: String) -> Dictionary:
	if not _npcs.has(npc_id): return _failure(ERR_INVALID_PARAMETER,"Unknown service NPC.")
	return _prepare(state,npc_id)


func _prepare(state: GameState, npc_id: String) -> Dictionary:
	if _data.is_empty(): return _failure(ERR_UNAVAILABLE,"World definitions are unavailable.")
	var error := validate_state(state)
	if not error.is_empty(): return _failure(ERR_INVALID_DATA,error)
	var before := _time_view(state.time_state)
	if before["day"] >= MAX_DAY and before["slot"] == 7: return _failure(ERR_UNAVAILABLE,"Next day cannot round-trip exactly through JSON.")
	var candidate := GameState.from_dict(state.to_dict())
	var trust_delta := 0
	var reputation_delta := 0
	if not npc_id.is_empty():
		if not state.world_flags.get("INSPECTED_"+npc_id,false): return _failure(ERR_UNAVAILABLE,"Meet this NPC before offering help.")
		if state.character_states.get(npc_id,{}).get("last_help_day",0) == before["day"]: return _failure(ERR_ALREADY_EXISTS,"This NPC has already received help today.")
		var relation: Dictionary = candidate.relationships.get(npc_id,{}).duplicate(true)
		var trust: int = int(relation.get("trust",0))
		trust_delta = mini(100,trust+1)-trust
		relation["trust"] = trust+trust_delta
		candidate.relationships[npc_id] = relation
		var reputation: int = int(candidate.world_flags.get(REP_FLAG,0))
		reputation_delta = mini(100,reputation+1)-reputation
		candidate.world_flags[REP_FLAG] = reputation+reputation_delta
		var character: Dictionary = candidate.character_states.get(npc_id,{}).duplicate(true)
		character["last_help_day"] = before["day"]
		candidate.character_states[npc_id] = character
	var next_slot: int = int(before["slot"])+1
	# Retain the public prototype's day/slot shape and any unrelated JSON keys.
	candidate.time_state["day"] = int(before["day"])+int(next_slot/8)
	candidate.time_state["slot"] = next_slot%8
	var placed := _prepare_locations(candidate)
	if not placed.is_empty(): return _failure(ERR_UNAVAILABLE,placed)
	error = validate_state(candidate)
	if not error.is_empty(): return _failure(ERR_INVALID_DATA,error)
	return {"error":OK,"state":candidate,"summary":{"action_id":"WORLD_WAIT_ONE" if npc_id.is_empty() else "WORLD_HELP_NPC","npc_id":npc_id,"time_cost":1,"trust_delta":trust_delta,"reputation_delta":reputation_delta,"before":before,"after":_time_view(candidate.time_state)},"message":""}


func _prepare_locations(candidate: GameState) -> String:
	for identifier: String in NPC_IDS:
		var npc: Dictionary = _npcs[identifier]
		var primary: int = int(npc["schedule"][int(candidate.time_state["slot"])])
		var order: Array[int] = [primary]
		for index: int in range(3):
			if index != primary: order.append(index)
		var chosen := -1
		for index: int in order:
			var position := _point(npc["anchors"][index]["position"])
			if candidate.scene_id == npc["scene_id"]:
				var player: Dictionary = candidate.player_state["position"]
				if _body(position).intersects(_body(Vector2(float(player["x"]),float(player["y"])))): continue
			chosen = index
			break
		if chosen < 0: return "No safe declared NPC anchor is available."
		var character: Dictionary = candidate.character_states.get(identifier,{}).duplicate(true)
		character["location"] = {"day":int(candidate.time_state["day"]),"slot":int(candidate.time_state["slot"]),"anchor":chosen}
		candidate.character_states[identifier] = character
	return ""


func _npc_view(state: GameState, identifier: String) -> Dictionary:
	var npc: Dictionary = _npcs[identifier]
	var anchor: int = int(npc["schedule"][int(state.time_state["slot"])])
	var location: Dictionary = state.character_states.get(identifier,{}).get("location",{})
	if not location.is_empty() and location["day"] == state.time_state["day"] and location["slot"] == state.time_state["slot"]: anchor = int(location["anchor"])
	var trust: int = int(state.relationships.get(identifier,{}).get("trust",0))
	var reputation: int = int(state.world_flags.get(REP_FLAG,0))
	var known: bool = state.world_flags.get("INSPECTED_"+identifier,false)
	var dialogue: Array[String] = [npc["time_dialogue"][int(state.time_state["slot"])],npc["anchors"][anchor]["label"],_trust_dialogue(trust),"WORLD_CHAT_REP_NEGATIVE" if reputation < 0 else ("WORLD_CHAT_REP_POSITIVE" if reputation > 0 else "WORLD_CHAT_REP_NEUTRAL")]
	return {"id":identifier,"name_key":_interactions[identifier]["name_key"],"text_key":_interactions[identifier]["text_key"],"scene_id":npc["scene_id"],"position":npc["anchors"][anchor]["position"].duplicate(),"anchor":anchor,"anchor_label":npc["anchors"][anchor]["label"],"trust":trust,"relationship_label":_relationship_label(trust),"known":known,"last_known_scene":npc["scene_id"] if known else "","can_help_today":known and state.character_states.get(identifier,{}).get("last_help_day",0) != state.time_state["day"],"dialogue_keys":dialogue}


func _time_view(time: Dictionary) -> Dictionary:
	return {"day":int(time["day"]),"slot":int(time["slot"]),"label":"WORLD_TIME_%d" % int(time["slot"])}


static func _relationship_label(trust: int) -> String:
	return "WORLD_REL_GUARDED" if trust < 0 else ("WORLD_REL_NEW" if trust == 0 else ("WORLD_REL_FRIENDLY" if trust < 5 else "WORLD_REL_TRUSTED"))


static func _trust_dialogue(trust: int) -> String:
	return "WORLD_CHAT_GUARDED" if trust < 0 else ("WORLD_CHAT_NEW" if trust == 0 else ("WORLD_CHAT_FRIENDLY" if trust < 5 else "WORLD_CHAT_TRUSTED"))


static func _reputation_label(reputation: int) -> String:
	return "WORLD_REP_SUSPECT" if reputation < 0 else ("WORLD_REP_KNOWN" if reputation > 0 else "WORLD_REP_UNKNOWN")


static func _fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return GameState.is_whole_number(value) and value >= minimum and value <= maximum


static func _day(value: Variant) -> bool:
	if value is int: return value >= 1
	# float(INT64_MAX) rounds up to 2^63 and cannot be converted safely.
	return value is float and GameState.is_whole_number(value) and value >= 1.0 and value < 9223372036854775808.0


static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0],0,8192) and _integer(value[1],0,8192)


static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))


static func _body(position: Vector2) -> Rect2:
	return Rect2(position-FEET/2,FEET)


static func _valid_region(region: Variant, scene: String) -> bool:
	if not region is Dictionary or not region.get("id") is String or region["id"] != scene or not _pair(region.get("size")) or not region.get("interactions") is Array or not region.get("obstacles") is Array or not region.get("spawns") is Dictionary: return false
	for obstacle: Variant in region["obstacles"]:
		if not obstacle is Dictionary or not obstacle.get("rect") is Array or obstacle["rect"].size() != 4: return false
		for value: Variant in obstacle["rect"]:
			if not _integer(value,0,8192): return false
		if obstacle["rect"][2] <= 0 or obstacle["rect"][3] <= 0: return false
	for target: Variant in region["interactions"]:
		if not target is Dictionary or not target.get("id") is String or not target["id"].is_valid_identifier() or not target.get("kind") in ["npc","document","exit"] or not _pair(target.get("position")): return false
	for point: Variant in region["spawns"].values():
		if not _pair(point): return false
	return true


static func _anchor_safe(region: Dictionary, position: Vector2, npc_id: String) -> bool:
	var body := _body(position)
	if not Rect2(Vector2(16,16),_point(region["size"])-Vector2(32,32)).encloses(body): return false
	for obstacle: Dictionary in region["obstacles"]:
		var rect: Array = obstacle["rect"]
		if body.intersects(Rect2(Vector2(rect[0],rect[1]),Vector2(rect[2],rect[3]))): return false
	for target: Dictionary in region["interactions"]:
		if target["id"] != npc_id and body.intersects(_body(_point(target["position"]))): return false
	for point: Array in region["spawns"].values():
		if body.intersects(_body(_point(point))): return false
	return true


static func _failure(error: Error, message: String) -> Dictionary:
	return {"error":error,"state":null,"summary":{},"message":message}
