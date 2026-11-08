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
	expect(dialogue.position.y > stage.size.y * 0.65, "Dialogue sits near the bottom of the story screen")
	var column = stage.get_node_or_null("StoryChoices")
	if column == null:
		return
	var choices = column.get_rect()
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

func inspect_board() -> void:
	for seed_value in ["20261104", "41", "918"]:
		game.chosen_seed = seed_value
		game._start_new()
		var run = game.run
		var view = game.view
		expect(view.board_fog.get_child_count() > 0 and view.tile_nodes.size() == 7, "Unexplored cells have clouds and no exposed props")
		var fringe_is_inward = view.board_fringe.get_child_count() > 0
		for patch in view.board_fringe.get_children():
			var arrays: Array = patch.mesh.surface_get_arrays(0)
			for i in range(0, arrays[Mesh.ARRAY_VERTEX].size(), view.board_surface.template.size()):
				var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
				var local: Vector2 = arrays[Mesh.ARRAY_TEX_UV][i] * 2.0 - Vector2.ONE
				var id = Hex.cell_at(vertex - Vector3(local.x, 0.0, local.y))
				var mask = 0
				for side in Hex.DIRECTIONS.size():
					var neighbor = Hex.key(Hex.coord(id) + Hex.DIRECTIONS[side])
					if run.data.tiles.has(neighbor) and not run.data.explored.has(neighbor):
						mask |= 1 << side
				fringe_is_inward = fringe_is_inward and run.data.explored.has(id) and mask != 0 \
					and roundi(arrays[Mesh.ARRAY_TEX_UV2][i].x) == mask
		expect(fringe_is_inward, "Soft fog edges lie on revealed hexes and only face unknown map neighbors")
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
		var ridge = ""
		var coastal_ridge = ""
		for id in run.data.tiles:
			run.data.explored[id] = true
			var terrain: String = run.data.tiles[id].terrain
			if terrain == "lake":
				for next in Hex.neighbors(id, run.data.tiles):
					if Hex.is_land(run.data.tiles, next):
						shore = next
						break
			if forest.is_empty() and terrain == "forest" and run.data.tiles[id].site == "":
				forest = id
			if terrain == "mountain":
				var neighbors = Hex.neighbors(id, run.data.tiles)
				if ridge.is_empty() and neighbors.any(func(next): return run.data.tiles[next].terrain == "mountain"):
					ridge = id
				if neighbors.size() < 6 and Hex.distance(Hex.coord(id), Hex.coord(run.data.start)) <= 2:
					coastal_ridge = id
		view.zoom_size = 38.0
		view.focus_cell("0,0")
		game._refresh()
		expect(view.board_fog.get_child_count() == 0 and view.board_fringe.get_child_count() == 0
			and view.board_surface.triangles.size() == 217, "All revealed cells render and support surface picking")
		verify_seams(view.board_surface)
		var rocky_mountain = verify_mountain_rocks(view)
		await create_timer(view.FOG_REVEAL_SECONDS + 0.1).timeout
		await capture("terrain-island-" + seed_value)
		game.selected_cell = shore
		view.zoom_size = 9.2
		view.focus_cell(shore)
		game._refresh()
		await capture("terrain-lake-" + seed_value)
		if seed_value == "20261104" and not forest.is_empty():
			await inspect_occlusion(forest)
			var areas = {"ridge": ridge, "coast-close": coastal_ridge, "ridge-close": ridge, "rocks-close": rocky_mountain}
			for detail in areas:
				var focus: String = areas[detail]
				if not focus.is_empty():
					view.zoom_size = view.MIN_MAP_ZOOM if detail.ends_with("-close") else view.DEFAULT_MAP_ZOOM
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

func verify_mountain_rocks(view: Node3D) -> String:
	var rocky_cell = ""
	var grounded = true
	for id in view.board_surface.profiles:
		if view.board_surface.profiles[id][0] != "mountain":
			continue
		for rock in view.tile_nodes[id].get_children():
			if not rock.scene_file_path.get_file().begins_with("Rock_"):
				continue
			rocky_cell = id
			var lowest = INF
			var highest = -INF
			for mesh in rock.find_children("*", "MeshInstance3D", true, false):
				for i in mesh.mesh.get_surface_count():
					for vertex in mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
						var point: Vector3 = mesh.global_transform * vertex
						var clearance: float = point.y - view.board_surface.height_at(point)
						lowest = minf(lowest, clearance)
						highest = maxf(highest, clearance)
			grounded = grounded and lowest < 0.0 and highest > 0.025
	expect(grounded and not rocky_cell.is_empty(), "Mountain rocks meet the actual ground mesh and remain partly visible")
	return rocky_cell

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
	var courier = run.actor("lorne")
	var original_courier = courier.duplicate()
	courier.joined = true
	courier.position = forest
	game._refresh()
	var companion = view.dolls.lorne
	var bounds: AABB = occluder.global_transform * occluder.get_aabb()
	var sight: Vector3 = -view.camera.global_basis.z
	var side = view.camera.global_basis.x * minf(0.16, minf(bounds.size.x, bounds.size.z) * 0.25)
	var covered_feet = bounds.get_center() + sight * 0.48 - Vector3.UP * 0.20
	companion.global_position = covered_feet + side
	actor.global_position = covered_feet - sight * 2.0
	view.set_process(false)
	await capture("terrain-forest-covered")
	view._update_occlusion(1.0)
	var targets: PackedVector3Array = view.fading_occluders.get(occluder, {}).get("targets", PackedVector3Array())
	expect(targets.size() == 1 and targets[0].is_equal_approx(companion.global_position + Vector3.UP * 0.20),
		"A tree covering only a non-selected squad member still fades")
	actor.global_position = covered_feet - side
	view._update_occlusion(1.0)
	expect(view.fading_occluders.has(occluder) and view.fading_occluders[occluder].targets.size() == 2
		and view.fading_occluders[occluder].amount > 0.9, "One tree can fade around two squad members at the same time")
	if not view.fading_occluders.has(occluder):
		run.data.actors.lorne = original_courier
		view.set_process(true)
		return
	var original: Material = view.fading_occluders[occluder].originals[0]
	await capture("terrain-forest-occlusion")
	view.zoom_size = 10.0
	view._update_camera()
	view._update_occlusion(1.0)
	expect(not view.fading_occluders.has(occluder) and occluder.get_surface_override_material(0) == original, "Zooming out restores the tree's original material")
	expect(view.canopy_batch.visible and not view.canopy_individual, "Wide view groups canopy meshes for rendering")
	run.data.actors.lorne = original_courier
	game._refresh()
	view.set_process(true)

func capture_node_examples() -> void:
	game._start_new()
	var run = game.run
	var original_seed: String = game.chosen_seed
	var seed_value: int = int(run.data.seed)
	var forest_rest = run.data.nodes.keys().filter(func(cell):
		return run.node_at(cell).kind == "rest" and run.data.tiles[cell].terrain == "forest")
	for candidate in range(24):
		if not forest_rest.is_empty():
			break
		seed_value = candidate
		run.new_run(seed_value, "wayfarer")
		forest_rest = run.data.nodes.keys().filter(func(cell):
			return run.node_at(cell).kind == "rest" and run.data.tiles[cell].terrain == "forest")
	var shops = run.data.nodes.keys().filter(func(cell): return run.node_at(cell).kind == "trade")
	expect(not forest_rest.is_empty() and not shops.is_empty(), "Node fixture seed has a forest recovery site and a shop")
	if forest_rest.is_empty() or shops.is_empty():
		return
	game.chosen_seed = str(seed_value)
	game._start_new()
	var rest: String = forest_rest[0]
	run.actor("hero").position = rest
	run.reveal(rest)
	game._select_actor("hero")
	game._node_dialog()
	await capture("node-forest-rest")
	game._close_modal()
	var shop: String = shops[0]
	run.actor("hero").position = shop
	run.reveal(shop)
	game._select_actor("hero")
	game._node_dialog()
	await capture("node-trader-story")
	game._node_choice("trade")
	await capture("node-trader-stock")
	game._close_modal()
	game.chosen_seed = original_seed

func inspect_character_poses() -> void:
	var ids = Catalog.COMPANIONS.keys() + ["hero", "war_god"]
	for id in ids:
		expect(game._story_portrait(id) is Texture2D, "Normal portrait is available " + id)
		var regions: Array[Rect2] = []
		for pose in ["serious", "friendly", "grief", "anger", "surprise", "battle"]:
			var portrait = game._story_portrait(id, pose)
			expect(portrait is AtlasTexture, "Pose loads from a distinct cell " + id + "/" + pose)
			if portrait is AtlasTexture:
				expect(not regions.has(portrait.region), "Pose is a separate illustration " + id + "/" + pose)
				regions.append(portrait.region)
	for group in ["human", "elf", "dwarf"]:
		for pose in ["concerned", "serious", "farewell", "grief", "battle"]:
			expect(game._story_portrait("villager_" + group, pose) is AtlasTexture, "Village pose is available " + group + "/" + pose)

func capture_finale() -> void:
	game._close_modal()
	game._start_new()
	var run = game.run
	var hero = run.actor("hero")
	for cell in run.data.tiles:
		run.data.explored[cell] = true
	for chapter in range(1, 5):
		run.finish_chapter(chapter)
	hero.position = run.data.boss
	run.reveal(hero.position)
	var battle = Combat.new()
	var encounter = {"position": hero.position, "origin": hero.position, "movers": [], "npc": "", "ambush": false}
	expect(battle.begin(run, encounter, ["hero"]).ok, "Finale starts the actual boss battle")
	game.combat = battle
	game.view.begin_battle(run, battle)
	battle.current = "hero"
	battle.unit("enemy_0").hp = 1
	game._perform_combat("gravity", "enemy_0")
	while game.view.is_animating():
		await process_frame
	game._process(0.1)
	expect(game.modal_layer.has_node("StoryScreen") and battle.reveal_pending and not battle.river,
		"The old strike triggers the flashback before the river")
	await capture("story-final-memory")
	for i in range(4):
		await advance_story()
	await capture("story-final-river")
	await advance_story()
	await process_frame
	expect(battle.river and hero.name == "伊文洛" and game.view.battle_root.get_meta("environment_signature").ends_with(":true"),
		"Leaving the flashback brings the river into the actual combat view")
	await capture("battle-final-river")
	game.combat = null
	game.view.end_battle()

func execute() -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://visual-test-run.json"
	game.chosen_seed = "20261104"
	await create_timer(1.0).timeout
	await capture("01-menu")
	game._begin_opening_story()
	await capture("story-world-intro")
	await advance_story()
	await advance_story()
	await capture("story-village-waking")
	inspect_story_layout()
	for i in range(6):
		await advance_story()
	await capture("story-village-farewell")
	await advance_story()
	await create_timer(0.5).timeout
	await capture("02-exploration")
	game.crew_collapsed = true
	game._refresh()
	await capture("02-exploration-folded")
	game.crew_collapsed = false
	game._refresh()
	await inspect_board()
	await capture_node_examples()
	# Inspect every biome through the exact same battle view used in the playable game.
	game.set_process(false)
	for biome in ["plains", "forest", "mountain", "ruins", "desert", "swamp"]:
		game._start_new()
		var run = game.run
		var position = run.actor("hero").position
		run.data.tiles[position].terrain = biome
		run.data.tiles[position].site = ""
		run.data.weather = "rain" if biome == "swamp" else "sun"
		for id in ["lorne", "cen", "eve", "grit", "ember", "tide"]:
			run.actor(id).position = position
			run.join_companion(id)
		run.data.tiles[position].enemies = ["spider", "furnace", "swarm", "canal"]
		var battle = Combat.new()
		var pending = {"position": position, "origin": position, "movers": [], "npc": "", "ambush": false}
		expect(battle.begin(run, pending, ["hero", "grit", "ember", "tide"]).ok, "Battle fixture begins " + biome)
		if biome == "forest":
			battle._apply_field_effect("ignite")
		elif biome == "swamp":
			battle._apply_field_effect("wet")
		game.combat = battle
		game.battle_timer = 0
		game.view.begin_battle(run, battle)
		game._refresh()
		await create_timer(0.6).timeout
		expect(game.view.battle_dolls.size() == 8, "Four friends and four distinct foes rendered")
		expect(game.view.battle_dolls.grit.skeleton.get_bone_count() >= 23 and game.view.battle_dolls.grit.rigged.animator != null, "Dragon in human form has a full imported rig and animation player")
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
			battle._apply_field_effect("wet")
			game.view.sync_event_environment({"environment_after": battle.field_view()})
			game._refresh()
			expect(game.view.battle_root.get_meta("environment_signature") == "forest:true:true:false", "Fire and wetness render together")
			await create_timer(0.6).timeout
			await capture("battle-forest-wet")
			expect(battle.retreat().ok, "Leave burning battle")
		game.combat = null
		game.view.end_battle()
		if biome == "forest":
			game._refresh()
			await capture("map-forest-after-battle")
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
	await capture("dialogue-portrait")
	await advance_story()
	inspect_story_layout()
	game._story_choice("join")
	await capture("story-lorne-joins")
	game._story_choice("later")
	await capture("story-courier-deferred")
	game._close_modal()
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
	inspect_character_poses()
	await capture_finale()
	print("VISUAL FIXTURES: %d checks; failed=%s; captures=%s" % [checks, failed, ProjectSettings.globalize_path(destination)])
	quit(1 if failed else 0)
