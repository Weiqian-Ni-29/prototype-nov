extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Model = preload("res://scripts/domain/expedition.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
var checks = 0
var failures = 0
var game
func _initialize(): call_deferred("execute")
func expect(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func press(text: String):
	for layer in [game.modal_layer, game.ui]:
		for button in layer.find_children("*", "Button", true, false):
			if button.text == text and button.is_visible_in_tree():
				expect(not button.disabled, "button enabled: " + text)
				button.pressed.emit()
				await process_frame
				return
	expect(false, "button exists: " + text)
func execute():
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-squad-retreat.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var origin = run.actor("hero").position
	for id in ["lorne", "grit"]:
		run.actor(id).position = origin
		expect(run.join_companion(id).ok, "recruit " + id)
	expect(run.split_squad(["lorne"]).ok, "resident receives own squad")
	var destination = ""
	for cell in Hex.neighbors(origin, run.data.tiles):
		if Hex.is_land(run.data.tiles, cell):
			destination = cell
			break
	run.actor("lorne").position = destination
	var resident_id = run.actor("lorne").squad_id
	var resident_color = run.data.squad_colors[resident_id]
	run.data.tiles[origin].enemies = []
	run.data.tiles[destination].enemies = ["boar"]
	game._select_actor("hero")
	game.move_target = destination
	game._move_selected()
	expect(run.data.pending_battle.get("movers", []) == ["hero", "grit"], "encounter remembers actual arriving movers")
	expect(run.squad_groups().size() == 1 and run.actor("hero").squad_id == resident_id, "arrival merges into resident squad")
	game.view.dolls.grit.move_tween.set_speed_scale(0.5)
	var deadline = Time.get_ticks_msec() + 5000
	while game.view.dolls.hero.is_moving() and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(game.view.dolls.grit.is_moving() and game.modal_layer.get_child_count() == 0,
		"Formation waits for the last moving squad member")
	while game.map_traveling and Time.get_ticks_msec() < deadline:
		await process_frame
	await press("开始战斗")
	expect(game.combat != null and run.data.status == "battle", "actual Battle.begin through formation button")
	# Retreat wounds one mover; the survivor remains selectable and can move.
	run.actor("grit").hp = 1
	await press("撤退")
	await press("确认")
	expect(game.combat == null and run.data.status == "exploring", "retreat confirmation completes _finish_battle")
	expect(not run.data.has("pending_arrival") and not game.modal_layer.has_node("StoryScreen"),
		"Retreat clears the abandoned encounter's arrival story")
	expect(run.actor("hero").position == origin and run.actor("grit").position == origin, "actual battle retreat relocates movers")
	expect(run.actor("lorne").position == destination, "resident remains at encounter")
	expect(run.actor("grit").hp == 0, "retreat can incapacitate squad member")
	expect(run.squad_groups().size() == 2, "retreat splits merged squad across locations")
	expect(run.actor("hero").squad_id != run.actor("lorne").squad_id, "different locations have distinct identities")
	expect(run.actor("lorne").squad_id == resident_id and run.data.squad_colors[resident_id] == resident_color, "stationary resident keeps original identity and color after retreat")
	expect(game.selected_cell == run.actor(game.selected_id).position, "selected cell follows retreat")
	expect(game.moving_ids.size() == 1 and game.moving_ids[0] == "hero", "post-retreat moving selection excludes resident and wounded mover")
	var colors = {}
	var identities = {}
	for id in run.joined_ids():
		identities[id] = run.actor(id).squad_id
		colors[id] = game.view.squad_markers.color_for_actor(id)
	game._refresh()
	expect(game.view.squad_markers.groups.size() == 2, "map displays both post-retreat squads")
	var loaded = Model.new()
	expect(loaded.load_game(run.save_path).ok, "retreat checkpoint reloads")
	for id in run.joined_ids():
		expect(loaded.actor(id).position == run.actor(id).position and loaded.actor(id).squad_id == identities[id], "saved position/identity retained: " + id)
		expect(loaded.data.squad_colors[loaded.actor(id).squad_id] == run.data.squad_colors[identities[id]], "saved color index retained: " + id)
	game._continue_run()
	await process_frame
	expect(game.moving_ids.size() == 1 and game.moving_ids[0] == "hero", "reload selects only healthy members at hero location")
	for id in run.joined_ids():
		expect(game.view.squad_markers.color_for_actor(id) == colors[id], "reload preserves visible marker color: " + id)
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(run.save_path + suffix)
	game.free()
	print("SQUAD RETREAT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
