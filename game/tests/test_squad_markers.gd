extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func has_label(parent: Node, text: String) -> bool:
	return parent.find_children("*", "Label", true, false).any(func(label): return text in label.text)

func wait_for_arrival(game: Node) -> void:
	var deadline = Time.get_ticks_msec() + 5000
	while game.map_traveling and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(not game.map_traveling, "Travel animation completes")

func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-hero-marker.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var origin: String = run.actor("hero").position
	var next: String = Hex.neighbors(origin, run.data.tiles).filter(func(cell): return Hex.is_land(run.data.tiles, cell))[0]
	run.data.tiles[next].enemies.clear()
	run.actor("lorne").position = origin
	expect(run.join_companion("lorne").ok, "Recruit companion")
	game._select_actor("lorne")
	expect(game.view.dolls.keys() == ["hero"], "Only the traveler is drawn on the map")
	expect(has_label(game.ui, "今日剩余移动步数 5"), "Sidebar shows five remaining steps")
	game._select_cell(next)
	expect(game.move_preview.visible and run.remaining_steps() == 5 and run.actor("hero").position == origin,
		"Selecting a destination only previews the move")
	game._select_cell(next)
	expect(run.actor("hero").position == next and run.actor("lorne").position == next
		and game.selected_id == "hero" and run.remaining_steps() == 4, "The traveler leads both characters and spends one step")
	await wait_for_arrival(game)
	game._close_modal()
	run.data.steps_today = 4
	game._refresh()
	expect(has_label(game.ui, "今日剩余移动步数 1"), "Sidebar shows the final step")
	game._select_cell(origin)
	game._select_cell(origin)
	expect(has_label(game.ui, "第 2 天") and has_label(game.ui, "今日剩余移动步数 5"),
		"Final step updates the date and resets the sidebar")
	await wait_for_arrival(game)
	game._cell_actions()
	for button in game.modal_layer.find_children("*", "Button", true, false):
		expect(button.text not in ["拆分小队", "结束一天"] and not button.text.begins_with("治疗队友"), "Removed actions stay absent")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(run.save_path + suffix)
	game.free()
	print("HERO MAP UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
