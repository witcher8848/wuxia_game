extends SceneTree
## External verifier: invoke with --main-pack <exported.pck> --script <absolute path>.
## The verifier itself is excluded from exported game resources.

const FORBIDDEN_PREFIXES: Array[String] = [
	"res://game/tests/", "res://game/tools/", "res://assets/source/",
	"res://tools/", "res://docs/", "res://builds/", "res://logs/",
	"res://.tools/", "res://.git/", "res://.github/", "res://.godot/editor/",
]
const FORBIDDEN_NAMES: Array[String] = [
	"steam_appid.txt", "export_credentials.cfg", ".env", ".DS_Store",
]
const REQUIRED_RESOURCES: Array[String] = [
	"res://game/presentation/main.tscn",
	"res://game/presentation/exploration/test_yard.tscn",
	"res://game/presentation/main.gd",
	"res://game/presentation/exploration/test_yard.gd",
	"res://game/domain/state/game_state.gd",
	"res://game/core/bootstrap/app.gd",
	"res://game/core/services/game_session.gd",
	"res://game/core/services/content_db.gd",
	"res://game/persistence/save_service.gd",
	"res://game/persistence/save_file_io.gd",
	"res://game/platform/offline/offline_platform_service.gd",
	"res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf",
]

var _files: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Godot consumes --main-pack before exposing script arguments. Check the
	# exported virtual filesystem itself, not a user-supplied flag.
	if not FileAccess.file_exists("res://project.binary") or FileAccess.file_exists("res://project.godot"):
		printerr("PACK_AUDIT_FAIL exported project.binary required; source-tree scanning is not package evidence.")
		quit(1)
		return
	_walk("res://")
	_files.sort()
	for path: String in _files:
		print("PACK_RESOURCE ", path)
		for prefix: String in FORBIDDEN_PREFIXES:
			if path.begins_with(prefix):
				_failures.append("Forbidden development resource: " + path)
		if path.get_file() in FORBIDDEN_NAMES or path.get_file().begins_with(".env."):
			_failures.append("Forbidden packaged file: " + path)
		if path.get_extension() in ["md", "sav", "bak", "tmp", "old", "log"]:
			_failures.append("Unexpected document, save, or temporary file: " + path)
	for resource: String in REQUIRED_RESOURCES:
		# Godot can export .tscn/.gd/font resources through remapped import paths.
		if not ResourceLoader.exists(resource):
			_failures.append("Missing required runtime resource: " + resource)
	var bootstrap_path: String = "res://game/content/data/bootstrap.json"
	if not FileAccess.file_exists(bootstrap_path):
		_failures.append("Missing bootstrap JSON in pack.")
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(bootstrap_path))
		if not parsed is Dictionary or not parsed.get("scenes") is Array:
			_failures.append("Pack bootstrap JSON is invalid.")
	if ProjectSettings.get_setting("application/run/main_scene", "") != REQUIRED_RESOURCES[0]:
		_failures.append("Pack main scene does not match the expected entry point.")
	if _files.is_empty():
		_failures.append("Pack resource listing is empty.")
	for failure: String in _failures:
		printerr("PACK_AUDIT_FAIL ", failure)
	if _failures.is_empty():
		print("PACK_AUDIT_PASS resources=", _files.size(), " required=", REQUIRED_RESOURCES.size() + 1)
	quit(0 if _failures.is_empty() else 1)


func _walk(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		_failures.append("Cannot list pack directory: " + path)
		return
	directory.include_hidden = true
	for file_name: String in directory.get_files():
		_files.append(path.path_join(file_name))
	for child: String in directory.get_directories():
		_walk(path.path_join(child))
