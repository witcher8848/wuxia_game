extends Node
## Versioned JSON slots with validated writes, per-slot backup, and explicit recovery.

const IO = preload("res://game/persistence/save_file_io.gd")
const SLOTS: Array[String] = [
	"manual_01", "manual_02", "manual_03", "manual_04", "manual_05", "quick",
	"auto_01", "auto_02", "auto_03",
]
const CHOICE_ANCHOR_NODE: String = "CH01_FIRST_LEAD"
const CHOICE_ANCHOR_VERSION: int = 1
const AUTOMATIC_SLOTS: Array[String] = ["auto_01", "auto_02", "auto_03"]
const AUTOMATIC_SEQUENCE_VERSION: int = 1
# JSON readers use doubles: preserve every sequence exactly, including restarts.
const MAX_AUTOMATIC_SEQUENCE: int = 9007199254740991

# Tests may only select an isolated subdirectory, never an arbitrary absolute path.
var test_root: String = ""


func save_game(slot: String, state: GameState) -> Error:
	return _write_save(slot, state)


func save_automatic(state: GameState) -> Dictionary:
	var session: Node = get_node_or_null("/root/GameSession") if is_inside_tree() else null
	if session != null and session.combat_active():
		return _automatic_failure(ERR_BUSY, "Cannot create an automatic save during combat.")
	if not _is_valid_root():
		return _automatic_failure(ERR_INVALID_PARAMETER, "Invalid automatic save test directory.")
	if state == null or not state.validate().is_empty() or not _content_error(state).is_empty():
		return _automatic_failure(ERR_INVALID_DATA, "Automatic save state is invalid.")
	var maximum: int = 0
	var candidates: Array[Dictionary] = []
	for slot: String in AUTOMATIC_SLOTS:
		var info: Dictionary = _automatic_slot_info(slot)
		maximum = maxi(maximum, info["sequence"])
		if not info["protected"]:
			candidates.append(info)
	if candidates.is_empty():
		return _automatic_failure(ERR_UNAVAILABLE, "All automatic slots contain protected newer or invalid metadata.")
	if maximum >= MAX_AUTOMATIC_SEQUENCE:
		return _automatic_failure(ERR_UNAVAILABLE, "Automatic save sequence has reached its supported limit.")
	# Empty slots first; then legacy/no-valid-copy slots; then the least recent
	# sequenced slot. Stable slot order breaks every tie, never filesystem mtime.
	var chosen: Dictionary = candidates[0]
	for candidate: Dictionary in candidates:
		if candidate["priority"] < chosen["priority"] \
			or (candidate["priority"] == chosen["priority"] and candidate["sequence"] < chosen["sequence"]):
			chosen = candidate
	var next_sequence := maximum + 1
	var write_error: Error = _write_save(chosen["slot"], state, next_sequence)
	if write_error != OK:
		return _automatic_failure(write_error, "Automatic save failed; confirmed runtime progress was not changed.")
	var stored: Dictionary = _read_valid_envelope(slot_path(chosen["slot"]))
	if stored["error"] != OK:
		return _automatic_failure(stored["error"], "Automatic save could not be read back.")
	var metadata: Dictionary = _automatic_metadata(stored["envelope"])
	if metadata["error"] != OK or metadata["sequence"] != next_sequence:
		return _automatic_failure(ERR_INVALID_DATA, "Automatic save read-back metadata does not match.")
	return {"error": OK, "slot": chosen["slot"], "sequence": next_sequence, "message": ""}


func _write_save(slot: String, state: GameState, automatic_sequence: int = 0) -> Error:
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
	var envelope: Dictionary = _make_envelope(slot, state)
	if automatic_sequence > 0:
		envelope["auto_sequence"] = automatic_sequence
		envelope["auto_sequence_version"] = AUTOMATIC_SEQUENCE_VERSION
	var write_error: Error = IO.write_text(temporary, JSON.stringify(envelope, "\t"))
	if write_error != OK:
		return write_error
	var validation: Dictionary = _read_valid_envelope(temporary)
	if validation["error"] != OK:
		return validation["error"]
	if automatic_sequence > 0 and _automatic_metadata(validation["envelope"])["error"] != OK:
		return ERR_INVALID_DATA
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


func _automatic_slot_info(slot: String) -> Dictionary:
	var info: Dictionary = {"slot": slot, "sequence": 0, "priority": 0, "protected": false}
	for path: String in [slot_path(slot), slot_path(slot) + ".old", backup_path(slot)]:
		if FileAccess.file_exists(path):
			info["priority"] = maxi(info["priority"], 1)
		var candidate: Dictionary = _read_valid_envelope(path)
		if candidate["error"] == ERR_UNAVAILABLE:
			info["protected"] = true
			continue
		# Corrupt JSON/payload may be replaced, but never copied over a good backup.
		# Unknown sequence metadata in an otherwise valid envelope is protected.
		if candidate["error"] != OK:
			continue
		var metadata: Dictionary = _automatic_metadata(candidate["envelope"])
		if metadata["error"] != OK:
			info["protected"] = true
			continue
		if metadata["sequence"] > 0:
			info["priority"] = 2
			info["sequence"] = maxi(info["sequence"], metadata["sequence"])
	return info


func _automatic_metadata(envelope: Dictionary) -> Dictionary:
	var failure: Dictionary = {"error": ERR_INVALID_DATA, "sequence": 0}
	# IO already type-checks save_kind, but retain a strict guard for direct tests.
	if not envelope.get("save_kind") is String or envelope["save_kind"] != "auto":
		return failure
	if not envelope.has("auto_sequence") and not envelope.has("auto_sequence_version"):
		return {"error": OK, "sequence": 0} # Existing automatic slots stay compatible.
	if not GameState.is_whole_number(envelope.get("auto_sequence_version")):
		return failure
	if float(envelope["auto_sequence_version"]) > AUTOMATIC_SEQUENCE_VERSION:
		return {"error": ERR_UNAVAILABLE, "sequence": 0}
	if int(envelope["auto_sequence_version"]) != AUTOMATIC_SEQUENCE_VERSION:
		return failure
	if not GameState.is_whole_number(envelope.get("auto_sequence")):
		return failure
	var sequence: float = float(envelope["auto_sequence"])
	if sequence < 1 or sequence > MAX_AUTOMATIC_SEQUENCE:
		return failure
	return {"error": OK, "sequence": int(sequence)}


func _automatic_failure(code: Error, message: String) -> Dictionary:
	return {"error": code, "slot": "", "sequence": 0, "message": message}


func load_game(slot: String, allow_auto_fallback: bool = true) -> Dictionary:
	var result: Dictionary = _read_slot(slot)
	if result["error"] == OK or result["error"] == ERR_UNAVAILABLE:
		return result
	if allow_auto_fallback and is_valid_slot(slot) and _is_valid_root():
		var recovered_auto: Dictionary = _load_latest_auto(slot)
		if recovered_auto["error"] == OK:
			return recovered_auto
	return result


func save_choice_anchor(node_id: String, state: GameState) -> Dictionary:
	# An anchor is immutable, outside slot rotation. A complete nonempty directory
	# is published by one rename, so a cooperating second writer cannot clobber it.
	var session: Node = get_node_or_null("/root/GameSession") if is_inside_tree() else null
	if session != null and session.combat_active():
		return _anchor_failure(ERR_BUSY, "Cannot create a choice anchor during combat.")
	if state == null:
		return _anchor_failure(ERR_INVALID_DATA, "Choice anchor state is missing.")
	var target: String = choice_anchor_path(state.route_id, node_id)
	if target.is_empty():
		return _anchor_failure(ERR_INVALID_PARAMETER, "Invalid choice anchor identity or test directory.")
	if not state.validate().is_empty() or not _content_error(state).is_empty():
		return _anchor_failure(ERR_INVALID_DATA, "Choice anchor state is invalid.")
	var directory: String = target.get_base_dir()
	if _anchor_location_exists(directory):
		return _existing_choice_anchor(state.route_id, node_id, state)
	var staging: String = directory + ".new"
	var parent_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.get_base_dir()))
	if parent_error != OK:
		return _anchor_failure(parent_error, "Choice anchor directory cannot be created.")
	# make_dir is the exclusive operation; FileAccess.WRITE itself is not O_EXCL.
	# A leftover directory is never reclaimed automatically after a crash.
	var claim_error: Error = DirAccess.make_dir_absolute(ProjectSettings.globalize_path(staging))
	if claim_error != OK:
		return _anchor_failure(ERR_BUSY if _anchor_location_exists(staging) else claim_error,
			"Choice anchor has an active or interrupted write; no existing files were replaced.")
	var temporary: String = staging.path_join("anchor.sav")
	var envelope: Dictionary = _make_envelope("choice_anchor", state)
	envelope["save_kind"] = "choice_anchor"
	envelope["choice_anchor"] = {
		"version": CHOICE_ANCHOR_VERSION, "route_id": state.route_id, "node_id": node_id,
		"anchor_id": _choice_anchor_id(state.route_id, node_id),
		"snapshot_sha256": _anchor_snapshot_hash(state),
	}
	var write_error: Error = IO.write_text(temporary, JSON.stringify(envelope, "\t", true, true))
	if write_error != OK:
		_release_owned_anchor_staging(staging, temporary)
		return _anchor_failure(write_error, "Choice anchor could not be written.")
	var validation: Dictionary = _read_choice_anchor(temporary, state.route_id, node_id)
	if validation["error"] != OK:
		_release_owned_anchor_staging(staging, temporary)
		return validation
	# Recheck after staging. Never use ordinary replace_file, backups, or fallback.
	if _anchor_location_exists(directory):
		_release_owned_anchor_staging(staging, temporary)
		return _existing_choice_anchor(state.route_id, node_id, state)
	var publish_error: Error = IO.rename_file(staging, directory)
	if publish_error != OK:
		_release_owned_anchor_staging(staging, temporary)
		return _anchor_failure(publish_error, "Choice anchor could not be published.")
	# Read the published envelope too; an error is surfaced, never 'repaired' by
	# deleting or replacing the committed anchor.
	var result: Dictionary = load_choice_anchor(state.route_id, node_id)
	if result["error"] == OK:
		result["created"] = true
	return result


func load_choice_anchor(route_id: String, node_id: String) -> Dictionary:
	var session: Node = get_node_or_null("/root/GameSession") if is_inside_tree() else null
	if session != null and session.combat_active():
		return _anchor_failure(ERR_BUSY, "Cannot read a choice anchor during combat.")
	var target: String = choice_anchor_path(route_id, node_id)
	if target.is_empty():
		return _anchor_failure(ERR_INVALID_PARAMETER, "Invalid choice anchor identity or test directory.")
	# Deliberately no slot fallback, backup substitution, or .new recovery.
	return _read_choice_anchor(target, route_id, node_id)


func choice_anchor_path(route_id: String, node_id: String) -> String:
	if not _is_valid_root() or node_id != CHOICE_ANCHOR_NODE or not _valid_anchor_route(route_id):
		return ""
	# Hashing keeps distinct case-sensitive IDs distinct on macOS/Windows too.
	return _save_root().path_join("anchors").path_join(route_id.sha256_text()).path_join(node_id).path_join("anchor.sav")


func _existing_choice_anchor(route_id: String, node_id: String, state: GameState) -> Dictionary:
	var result: Dictionary = load_choice_anchor(route_id, node_id)
	if result["error"] != OK:
		return result
	if _anchor_snapshot_hash(result["state"]) != _anchor_snapshot_hash(state):
		return _anchor_failure(ERR_ALREADY_EXISTS, "This choice anchor already contains a different snapshot.")
	result["created"] = false
	return result


func _read_choice_anchor(path: String, route_id: String, node_id: String) -> Dictionary:
	var result: Dictionary = _read_valid_envelope(path)
	if result["error"] != OK:
		result["anchor_id"] = ""
		return result
	var envelope: Dictionary = result["envelope"]
	if envelope.get("save_kind") != "choice_anchor" or not envelope.get("choice_anchor") is Dictionary:
		return _anchor_failure(ERR_INVALID_DATA, "File is not a choice anchor.")
	var identity: Dictionary = envelope["choice_anchor"]
	if not GameState.is_whole_number(identity.get("version")):
		return _anchor_failure(ERR_INVALID_DATA, "Invalid choice anchor version.")
	if float(identity["version"]) > CHOICE_ANCHOR_VERSION:
		return _anchor_failure(ERR_UNAVAILABLE, "This choice anchor requires a newer game version.")
	if int(identity["version"]) != CHOICE_ANCHOR_VERSION:
		return _anchor_failure(ERR_INVALID_DATA, "Unsupported choice anchor version.")
	# Compare only known String operands: malformed JSON can otherwise trigger
	# a GDScript invalid Dictionary/String comparison instead of a clean refusal.
	for field: String in ["route_id", "node_id", "anchor_id", "snapshot_sha256"]:
		if not identity.get(field) is String:
			return _anchor_failure(ERR_INVALID_DATA, "Invalid choice anchor identity field: " + field)
	# Additional metadata is tolerated for compatible annotations. Required
	# fields and version are never inferred from or replaced by those extras.
	if identity.get("route_id") != route_id or identity.get("node_id") != node_id \
		or identity.get("anchor_id") != _choice_anchor_id(route_id, node_id) \
		or envelope["route_id"] != route_id or result["state"].route_id != route_id \
		or identity.get("snapshot_sha256") != _anchor_snapshot_hash(result["state"]):
		return _anchor_failure(ERR_INVALID_DATA, "Choice anchor identity or snapshot does not match.")
	result["anchor_id"] = identity["anchor_id"]
	result["source"] = "choice_anchor"
	return result


func _release_owned_anchor_staging(staging: String, temporary: String) -> void:
	# Only called after this invocation won make_dir. Never scan or reclaim an
	# existing .new directory, another route, committed anchors, or player slots.
	if FileAccess.file_exists(temporary):
		IO.remove_file(temporary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(staging))


func _anchor_location_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _valid_anchor_route(route_id: String) -> bool:
	if route_id.is_empty() or route_id.length() > 96 or not route_id.is_valid_identifier():
		return false
	for character: String in route_id:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true


func _choice_anchor_id(route_id: String, node_id: String) -> String:
	return route_id + ":" + node_id


func _anchor_snapshot_hash(state: GameState) -> String:
	# JSON decodes every number as a float. Normalize both fresh and restored
	# snapshots identically before hashing, rather than int/float Variant spelling.
	var normalized: Variant = JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()


func _anchor_failure(code: Error, message: String) -> Dictionary:
	var result: Dictionary = IO.failure(code, message)
	result["anchor_id"] = ""
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
	var candidates: Array[Dictionary] = []
	for slot: String in AUTOMATIC_SLOTS:
		if slot == excluded_slot:
			continue
		for path: String in [slot_path(slot), slot_path(slot) + ".old", backup_path(slot)]:
			var candidate: Dictionary = _read_valid_envelope(path)
			if candidate["error"] != OK:
				continue
			var metadata := _automatic_metadata(candidate["envelope"])
			if metadata["error"] != OK: continue
			candidate["source"] = slot + ("_backup" if path.ends_with(".bak") else ("_rollback" if path.ends_with(".old") else ""))
			candidate["message"] = "Recovered from automatic slot " + slot + "."
			candidates.append({"result":candidate,"sequence":metadata["sequence"],"modified":FileAccess.get_modified_time(path)})
	return _select_latest_auto(candidates)


func _select_latest_auto(candidates: Array[Dictionary]) -> Dictionary:
	# New rotation order is persistent, not dependent on one-second mtime. Keep
	# legacy slots usable if strictly newer than every sequenced copy; ties favor
	# the monotonic receipt. Two pools avoid a non-transitive mixed comparator.
	var sequenced: Dictionary = {}
	var legacy: Dictionary = {}
	var newest_sequenced_mtime: int = -1
	for candidate: Dictionary in candidates:
		if candidate["sequence"] == 0:
			if legacy.is_empty() or candidate["modified"] > legacy["modified"]: legacy = candidate
		else:
			newest_sequenced_mtime = maxi(newest_sequenced_mtime,candidate["modified"])
			if sequenced.is_empty() or candidate["sequence"] > sequenced["sequence"] or (candidate["sequence"] == sequenced["sequence"] and candidate["modified"] > sequenced["modified"]): sequenced = candidate
	if not legacy.is_empty() and (sequenced.is_empty() or legacy["modified"] > newest_sequenced_mtime): return legacy["result"]
	if not sequenced.is_empty(): return sequenced["result"]
	return IO.failure(ERR_FILE_NOT_FOUND, "No valid automatic backup exists.")


func _content_error(state: GameState) -> String:
	var content: Node = get_node_or_null("/root/ContentDB") if is_inside_tree() else null
	return content.validate_persistent_state(state) if content != null else ""


func _read_valid_envelope(path: String) -> Dictionary:
	var result: Dictionary = IO.read_envelope(path)
	if result["error"] != OK: return result
	var error := _content_error(result["state"])
	return result if error.is_empty() else IO.failure(ERR_INVALID_DATA, error)
