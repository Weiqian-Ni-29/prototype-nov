extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
const ENEMIES = {
	"plains": ["boar", "hunter_elite"], "forest": ["spider", "hunter_elite"],
	"mountain": ["boar", "furnace_elite"], "ruins": ["furnace", "furnace_elite"],
	"desert": ["archer", "furnace_elite"], "swamp": ["lurker", "hunter_elite"],
}
const OUTPUT = "user://visual-checks"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func execute() -> void:
	create_timer(25.0).timeout.connect(func(): quit(1))
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.chosen_seed = "20261104"
	game.run.save_path = "user://test-map-landmarks-%d.json" % OS.get_process_id()
	game._start_new()
	var run = game.run
	var view = game.view
	var village := "0,0"
	run.data.tiles[run.data.start].site = ""
	run.data.start = village
	run.data.tiles[village].site = "start"
	run.actor("hero").position = village
	run.data.visited = {village: true}
	run.location_names[village] = "村庄"
	game.selected_cell = village
	var adjacent := Hex.neighbors(village, run.data.tiles)
	var battle := adjacent[5]
	var elite := adjacent[1]
	var cache := adjacent[0]
	var supply := adjacent[4]
	var hidden: String = run.data.tiles.keys().filter(func(id):
		return not run.data.explored.has(id) and Hex.is_land(run.data.tiles, id))[0]
	run.data.tiles[hidden].enemies = ["boar"]
	game._refresh()
	expect(not view.landmarks.has(hidden), "A node under the fog has no model")
	run.data.explored[hidden] = true
	game._refresh()
	expect(view.landmarks.has(hidden) and not view.landmarks[hidden].visible, "An enemy stays hidden during the fog dissolve")
	await create_timer(view.FOG_REVEAL_SECONDS + 0.1).timeout
	expect(view.landmarks[hidden].visible, "An enemy becomes visible after the fog dissolves")

	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for biome in ENEMIES:
		run.data.explored.clear()
		for id in [village, battle, elite, cache, supply]:
			run.data.tiles[id].terrain = biome
			run.data.tiles[id].base_terrain = biome
			run.data.tiles[id].enemies.clear()
			run.data.tiles[id].hidden = false
			run.data.tiles[id].quantity = 0
			run.data.explored[id] = true
		run.data.tiles[battle].enemies = [ENEMIES[biome][0]]
		run.data.tiles[elite].enemies = [ENEMIES[biome][1]]
		run.data.nodes[battle].kind = "battle"
		run.data.nodes[elite].kind = "elite"
		run.data.nodes[cache] = {"kind": "cache", "result": ""}
		run.data.nodes[supply] = {"kind": "supply", "result": ""}
		view.reset()
		game._refresh()
		view.focus_cell(village)
		view.focus_point.z -= (0.75 if biome == "mountain" else 0.30)
		view._update_camera()
		expect(view.landmarks.size() == 5, "Five modelled sites appear in " + biome)
		expect(view.landmarks[battle].get_node("Enemy").get_meta("enemy_type") == ENEMIES[biome][0],
			"The map uses the actual enemy at the site in " + biome)
		expect(view.landmarks[elite].has_node("EliteBanner"), "The elite has a banner in " + biome)
		expect(view.landmarks[village].has_node("Village"), "The starting village has buildings in " + biome)
		var chest = view.landmarks[cache].get_node("Chest")
		var crates = view.landmarks[supply].get_node("Supplies")
		expect(chest.mesh.get_aabb().size.x > 0.45 and crates.mesh.get_aabb().size.y > 0.20,
			"Chest and supplies have solid meshes in " + biome)
		var model: Node3D = view.landmarks[cache]
		var chest_bounds: AABB = model.get_meta("bounds")
		var point := model.to_global(chest_bounds.get_center())
		var cursor: Vector2 = view.camera.unproject_position(point)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.position = cursor
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			root.push_input(click, true)
		expect(game.move_target == cache and game.move_preview.visible,
			"A real click on the chest previews its tile in " + biome)
		game.selected_cell = village
		game._clear_map_move()
		game._refresh()
		var closed: Mesh = chest.mesh
		var full: Mesh = crates.mesh
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		expect(image.save_png(OUTPUT.path_join("map-landmarks-" + biome + ".png")) == OK,
			"Saved the in-game rendering of " + biome)
		run.data.tiles[battle].enemies.clear()
		run.data.nodes[cache].result = "search"
		run.data.nodes[supply].result = "collect"
		game._refresh()
		expect(not view.landmarks.has(battle), "The defeated enemy disappears from " + biome)
		expect(view.landmarks[cache].get_node("Chest").mesh != closed, "An opened chest remains in " + biome)
		expect(view.landmarks[supply].get_node("Supplies").mesh != full, "An empty supply facility remains in " + biome)
		if biome == "plains":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(OUTPUT.path_join("map-landmarks-claimed.png")) == OK,
				"Saved empty supply and chest states")
	run.data.tiles[elite].hidden = true
	run.data.tiles[elite].discovered_enemy = false
	game._refresh()
	expect(not view.landmarks.has(elite), "An undiscovered ambush stays concealed on revealed terrain")
	run.data.tiles[elite].discovered_enemy = true
	run.data.visited[elite] = true
	game._refresh()
	expect(view.landmarks.has(elite), "A discovered ambush has a visible enemy model")
	view.reset()
	expect(view.landmarks.is_empty() and view.revealing_cells.is_empty(), "Reset clears landmark state and reveal tracking")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(run.save_path + suffix):
			DirAccess.remove_absolute(run.save_path + suffix)
	game.queue_free()
	await process_frame
	print("MAP LANDMARKS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
