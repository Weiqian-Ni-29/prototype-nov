extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Markers = preload("res://scripts/presentation/squad_markers.gd")
var failures = 0
var checks = 0
func _initialize() -> void: call_deferred("execute")
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var directory = ProjectSettings.globalize_path("res://../test-results")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game._start_new()
	var run = game.run
	var start: String = run.actor("hero").position
	for id in ["lorne", "grit", "ember"]:
		run.actor(id).position = start
		run.join_companion(id)
	game._select_actor("hero")
	await process_frame
	var markers = game.view.squad_markers
	expect(markers.groups.size() == 1, "recruited crew share one squad")
	expect(game.moving_ids.size() == 4, "selecting a squad selects its members")
	game._cell_actions()
	var split_button: Button
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text == "拆分小队": split_button = button
	expect(split_button != null and not split_button.disabled, "action menu offers squad split")
	split_button.pressed.emit()
	await process_frame
	var confirm: Button
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text == "组成新小队": confirm = button
	expect(confirm != null and confirm.disabled, "empty split disabled")
	for id in ["lorne", "grit"]:
		game.modal_layer.find_child("SplitMember_" + id, true, false).button_pressed = true
	expect(not confirm.disabled, "multiple members may form a squad")
	await capture("squad-split-dialog")
	confirm.pressed.emit()
	await process_frame
	expect(markers.groups.size() == 2, "explicit same-cell split keeps two arrows")
	expect(run.squad_members("lorne").size() == 2, "chosen members persist in new squad")
	expect(game.selected_id == "lorne", "new squad becomes selected")
	expect(game.ui.find_children("SquadFrame_*", "PanelContainer", true, false).size() == 2, "sidebar frames correspond to squads")
	var hero_color = markers.color_for_actor("hero")
	var split_color = markers.color_for_actor("lorne")
	expect(hero_color != split_color, "split squads have distinct colors")
	game._select_actor("hero")
	await process_frame
	expect(markers.color_for_actor("hero") == hero_color and markers.color_for_actor("lorne") == split_color, "selection preserves colors")
	expect(markers.groups.filter(func(g): return g.selected).size() == 1, "one selected squad")
	expect(markers.markers.size() == 2 and markers.markers[0].point.distance_to(markers.markers[1].point) >= 32, "same-cell arrows do not overlap")
	var other_point: Vector2
	for marker in markers.markers:
		if marker.leader == "lorne": other_point = marker.point
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = other_point
		root.push_input(event, true)
	await process_frame
	expect(game.selected_id == "lorne", "clicking other same-cell arrow selects that squad")
	game._select_actor("hero")
	await process_frame
	await capture("squad-same-cell")
	game.view.zoom_size = 38
	game.view._update_camera()
	await process_frame
	expect(markers.markers.size() == 2, "arrows survive maximum map zoom")
	for marker in markers.markers:
		expect(markers.pick(marker.point) == marker.leader, "each arrow is selectable")
	await capture("squad-far-zoom")
	run.actor("ember").hp = 0
	game._select_actor("hero")
	expect("ember" not in game.moving_ids, "injured members do not block default squad movement")
	run.actor("ember").hp = run.actor("ember").hp_max
	game._select_actor("hero")
	game.view.zoom_size = 7.5
	game.view._update_camera()
	var destination: String = Hex.neighbors(start, run.data.tiles)[0]
	run.data.tiles[destination].enemies = []
	run.data.tiles[destination].terrain = "plains"
	run.actor("lorne").position = destination
	run.actor("grit").position = destination
	game._refresh()
	await process_frame
	var ground = Hex.world(destination)
	ground.y = game.view.board_surface.height_at(ground) + 0.01
	var target_point: Vector2 = game.view.camera.unproject_position(ground)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = target_point
		root.push_input(event, true)
	await process_frame
	expect(game.move_target == destination and game.selected_id == "hero", "mouse click on occupied adjacent ground previews move instead of switching squad")
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = target_point
		root.push_input(event, true)
	await process_frame
	expect(run.actor("hero").position == destination, "second ground click confirms movement into occupied tile")
	expect(game.moving_ids.size() == 4, "arrival merge updates next movement to entire merged squad")
	game._close_modal()
	# Restore two same-cell squads for the forest screenshot.
	run.split_squad(["lorne", "grit"])
	start = destination
	game._select_actor("hero")
	var generated: Dictionary = {}
	for i in 100: generated[Markers.color_at(i).to_html()] = true
	expect(generated.size() == 100, "palette extends beyond built-in crew count")
	game.view.hide()
	expect(not markers.visible, "markers hidden with story/menu world")
	game.view.show()
	game.view.battle_mode = true
	await process_frame
	await process_frame
	expect(not markers.visible, "exploration markers hidden in battle")
	game.view.battle_mode = false
	game.view.zoom_size = 7.5
	game.view._update_camera()
	game._select_actor("hero")
	await process_frame
	# A forest fixture verifies overlay arrows are independent of tree opacity.
	for cell in run.data.explored:
		run.data.tiles[cell].terrain = "forest"
	game.view.reset()
	game._refresh()
	game.view.focus_cell(start)
	await process_frame
	await capture("squad-forest")
	print("Squad markers: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)
