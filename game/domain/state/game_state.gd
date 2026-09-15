class_name GameState
extends RefCounted
## Persistent domain state. Scene nodes and platform services never enter this object.

const SCHEMA_VERSION: int = 1
const DICTIONARY_FIELDS: Array[String] = [
	"time_state", "world_flags", "quest_states", "character_states", "relationships",
	"evidence_states", "martial_states", "inventory", "player_state",
]

var route_id: String = "ROUTE_BOOTSTRAP"
var scene_id: String = "SCENE_TEST_YARD"
var spawn_id: String = "SPAWN_START"
var playtime_seconds: float = 0.0
var time_state: Dictionary = {"day": 1, "slot": 0}
var world_flags: Dictionary = {}
var quest_states: Dictionary = {}
var character_states: Dictionary = {}
var relationships: Dictionary = {}
var evidence_states: Dictionary = {}
var martial_states: Dictionary = {"mastery": {}, "loadout": {}}
var inventory: Dictionary = {}
var player_state: Dictionary = {
	"character_id": "CHAR_PROTAGONIST", "name": "无名",
	"position": {"x": 320.0, "y": 180.0}, "facing": "down", "hp": 20, "qi": 5,
}


func to_dict() -> Dictionary:
	var result: Dictionary = {
		"save_version": SCHEMA_VERSION, "route_id": route_id,
		"scene_id": scene_id, "spawn_id": spawn_id, "playtime_seconds": playtime_seconds,
	}
	for field: String in DICTIONARY_FIELDS:
		var value: Dictionary = get(field)
		result[field] = value.duplicate(true)
	return result


static func from_dict(data: Dictionary) -> GameState:
	if not is_whole_number(data.get("save_version")) or int(data["save_version"]) != SCHEMA_VERSION:
		return null
	for field: String in ["route_id", "scene_id", "spawn_id"]:
		if not data.get(field) is String:
			return null
	for field: String in DICTIONARY_FIELDS:
		if not data.get(field) is Dictionary:
			return null
	if not is_number(data.get("playtime_seconds")):
		return null
	var result: GameState = GameState.new()
	result.route_id = data["route_id"]
	result.scene_id = data["scene_id"]
	result.spawn_id = data["spawn_id"]
	result.playtime_seconds = float(data["playtime_seconds"])
	for field: String in DICTIONARY_FIELDS:
		result.set(field, data[field].duplicate(true))
	return result if result.validate().is_empty() else null


func validate() -> String:
	for identifier: String in [route_id, scene_id, spawn_id]:
		if identifier.is_empty() or not identifier.is_valid_identifier():
			return "Invalid stable state identifier."
	if not is_finite(playtime_seconds) or playtime_seconds < 0.0:
		return "Invalid playtime."
	if not is_whole_number(time_state.get("day")) or int(time_state["day"]) < 1:
		return "Invalid in-game day."
	if not is_whole_number(time_state.get("slot")) or float(time_state["slot"]) < 0 or float(time_state["slot"]) > 7:
		return "Invalid in-game time slot."
	if not player_state.get("position") is Dictionary:
		return "Missing player position."
	var position: Dictionary = player_state["position"]
	if not is_number(position.get("x")) or not is_number(position.get("y")):
		return "Invalid player coordinates."
	if not player_state.get("name") is String or not player_state.get("character_id") is String:
		return "Missing player identity."
	if not player_state.get("facing") in ["up", "down", "left", "right"]:
		return "Invalid player facing."
	for statistic: String in ["hp", "qi"]:
		if not is_whole_number(player_state.get(statistic)) or int(player_state[statistic]) < 0:
			return "Invalid player statistic."
	for field: String in DICTIONARY_FIELDS:
		if not is_json_value(get(field)):
			return "State contains a non-JSON value: " + field
	return ""


static func is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func is_whole_number(value: Variant) -> bool:
	return is_number(value) and float(value) == floor(float(value))


static func is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int or value is float:
		return is_number(value)
	if value is Array:
		for entry: Variant in value:
			if not is_json_value(entry, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not is_json_value(value[key], depth + 1):
				return false
		return true
	return false
