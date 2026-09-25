extends SceneTree
## Real menu/input and persistence regression; never touches user://saves.

const IO = preload("res://game/persistence/save_file_io.gd")
const MAIN := "res://game/presentation/main.tscn"
var checks: int = 0
var failures: Array[String] = []
var fixture: String
var main: Node
var saves: Node
var session: Node
var app: Node

func _initialize() -> void:
	create_timer(75).timeout.connect(func() -> void:
		printerr("SAVE_SLOTS_UI_FAIL 75-second watchdog")
		quit(124))
	_run.call_deferred()

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("SAVE_SLOTS_UI_FAIL ", message)
	return condition

func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _step(frames: int = 2) -> void:
	for _frame in range(frames):
		await physics_frame
		await process_frame

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _tap(code: Key) -> void:
	_key(code, true)
	await _step(1)
	_key(code, false)
	await _step(2)

func _find_button(node: Node, value: String, by_text: bool = false) -> Button:
	if node is Button and ((by_text and node.text == value) or (not by_text and node.name == value)):
		return node
	for child: Node in node.get_children():
		var found: Button = _find_button(child, value, by_text)
		if found != null:
			return found
	return null

func _activate(value: String, by_text: bool = false) -> bool:
	var button: Button = _find_button(main.menu, value, by_text)
	if not check(button != null and not button.disabled, "enabled menu button exists: " + value):
		return false
	# Focus traversal is keyboard driven too; do not grant focus via test setters.
	for _attempt in range(24):
		if root.gui_get_focus_owner() == button:
			await _tap(KEY_E)
			return true
		await _tap(KEY_TAB)
	return check(false, "keyboard cannot reach button: " + value)

func _region() -> Node2D:
	return main.get_node("SceneHost").get_child(0) as Node2D

func _snapshot_files(path: String = "") -> Dictionary:
	if path.is_empty():
		path = fixture
	var result: Dictionary = {}
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for child: String in directory.get_files():
		var child_path: String = path.path_join(child)
		result[child_path.trim_prefix(fixture + "/")] = FileAccess.get_sha256(child_path)
	for child: String in directory.get_directories():
		result.merge(_snapshot_files(path.path_join(child)))
	return result

func _layout(label: String) -> void:
	await _step(3)
	var screen := Rect2(0, 0, 640, 360)
	var panel: Rect2 = main.menu.get_global_rect()
	check(screen.encloses(panel), label + " panel fits 640x360")
	check(panel.end.y <= 310, label + " panel does not overlap status footer")
	check(screen.encloses(main.status.get_global_rect()), label + " status stays in viewport")
	_check_children(main.menu, panel, label)

func _check_children(node: Node, bounds: Rect2, label: String) -> void:
	for child: Node in node.get_children():
		if child is Control and child.is_visible_in_tree():
			check(bounds.grow(0.1).encloses(child.get_global_rect()), label + " child stays inside panel: " + str(child.name))
			if child is Button:
				var font: Font = child.get_theme_font("font")
				var font_size: int = child.get_theme_font_size("font_size")
				for line: String in child.text.split("\n"):
					check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= child.size.x - 8, label + " full Chinese button line fits: " + line)
		_check_children(child, bounds, label)

func _run() -> void:
	await process_frame
	TranslationServer.set_locale("zh_CN")
	saves = root.get_node("SaveService")
	session = root.get_node("GameSession")
	app = root.get_node("App")
	fixture = "user://tests/save_slots_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	saves.test_root = fixture
	check(saves.list_slot_summaries().size() == 9, "summary reports five manual plus quick plus three automatic slots")
	check(not DirAccess.dir_exists_absolute(fixture), "empty summary query creates no files or directories")
	session.start_new_game()
	var automatic: GameState = GameState.from_dict(session.state.to_dict())
	automatic.route_id = "ROUTE_AUTOMATIC_FIXTURE"
	automatic.world_flags["AUTO_ONLY"] = true
	check(saves.save_game("auto_01", automatic) == OK, "automatic fixture lives only under isolated root")
	var before_query: Dictionary = _snapshot_files()
	var state_before: Dictionary = session.state.to_dict()
	for _query in range(3):
		var summaries: Array[Dictionary] = saves.list_slot_summaries()
		check(summaries.size() == 9 and not saves.slot_summary("manual_04")["exists"], "automatic data never impersonates an empty manual slot")
	check(_snapshot_files() == before_query and session.state.to_dict() == state_before, "listing is read-only for every file and active state")
	check(saves.load_game("manual_04", false)["error"] == ERR_FILE_NOT_FOUND, "strict selected-slot load cannot cross to auto")
	check(saves.load_game("manual_04")["source"] == "auto_01", "legacy explicit recovery API remains backwards compatible")
	main = load(MAIN).instantiate()
	root.add_child(main)
	await _step(3)
	await _tap(KEY_S)
	check(root.gui_get_focus_owner().text == "读取存档", "title arrow navigation reaches load list entry")
	await _tap(KEY_E)
	check(main._menu_kind == &"load_slots" and main.slot_entries.size() == 7, "title opens independent load list with only existing automatic slots")
	check(_find_button(main.menu, "Slot_quick").disabled and _find_button(main.menu, "Slot_quick").text.contains("空槽"), "empty quick slot is visibly empty and cannot load")
	check(main.status.text.contains("自动存档触发尚未实现"), "UI explains automatic trigger is not implemented")
	await _layout("empty title load list")
	main._load_game("manual_04")
	check(main.status.text.contains("空槽") and main.get_node("SceneHost").get_child_count() == 0, "empty explicit load gives error without entering unrelated auto route")
	await _tap(KEY_ESCAPE)
	check(main._menu_kind == &"title" and app.current_context() == &"system_menu", "Escape from title list returns to title")
	await _tap(KEY_ESCAPE)
	check(app.current_context() == &"system_menu" and main.get_node("SceneHost").get_child_count() == 0, "Escape on title cannot resume nonexistent map")
	main._start_game()
	check(session.enter_region("SCENE_HOME_COURTYARD", "SPAWN_FROM_TOWN") == OK, "home-map fixture enters valid region")
	main._enter_yard()
	await _step(3)
	session.state.world_flags["MANUAL_MARKER"] = 1
	await _tap(KEY_F5)
	var quick_bytes: String = FileAccess.get_file_as_string(saves.slot_path("quick"))
	check(saves.load_game("quick", false)["state"].scene_id == "SCENE_HOME_COURTYARD", "F5 records actual current map into quick only")
	await _tap(KEY_ESCAPE)
	await _layout("pause with separate save actions")
	check(_find_button(main.menu, "快速存档", true) != null and _find_button(main.menu, "手动存档", true) != null, "pause distinguishes quick and manual save")
	await _activate("手动存档", true)
	check(main.slot_entries.size() == 5 and main.slot_buttons.size() == 3, "manual list exposes only five manual slots with bounded pages")
	await _tap(KEY_E)
	check(saves.slot_summary("manual_01")["can_load"] and main._menu_kind == &"save_slots", "empty manual slot writes directly and stays in list")
	check(FileAccess.get_file_as_string(saves.slot_path("quick")) == quick_bytes, "manual save never overwrites quick")
	check(_find_button(main.menu, "Slot_manual_01").text.contains("UTC") and _find_button(main.menu, "Slot_manual_01").text.contains("院落"), "occupied row shows save time and localized location")
	await _layout("manual rows with Chinese summary")
	await _test_overwrite(quick_bytes)
	await _test_manual_five(quick_bytes)
	await _test_bad_and_recovery()
	# Replace several menus before any deferred focus callback can execute.
	main._render_pause()
	main._show_save_slots()
	main._request_save_slot("manual_01")
	await _step(3)
	check(root.gui_get_focus_owner().name == "OverwriteCancel", "same-frame menu replacement focuses only current confirmation")
	check(main.slot_buttons.is_empty(), "leaving slot list removes stale freed row references")
	await _finish()

func _test_overwrite(quick_bytes: String) -> void:
	session.state.world_flags["MANUAL_MARKER"] = 2
	var original_files: Dictionary = _snapshot_files()
	await _activate("Slot_manual_01")
	check(main._menu_kind == &"overwrite" and root.gui_get_focus_owner().name == "OverwriteCancel", "occupied slot requires confirmation defaulting to Cancel")
	await _layout("overwrite confirmation")
	_key(KEY_E, true, true)
	await _step()
	_key(KEY_E, false)
	check(main._menu_kind == &"overwrite" and _snapshot_files() == original_files, "held confirm repeat cannot accept or bypass overwrite prompt")
	await _tap(KEY_E)
	check(main._menu_kind == &"save_slots" and _snapshot_files() == original_files, "default Cancel preserves every save byte")
	await _activate("Slot_manual_01")
	await _tap(KEY_ESCAPE)
	check(main._menu_kind == &"save_slots" and _snapshot_files() == original_files, "Escape cancels overwrite and returns one menu level")
	await _activate("Slot_manual_01")
	await _tap(KEY_S)
	check(root.gui_get_focus_owner().name == "OverwriteConfirm", "deliberate directional input selects overwrite confirmation")
	await _tap(KEY_E)
	check(main._menu_kind == &"save_slots" and saves.load_game("manual_01", false)["state"].world_flags["MANUAL_MARKER"] == 2, "explicit confirmation replaces only selected manual slot")
	check(IO.read_envelope(saves.backup_path("manual_01"))["state"].world_flags["MANUAL_MARKER"] == 1, "overwrite retains prior valid slot as its own backup")
	check(FileAccess.get_file_as_string(saves.slot_path("quick")) == quick_bytes, "overwrite leaves quick slot unchanged")
	var stopped: Vector2 = _region().player_position
	_key(KEY_D, true)
	await _step(4)
	await _tap(KEY_F5)
	check(_region().player_position == stopped and FileAccess.get_file_as_string(saves.slot_path("quick")) == quick_bytes, "manual list blocks gameplay movement and F5")
	await _tap(KEY_ESCAPE)
	check(main._menu_kind == &"pause" and app.current_context() == &"system_menu", "Escape from manual list returns to pause without movement")
	await _tap(KEY_ESCAPE)
	await _step(4)
	check(app.current_context() == &"exploration" and _region().player_position == stopped, "resume rejects direction held beneath menus")
	_key(KEY_D, false)
	await _step()
	_key(KEY_D, true)
	await _step(3)
	_key(KEY_D, false)
	check(_region().player_position.x > stopped.x, "fresh direction after menu close moves normally")
	await _step()

func _test_manual_five(quick_bytes: String) -> void:
	check(session.enter_region("SCENE_RIVER_DOCK", "SPAWN_FROM_TOWN") == OK, "manual-five fixture uses a different real region")
	main._enter_yard()
	await _step(3)
	session.state.world_flags["MANUAL_MARKER"] = 5
	session.state.time_state = {"day": 4, "slot": 3}
	var expected: Dictionary = session.state.to_dict()
	var one_bytes: String = FileAccess.get_file_as_string(saves.slot_path("manual_01"))
	await _tap(KEY_ESCAPE)
	await _activate("手动存档", true)
	await _activate("SlotNext")
	check(main._slot_page == 1 and _find_button(main.menu, "Slot_manual_05") != null, "keyboard pagination reaches fifth manual slot")
	await _activate("Slot_manual_05")
	check(_same(saves.load_game("manual_05", false)["state"].to_dict(), expected), "fifth slot saves complete current map and state")
	check(FileAccess.get_file_as_string(saves.slot_path("quick")) == quick_bytes and FileAccess.get_file_as_string(saves.slot_path("manual_01")) == one_bytes, "fifth slot cannot overwrite quick or first slot")
	await _layout("manual second page")
	await _tap(KEY_ESCAPE)
	await _activate("读取存档", true)
	await _activate("SlotNext")
	await _layout("pause load second page")
	await _tap(KEY_ESCAPE)
	check(main._menu_kind == &"pause", "Escape from pause load list returns to pause")
	main._return_to_title()
	await _step(3)
	await _activate("读取存档", true)
	await _activate("SlotNext")
	await _activate("Slot_manual_05")
	check(app.current_context() == &"exploration" and not main.menu.visible, "title-selected manual load enters exploration")
	check(_same(session.state.to_dict(), expected) and _region().scene_id == "SCENE_RIVER_DOCK", "explicit manual-five load restores full intended route instead of quick or auto")
	check(main.status.text.contains("手动存档 5") and main.status.text.contains("primary"), "load feedback names selected slot and primary source")
	var manual_before: String = FileAccess.get_file_as_string(saves.slot_path("manual_05"))
	session.state.world_flags["QUICK_ONLY"] = true
	await _tap(KEY_F5)
	check(FileAccess.get_file_as_string(saves.slot_path("manual_05")) == manual_before, "later F5 updates only quick and preserves fifth manual slot")
	check(saves.load_game("quick", false)["state"].world_flags.has("QUICK_ONLY"), "later F5 actually updates quick slot")

func _test_bad_and_recovery() -> void:
	var old: GameState = GameState.from_dict(session.state.to_dict())
	old.world_flags["RECOVERY_MARKER"] = "old"
	check(saves.save_game("manual_02", old) == OK, "recovery fixture writes original selected slot")
	var recent: GameState = GameState.from_dict(old.to_dict())
	recent.world_flags["RECOVERY_MARKER"] = "new"
	check(saves.save_game("manual_02", recent) == OK, "recovery fixture creates selected-slot backup")
	check(IO.write_text(saves.slot_path("manual_02"), "{broken") == OK, "damage only isolated selected primary")
	var before_summary: Dictionary = _snapshot_files()
	check(saves.slot_summary("manual_02")["source"] == "backup", "summary reports backup instead of empty or unrelated automatic")
	check(_snapshot_files() == before_summary, "summary never repairs damaged primary as a side effect")
	await _tap(KEY_ESCAPE)
	await _activate("读取存档", true)
	check(_find_button(main.menu, "Slot_manual_02").text.contains("backup"), "load list clearly labels backup recovery")
	await _layout("load rows including backup")
	await _activate("Slot_manual_02")
	check(_same(session.state.to_dict(), old.to_dict()), "explicit damaged slot restores its own complete backup state")
	check(main.status.text.contains("手动存档 2") and main.status.text.contains("backup"), "load feedback identifies slot and backup source")
	check(saves.save_game("manual_03", recent) == OK, "rollback fixture writes own primary")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saves.slot_path("manual_03")))
	envelope["preview"] = {}
	check(IO.write_text(saves.slot_path("manual_03"), JSON.stringify(envelope)) == OK, "valid sparse preview fixture is written")
	check(saves.slot_summary("manual_03")["can_load"] and saves.slot_summary("manual_03")["scene_id"] == recent.scene_id, "summary derives location from validated state even with empty preview")
	check(IO.write_text(saves.slot_path("manual_03") + ".old", JSON.stringify(envelope)) == OK, "isolated interrupted-write sibling exists")
	check(IO.write_text(saves.slot_path("manual_03"), "{broken") == OK, "rollback selected primary is damaged")
	check(saves.slot_summary("manual_03")["source"] == "rollback" and saves.load_game("manual_03", false)["source"] == "rollback", "summary and explicit load share primary then rollback then backup ordering")
	var future: Dictionary = envelope.duplicate(true)
	future["schema_version"] = 99
	check(IO.write_text(saves.slot_path("manual_04"), JSON.stringify(future)) == OK, "future-version fixture is isolated")
	await _assert_newer_protected("future primary")
	check(IO.write_text(saves.slot_path("manual_04"), "{broken") == OK, "future-backup fixture has broken current file")
	check(IO.write_text(saves.backup_path("manual_04"), JSON.stringify(future)) == OK, "future backup fixture is isolated")
	await _assert_newer_protected("future backup")
	check(IO.write_text(saves.slot_path("manual_04"), JSON.stringify(envelope)) == OK, "readable current-version primary can coexist with protected future backup")
	var mixed_summary: Dictionary = saves.slot_summary("manual_04")
	check(mixed_summary["can_load"] and not mixed_summary["can_overwrite"], "readable primary does not permit destruction of newer backup")
	var mixed_before: Dictionary = _snapshot_files()
	check(saves.save_game("manual_04", session.state) == ERR_UNAVAILABLE and _snapshot_files() == mixed_before, "direct service save also preserves newer backup beside readable primary")
	check(main._save_game("manual_04") == ERR_UNAVAILABLE and _snapshot_files() == mixed_before, "future backup is protected even when valid primary takes read priority")
	await _tap(KEY_ESCAPE)
	await _activate("手动存档", true)
	await _activate("SlotNext")
	check(_find_button(main.menu, "Slot_manual_04").disabled and _find_button(main.menu, "Slot_manual_04").text.contains("新版"), "save list explains future-backup overwrite restriction")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)
	check(IO.write_text(saves.backup_path("auto_03"), "{broken") == OK, "orphan damaged backup fixture has no primary")
	var orphan: Dictionary = saves.slot_summary("auto_03")
	check(orphan["exists"] and not orphan["can_load"] and orphan["error"] != ERR_FILE_NOT_FOUND, "backup-only damaged slot is occupied and damaged rather than empty")
	var before_orphan: Dictionary = session.state.to_dict()
	main._load_game("auto_03")
	check(main.status.text.contains("损坏") and _same(session.state.to_dict(), before_orphan), "explicit orphan-backup load explains damage without unrelated auto recovery")
	# A valid envelope can still reference unavailable game content. The UI must
	# preserve the currently playable scene and state on this separate failure.
	var missing: GameState = GameState.from_dict(session.state.to_dict())
	missing.scene_id = "SCENE_NOT_INSTALLED"
	missing.spawn_id = "SPAWN_NOT_INSTALLED"
	check(saves.save_game("manual_03", missing) == OK, "unknown-content save remains structurally valid")
	await _tap(KEY_ESCAPE)
	await _activate("读取存档", true)
	await _activate("SlotNext")
	var state_before: Dictionary = session.state.to_dict()
	var region_before: Node2D = _region()
	await _activate("Slot_manual_03")
	check(_region() == region_before and _same(session.state.to_dict(), state_before), "unknown-content load keeps exact current region and complete route")
	check(main.menu.visible and main._menu_kind == &"load_slots" and main.status.text.contains("无效"), "unknown-content load leaves usable list with clear error")
	check(IO.write_text(saves.slot_path("manual_03"), "{broken") == OK, "all-bad selected primary fixture")
	check(IO.write_text(saves.slot_path("manual_03") + ".old", "{broken") == OK, "all-bad selected rollback fixture")
	check(IO.write_text(saves.backup_path("manual_03"), "{broken") == OK, "all-bad selected backup fixture")
	var damaged: Dictionary = saves.slot_summary("manual_03")
	check(damaged["exists"] and not damaged["can_load"], "damaged occupied slot is not mislabeled empty")
	main._load_game("manual_03")
	check(_region() == region_before and _same(session.state.to_dict(), state_before) and main.status.text.contains("损坏"), "unrecoverable selected slot cannot switch to automatic route")
	main._show_slot_list(&"load_slots", 1)
	await _step(3)
	check(_find_button(main.menu, "Slot_manual_03").disabled, "unrecoverable load row is disabled")
	await _layout("unreadable and future-version rows")
	var before: Dictionary = _snapshot_files()
	saves.list_slot_summaries()
	check(_snapshot_files() == before, "final mixed-state summary remains byte-for-byte read-only")
	await _tap(KEY_ESCAPE)
	await _activate("手动存档", true)
	await _activate("Slot_manual_03")
	check(main._menu_kind == &"overwrite" and root.gui_get_focus_owner().name == "OverwriteCancel", "damaged occupied slot still requires default-cancel confirmation")
	await _tap(KEY_ESCAPE)
	check(_snapshot_files() == before, "cancelling damaged-slot overwrite preserves every file")

func _assert_newer_protected(label: String) -> void:
	var files_before: Dictionary = _snapshot_files()
	var state_before: Dictionary = session.state.to_dict()
	var region_before: Node2D = _region()
	check(saves.slot_summary("manual_04")["exists"] and saves.slot_summary("manual_04")["error"] == ERR_UNAVAILABLE, label + " summary identifies occupied newer schema")
	check(saves.save_game("manual_04", session.state) == ERR_UNAVAILABLE and _snapshot_files() == files_before, label + " service refuses overwrite without mutating files")
	check(main._save_game("manual_04") == ERR_UNAVAILABLE, label + " main save refuses overwrite")
	main._load_game("manual_04")
	check(_snapshot_files() == files_before and _region() == region_before and _same(session.state.to_dict(), state_before), label + " load and save leave all data and runtime untouched")
	await _tap(KEY_ESCAPE)
	await _activate("手动存档", true)
	await _activate("SlotNext")
	check(_find_button(main.menu, "Slot_manual_04").disabled, label + " cannot be selected for overwrite")
	main._request_save_slot("manual_04")
	check(main._menu_kind == &"save_slots" and _snapshot_files() == files_before, label + " rechecks compatibility at save execution")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_ESCAPE)

func _finish() -> void:
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_E, KEY_ESCAPE, KEY_TAB, KEY_F5]:
		_key(code, false)
	if is_instance_valid(main):
		root.remove_child(main)
		main.queue_free()
	await process_frame
	await process_frame
	saves.test_root = ""
	_cleanup(fixture)
	if failures.is_empty():
		print("SAVE_SLOTS_UI_PASS checks=", checks, " (isolated files; real keyboard menus; exact-slot semantics; Chinese layout bounds)")
	quit(0 if failures.is_empty() else 1)

func _cleanup(path: String) -> void:
	if not fixture.begins_with("user://tests/save_slots_ui_") or (path != fixture and not path.begins_with(fixture + "/")):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_cleanup(path.path_join(child))
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
