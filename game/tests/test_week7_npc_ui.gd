extends SceneTree
## Real projected regions, physics bodies/rays and production journal keyboard
## handlers. Headless source/PCK compatible; no source JSON or save-file writes.
const Journal = preload("res://game/presentation/investigation/journal_view.gd")
var Region: GDScript
var Activity: GDScript
var checks := 0
var failures: Array[String] = []
var session: Node
var content: Node
var app: Node
var region: Node2D
var panel: Control

func _initialize() -> void:
	create_timer(70, true).timeout.connect(func() -> void: printerr("WEEK7_NPC_UI_FAIL watchdog"); quit(1))
	_run.call_deferred()

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("WEEK7_NPC_UI_FAIL ", label)
	return condition

func step(frames := 2) -> void:
	for _frame in frames:
		await physics_frame
		await process_frame

func same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func target(identifier: String) -> Dictionary:
	for item: Dictionary in region.definition["interactions"]:
		if item["id"] == identifier: return item
	return {}

func point(values: Array) -> Vector2:
	return Vector2(values[0], values[1])

func position_in(state: GameState) -> Vector2:
	return Vector2(state.player_state["position"]["x"], state.player_state["position"]["y"])

func hits_body(at: Vector2, body: StaticBody2D) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = at
	query.collision_mask = 1
	for hit: Dictionary in region.get_world_2d().direct_space_state.intersect_point(query):
		if hit["rid"] == body.get_rid(): return true
	return false

func install(scene: String) -> bool:
	if is_instance_valid(region):
		root.remove_child(region)
		region.queue_free()
		await step()
	session.start_new_game()
	var state := GameState.from_dict(session.state.to_dict())
	state.scene_id = scene
	state.spawn_id = content.get_scene_definition(scene)["spawn_ids"][0]
	var spawn: Vector2 = content.get_spawn_position(scene, state.spawn_id)
	state.player_state["position"] = {"x":spawn.x,"y":spawn.y}
	if not check(session.replace_state(state) == OK, scene+" fixture accepted by production session"): return false
	region = Region.new()
	region.scene_id = scene
	root.add_child(region)
	await step()
	if not check(is_instance_valid(region.player), scene+" actual region owns player"): return false
	# Freeze autonomous movement/session position polling, not physics bodies.
	# State changes below must reach the region through state_replaced itself.
	region.set_physics_process(false)
	region.player.movement_enabled = false
	return true

func region_schedule(scene: String, npc: String) -> void:
	if not await install(scene): return
	var initial := point(target(npc)["position"])
	var original_definition: Dictionary = content.get_exploration_region(scene)
	var baseline: Vector2
	for item: Dictionary in original_definition["interactions"]:
		if item["id"] == npc: baseline = point(item["position"])
	check(initial == baseline, npc+" slot zero preserves original authored position")
	var body: StaticBody2D = region._target_bodies[npc]
	var body_id := body.get_instance_id()
	var children := region.get_child_count()
	var anchors: Array[Vector2] = []
	for slot in 8:
		var next := GameState.from_dict(session.state.to_dict())
		next.time_state = {"day":1,"slot":slot}
		var before := next.to_dict().duplicate(true)
		var projection: Dictionary = content.exploration_view(scene,next)
		check(projection["error"].is_empty() and same(next.to_dict(), before), npc+" pure complete projection slot%d" % slot)
		region.selected_target = target(npc).duplicate(true)
		check(session.replace_state(next) == OK, npc+" time snapshot emits real session signal slot%d" % slot)
		await step()
		var at := point(target(npc)["position"])
		if not at in anchors: anchors.append(at)
		check(same(region.definition,projection["region"]), npc+" drawing/interaction definition matches projection slot%d" % slot)
		check(target(npc).get("character_id","") == npc, npc+" projected stable character identity slot%d" % slot)
		check(body.get_instance_id() == body_id and body.position == at, npc+" body reuses identity at same drawn anchor slot%d" % slot)
		check(region.get_child_count() == children, npc+" no duplicate/ghost bodies slot%d" % slot)
		check(region.selected_target.is_empty(), npc+" old interaction selection invalidated slot%d" % slot)
		check(hits_body(at,body), npc+" real physics sees current body slot%d" % slot)
		if at != initial: check(not hits_body(initial,body), npc+" vacated anchor no longer blocks physics slot%d" % slot)
		region.player_position = at + Vector2(0,40)
		region.player.facing = "up"
		await step()
		check(region.choose_target().get("id","") == npc, npc+" current anchor ray excludes own body and can be selected slot%d" % slot)
		check(region.player.test_move(Transform2D(0,at+Vector2(0,30)),Vector2(0,-30)), npc+" actual feet cannot walk through current NPC slot%d" % slot)
	check(anchors.size() >= 3, npc+" eight slots actually visit three authored anchors")
	check(same(content.get_exploration_region(scene),original_definition), npc+" projection never edits static registry")
	# An intervening solid must still occlude the query, not just the NPC's body.
	var at := point(target(npc)["position"])
	var blocker: StaticBody2D = region._add_obstacle(Rect2(at+Vector2(-5,16),Vector2(10,8)))
	await step()
	check(region.choose_target().get("id","") != npc, npc+" intervening body still blocks interaction ray")
	region.remove_child(blocker)
	blocker.queue_free()
	await step()
	check(region.choose_target().get("id","") == npc, npc+" removing intervening body restores current interaction")
	# Explicitly simulate an old in-memory story-clock mutation: presentation must
	# not invent a new anchor every frame; a committed state replacement refreshes.
	var displayed := target(npc).duplicate(true)
	session.state.time_state["slot"] = 0
	await step(3)
	check(same(target(npc),displayed), npc+" frame polling does not reproject NPCs")
	check(session.replace_state(session.state) == OK, npc+" authoritative replacement accepted after legacy tick")
	await step()
	check(point(target(npc)["position"]) == initial, npc+" committed signal refreshes to slot-zero anchor")
	# Legacy save can place the player where the newly projected NPC stands.
	var legacy := GameState.from_dict(session.state.to_dict())
	legacy.player_state["position"] = {"x":initial.x,"y":initial.y}
	legacy.player_state["facing"] = "left"
	var caller_before := legacy.to_dict().duplicate(true)
	check(session.replace_state(legacy) == OK, npc+" overlapping legacy snapshot accepted for presentation recovery")
	await step()
	var recovered: Vector2 = region.player_position
	check(Region.is_safe_position(region.definition,recovered), npc+" recovered feet clear dynamic solids and boundaries")
	check(is_equal_approx(recovered.distance_to(initial),12.05), npc+" recovery chooses nearest foot-clear edge, not distant spawn")
	check(recovered == position_in(session.state), npc+" repaired position synchronized to authoritative session")
	check(region.player.facing == "left", npc+" overlap recovery preserves facing")
	check(same(legacy.to_dict(),caller_before), npc+" recovery does not mutate caller snapshot")
	check(same(session.state.character_states,legacy.character_states) and same(session.state.relationships,legacy.relationships) and same(session.state.time_state,legacy.time_state) and same(session.state.world_flags,legacy.world_flags), npc+" recovery only changes player position, never NPC/time/relations/facts")
	# A vacated legacy anchor is legal; no static-registry fallback may move it.
	for slot in 8:
		var next := GameState.from_dict(session.state.to_dict())
		next.time_state = {"day":1,"slot":slot}
		next.player_state["position"] = {"x":initial.x,"y":initial.y}
		var projection: Dictionary = content.exploration_view(scene,next)
		if projection["error"].is_empty() and Region.is_safe_position(projection["region"],initial):
			check(session.replace_state(next) == OK, npc+" vacated-anchor save valid")
			await step()
			check(region.player_position == initial and position_in(session.state) == initial, npc+" vacated original NPC anchor preserved on load")
			break
	# Fault-inject an invalid live clock only to exercise atomic view failure; no
	# production command can publish this state, and the valid snapshot is restored.
	var valid_state: Dictionary = session.state.to_dict().duplicate(true)
	var drawn: Dictionary = region.definition.duplicate(true)
	var body_position := body.position
	var player_position: Vector2 = region.player_position
	session.state.time_state["slot"] = 8
	var invalid_before: Dictionary = session.state.to_dict().duplicate(true)
	check(not region.refresh_world_view(),npc+" invalid projection fails closed")
	check(same(region.definition,drawn) and body.position == body_position and region.player_position == player_position,npc+" failed projection preserves drawn targets, bodies and player atomically")
	check(same(session.state.to_dict(),invalid_before),npc+" failed view never repairs or mutates invalid domain input")
	check(session.replace_state(GameState.from_dict(valid_state)) == OK,npc+" valid route restored after explicit invalid-state fixture")

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	panel.handle_input(event)

func install_panel(tutorial := false) -> void:
	if is_instance_valid(panel):
		root.remove_child(panel)
		panel.queue_free()
		await process_frame
	panel = Activity.new()
	panel.onboarding = tutorial
	root.add_child(panel)
	await process_frame

func journal_people() -> void:
	if is_instance_valid(region):
		root.remove_child(region)
		region.queue_free()
		await step()
	session.start_new_game()
	await install_panel()
	var before: Dictionary = session.state.to_dict().duplicate(true)
	key(KEY_R)
	check(panel.tab == 1,"normal journal first R opens legacy evidence page")
	key(KEY_R)
	check(panel.tab == 2 and panel.entries.is_empty(),"normal journal second R opens empty known-person page")
	check(panel.body.text.contains(TranslationServer.translate("INV_EMPTY_PEOPLE")),"empty people page explains missing acquaintances")
	check(not panel.body.text.contains("INV_EMPTY_EVIDENCE"),"people page never reports missing evidence")
	key(KEY_E)
	check(panel.mode == "journal" and panel.tab == 2,"people confirm cannot open evidence comparison")
	for _cycle in 4:
		key(KEY_R)
		check(panel.tab == 0,"normal journal skips unavailable routes page forwards")
		key(KEY_Q)
		check(panel.tab == 2,"normal journal skips unavailable routes page backwards")
	check(same(session.state.to_dict(),before),"journal navigation and person inspection are read-only")
	var state := GameState.from_dict(session.state.to_dict())
	state.world_flags["INSPECTED_NPC_STREET_VENDOR"] = true
	check(session.replace_state(state) == OK,"known person fact accepted by real session")
	check(panel.entries.size() == 1 and panel.entries[0]["id"] == "NPC_STREET_VENDOR","state signal refreshes open people page and hides unknown dock worker")
	if not panel.entries.is_empty():
		check(panel.choices[0].visible and panel.choices[0].text.contains(panel.entries[0]["title"]),"known person is actually listed in visible keyboard row")
		check(panel.body.text.contains(panel.entries[0]["detail"]),"selected person detail is visible")
	var cards: Array = content.people_entries(session.state)
	var source := cards.duplicate(true)
	var projected := Journal.people_entries(cards)
	check(same(cards,source) and projected.size() == 1,"journal projection preserves localized source cards")
	if not projected.is_empty():
		check(projected[0].keys().size() == 3 and projected[0].has("id") and projected[0].has("title") and projected[0].has("detail"),"people cards expose only published text, no hidden trust/XY fields")
		projected[0]["title"] = "test-only mutation"
		check(same(cards,source),"UI card mutation cannot alter content view")
	state = GameState.from_dict(session.state.to_dict())
	state.world_flags["INSPECTED_NPC_DOCK_WORKER"] = true
	check(session.replace_state(state) == OK,"second acquaintance fact accepted")
	check(panel.entries.size() == 2,"both and only encountered NPCs appear")
	key(KEY_DOWN)
	var remembered: String = panel.entries[panel.cursor]["id"]
	key(KEY_Q)
	key(KEY_R)
	check(panel.tab == 2 and panel.entries[panel.cursor]["id"] == remembered,"people selection survives page return")
	before = session.state.to_dict().duplicate(true)
	key(KEY_E)
	check(same(session.state.to_dict(),before),"person confirmation does not farm trust or advance time")
	var original_locale := TranslationServer.get_locale()
	for locale: String in ["zh_CN","en"]:
		TranslationServer.set_locale(locale)
		for trust: int in [-1,1,5]:
			state = GameState.from_dict(session.state.to_dict())
			state.relationships["NPC_STREET_VENDOR"] = {"trust":trust,"alignment":0}
			state.world_flags["REP_TOWN"] = -1 if trust < 0 else 1
			check(session.replace_state(state) == OK,"localized people state accepted "+locale+str(trust))
			var relation_key := "WORLD_REL_GUARDED" if trust < 0 else ("WORLD_REL_FRIENDLY" if trust < 5 else "WORLD_REL_TRUSTED")
			var card: Dictionary = panel.entries[0]
			check(card["detail"].contains(TranslationServer.translate(relation_key)),"people card shows localized relationship stage "+locale+str(trust))
			check(card["detail"].contains(TranslationServer.translate("WORLD_REP_SUSPECT" if trust < 0 else "WORLD_REP_KNOWN")),"people card shows localized reputation stage "+locale+str(trust))
			check(not card["detail"].contains("WORLD_") and not card["title"].begins_with("NPC_"),"people prose contains no untranslated world/name keys "+locale+str(trust))
	TranslationServer.set_locale(original_locale)
	panel.refresh()
	before = session.state.to_dict().duplicate(true)
	await install_panel(true)
	key(KEY_R)
	check(panel.tab == 1,"tutorial keeps first R on evidence")
	key(KEY_R)
	check(panel.tab == 0,"tutorial preserves original two-page teaching loop")
	key(KEY_Q)
	check(panel.tab == 1,"tutorial backwards navigation also excludes people/routes")
	check(same(session.state.to_dict(),before),"tutorial page navigation is read-only")
	root.remove_child(panel)
	panel.queue_free()
	await process_frame

func recovery_geometry() -> void:
	var fixture := {"size":[640,384],"obstacles":[{"rect":[256,128,64,64]}],"interactions":[{"kind":"npc","position":[128,128]},{"kind":"document","position":[128,160]},{"kind":"exit","position":[64,64]}]}
	for origin: Vector2 in [Vector2(128,128),Vector2(128,160),Vector2(280,150),Vector2(-2,50),Vector2(630,380)]:
		var before := fixture.duplicate(true)
		var safe: Vector2 = Region.nearest_safe_position(fixture,origin)
		check(Region.is_safe_position(fixture,safe),"recovery handles NPC/document/solid/bounds "+str(origin))
		check(same(fixture,before),"recovery never edits projected geometry "+str(origin))
	var free := Vector2(100.25,100.75)
	check(Region.nearest_safe_position(fixture,free) == free,"safe fractional player position is untouched")
	check(Region.is_safe_position(fixture,Vector2(64,64)),"exit is not incorrectly treated as physical NPC")
	check(Region.nearest_safe_position(fixture,Vector2.INF) == Vector2.INF,"invalid nonfinite recovery returns failure instead of unsafe coordinates")

func _run() -> void:
	await process_frame
	session = root.get_node("GameSession")
	content = root.get_node("ContentDB")
	app = root.get_node("App")
	app.reset_contexts()
	if not check(content.last_error.is_empty(),"production content loaded"): quit(1); return
	Region = load("res://game/presentation/exploration/exploration_region.gd")
	Activity = load("res://game/presentation/investigation/activity_panel.gd")
	recovery_geometry()
	await region_schedule("SCENE_TOWN_STREET","NPC_STREET_VENDOR")
	await region_schedule("SCENE_RIVER_DOCK","NPC_DOCK_WORKER")
	await journal_people()
	if failures.is_empty(): print("WEEK7_NPC_UI_PASS checks=%d (projected NPC physics/rays, legacy overlap recovery, known-person journal; headless)" % checks)
	quit(0 if failures.is_empty() else 1)
