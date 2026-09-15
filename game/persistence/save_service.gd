extends Node
## Versioned JSON slots with validated writes, per-slot backup, and explicit recovery.

const IO = preload("res://game/persistence/save_file_io.gd")
const GAME_VERSION: String = "0.1.0"
const CONTENT_VERSION: String = "0.1.0"
const SLOTS: Array[String] = [
	"manual_01", "manual_02", "manual_03", "manual_04", "manual_05", "quick",
	"auto_01", "auto_02", "auto_03",
]

# Tests may only select an isolated subdirectory, never an arbitrary absolute path.
var test_root: String = ""


func save_game(slot: String, state: GameState) -> Error:
	if not is_valid_slot(slot) or not _is_valid_root():
		return ERR_INVALID_PARAMETER
	if state == null or not state.validate().is_empty():
		return ERR_INVALID_DATA
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_save_root().path_join("backups")))
	if directory_error != OK:
		return directory_error
	var target: String = slot_path(slot)
	var old: String = target + ".old"
	# A crash may leave the last committed file in its rollback name.
	if not FileAccess.file_exists(target) and FileAccess.file_exists(old):
		var restore_error: Error = IO.rename_file(old, target)
		if restore_error != OK:
			return restore_error
	var current: Dictionary = IO.read_envelope(target)
	if current["error"] == ERR_UNAVAILABLE:
		return ERR_UNAVAILABLE
	var temporary: String = target + ".tmp"
	var write_error: Error = IO.write_text(temporary, JSON.stringify(_make_envelope(slot, state), "\t"))
	if write_error != OK:
		return write_error
	var validation: Dictionary = IO.read_envelope(temporary)
	if validation["error"] != OK:
		return validation["error"]
	# Never overwrite a valid backup with a damaged primary file.
	if current["error"] == OK:
		var backup: String = backup_path(slot)
		var backup_temporary: String = backup + ".tmp"
		var copy_error: Error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(target), ProjectSettings.globalize_path(backup_temporary))
		if copy_error != OK:
			return copy_error
		var backup_validation: Dictionary = IO.read_envelope(backup_temporary)
		if backup_validation["error"] != OK:
			return backup_validation["error"]
		var backup_error: Error = IO.replace_file(backup_temporary, backup)
		if backup_error != OK:
			return backup_error
	return IO.replace_file(temporary, target)


func load_game(slot: String) -> Dictionary:
	if not is_valid_slot(slot) or not _is_valid_root():
		return IO.failure(ERR_INVALID_PARAMETER, "Invalid save slot or test directory.")
	var primary: Dictionary = IO.read_envelope(slot_path(slot))
	if primary["error"] == OK:
		primary["source"] = "primary"
		return primary
	# Do not disguise an unsupported newer save as an older successful load.
	if primary["error"] == ERR_UNAVAILABLE:
		return primary
	var candidates: Array[Dictionary] = [
		{"path": slot_path(slot) + ".old", "source": "rollback"},
		{"path": backup_path(slot), "source": "backup"},
	]
	for candidate: Dictionary in candidates:
		var recovered: Dictionary = IO.read_envelope(candidate["path"])
		if recovered["error"] == ERR_UNAVAILABLE:
			return recovered
		if recovered["error"] == OK:
			recovered["source"] = candidate["source"]
			recovered["message"] = "Recovered from the slot's " + String(candidate["source"]) + "."
			return recovered
	var recovered_auto: Dictionary = _load_latest_auto(slot)
	if recovered_auto["error"] == OK:
		return recovered_auto
	return primary


func is_valid_slot(slot: String) -> bool:
	return slot in SLOTS


func slot_path(slot: String) -> String:
	return _save_root().path_join(slot + ".sav") if is_valid_slot(slot) and _is_valid_root() else ""


func backup_path(slot: String) -> String:
	return _save_root().path_join("backups/" + slot + ".bak") if is_valid_slot(slot) and _is_valid_root() else ""


func _save_root() -> String:
	return "user://saves" if test_root.is_empty() else test_root.path_join("saves")


func _is_valid_root() -> bool:
	if test_root.is_empty():
		return true
	if not test_root.begins_with("user://tests/"):
		return false
	var suffix: String = test_root.trim_prefix("user://tests/")
	return not suffix.is_empty() and suffix.is_valid_identifier() and suffix.length() <= 96


func _make_envelope(slot: String, state: GameState) -> Dictionary:
	var created: String = Time.get_datetime_string_from_system(true) + "Z"
	return {
		"schema_version": GameState.SCHEMA_VERSION, "game_version": GAME_VERSION,
		"content_version": CONTENT_VERSION, "save_id": "%s_%d" % [slot, Time.get_ticks_usec()],
		"save_kind": "auto" if slot.begins_with("auto_") else ("quick" if slot == "quick" else "manual"),
		"created_at_utc": created, "playtime_seconds": state.playtime_seconds,
		"route_id": state.route_id, "scene_id": state.scene_id, "spawn_id": state.spawn_id,
		"preview": {"character_name": state.player_state["name"], "chapter": "CH01",
			"time": state.time_state.duplicate(true), "location": state.scene_id, "thumbnail_key": ""},
		"payload": state.to_dict(),
	}


func _load_latest_auto(excluded_slot: String) -> Dictionary:
	var best: Dictionary = IO.failure(ERR_FILE_NOT_FOUND, "No valid automatic backup exists.")
	var newest: int = -1
	for slot: String in ["auto_01", "auto_02", "auto_03"]:
		if slot == excluded_slot:
			continue
		for path: String in [slot_path(slot), backup_path(slot)]:
			var candidate: Dictionary = IO.read_envelope(path)
			if candidate["error"] != OK:
				continue
			var modified: int = FileAccess.get_modified_time(path)
			if modified > newest:
				newest = modified
				best = candidate
				best["source"] = slot + ("_backup" if path.ends_with(".bak") else "")
				best["message"] = "Recovered from automatic slot " + slot + "."
	return best
