extends SceneTree
## Presentation fixtures, deliberately separate from no-cheat end-to-end journeys.
const Main = preload("res://scenes/main.tscn")
const Game = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
var game: Node
var destination = "user://visual-checks"
var checks = 0
var failed = false

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		printerr("FAIL VISUAL: ", label)

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	expect(image != null and image.get_width() > 800, "Rendered image " + name)
	if image:
		var error = image.save_png(destination.path_join(name + ".png"))
		expect(error == OK, "Saved image " + name)

func inspect_story_layout() -> void:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	if stage == null:
		expect(false, "Story screen is visible")
		return
	var dialogue = stage.get_node("Dialogue").get_rect()
	var choices = stage.get_node("StoryChoices").get_rect()
	expect(dialogue.position.y > stage.size.y * 0.65, "Dialogue sits near the bottom of the story screen")
	expect(choices.position.x > stage.size.x * 0.5 and choices.end.x <= stage.size.x, "Choices stay in the right column")
	expect(dialogue.end.x < choices.position.x, "Story text and choices do not overlap")

func advance_story() -> void:
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = root.get_visible_rect().size * Vector2(0.78, 0.27)
		root.push_input(event, true)
	await process_frame

func inspect_portrait_mattes() -> void:
	for id in ["hero", "hero-guardian", "hero-arcanist", "cen", "lorne", "eve", "grit", "ember", "tide", "inn", "home", "exit"]:
		var path = "res://assets/portraits/mattes/" + id + ".png"
		if not ResourceLoader.exists(path):
			expect(false, "Portrait matte bundled for " + id)
			continue
		var matte: Image = load(path).get_image()
		expect(matte.get_pixel(matte.get_width() / 2, matte.get_height() / 2).r > 0.9
			and matte.get_pixel(0, 0).r < 0.05 and matte.get_pixel(matte.get_width() - 1, 0).r < 0.05,
			"Portrait matte preserves the figure and clears the background for " + id)

func capture_landmark_discovery() -> void:
	var run = game.run
	var target: String = run.actor("lorne").position
	var path = Hex.path(run.data.tiles, run.data.start, target, true)
	for id in path.slice(1, -1):
		game._select_cell(id)
		game._select_cell(id)
	game._select_cell(target)
	game.view.focus_cell(target)
	expect(run.data.explored.has(target) and not run.has_visited(target), "Courier's hex is visible before arrival")
	await capture("discovery-before-arrival")
	game._select_cell(target)
	expect(run.has_visited(target) and game.view.dolls.has("lorne"), "Arriving reveals the courier")
	await create_timer(0.9).timeout
	await capture("discovery-after-arrival")

func inspect_board() -> void:
	for seed_value in ["20261104", "41", "918"]:
		game.chosen_seed = seed_value
		game._start_new()
		var run = game.run
		var view = game.view
		expect(view.board_fog.mesh != null and view.tile_nodes.size() == 7, "Unexplored cells have clouds and no exposed props")
		var hidden = ""
		for id in run.data.tiles:
			if not run.data.explored.has(id):
				hidden = id
				break
		var point = Hex.world(hidden)
		var old_height = view.board_surface.height_at(point)
		var old_terrain = run.data.tiles[hidden].terrain
		run.data.tiles[hidden].terrain = "mountain" if old_terrain != "mountain" else "lake"
		game._refresh()
		expect(not view.board_surface.profiles.has(hidden) and is_equal_approx(old_height, view.board_surface.height_at(point)), "Hidden terrain cannot influence relief")
		run.data.tiles[hidden].terrain = old_terrain
		var shore = ""
		var forest = ""
		var burned = ""
		var ridge = ""
		for id in run.data.tiles:
			run.data.explored[id] = true
			var terrain: String = run.data.tiles[id].terrain
			if terrain == "lake":
				for next in Hex.neighbors(id, run.data.tiles):
					if Hex.is_land(run.data.tiles, next):
						shore = next
						break
			if terrain == "forest" and run.data.tiles[id].site == "":
				if forest.is_empty():
					forest = id
				elif Hex.distance(Hex.coord(id), Hex.coord(forest)) > 2:
					burned = id
			if terrain == "mountain" and ridge.is_empty():
				for next in Hex.neighbors(id, run.data.tiles):
					if run.data.tiles[next].terrain == "mountain":
						ridge = id
						break
		if not burned.is_empty():
			run.data.tiles[burned].terrain = "scorched"
			for next in Hex.neighbors(burned, run.data.tiles):
				if run.data.tiles[next].terrain == "forest" and run.data.tiles[next].site == "":
					run.data.tiles[next].terrain = "scorched"
		view.zoom_size = 38.0
		view.focus_cell("0,0")
		game._refresh()
		expect(view.board_fog.mesh == null and view.board_surface.triangles.size() == 217, "All revealed cells render and support surface picking")
		verify_seams(view.board_surface)
		await capture("terrain-island-" + seed_value)
		game.selected_cell = shore
		view.zoom_size = 9.2
		view.focus_cell(shore)
		game._refresh()
		await capture("terrain-lake-" + seed_value)
		if seed_value == "20261104" and not forest.is_empty():
			await inspect_occlusion(forest)
			var areas = {"ridge": ridge, "scorched": burned}
			for detail in areas:
				var focus: String = areas[detail]
				if not focus.is_empty():
					game.selected_cell = focus
					view.focus_cell(focus)
					game._refresh()
					await capture("terrain-" + detail)
	game.chosen_seed = "20261104"
	game.view.zoom_size = game.view.DEFAULT_MAP_ZOOM

func verify_seams(surface: RefCounted) -> void:
	var matched = true
	for id in surface.tiles:
		var own := {}
		for point in surface.triangles[id]:
			own[Vector2(point.x, point.z)] = point.y
		for next in Hex.neighbors(id, surface.tiles):
			if id > next:
				continue
			var shared := {}
			for point in surface.triangles[next]:
				var key = Vector2(point.x, point.z)
				if own.has(key):
					shared[key] = true
					matched = matched and is_equal_approx(own[key], point.y)
			matched = matched and shared.size() == surface.SUBDIVISIONS + 1
	expect(matched, "Every internal edge shares all tessellated world vertices and heights")

func inspect_occlusion(forest: String) -> void:
	var view = game.view
	var run = game.run
	run.actor("hero").position = forest
	game.selected_cell = forest
	view.zoom_size = 8.0
	view.focus_cell(forest)
	game._refresh()
	expect(not view.canopy_batch.visible and view.canopy_individual, "Close view can fade individual props")
	var actor = view.dolls.hero
	while actor.is_moving():
		await process_frame
	var occluder: MeshInstance3D
	for candidate in view.map_occluders:
		var bounds: AABB = candidate.global_transform * candidate.get_aabb()
		if bounds.get_center().distance_to(actor.global_position) < 1.3 and bounds.size.y > 0.42:
			occluder = candidate
			break
	if not is_instance_valid(occluder):
		expect(false, "A tall forest occluder exists for the close-up")
		return
	var bounds: AABB = occluder.global_transform * occluder.get_aabb()
	var sight: Vector3 = -view.camera.global_basis.z
	actor.global_position = bounds.get_center() + sight * 0.48 - Vector3.UP * 0.20
	view.set_process(false)
	await capture("terrain-forest-covered")
	view._update_occlusion(1.0)
	expect(view.fading_occluders.has(occluder) and view.fading_occluders[occluder].amount > 0.9, "A tree covering the selected character fades at close range")
	if not view.fading_occluders.has(occluder):
		view.set_process(true)
		return
	var original: Material = view.fading_occluders[occluder].originals[0]
	await capture("terrain-forest-occlusion")
	view.zoom_size = 10.0
	view._update_camera()
	view._update_occlusion(1.0)
	expect(not view.fading_occluders.has(occluder) and occluder.get_surface_override_material(0) == original, "Zooming out restores the tree's original material")
	expect(view.canopy_batch.visible and not view.canopy_individual, "Wide view groups canopy meshes for rendering")
	view.set_process(true)

func execute() -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://visual-test-run.json"
	await create_timer(1.0).timeout
	await capture("01-menu")
	game._show_opening(Game.Screen.PROFESSION)
	for profession in Catalog.PROFESSIONS:
		game._choose_profession(profession)
		await capture("01-profession-" + profession)
	game._choose_profession("wayfarer")
	game._begin_opening_story()
	await capture("story-opening-road")
	game._opening_beat("bridge")
	await capture("story-opening-bridge")
	game._opening_beat("shelter")
	await capture("story-opening-shelter")
	inspect_story_layout()
	game._opening_beat("lamps", "lamps")
	await capture("story-opening-lamps")
	game._start_new()
	await create_timer(0.5).timeout
	await capture("02-exploration")
	await capture_landmark_discovery()
	await inspect_board()
	# Inspect every biome through the exact same battle view used in the playable game.
	game.set_process(false)
	for biome in ["plains", "forest", "mountain", "ruins", "desert", "swamp", "scorched"]:
		game._start_new()
		var run = game.run
		var position = run.actor("hero").position
		run.data.tiles[position].terrain = biome
		run.data.tiles[position].site = ""
		run.data.tiles[position].burning = biome == "forest"
		run.data.tiles[position].wet_until = 3 if biome == "swamp" else 0
		run.data.weather = "rain" if biome == "swamp" else "sun"
		for id in Catalog.COMPANIONS:
			run.actor(id).position = position
			run.join_companion(id)
		run.data.tiles[position].enemies = ["spider", "furnace", "swarm", "canal"]
		var battle = Combat.new()
		var pending = {"position": position, "origin": position, "movers": [], "npc": "", "ambush": false}
		expect(battle.begin(run, pending, ["hero", "grit", "ember", "tide"]).ok, "Battle fixture begins " + biome)
		game.combat = battle
		game.battle_timer = 0
		game.view.begin_battle(run, battle)
		game._refresh()
		await create_timer(0.6).timeout
		expect(game.view.battle_dolls.size() == 8, "Four friends and four distinct foes rendered")
		expect(game.view.battle_dolls.grit.skeleton.get_bone_count() >= 23 and game.view.battle_dolls.grit.rigged.animator!=null, "Four-legged character has a full imported rig and animation player")
		expect(game.view.battle_dolls.enemy_0.family == "spider" and game.view.battle_dolls.enemy_2.family == "swarm", "Enemy silhouettes match spider and swarm")
		await capture("battle-" + biome)
		if biome == "plains":
			battle.step_auto()
			game._refresh()
			await capture("battle-friendly-decision")
		var caster = game.view.battle_dolls.ember
		caster.play_action("cast")
		var before_pose = caster.skeleton.get_bone_pose_rotation(caster.bones.arm_r)
		await create_timer(0.22).timeout
		var after_pose = caster.skeleton.get_bone_pose_rotation(caster.bones.arm_r)
		expect(not before_pose.is_equal_approx(after_pose), "Skeletal cast motion changes pose over real frames")
		if biome == "forest":
			await capture("animation-cast-forest")
		game.combat = null
		game.view.end_battle()
	# Seven-person inventory and portrait dialogue layout use explicit presentation fixtures.
	game.run.data.status = "exploring"
	game.run.data.pending_battle = {}
	game._inventory_dialog("hero")
	await capture("inventory-seven-members")
	game._transfer_dialog("hero", "salve")
	await capture("transfer-seven-members")
	game._close_modal()
	# Stage the courier before recruitment at his original encounter site.
	for position in game.run.data.tiles:
		if game.run.data.tiles[position].npc == "lorne":
			game.run.actor("hero").position = position
			game.run.actor("lorne").position = position
			break
	game.run.actor("lorne").joined = false
	game.run.data.story.lorne.met = false
	game.run.data.story.lorne.relation = "unmet"
	game._talk("lorne")
	await capture("story-courier-first-meeting")
	for i in range(3):
		await advance_story()
	await capture("dialogue-portrait")
	inspect_story_layout()
	game._story_choice("later")
	await capture("story-courier-deferred")
	game._close_modal()
	inspect_portrait_mattes()
	game.run.actor("hero").position = game.run.actor("eve").position
	game.run.actor("eve").joined = false
	game.run.data.story.eve.met = false
	game.run.data.story.eve.relation = "unmet"
	game._talk("eve")
	await capture("story-eve-first-meeting")
	for i in range(3):
		await advance_story()
	await capture("story-eve-decision")
	game._close_modal()
	# Instantiate every remaining enemy art family and verify its skeleton in the tree.
	for id in Catalog.ENEMIES:
		var definition = Catalog.ENEMIES[id].duplicate(true)
		definition.id = "visual_" + id
		definition.type = id
		var doll = load("res://scripts/presentation/doll.gd").new()
		game.view.add_child(doll)
		doll.configure(definition)
		expect(doll.skeleton.get_bone_count() >= 6, "Enemy has rig " + id)
		doll.queue_free()
	print("VISUAL FIXTURES: %d checks; failed=%s; captures=%s" % [checks, failed, ProjectSettings.globalize_path(destination)])
	quit(1 if failed else 0)
