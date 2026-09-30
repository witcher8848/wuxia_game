extends Node
## Transactional, data-only registry. Scene nodes never enter content or saves.

const BOOTSTRAP_PATH: String = "res://game/content/data/bootstrap.json"
const GRID_SIZE: int = 32
const PLAYER_FEET: Vector2 = Vector2(20, 12)
const Investigation = preload("res://game/domain/investigation/investigation_rules.gd")
const Dialogue = preload("res://game/domain/investigation/dialogue_catalog.gd")
const Inquiry = preload("res://game/domain/investigation/inquiry_rules.gd")
const StoryEncounter = preload("res://game/domain/investigation/story_encounter_rules.gd")
var _investigation: RefCounted = Investigation.new()
var _dialogue: RefCounted = Dialogue.new()
var _inquiry: RefCounted = Inquiry.new()
var _story_encounter: RefCounted = StoryEncounter.new()

var content_version: String = ""
var start_scene_id: String = ""
var start_spawn_id: String = ""
var last_error: String = ""
var _scenes: Dictionary = {}
var _regions: Dictionary = {}


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


func load_definitions(data: Dictionary, exploration_data: Variant = null, investigation_data: Variant = null, dialogue_data: Variant = null, encounter_data: Variant = null) -> Error:
	# Only publish the new registry once every definition and reference passes.
	if not GameState.is_json_value(data):
		return _invalid("Bootstrap must contain only finite JSON values.")
	var scenes: Dictionary = {}
	for key: String in ["content_version", "start_scene_id", "start_spawn_id"]:
		if not _is_text(data.get(key)):
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
		if not _is_text(entry.get("name_key")):
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
		if entry.has("spawn_positions"):
			if not entry["spawn_positions"] is Dictionary:
				return _invalid("Optional spawn positions must be an object.")
			for spawn: Variant in entry["spawn_positions"]:
				if not spawn in spawns or not _is_point(entry["spawn_positions"][spawn]):
					return _invalid("Invalid optional spawn position.")
		scenes[identifier] = entry.duplicate(true)
	if not scenes.has(data["start_scene_id"]):
		return _invalid("Start scene references a missing definition.")
	if not data["start_spawn_id"] in scenes[data["start_scene_id"]]["spawn_ids"]:
		return _invalid("Start spawn references a missing definition.")
	var regions: Dictionary = {}
	if exploration_data == null and data.has("exploration_path"):
		var exploration_path: Variant = data["exploration_path"]
		if not exploration_path is String or not String(exploration_path).begins_with("res://game/content/data/") or ".." in String(exploration_path) or not String(exploration_path).ends_with(".json"):
			return _invalid("Exploration path must be a content JSON resource.")
		var file: FileAccess = FileAccess.open(exploration_path, FileAccess.READ)
		if file == null:
			return _invalid("Cannot open exploration content.")
		var parser: JSON = JSON.new()
		var parsed: Error = parser.parse(file.get_as_text())
		file.close()
		if parsed != OK:
			return _invalid("Exploration content must be valid JSON.")
		exploration_data = parser.data
	if exploration_data != null:
		regions = _build_regions(exploration_data, scenes, data["start_scene_id"])
		if regions.is_empty():
			return ERR_INVALID_DATA
	var investigation: RefCounted = Investigation.new()
	if investigation_data == null and data.has("investigation_path"):
		var path: Variant = data["investigation_path"]
		if not path is String or not path.begins_with("res://game/content/data/") or ".." in path or not path.ends_with(".json"):
			return _invalid("Investigation path must be a content JSON resource.")
		if not FileAccess.file_exists(path):
			return _invalid("Cannot open investigation content.")
		investigation_data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not investigation_data is Dictionary:
			return _invalid("Investigation content must be a JSON object.")
	if investigation_data != null:
		if not investigation_data is Dictionary:
			return _invalid("Investigation definitions must be an object.")
		var investigation_error: String = investigation.configure(investigation_data)
		if not investigation_error.is_empty():
			return _invalid(investigation_error)
	var dialogue: RefCounted = Dialogue.new()
	if dialogue_data == null and data.has("dialogue_path"):
		var path: Variant = data["dialogue_path"]
		if not path is String or not path.begins_with("res://game/content/dialogue/") or ".." in path or not path.ends_with(".json"):
			return _invalid("Dialogue path must be a content dialogue JSON resource.")
		if not FileAccess.file_exists(path):
			return _invalid("Cannot open dialogue content.")
		dialogue_data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not dialogue_data is Dictionary:
			return _invalid("Dialogue content must be a JSON object.")
	if dialogue_data != null:
		if not dialogue_data is Dictionary:
			return _invalid("Dialogue definitions must be an object.")
		var interactions: Array = []
		for region: Dictionary in regions.values():
			for target: Dictionary in region["interactions"]:
				if target["kind"] in ["npc", "document"]:
					interactions.append(target["id"])
		var text_keys: Dictionary = dialogue_text_keys()
		var dialogue_error: String = dialogue.configure(dialogue_data, investigation, text_keys, interactions)
		if not dialogue_error.is_empty():
			return _invalid(dialogue_error)
	var inquiry: RefCounted = Inquiry.new()
	var inquiry_error: String = inquiry.configure(investigation.definitions().get("inquiries", []), investigation, dialogue_text_keys())
	if not inquiry_error.is_empty():
		return _invalid(inquiry_error)
	var encounter: RefCounted = StoryEncounter.new()
	if encounter_data == null and data.has("encounter_path"):
		var path: Variant = data["encounter_path"]
		if not path is String or not path.begins_with("res://game/content/data/") or ".." in path or not path.ends_with(".json") or not FileAccess.file_exists(path):
			return _invalid("Invalid story encounter path.")
		encounter_data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not encounter_data is Dictionary: return _invalid("Story encounter must be an object.")
	if encounter_data != null:
		if not encounter_data is Dictionary: return _invalid("Story encounter must be an object.")
		var skills: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/content/data/battle_skills.json"))
		if not skills is Array: return _invalid("Invalid battle skills.")
		var encounter_error: String = encounter.configure(encounter_data, skills, investigation)
		if not encounter_error.is_empty(): return _invalid(encounter_error)
	_investigation = investigation
	_dialogue = dialogue
	_inquiry = inquiry
	_story_encounter = encounter
	_scenes = scenes
	_regions = regions
	content_version = data["content_version"]
	start_scene_id = data["start_scene_id"]
	start_spawn_id = data["start_spawn_id"]
	last_error = ""
	return OK


func get_scene_path(scene_id: String) -> String:
	return String(_scenes.get(scene_id, {}).get("path", ""))


func get_investigation_definitions() -> Dictionary:
	return _investigation.definitions()


func prepare_investigation_step(state: GameState, step_id: String) -> Dictionary:
	return _investigation.prepare_step(state, step_id)


func investigation_condition(state: GameState, condition: Dictionary) -> bool:
	return _investigation.condition_matches(state, condition)


func dialogue_text_keys() -> Dictionary:
	var keys: Dictionary = {}
	var chinese := load("res://game/content/localization/investigation.zh_CN.translation") as Translation
	var english := load("res://game/content/localization/investigation.en.translation") as Translation
	if chinese == null or english == null:
		return keys
	# OptimizedTranslation does not expose get_message_list; CSV import is configured
	# uncompressed so the registry can validate every source key in exported builds.
	for key: String in chinese.get_message_list():
		if not chinese.get_message(key).is_empty() and not english.get_message(key).is_empty():
			keys[key] = true
	return keys


func get_dialogue_definitions() -> Dictionary:
	return _dialogue.definitions()


func dialogue_entry(target: String, state: GameState) -> String:
	return _dialogue.entry(target, state)


func dialogue_view(identifier: String, state: GameState) -> Dictionary:
	return _dialogue.node_view(identifier, state)


func inquiry_view(identifier: String, state: GameState, first: String = "") -> Dictionary:
	return _inquiry.view(identifier, state, first)


func prepare_inquiry(state: GameState, identifier: String, selected: Array) -> Dictionary:
	return _inquiry.prepare(state, identifier, selected)


func prepare_story_encounter(state: GameState) -> Dictionary:
	return _story_encounter.prepare(state)


func finish_story_encounter(state: GameState, result: Dictionary, instance_id: String) -> Dictionary:
	return _story_encounter.finish(state, result, instance_id)


func validate_investigation_state(state: GameState) -> String:
	return _investigation.validate_state(state)


func validate_persistent_state(state: GameState) -> String:
	var error: String = _investigation.validate_state(state)
	if not error.is_empty(): return error
	return _story_encounter.validate_persistent_state(state)


func has_spawn(scene_id: String, spawn_id: String) -> bool:
	return spawn_id in _scenes.get(scene_id, {}).get("spawn_ids", [])


func get_scene_definition(scene_id: String) -> Dictionary:
	return _scenes.get(scene_id, {}).duplicate(true)


func get_exploration_region(scene_id: String) -> Dictionary:
	return _regions.get(scene_id, {}).duplicate(true)


func get_spawn_position(scene_id: String, spawn_id: String) -> Vector2:
	var points: Dictionary = _regions.get(scene_id, {}).get("spawns", {})
	if not points.has(spawn_id):
		points = _scenes.get(scene_id, {}).get("spawn_positions", {})
	if not points.has(spawn_id):
		return Vector2.INF
	var point: Array = points[spawn_id]
	return Vector2(float(point[0]), float(point[1]))


func is_walkable_position(scene_id: String, position: Vector2) -> bool:
	if not _regions.has(scene_id) or not is_finite(position.x) or not is_finite(position.y):
		return false
	return _walkable(_regions[scene_id], position)


func is_safe_player_position(scene_id: String, position: Vector2) -> bool:
	# Interaction anchors remain walkable for map reachability checks, but a
	# player's feet cannot spawn or be restored inside their physical bodies.
	if not _regions.has(scene_id) or not is_finite(position.x) or not is_finite(position.y):
		return false
	return _safe_player_position(_regions[scene_id], position)


func has_inspectable(interaction_id: String) -> bool:
	for region: Dictionary in _regions.values():
		for interaction: Dictionary in region["interactions"]:
			if interaction["id"] == interaction_id and interaction["kind"] in ["npc", "document"]:
				return true
	return false


func _build_regions(data: Variant, scenes: Dictionary, start_id: String) -> Dictionary:
	if not GameState.is_json_value(data):
		return _invalid_regions("Exploration content must contain only finite JSON values.")
	if not data is Dictionary or not data.get("regions") is Array or data["regions"].is_empty():
		return _invalid_regions("Exploration regions must be a nonempty array.")
	var regions: Dictionary = {}
	var interaction_ids: Dictionary = {}
	for entry: Variant in data["regions"]:
		if not entry is Dictionary:
			return _invalid_regions("Region must be an object.")
		var identifier: Variant = entry.get("id")
		if not identifier is String or not scenes.has(identifier) or regions.has(identifier):
			return _invalid_regions("Duplicate or unknown region scene ID.")
		if not _is_text(entry.get("name_key")) or entry["name_key"] != scenes[identifier]["name_key"]:
			return _invalid_regions("Region requires the registered localization name key.")
		if not _is_grid_point(entry.get("size")) or float(entry["size"][0]) < 640 or float(entry["size"][1]) < 360 or float(entry["size"][0]) > 8192 or float(entry["size"][1]) > 8192:
			return _invalid_regions("Region size must use the 32px grid and fit allowed limits.")
		if not entry.get("ground") is String or not Color.html_is_valid(entry["ground"]):
			return _invalid_regions("Region requires a valid ground color.")
		if not entry.get("obstacles") is Array:
			return _invalid_regions("Region requires an obstacles array.")
		for obstacle: Variant in entry["obstacles"]:
			if not obstacle is Dictionary or not obstacle.get("kind") in ["building", "water", "crate"]:
				return _invalid_regions("Unknown obstacle type.")
			if not obstacle.get("rect") is Array or obstacle["rect"].size() != 4:
				return _invalid_regions("Obstacle requires a rectangle.")
			var rect: Array = obstacle["rect"]
			if not _is_grid_point([rect[0], rect[1]]) or not _is_grid_point([rect[2], rect[3]]) or float(rect[2]) <= 0 or float(rect[3]) <= 0:
				return _invalid_regions("Obstacle geometry must use the 32px grid.")
			if float(rect[0]) < 0 or float(rect[1]) < 0 or float(rect[0]) + float(rect[2]) > float(entry["size"][0]) or float(rect[1]) + float(rect[3]) > float(entry["size"][1]):
				return _invalid_regions("Obstacle exceeds region bounds.")
			if obstacle.has("label_key") and not _is_text(obstacle["label_key"]):
				return _invalid_regions("Obstacle label requires a localization key.")
		if not entry.get("spawns") is Dictionary or entry["spawns"].size() != scenes[identifier]["spawn_ids"].size():
			return _invalid_regions("Region must define every registered spawn exactly once.")
		for spawn: Variant in entry["spawns"]:
			if not spawn in scenes[identifier]["spawn_ids"] or not _is_grid_point(entry["spawns"][spawn]):
				return _invalid_regions("Unknown or malformed region spawn.")
			if not _walkable(entry, _point(entry["spawns"][spawn])):
				return _invalid_regions("Spawn feet overlap an obstacle or map boundary.")
		if not entry.get("interactions") is Array:
			return _invalid_regions("Region requires an interactions array.")
		for interaction: Variant in entry["interactions"]:
			if not interaction is Dictionary or not _is_text(interaction.get("id")):
				return _invalid_regions("Interaction requires an ID.")
			if not String(interaction["id"]).is_valid_identifier() or interaction_ids.has(interaction["id"]):
				return _invalid_regions("Interaction IDs must be globally unique stable identifiers.")
			interaction_ids[interaction["id"]] = true
			if not interaction.get("kind") in ["npc", "document", "exit"] or not _is_text(interaction.get("name_key")):
				return _invalid_regions("Unknown interaction type or localization key.")
			if not _is_grid_point(interaction.get("position")) or not _walkable(entry, _point(interaction["position"])):
				return _invalid_regions("Interaction must have a safe grid-aligned standing point.")
			if interaction["kind"] == "exit":
				if not _is_text(interaction.get("target_scene")) or not _is_text(interaction.get("target_spawn")):
					return _invalid_regions("Exit requires target scene and spawn IDs.")
			elif not _is_text(interaction.get("text_key")):
				return _invalid_regions("Readable interactions require localized text.")
		for spawn: Array in entry["spawns"].values():
			if not _safe_player_position(entry, _point(spawn)):
				return _invalid_regions("Spawn feet overlap an NPC or document body.")
		if not _all_points_reachable(entry):
			return _invalid_regions("Region has an unreachable spawn or interaction.")
		regions[identifier] = entry.duplicate(true)
	if not regions.has(start_id):
		return _invalid_regions("The configured start scene must be an exploration region.")
	for region: Dictionary in regions.values():
		for interaction: Dictionary in region["interactions"]:
			if interaction["kind"] != "exit":
				continue
			if not regions.has(interaction["target_scene"]) or not regions[interaction["target_scene"]]["spawns"].has(interaction["target_spawn"]):
				return _invalid_regions("Exit references a missing region or spawn.")
	# Every map must be reachable from the start and have a route back.
	for identifier: String in regions:
		if not _region_reaches(regions, start_id, identifier) or not _region_reaches(regions, identifier, start_id):
			return _invalid_regions("Exploration regions must be mutually connected.")
	return regions


func _all_points_reachable(region: Dictionary) -> bool:
	var points: Array[Vector2] = []
	for spawn: Array in region["spawns"].values():
		points.append(_point(spawn))
	var visited: Dictionary = {points[0]: true}
	var pending: Array[Vector2] = [points[0]]
	var index: int = 0
	while index < pending.size():
		var current: Vector2 = pending[index]
		index += 1
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var next: Vector2 = current + direction * GRID_SIZE
			if not visited.has(next) and _safe_player_position(region, next):
				visited[next] = true
				pending.append(next)
	for point: Vector2 in points:
		if not visited.has(point):
			return false
	# Readable anchors contain bodies. A grid-aligned standing point one tile
	# away is within the 58px interaction range and must be reachable instead.
	for interaction: Dictionary in region["interactions"]:
		var point: Vector2 = _point(interaction["position"])
		if interaction["kind"] == "exit":
			if not visited.has(point):
				return false
			continue
		var can_approach: bool = false
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			if visited.has(point + direction * GRID_SIZE):
				can_approach = true
				break
		if not can_approach:
			return false
	return true


func _region_reaches(regions: Dictionary, source: String, target: String) -> bool:
	var visited: Dictionary = {}
	var pending: Array[String] = [source]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if current == target:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for interaction: Dictionary in regions[current]["interactions"]:
			if interaction["kind"] == "exit":
				pending.append(interaction["target_scene"])
	return false


func _walkable(region: Dictionary, position: Vector2) -> bool:
	var feet: Rect2 = Rect2(position - PLAYER_FEET / 2.0, PLAYER_FEET)
	var bounds: Rect2 = Rect2(Vector2.ONE * 16, _point(region["size"]) - Vector2.ONE * 32)
	if not bounds.encloses(feet):
		return false
	for obstacle: Dictionary in region["obstacles"]:
		var rect: Array = obstacle["rect"]
		if feet.intersects(Rect2(Vector2(rect[0], rect[1]), Vector2(rect[2], rect[3]))):
			return false
	return true


func _safe_player_position(region: Dictionary, position: Vector2) -> bool:
	if not _walkable(region, position):
		return false
	var feet: Rect2 = Rect2(position - PLAYER_FEET / 2.0, PLAYER_FEET)
	for interaction: Dictionary in region["interactions"]:
		if interaction["kind"] not in ["npc", "document"]:
			continue
		var body: Rect2 = Rect2(_point(interaction["position"]) - PLAYER_FEET / 2.0, PLAYER_FEET)
		if feet.intersects(body):
			return false
	return true


func _is_text(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


func _is_point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and GameState.is_number(value[0]) and GameState.is_number(value[1])


func _is_grid_point(value: Variant) -> bool:
	return _is_point(value) and fmod(float(value[0]), GRID_SIZE) == 0.0 and fmod(float(value[1]), GRID_SIZE) == 0.0


func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _invalid_regions(message: String) -> Dictionary:
	last_error = message
	return {}


func _invalid(message: String) -> Error:
	last_error = message
	return ERR_INVALID_DATA
