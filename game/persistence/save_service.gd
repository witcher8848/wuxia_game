extends Node
## Versioned JSON slots with validated writes, per-slot backup, and explicit recovery.

const IO = preload("res://game/persistence/save_file_io.gd")
const SLOTS: Array[String] = [
	"manual_01", "manual_02", "manual_03", "manual_04", "manual_05", "quick",
	"auto_01", "auto_02", "auto_03",
]

# Tests may only select an isolated subdirectory, never an arbitrary absolute path.
var test_root: String = ""


func save_game(slot: String, state: GameState) -> Error:
	var session: Node = get_node_or_null("/root/GameSession") if is_inside_tree() else null
	if session != null and session.combat_active(): return ERR_BUSY
	if not is_valid_slot(slot) or not _is_valid_root():
		return ERR_INVALID_PARAMETER
	if state == null or not state.validate().is_empty():
		return ERR_INVALID_DATA
	if not _content_error(state).is_empty(): return ERR_INVALID_DATA
	# Protect every copy before creating directories or restoring rollback files;
	# callers other than the slot menu must honor the same version boundary.
	if not slot_summary(slot)["can_overwrite"]:
		return ERR_UNAVAILABLE
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
	var current: Dictionary = _read_valid_envelope(target)
	if current["error"] == ERR_UNAVAILABLE:
		return ERR_UNAVAILABLE
	var temporary: String = target + ".tmp"
	var write_error: Error = IO.write_text(temporary, JSON.stringify(_make_envelope(slot, state), "\t"))
	if write_error != OK:
		return write_error
	var validation: Dictionary = _read_valid_envelope(temporary)
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
		var backup_validation: Dictionary = _read_valid_envelope(backup_temporary)
		if backup_validation["error"] != OK:
			return backup_validation["error"]
		var backup_error: Error = IO.replace_file(backup_temporary, backup)
		if backup_error != OK:
			return backup_error
	return IO.replace_file(temporary, target)


func load_game(slot: String, allow_auto_fallback: bool = true) -> Dictionary:
	var result: Dictionary = _read_slot(slot)
	if result["error"] == OK or result["error"] == ERR_UNAVAILABLE:
		return result
	if allow_auto_fallback and is_valid_slot(slot) and _is_valid_root():
		var recovered_auto: Dictionary = _load_latest_auto(slot)
		if recovered_auto["error"] == OK:
			return recovered_auto
	return result


func _read_slot(slot: String) -> Dictionary:
	# Exact-slot read: never substitute a different route from an automatic slot.
	if not is_valid_slot(slot) or not _is_valid_root():
		return IO.failure(ERR_INVALID_PARAMETER, "Invalid save slot or test directory.")
	var primary: Dictionary = _read_valid_envelope(slot_path(slot))
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
	var failure: Dictionary = primary
	for candidate: Dictionary in candidates:
		var recovered: Dictionary = _read_valid_envelope(candidate["path"])
		if recovered["error"] == ERR_UNAVAILABLE:
			return recovered
		if recovered["error"] == OK:
			recovered["source"] = candidate["source"]
			recovered["message"] = "Recovered from the slot's " + String(candidate["source"]) + "."
			return recovered
		if failure["error"] == ERR_FILE_NOT_FOUND and recovered["error"] != ERR_FILE_NOT_FOUND:
			failure = recovered
	return failure


func slot_summary(slot: String) -> Dictionary:
	var summary: Dictionary = {"slot": slot, "exists": false, "can_load": false, "can_overwrite": false,
		"error": ERR_INVALID_PARAMETER, "source": "", "created_at_utc": "",
		"scene_id": "", "character_name": "", "message": ""}
	if not is_valid_slot(slot) or not _is_valid_root():
		return summary
	summary["can_overwrite"] = true
	for path: String in [slot_path(slot), slot_path(slot) + ".old", backup_path(slot)]:
		if FileAccess.file_exists(path):
			summary["exists"] = true
			# Saving replaces backups too, even if a readable primary takes priority.
			if _read_valid_envelope(path)["error"] == ERR_UNAVAILABLE:
				summary["can_overwrite"] = false
	var result: Dictionary = _read_slot(slot)
	summary["error"] = result["error"]
	summary["message"] = result.get("message", "")
	if result["error"] == OK:
		summary["can_load"] = true
		summary["source"] = result["source"]
		summary["created_at_utc"] = result["envelope"]["created_at_utc"]
		summary["scene_id"] = result["state"].scene_id
		summary["character_name"] = result["state"].player_state["name"]
	return summary


func list_slot_summaries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: String in SLOTS:
		result.append(slot_summary(slot))
	return result


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
	var content: Node = get_node_or_null("/root/ContentDB") if is_inside_tree() else null
	var content_version: String = content.content_version if content != null else "0.2.0"
	return {
		"schema_version": GameState.SCHEMA_VERSION, "game_version": str(ProjectSettings.get_setting("application/config/version", "0.2.1-week2")),
		"content_version": content_version, "save_id": "%s_%d" % [slot, Time.get_ticks_usec()],
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
			var candidate: Dictionary = _read_valid_envelope(path)
			if candidate["error"] != OK:
				continue
			var modified: int = FileAccess.get_modified_time(path)
			if modified > newest:
				newest = modified
				best = candidate
				best["source"] = slot + ("_backup" if path.ends_with(".bak") else "")
				best["message"] = "Recovered from automatic slot " + slot + "."
	return best


func _content_error(state: GameState) -> String:
	var content: Node = get_node_or_null("/root/ContentDB") if is_inside_tree() else null
	return content.validate_persistent_state(state) if content != null else ""


func _read_valid_envelope(path: String) -> Dictionary:
	var result: Dictionary = IO.read_envelope(path)
	if result["error"] != OK: return result
	var error := _content_error(result["state"])
	return result if error.is_empty() else IO.failure(ERR_INVALID_DATA, error)
