extends SceneTree
## Procedural pose diagram only: not character art, and no original PNG is edited.
## ./tools/godot.sh --path . --rendering-method gl_compatibility --script res://tools/render_hero_walk_pose_guide_20261010.gd -- --capture
## Optional --phase=0, --phase=1 or --phase=3 selects a separate output; omit for original phase 2.
const OUTPUT := "res://docs/art_reference/hero_imagegen_walk_20261010/pose_guide_opposite_contact.png"
const PHASE_OUTPUTS := {0:"pose_guide_phase_0_contact.png",1:"pose_guide_phase_1_passing.png",3:"pose_guide_phase_3_passing.png"}
const FONT_PATH := "res://assets/runtime/fonts/NotoSansCJKsc-Regular.otf"
const NEAR := Color("#246da8")
const FAR := Color("#626871")
const INK := Color("#303740")
const BACKGROUND := Color("#f1eee6")

class PoseGuide extends Node2D:
	var font: Font
	var phase := 2
	func limb(points: PackedVector2Array, ink: Color) -> void:
		draw_polyline(points,ink,14.0,false)
		for at: Vector2 in points:
			draw_circle(at,8.0,ink)

	func _draw() -> void:
		var near_arm := PackedVector2Array([Vector2(300,225),Vector2(354,274),Vector2(407,319)])
		var far_arm := PackedVector2Array([Vector2(300,225),Vector2(246,278),Vector2(208,328)])
		var near_leg := PackedVector2Array([Vector2(300,368),Vector2(250,447),Vector2(190,526)])
		var far_leg := PackedVector2Array([Vector2(300,368),Vector2(340,450),Vector2(402,526)])
		var foot_length := 44.0
		match phase:
			0:
				near_arm = PackedVector2Array([Vector2(300,225),Vector2(246,278),Vector2(208,328)])
				far_arm = PackedVector2Array([Vector2(300,225),Vector2(354,274),Vector2(407,319)])
				near_leg = PackedVector2Array([Vector2(300,368),Vector2(340,450),Vector2(402,526)])
				far_leg = PackedVector2Array([Vector2(300,368),Vector2(250,447),Vector2(190,526)])
			1,3:
				var back_arm := PackedVector2Array([Vector2(300,225),Vector2(286,278),Vector2(280,333)])
				var front_arm := PackedVector2Array([Vector2(300,225),Vector2(318,278),Vector2(330,328)])
				var support_leg := PackedVector2Array([Vector2(300,368),Vector2(300,448),Vector2(300,526)])
				var passing_leg := PackedVector2Array([Vector2(300,368),Vector2(340,445),Vector2(360,492)])
				near_arm = back_arm if phase == 1 else front_arm
				far_arm = front_arm if phase == 1 else back_arm
				near_leg = support_leg if phase == 1 else passing_leg
				far_leg = passing_leg if phase == 1 else support_leg
				foot_length = 34.0
		draw_rect(Rect2(0,0,600,600),BACKGROUND)
		draw_string(font,Vector2(24,30),"POSE ONLY · 骨架姿态引导 · 面向右 →",HORIZONTAL_ALIGNMENT_LEFT,-1,20,INK)
		if phase != 2:
			draw_string(font,Vector2(440,60),"PHASE %d" % phase,HORIZONTAL_ALIGNMENT_LEFT,-1,18,INK)
		draw_line(Vector2(128,526),Vector2(460,526),Color("#b6b7b3"),1.0)
		# Far anatomical-right limbs are drawn first, behind the torso/near limbs.
		limb(far_arm,FAR)
		limb(far_leg,FAR)
		draw_line(far_leg[2],far_leg[2]+Vector2(foot_length,0),FAR,14.0,false)
		draw_circle(Vector2(300,125),65.0,INK,false,6.0,false)
		draw_polyline(PackedVector2Array([Vector2(365,125),Vector2(383,135),Vector2(365,141)]),INK,5.0,false)
		draw_line(Vector2(300,190),Vector2(300,368),INK,9.0,false)
		draw_circle(Vector2(300,225),11.0,INK)
		draw_circle(Vector2(300,368),11.0,INK)
		# Near anatomical-left limbs are always drawn last to preserve overlap.
		limb(near_arm,NEAR)
		limb(near_leg,NEAR)
		draw_line(near_leg[2],near_leg[2]+Vector2(foot_length,0),NEAR,14.0,false)
		draw_string(font,Vector2(40,565),"蓝：近侧／角色左侧",HORIZONTAL_ALIGNMENT_LEFT,-1,18,NEAR)
		draw_string(font,Vector2(330,565),"灰：远侧／角色右侧",HORIZONTAL_ALIGNMENT_LEFT,-1,18,FAR)
		var note := "仅姿态输入；非游戏美术。两脚同一基线，头与躯干直立。"
		if phase in [1,3]: note = "仅姿态输入；非游戏美术。支撑脚y526；前传脚y492（离地34）。"
		draw_string(font,Vector2(40,590),note,HORIZONTAL_ALIGNMENT_LEFT,-1,16,INK)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var phase := 2
	var output_path := OUTPUT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			if argument not in ["--phase=0","--phase=1","--phase=3"]:
				printerr("POSE_GUIDE_FAIL unsupported phase; use 0/1/3 or omit for original phase 2")
				quit(1)
				return
			phase = int(argument.trim_prefix("--phase="))
			output_path = OUTPUT.get_base_dir()+"/"+PHASE_OUTPUTS[phase]
	var original_hash := FileAccess.get_sha256(OUTPUT) if FileAccess.file_exists(OUTPUT) else ""
	create_timer(20).timeout.connect(func() -> void: printerr("POSE_GUIDE_FAIL watchdog"); quit(1))
	if DisplayServer.get_name() == "headless":
		printerr("POSE_GUIDE_UNSUPPORTED: headless has no real renderer here; no PNG written.")
		quit(2)
		return
	if not FileAccess.file_exists(FONT_PATH):
		printerr("POSE_GUIDE_FAIL required font missing: ",FONT_PATH)
		quit(1)
		return
	var font := load(FONT_PATH) as Font
	if font == null:
		printerr("POSE_GUIDE_FAIL required font failed to load")
		quit(1)
		return
	# Local window override only: project.godot and the game viewport stay unchanged.
	root.content_scale_size = Vector2i(600,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(600,600)
	root.title = "POSE ONLY · 朝右反相接触姿态"
	var guide := PoseGuide.new()
	guide.font = font
	guide.phase = phase
	root.add_child(guide)
	await process_frame
	guide.queue_redraw()
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.get_size() != Vector2i(600,600):
		printerr("POSE_GUIDE_FAIL no real 600x600 rendered image")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK or capture.save_png(output_path) != OK:
		printerr("POSE_GUIDE_FAIL PNG save failed")
		quit(1)
		return
	if phase != 2 and not original_hash.is_empty() and FileAccess.get_sha256(OUTPUT) != original_hash:
		printerr("POSE_GUIDE_FAIL original phase 2 PNG changed")
		quit(1)
		return
	print("POSE_GUIDE_RENDER_PASS renderer=",DisplayServer.get_name()," size=600x600 phase=",phase," path=",output_path,"; procedural skeleton only, no character image input or edits")
	quit()
