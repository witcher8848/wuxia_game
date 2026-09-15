extends Node
## Small, validated content registry. Story definitions will extend this in week two.

const BOOTSTRAP_PATH: String = "res://game/content/data/bootstrap.json"

var content_version: String = ""
var start_scene_id: String = ""
var start_spawn_id: String = ""
var last_error: String = ""
var _scenes: Dictionary = {}


func _ready() -> void:
	if reload_content() != OK:
		push_error("ContentDB: " + last_error)


func reload_content(path: String = BOOTSTRAP_PATH) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Cannot open bootstrap content."
		return ERR_FILE_CANT_OPEN
	var parser: JSON = JSON.new()
	var parsed: Error = parser.parse(file.get_as_text())
	file.close()
	if parsed != OK or not parser.data is Dictionary:
		last_error = "Bootstrap must be a JSON object."
		return ERR_PARSE_ERROR
	return load_definitions(parser.data)


func load_definitions(data: Dictionary) -> Error:
	# Only publish the new registry once every definition and reference passes.
	var scenes: Dictionary = {}
	for key: String in ["content_version", "start_scene_id", "start_spawn_id"]:
		if not data.get(key) is String or String(data[key]).is_empty():
			return _invalid("Missing bootstrap string: " + key)
	if not data.get("scenes") is Array or data["scenes"].is_empty():
		return _invalid("Bootstrap scenes must be a nonempty array.")
	for entry: Variant in data["scenes"]:
		if not entry is Dictionary:
			return _invalid("Scene definition must be an object.")
		var identifier: Variant = entry.get("id")
		if not identifier is String or not String(identifier).begins_with("SCENE_"):
			return _invalid("Invalid scene ID.")
		if not String(identifier).is_valid_identifier() or scenes.has(identifier):
			return _invalid("Duplicate or malformed scene ID: " + String(identifier))
		var scene_path: Variant = entry.get("path")
		if not scene_path is String or not String(scene_path).begins_with("res://game/presentation/"):
			return _invalid("Scene path must be under game/presentation.")
		if ".." in String(scene_path) or not String(scene_path).ends_with(".tscn"):
			return _invalid("Invalid scene resource path.")
		if not ResourceLoader.exists(scene_path):
			return _invalid("Scene resource does not exist: " + String(identifier))
		if not entry.get("name_key") is String or String(entry["name_key"]).is_empty():
			return _invalid("Scene requires a localization name key.")
		if not entry.get("spawn_ids") is Array or entry["spawn_ids"].is_empty():
			return _invalid("Scene requires spawn IDs.")
		var spawns: Array[String] = []
		for spawn: Variant in entry["spawn_ids"]:
			if not spawn is String or not String(spawn).begins_with("SPAWN_"):
				return _invalid("Invalid spawn ID.")
			if not String(spawn).is_valid_identifier() or spawn in spawns:
				return _invalid("Duplicate or malformed spawn ID.")
			spawns.append(spawn)
		scenes[identifier] = entry.duplicate(true)
	if not scenes.has(data["start_scene_id"]):
		return _invalid("Start scene references a missing definition.")
	if not data["start_spawn_id"] in scenes[data["start_scene_id"]]["spawn_ids"]:
		return _invalid("Start spawn references a missing definition.")
	_scenes = scenes
	content_version = data["content_version"]
	start_scene_id = data["start_scene_id"]
	start_spawn_id = data["start_spawn_id"]
	last_error = ""
	return OK


func get_scene_path(scene_id: String) -> String:
	return String(_scenes.get(scene_id, {}).get("path", ""))


func has_spawn(scene_id: String, spawn_id: String) -> bool:
	return spawn_id in _scenes.get(scene_id, {}).get("spawn_ids", [])


func get_scene_definition(scene_id: String) -> Dictionary:
	return _scenes.get(scene_id, {}).duplicate(true)


func _invalid(message: String) -> Error:
	last_error = message
	return ERR_INVALID_DATA
