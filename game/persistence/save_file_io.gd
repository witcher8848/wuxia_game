extends RefCounted
## File operations and envelope validation, kept outside the active game session.

const MAX_SAVE_BYTES: int = 8 * 1024 * 1024
const REQUIRED_STRINGS: Array[String] = [
	"game_version", "content_version", "save_id", "save_kind", "created_at_utc",
	"route_id", "scene_id", "spawn_id",
]


static func read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return failure(ERR_FILE_NOT_FOUND, "Save file is missing.")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return failure(ERR_FILE_CANT_OPEN, "Save file cannot be opened.")
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return failure(ERR_INVALID_DATA, "Save file exceeds the supported size.")
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return failure(ERR_PARSE_ERROR, "Save JSON is damaged.")
	var envelope: Dictionary = parser.data
	if not GameState.is_whole_number(envelope.get("schema_version")):
		return failure(ERR_INVALID_DATA, "Save schema is invalid.")
	# Compare before converting to int, so oversized future versions cannot wrap.
	if float(envelope["schema_version"]) > GameState.SCHEMA_VERSION:
		return failure(ERR_UNAVAILABLE, "This save requires a newer game version.")
	if int(envelope["schema_version"]) != GameState.SCHEMA_VERSION:
		return failure(ERR_INVALID_DATA, "No migration exists for this save schema.")
	for field: String in REQUIRED_STRINGS:
		if not envelope.get(field) is String or String(envelope[field]).is_empty():
			return failure(ERR_INVALID_DATA, "Missing save metadata: " + field)
	if not GameState.is_number(envelope.get("playtime_seconds")):
		return failure(ERR_INVALID_DATA, "Invalid save playtime.")
	if not envelope.get("preview") is Dictionary or not envelope.get("payload") is Dictionary:
		return failure(ERR_INVALID_DATA, "Missing save preview or payload.")
	var state: GameState = GameState.from_dict(envelope["payload"])
	if state == null:
		return failure(ERR_INVALID_DATA, "Save payload is invalid.")
	for field: String in ["route_id", "scene_id", "spawn_id", "playtime_seconds"]:
		if envelope[field] != state.get(field):
			return failure(ERR_INVALID_DATA, "Save metadata and payload disagree.")
	return {"error": OK, "state": state, "envelope": envelope, "source": path, "message": ""}


static func write_text(path: String, text: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var result: Error = file.get_error()
	file.close()
	return result


static func replace_file(temporary: String, target: String) -> Error:
	# Preserve a rollback sibling until the renamed file passes a full read-back.
	var old: String = target + ".old"
	if FileAccess.file_exists(old):
		if not FileAccess.file_exists(target):
			var restore_error: Error = rename_file(old, target)
			if restore_error != OK:
				return restore_error
		else:
			var cleanup_error: Error = remove_file(old)
			if cleanup_error != OK:
				return cleanup_error
	if FileAccess.file_exists(target):
		var old_error: Error = rename_file(target, old)
		if old_error != OK:
			return old_error
	var replacement_error: Error = rename_file(temporary, target)
	if replacement_error != OK:
		if FileAccess.file_exists(old):
			rename_file(old, target)
		return replacement_error
	var result: Dictionary = read_envelope(target)
	if result["error"] != OK:
		remove_file(target)
		if FileAccess.file_exists(old):
			rename_file(old, target)
		return result["error"]
	if FileAccess.file_exists(old):
		return remove_file(old)
	return OK


static func rename_file(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))


static func remove_file(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func failure(code: Error, message: String) -> Dictionary:
	return {"error": code, "state": null, "source": "", "message": message}
