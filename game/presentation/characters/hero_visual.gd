extends Node2D
## Presentation-only shared renderer. No damage, action or save state is decided here.
const ATLAS = preload("res://assets/runtime/characters/chr_protagonist_atlas.png")
# Legacy source/export fixtures retain this exact contract even after activation.
const DATA_PATH := "res://assets/runtime/characters/chr_protagonist_atlas.json"
const IMAGEGEN_DATA_PATH := "res://assets/runtime/characters/chr_protagonist_imagegen_20261012.json"
# Promotion changes only this choice, after the complete manifest is validated.
const ACTIVE_DATA_PATH := IMAGEGEN_DATA_PATH
# Fixed 16x6 pixel ellipse. Rows share the feet anchor in every scene.
const SHADOW_ROWS := [Rect2(-4,-3,8,1),Rect2(-7,-2,14,1),Rect2(-8,-1,16,2),Rect2(-7,1,14,1),Rect2(-4,2,8,1)]
static var data: Dictionary = {}
static var _texture_cache: Dictionary = {}
var facing := "down"
var walking := false
var sprinting := false
var step_time := 0.0
var external_clock := false
var _action := ""
var _elapsed := 0.0
var _manifest: Dictionary = {}
var _manifest_path := ""
var _geometry_cache: Array[Dictionary] = []
var _bounds_cache: Dictionary = {}
var default_manifest_error: Error = OK

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_legacy_data()
	# PlayerVisual's super._ready(), the battle board and the lab all enter here.
	# A deliberately configured instance must not be overwritten on tree entry.
	if _manifest.is_empty():
		var error := configure_default_manifest()
		if error != OK:
			push_error("HERO_MANIFEST_DEFAULT_FAIL %s error=%d" % [ACTIVE_DATA_PATH,error])
	queue_redraw()

func _ensure_legacy_data() -> void:
	if not data.is_empty(): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary: data = parsed

## One default selection for every runtime consumer; no scene-local overrides.
func configure_default_manifest() -> Error:
	default_manifest_error = configure_manifest(ACTIVE_DATA_PATH)
	return default_manifest_error

func manifest_path() -> String:
	return _manifest_path if not _manifest_path.is_empty() else DATA_PATH

## An explicit fixture/preview override never changes the shared default choice.
## PNGs are loaded as imported textures, never cropped, resized or written back.
func configure_manifest(path: String) -> Error:
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return ERR_PARSE_ERROR
	var error := _validate_manifest(parsed)
	if error != OK: return error
	var geometries := _build_geometry(parsed)
	_manifest = parsed
	_manifest_path = path
	_geometry_cache = geometries
	_bounds_cache.clear()
	reset_pose()
	return OK

func manifest_data() -> Dictionary:
	_ensure_legacy_data()
	return _manifest if not _manifest.is_empty() else data

func clip_data(name: String = "") -> Dictionary:
	var manifest := manifest_data()
	return manifest.get("clips",{}).get(clip_name() if name.is_empty() else name,{})

func frame_count() -> int:
	var manifest := manifest_data()
	return int(manifest.get("frame_count",0))

func display_size() -> Vector2:
	var geometry := frame_geometry(frame_number())
	return geometry.get("display_size",Vector2.ZERO)

## Anchor is in logical display pixels, relative to the displayed region.
func frame_geometry(frame: int) -> Dictionary:
	var manifest := manifest_data()
	if frame < 0 or frame >= frame_count(): return {}
	if _geometry_cache.is_empty(): _geometry_cache = _build_geometry(manifest)
	# Return a copy so a caller cannot corrupt a later frame's cached geometry.
	return _geometry_cache[frame].duplicate()

func _build_geometry(manifest: Dictionary) -> Array[Dictionary]:
	var geometries: Array[Dictionary] = []
	for frame: int in int(manifest.get("frame_count",0)):
		if int(manifest.get("schema_version",1)) == 2:
			var record: Dictionary = manifest["frames"][frame]
			geometries.append({
				"texture":_load_texture(record["texture"]),
				"region":Rect2(record["region"][0],record["region"][1],record["region"][2],record["region"][3]),
				"display_size":Vector2(record["display_size"][0],record["display_size"][1]),
				"anchor":Vector2(record["anchor"][0],record["anchor"][1]),
			})
		else:
			var size: Array = manifest.get("frame_size",[32,48])
			var anchor: Array = manifest.get("anchor",[16,44])
			var columns := int(manifest.get("columns",8))
			geometries.append({
				"texture":ATLAS,
				"region":Rect2((frame%columns)*size[0],int(frame/columns)*size[1],size[0],size[1]),
				"display_size":Vector2(size[0],size[1]),
				"anchor":Vector2(anchor[0],anchor[1]),
			})
	return geometries

## Union across the current clip keeps preview placement stable between frames.
func presentation_bounds() -> Rect2:
	var name := clip_name()
	if _bounds_cache.has(name): return _bounds_cache[name]
	var bounds := Rect2()
	var first := true
	for cell: Variant in clip_data().get("cells",[]):
		var geometry := frame_geometry(int(cell))
		if geometry.is_empty(): continue
		var rectangle := Rect2(-geometry["anchor"],geometry["display_size"])
		bounds = rectangle if first else bounds.merge(rectangle)
		first = false
	_bounds_cache[name] = bounds
	return bounds

func _load_texture(path: String) -> Texture2D:
	if not _texture_cache.has(path):
		_texture_cache[path] = ResourceLoader.load(path,"Texture2D") as Texture2D
	return _texture_cache[path]

func _number_array(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number: Variant in value:
		if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)): return false
	return true

func _validate_manifest(manifest: Dictionary) -> Error:
	var version_value: Variant = manifest.get("schema_version",1)
	if typeof(version_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(version_value)): return ERR_INVALID_DATA
	var version := int(version_value)
	if version_value != version: return ERR_INVALID_DATA
	if version not in [1,2]: return ERR_INVALID_DATA
	var count_value: Variant = manifest.get("frame_count")
	if typeof(count_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(count_value)): return ERR_INVALID_DATA
	var count := int(count_value)
	if count <= 0 or count_value != count: return ERR_INVALID_DATA
	if not manifest.get("clips") is Dictionary or manifest["clips"].is_empty(): return ERR_INVALID_DATA
	for direction: String in ["up","down","left","right"]:
		for action: String in ["idle","walk","strike","thrust","slash","guard","hit"]:
			if not manifest["clips"].has(action+"_"+direction): return ERR_INVALID_DATA
	if not manifest["clips"].has("down"): return ERR_INVALID_DATA
	if version == 2:
		if not manifest.get("frames") is Array or manifest["frames"].size() != count: return ERR_INVALID_DATA
		for record: Variant in manifest["frames"]:
			if not record is Dictionary: return ERR_INVALID_DATA
			var texture_path: Variant = record.get("texture")
			if not texture_path is String: return ERR_INVALID_DATA
			if not texture_path.begins_with("res://assets/runtime/characters/") or texture_path.get_extension().to_lower() != "png" or texture_path.simplify_path() != texture_path: return ERR_INVALID_DATA
			if not ResourceLoader.exists(texture_path,"Texture2D"): return ERR_FILE_NOT_FOUND
			var texture := _load_texture(record["texture"])
			if texture == null: return ERR_INVALID_DATA
			if not _number_array(record.get("region"),4) or not _number_array(record.get("display_size"),2) or not _number_array(record.get("anchor"),2): return ERR_INVALID_DATA
			var region: Array = record["region"]
			for coordinate: Variant in region:
				if coordinate != int(coordinate): return ERR_INVALID_DATA
			if region[0] < 0 or region[1] < 0 or region[2] <= 0 or region[3] <= 0: return ERR_INVALID_DATA
			if region[0]+region[2] > texture.get_width() or region[1]+region[3] > texture.get_height(): return ERR_INVALID_DATA
			var size: Array = record["display_size"]
			if size[0] <= 0 or size[1] <= 0 or not is_equal_approx(float(size[0])/float(region[2]),float(size[1])/float(region[3])): return ERR_INVALID_DATA
			var anchor: Array = record["anchor"]
			if anchor[0] < 0 or anchor[1] < 0 or anchor[0] > size[0] or anchor[1] > size[1]: return ERR_INVALID_DATA
			var hash_value: Variant = record.get("source_sha256")
			# Original PNG byte parity is checked offline before promotion/export.
			# PCK textures may be remapped to .ctex, so never hash source PNGs here.
			if not hash_value is String or hash_value.length() != 64: return ERR_INVALID_DATA
			for character: String in hash_value:
				if character not in "0123456789abcdefABCDEF": return ERR_INVALID_DATA
	else:
		if not _number_array(manifest.get("frame_size"),2) or not _number_array(manifest.get("anchor"),2): return ERR_INVALID_DATA
		var size: Array = manifest["frame_size"]
		var columns_value: Variant = manifest.get("columns")
		if typeof(columns_value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(columns_value)): return ERR_INVALID_DATA
		var columns := int(columns_value)
		if columns <= 0 or columns_value != columns or size[0] <= 0 or size[1] <= 0: return ERR_INVALID_DATA
		if columns*size[0] > ATLAS.get_width() or ceili(float(count)/columns)*size[1] > ATLAS.get_height(): return ERR_INVALID_DATA
	for clip: Variant in manifest["clips"].values():
		if not clip is Dictionary or not clip.get("cells") is Array or clip["cells"].is_empty(): return ERR_INVALID_DATA
		var fps: Variant = clip.get("fps")
		if typeof(fps) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(fps)) or fps <= 0 or not clip.get("loop") is bool: return ERR_INVALID_DATA
		for cell: Variant in clip["cells"]:
			if typeof(cell) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(cell)) or cell != int(cell) or cell < 0 or cell >= count: return ERR_INVALID_DATA
	if manifest["clips"]["down"]["loop"]: return ERR_INVALID_DATA
	return OK

func play_action(action: String, direction: String) -> void:
	if direction in ["up","down","left","right"]: facing = direction
	if action not in ["strike","thrust","slash","guard","hit","down"]: return
	_action = action
	_elapsed = 0.0
	walking = false
	queue_redraw()

func reset_pose() -> void:
	_action = ""
	_elapsed = 0.0
	walking = false
	step_time = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not external_clock: step_time += delta * (300.0/180.0 if sprinting else 1.0)
	if not _action.is_empty():
		_elapsed += delta
		var clip := clip_data()
		if not clip.is_empty():
			var duration: float = clip["cells"].size()/float(clip["fps"])
			if _action == "down": _elapsed = minf(_elapsed,duration)
			elif _elapsed >= duration: _action = ""
	queue_redraw()

func clip_name() -> String:
	if _action == "down": return "down"
	return (_action if not _action.is_empty() else "walk" if walking else "idle") + "_" + facing

func frame_number() -> int:
	var clip := clip_data()
	if clip.is_empty(): return 0
	var elapsed := step_time if _action.is_empty() else _elapsed
	var index := int(elapsed*clip["fps"])
	index = posmod(index,clip["cells"].size()) if clip["loop"] else clampi(index,0,clip["cells"].size()-1)
	return int(clip["cells"][index])

func _draw() -> void:
	draw_at(self,Vector2.ZERO)

## Optional presentation-only scale. The default keeps exploration/lab geometry
## byte-for-byte equivalent; battle can fit the original texture into its grid.
func frame_draw_rectangle(frame: int, at: Vector2, render_scale := 1.0) -> Rect2:
	if not is_finite(render_scale) or render_scale <= 0.0: return Rect2()
	var geometry := frame_geometry(frame)
	if geometry.is_empty(): return Rect2()
	return Rect2(at-geometry["anchor"]*render_scale,geometry["display_size"]*render_scale)

func draw_at(canvas: CanvasItem, at: Vector2, render_scale := 1.0) -> void:
	if clip_data().is_empty(): return
	var geometry := frame_geometry(frame_number())
	if geometry.is_empty(): return
	var rectangle := frame_draw_rectangle(frame_number(),at,render_scale)
	if not rectangle.has_area(): return
	# Separate fixed pixel shadow; anchor always follows physics feet exactly.
	for row: Rect2 in SHADOW_ROWS:
		canvas.draw_rect(Rect2(at+row.position*render_scale,row.size*render_scale),Color("#333b46"))
	canvas.draw_texture_rect_region(geometry["texture"],rectangle,geometry["region"])
	if sprinting and walking:
		var behind := Vector2.UP if facing == "down" else Vector2.DOWN if facing == "up" else Vector2.LEFT if facing == "right" else Vector2.RIGHT
		canvas.draw_rect(Rect2(at+(behind*14*render_scale).round(),Vector2(3,2)*render_scale),Color("#d19a5c"))
		canvas.draw_rect(Rect2(at+((behind*19+Vector2(3,1))*render_scale).round(),Vector2(2,1)*render_scale),Color("#a9ada4"))
