extends SceneTree
## Viewport-caption geometry and actual character-lab contrast. Fixtures are
## presentation placement, not keyboard traversal or human art acceptance.
var checks := 0
var failures: Array[String] = []
var capture_enabled := false
var captured := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("REVIEW_PRESENTATION_FAIL ", label)

func frames() -> void:
	await physics_frame
	await process_frame
	await process_frame

func capture(label: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	var folder := "res://builds/qa/weeks3_7_review"
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "create screenshot folder")
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == Vector2i(640,360), "actual logical viewport")
	check(picture.save_png(folder.path_join(label+".png")) == OK, "capture "+label)
	captured += 1

func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126*linear.r+0.7152*linear.g+0.0722*linear.b

func contrast(first: Color, second: Color) -> float:
	return (maxf(luminance(first),luminance(second))+0.05)/(minf(luminance(first),luminance(second))+0.05)

func _run() -> void:
	create_timer(45).timeout.connect(func() -> void: printerr("REVIEW_PRESENTATION_FAIL watchdog"); quit(1))
	await frames()
	capture_enabled = "--capture-review" in OS.get_cmdline_user_args()
	check(not capture_enabled or DisplayServer.get_name() != "headless", "native renderer required for captures")
	var session: Node = root.get_node("GameSession")
	root.get_node("App").reset_contexts()
	session.start_new_game()
	var region: Node2D = load("res://game/presentation/exploration/town_street.tscn").instantiate()
	root.add_child(region)
	await frames()
	region.set_physics_process(false)
	region.player.movement_enabled = false
	var target: Dictionary = {}
	for entry: Dictionary in region.definition["interactions"]:
		if entry["id"] == "EXIT_STREET_DOCK": target = entry
	check(not target.is_empty(), "actual registered exit fixture")
	var before: Dictionary = session.state.to_dict()
	for locale: String in ["zh_CN","en"]:
		TranslationServer.set_locale(locale)
		region.player_position = Vector2(550,384)
		region.camera.follow(region.player_position)
		region.queue_redraw()
		await frames()
		var label: Dictionary = region.caption_layout(target)
		check(not label.is_empty(), "onscreen destination has caption "+locale)
		if not label.is_empty():
			var transform: Transform2D = region.get_global_transform_with_canvas()
			var screen := Rect2(transform*label["rect"].position,label["rect"].size)
			check(root.get_visible_rect().grow(-3).encloses(screen), "entire caption remains inside viewport "+locale)
			check(label["text"] == TranslationServer.translate(target["name_key"]), "normal destination text stays complete")
		await capture("caption_edge_"+locale)
		region.player_position = Vector2(512,384)
		region.camera.follow(region.player_position)
		region.queue_redraw()
		await frames()
		check(region.caption_layout(target).is_empty(), "offscreen exit cannot leave a half-word or false onscreen label")
		await capture("caption_offscreen_"+locale)
		var long_target := target.duplicate(true)
		long_target["position"] = [512,384]
		long_target["name_key"] = "超长目的地".repeat(40)
		label = region.caption_layout(long_target)
		check(label.get("text", "").ends_with("…"), "oversized captions are visibly abbreviated")
		if not label.is_empty():
			var transform: Transform2D = region.get_global_transform_with_canvas()
			check(root.get_visible_rect().grow(-3).encloses(Rect2(transform*label["rect"].position,label["rect"].size)), "oversized caption is also contained")
	check(session.state.to_dict() == before, "layout queries and preview placement do not write persistent state")
	root.remove_child(region)
	region.free()
	var lab: Node2D = load("res://game/presentation/characters/character_lab.tscn").instantiate()
	root.add_child(lab)
	await frames()
	lab.paused = true
	lab.zoom = 3
	check(lab.single_direction_mode(), "production 3x uses single-direction panel")
	check(not lab.TITLE.contains("第五周"), "reusable lab title is not tied to an obsolete week")
	for index: int in 2:
		lab.direction_index = index
		lab.queue_redraw()
		await frames()
		var background := Color("#a9ada4") if index%2 == 0 else Color("#203934")
		check(contrast(lab.status_ink(),background) >= 4.5, "3x status text has readable contrast on both backgrounds")
		check(lab.status_lines().size() == 2, "3x action and playback status use separate lines")
		for line: String in lab.status_lines():
			check(lab.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x <= 180, "complete 3x caption fits the side column without cutting pause state")
		await capture("lab_3x_"+("light" if index == 0 else "dark"))
	root.remove_child(lab)
	lab.free()
	if failures.is_empty(): print("REVIEW_PRESENTATION_PASS checks=%d captures=%d" % [checks,captured])
	else: printerr("REVIEW_PRESENTATION_FAILED ",failures)
	quit(0 if failures.is_empty() else 1)
