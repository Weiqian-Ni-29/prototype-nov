extends SceneTree
## Real legal movement with queued presentation; fixture joins only for crowded-layout checks.
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("execute")
func expect(value: bool,text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",text)

func pointer_button(button: MouseButton, pressed: bool, point: Vector2) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	root.push_input(event, true)

func pointer_motion(point: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func check_camera_drag(game: Node, start: String, next: String) -> void:
	var view = game.view
	var normal_zoom: float = view.zoom_size
	expect(is_equal_approx(view.camera.size, 5.5), "New expedition starts at the previous closest view")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://map-camera-default.png")
	var before = JSON.stringify(game.run.data)
	var point = view.camera.unproject_position(Hex.world(next) + Vector3.UP * 0.05)
	pointer_button(MOUSE_BUTTON_LEFT, true, point)
	pointer_motion(point + Vector2(3, 0))
	expect(game.selected_cell == start and view.focus_point.is_equal_approx(Hex.world(start)), "Short motion waits for a click release")
	pointer_button(MOUSE_BUTTON_LEFT, false, point + Vector2(3, 0))
	expect(game.selected_cell == next and view.focus_point.is_equal_approx(Hex.world(start)), "Click still selects its hex without moving the camera")
	expect(game.move_preview.visible and JSON.stringify(game.run.data) == before, "First mouse click shows the route without paying or moving")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://map-move-preview.png")

	var screen = root.get_visible_rect().size
	var center = screen * 0.5
	var over_sidebar = Vector2(45, center.y + 40)
	var held_world_point: Vector3 = view._map_point(center)
	pointer_button(MOUSE_BUTTON_LEFT, true, center)
	pointer_motion(over_sidebar)
	pointer_button(MOUSE_BUTTON_LEFT, false, over_sidebar)
	expect(view.camera.unproject_position(held_world_point).distance_to(over_sidebar) < 1.0, "Dragging tracks the cursor on the slanted map, including across the HUD")
	expect(game.selected_cell == next and not view.map_pointer_down, "Drag release over the HUD keeps selection and ends capture")

	for i in range(14):
		pointer_button(MOUSE_BUTTON_LEFT, true, center)
		pointer_motion(Vector2(screen.x * 0.22, center.y))
		pointer_button(MOUSE_BUTTON_LEFT, false, Vector2(screen.x * 0.22, center.y))
	expect(is_equal_approx(view.focus_point.x, view.map_max.x), "Repeated drags reach the far coast without losing the island")
	var eastmost = Hex.closest(Vector3(view.map_max.x, 0.0, 0.0), game.run.data.tiles)
	point = view.camera.unproject_position(Hex.world(eastmost) + Vector3.UP * 0.05)
	pointer_button(MOUSE_BUTTON_LEFT, true, point)
	pointer_button(MOUSE_BUTTON_LEFT, false, point)
	expect(game.selected_cell == eastmost, "An unexplored hex remains selectable after panning")

	var edge: Vector3 = view.focus_point
	pointer_button(MOUSE_BUTTON_LEFT, true, center)
	game._settings_dialog()
	pointer_motion(over_sidebar)
	pointer_button(MOUSE_BUTTON_LEFT, false, over_sidebar)
	expect(view.focus_point.is_equal_approx(edge) and not view.map_pointer_down, "Opening a dialog cancels the map gesture")
	game._close_modal()
	for i in range(22):
		pointer_button(MOUSE_BUTTON_WHEEL_DOWN, true, center)
	expect(is_equal_approx(view.camera.size, 38.0), "Wheel zoom can reach the island overview")
	var island_center = view.camera.unproject_position(Vector3.UP * 0.05)
	pointer_button(MOUSE_BUTTON_LEFT, true, island_center)
	pointer_motion(center)
	pointer_button(MOUSE_BUTTON_LEFT, false, center)
	var map_area = Rect2(Vector2(270, 110), screen - Vector2(620, 250))
	var all_visible = true
	for id in game.run.data.tiles:
		if not map_area.has_point(view.camera.unproject_position(Hex.world(id))):
			all_visible = false
			break
	expect(all_visible, "Panning back at overview zoom fits the island between the HUD panels")
	expect(JSON.stringify(game.run.data) == before, "Map browsing spends no actions and does not reveal terrain")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://map-camera-overview.png")
	view.zoom_size = normal_zoom
	game._select_actor("hero")
	var detail_pointer = center + Vector2(90, 30)
	var detail_anchor: Vector3 = view._map_point(detail_pointer)
	pointer_button(MOUSE_BUTTON_WHEEL_UP, true, detail_pointer)
	expect(view.camera.unproject_position(detail_anchor).distance_to(detail_pointer) < 1.0, "Zooming keeps the indicated ground point under the cursor")
	for i in range(12):
		pointer_button(MOUSE_BUTTON_WHEEL_UP, true, center)
	expect(is_equal_approx(view.camera.size, 3.8), "Wheel zoom can move closer than the old limit")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://map-camera-detail.png")
	game._continue_run()
	expect(is_equal_approx(view.camera.size, normal_zoom), "Continuing an expedition starts at the default view")
	expect(view.fog_reveals.get_child_count() == 0, "Loading explored terrain does not animate fog")
	point = view.camera.unproject_position(Hex.world(next) + Vector3.UP * 0.05)
	var before_ap = int(game.run.actor("hero").ap)
	var cost = game.run.move_cost("hero", next)
	var initial_focus: Vector3 = view.focus_point
	var far_fog = view.board_fog.get_node("Chunk_2_0")
	var far_mesh = far_fog.mesh
	for i in range(2):
		pointer_button(MOUSE_BUTTON_LEFT, true, point)
		pointer_button(MOUSE_BUTTON_LEFT, false, point)
	expect(game.run.actor("hero").position == next and game.run.actor("hero").ap == before_ap - cost
		and not game.move_preview.visible, "Clicking the same hex twice moves and charges once")
	expect(view.focus_point.is_equal_approx(initial_focus), "Confirming movement does not jump the camera")
	expect(far_fog.mesh == far_mesh, "Movement does not rebuild distant fog")
	expect(view.fog_reveals.get_child_count() == 1, "A move starts one veil over its newly revealed hexes")
	var veil = view.fog_reveals.get_child(0) if view.fog_reveals.get_child_count() > 0 else null
	var material: ShaderMaterial = veil.material_override if veil != null else null
	expect(material != null and is_zero_approx(material.get_shader_parameter("progress")), "The reveal starts fully opaque")
	var mover = view.dolls.hero
	var midpoint_seen = false
	var dissolve_seen = false
	var destination = Hex.world(next)
	var deadline = Time.get_ticks_msec() + 3000
	while (is_instance_valid(view.map_follow_actor) or is_instance_valid(veil)) and Time.get_ticks_msec() < deadline:
		await process_frame
		if mover.is_moving() and view.focus_point.distance_to(initial_focus) > 0.15 and view.focus_point.distance_to(destination) > 0.15:
			midpoint_seen = true
		if not dissolve_seen and is_instance_valid(veil):
			var progress: float = material.get_shader_parameter("progress")
			if progress > 0.3 and progress < 0.85:
				dissolve_seen = true
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://fog-reveal-mid.png")
	expect(midpoint_seen and view.focus_point.is_equal_approx(destination), "Camera follows the walking doll and settles on arrival")
	expect(dissolve_seen and not is_instance_valid(veil), "The reveal fades through intermediate opacity and then removes its veil")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://fog-reveal-settled.png")
	game._start_new()

func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-map-motion.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var start = run.actor("hero").position
	var next = Hex.neighbors(start,run.data.tiles)[0]
	await process_frame
	await check_camera_drag(game, start, next)
	var doll = game.view.dolls.hero
	expect(run.move(["hero"],next).ok,"First legal movement")
	game._refresh()
	var waypoint = doll.movement_target
	var next2 = Hex.neighbors(next,run.data.tiles)[0]
	if next2==start: next2 = Hex.neighbors(next,run.data.tiles)[1]
	expect(run.move(["hero"],next2).ok,"Second legal movement while the first is animating")
	game._refresh()
	var destination = doll.movement_queue[-1]
	var state = JSON.stringify(run.data)
	var visited_waypoint = false
	var started = Time.get_ticks_msec()
	while doll.is_moving() and Time.get_ticks_msec()-started<5000:
		if doll.position.distance_to(waypoint)<0.15: visited_waypoint = true
		game._refresh()
		await process_frame
	expect(visited_waypoint,"Continuous clicks preserve the intermediate hex visually")
	expect(doll.position.distance_to(destination)<0.02 and not doll.is_moving(),"Movement queue reaches the real final position")
	expect(JSON.stringify(run.data)==state,"Animation and repeated interface refreshes do not charge resources again")
	for id in Catalog.COMPANIONS:
		run.actor(id).position = run.actor("hero").position
		run.join_companion(id)
	game._refresh()
	await create_timer(0.2).timeout
	var ids = run.joined_ids()
	for i in range(ids.size()):
		for j in range(i+1,ids.size()):
			expect(game.view.dolls[ids[i]].position.distance_to(game.view.dolls[ids[j]].position)>0.45,"Crowded cell separates actor bases")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://map-seven-actors.png")
	game.queue_free()
	await create_timer(0.1).timeout
	print("MAP MOTION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
