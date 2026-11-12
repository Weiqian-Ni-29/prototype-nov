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
	game.sound.set_volume(0.0, false)
	game.run.save_path = "user://test-squad-retreat.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var origin = run.actor("hero").position
	for id in ["lorne", "grit"]:
		run.actor(id).position = origin
		expect(run.join_companion(id).ok, "recruit " + id)
	var destination = ""
	for cell in Hex.neighbors(origin, run.data.tiles):
		if Hex.is_land(run.data.tiles, cell):
			destination = cell
			break
	run.data.tiles[origin].enemies = []
	run.data.tiles[destination].enemies = ["boar"]
	game._select_actor("hero")
	game.move_target = destination
	game._move_selected()
	expect(run.data.pending_battle.origin == origin and run.remaining_steps() == 4, "Encounter remembers origin and committed step")
	expect(run.same_cell(destination).size() == 3, "All companions arrive together")
	var deadline = Time.get_ticks_msec() + 5000
	expect(game.map_traveling and game.modal_layer.get_child_count() == 0, "Encounter story waits while the traveler is walking")
	while game.map_traveling and Time.get_ticks_msec() < deadline:
		await process_frame
	await press("编辑卡组与开战")
	await press("开始战斗")
	expect(game.combat != null and run.data.status == "battle", "Actual chess battle begins through the deck editor")
	game.combat.enemy_turn()
	game.chess_view.render()
	var hero_health: int = run.actor("hero").hp
	await press("撤退")
	await press("确认")
	expect(game.combat == null and run.data.status == "exploring", "retreat confirmation completes _finish_battle")
	expect(not run.data.has("pending_arrival") and not game.modal_layer.has_node("StoryScreen"),
		"Retreat clears the abandoned encounter's arrival story")
	expect(run.same_cell(origin).size() == 3, "Actual battle retreat moves the whole party")
	expect(run.actor("hero").hp < hero_health, "Retreat wounds the traveler")
	expect(game.selected_cell == origin and run.remaining_steps() == 4, "Retreat returns without advancing or refunding a step")
	expect(game.view.dolls.keys() == ["hero"], "Map still shows only the traveler")
	var loaded = Model.new()
	expect(loaded.load_game(run.save_path).ok, "Retreat checkpoint reloads")
	expect(loaded.same_cell(origin).size() == 3 and loaded.actor("hero").hp < hero_health and loaded.remaining_steps() == 4,
		"Reload retains the party, injury and remaining steps")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(run.save_path + suffix)
	game.queue_free()
	await process_frame
	print("SQUAD RETREAT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
