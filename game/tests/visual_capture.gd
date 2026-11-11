extends SceneTree
## Presentation fixtures, deliberately separate from no-cheat end-to-end journeys.
const Main = preload("res://scenes/main.tscn")
const Game = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
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
	if game.modal_layer.has_node("StoryScreen"):
		inspect_story_layout()
	var image = root.get_texture().get_image()
	expect(image != null and image.get_width() > 800, "Rendered image " + name)
	if image:
		var error = image.save_png(destination.path_join(name + ".png"))
		expect(error == OK, "Saved image " + name)

func story_text() -> Label:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	return stage.find_child("StoryText", true, false) as Label if stage != null else null

func story_page() -> Vector2i:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	var counter = stage.find_child("PageCounter", true, false) as Label if stage != null else null
	expect(counter != null and counter.is_visible_in_tree(), "Rendered page counter exists")
	if counter == null:
		return Vector2i.ZERO
	var pattern = RegEx.new()
	pattern.compile("^第 ([0-9]+) / ([0-9]+) 页$")
	var matched = pattern.search(counter.text)
	expect(matched != null, "Rendered counter uses 第 n / m 页")
	if matched == null:
		return Vector2i.ZERO
	var page = Vector2i(int(matched.get_string(1)), int(matched.get_string(2)))
	expect(page.x >= 1 and page.x <= page.y, "Rendered page index is valid")
	return page

func inspect_story_layout() -> void:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	var label = story_text()
	if stage == null or label == null:
		expect(false, "Story screen and named body Label are visible")
		return
	var dialogue = stage.get_node("Dialogue") as Control
	expect(not dialogue is Container, "Dialogue is fixed rather than sized by its text")
	expect(dialogue.find_children("*", "ScrollContainer", true, false).is_empty(), "Rendered body never needs scrolling")
	var frame = dialogue.get_global_rect()
	expect(frame.position.y > stage.size.y * 0.65 and root.get_visible_rect().encloses(frame), "Dialogue stays inside the bottom of the screen")
	expect(frame.encloses(label.get_global_rect()), "Rendered body rectangle stays inside Dialogue")
	var line_count = label.get_line_count()
	var height = 0.0
	for line in line_count:
		height += label.get_line_height(line)
	height += maxi(0, line_count - 1) * label.get_theme_constant("line_spacing")
	expect(height <= label.size.y, "Every rendered body line fits, including the last line")
	expect(label.lines_skipped == 0 and label.visible_characters == -1
		and (label.max_lines_visible == -1 or label.max_lines_visible >= line_count), "Rendered text does not hide overflowing lines or characters")
	var measured = label.get_theme_font("font").get_multiline_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, label.size.x, label.get_theme_font_size("font_size"), -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	expect(measured.x <= label.size.x, "Rendered glyphs fit the real body width")
	var page = story_page()
	var counter = stage.find_child("PageCounter", true, false) as Label
	expect(counter != null and not dialogue.is_ancestor_of(counter)
		and counter.get_global_rect().end.y < frame.position.y, "Page counter is in the header")
	for actor in stage.find_children("StoryActor*", "TextureRect", true, false):
		var portrait_rect: Rect2 = actor.get_global_rect()
		expect(portrait_rect.position.y < stage.size.y * 0.31 and portrait_rect.end.y > frame.position.y,
			"Portrait reaches into the scene above and the shaded dialogue area below")
	expect((story_button("上一页") != null) == (page.x > 1), "Previous page is shown only after page one")
	expect(story_button("下一页") == null and story_button("继续") == null, "Story has no redundant forward buttons")
	var column = stage.get_node_or_null("StoryChoices") as Control
	if page.x < page.y:
		expect(column == null, "Intermediate screenshots expose no decisions")
	if column != null:
		var choices = column.get_global_rect()
		expect(choices.position.x > stage.size.x * 0.5 and root.get_visible_rect().encloses(choices), "Choices stay in the right column")
		expect(not frame.intersects(choices), "Story text and choices do not overlap")
	var leaves: Array[Control] = []
	for control in stage.find_children("*", "Control", true, false):
		if (control is Label or control is Button) and control.is_visible_in_tree():
			expect(root.get_visible_rect().encloses(control.get_global_rect()), "Rendered story control stays on screen: " + control.name)
			for other in leaves:
				if not control.is_ancestor_of(other) and not other.is_ancestor_of(control):
					expect(not control.get_global_rect().intersects(other.get_global_rect()), "Rendered controls do not overlap: %s / %s" % [control.name, other.name])
			leaves.append(control)

func advance_story() -> void:
	await process_frame
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	expect(stage != null and not stage.has_node("StoryChoices"), "Mouse reading does not skip a choice")
	if stage == null or stage.has_node("StoryChoices"):
		return
	inspect_story_layout()
	await click_at(root.get_visible_rect().size * Vector2(0.76, 0.30))

func advance_until_text(fragment: String) -> void:
	for index in range(128):
		if story_contains(fragment):
			return
		if not game.modal_layer.has_node("StoryScreen"):
			break
		await advance_story()
	expect(false, "Bounded story reading reaches: " + fragment)

func finish_linear_story() -> void:
	for index in range(128):
		if not game.modal_layer.has_node("StoryScreen"):
			return
		await advance_story()
	expect(false, "Bounded linear story reaches its destination")

func capture_story_body(prefix: String, expected: String) -> PackedStringArray:
	await process_frame
	var first = story_page()
	expect(first.x == 1 and first.y <= 128, "Capture starts at page one with a bounded page count")
	var pages = PackedStringArray()
	for index in range(mini(first.y, 128)):
		inspect_story_layout()
		expect(story_page() == Vector2i(index + 1, first.y), "Actual mouse click advances exactly one rendered page")
		var label = story_text()
		if label == null:
			return pages
		pages.append(label.text)
		if index == 0:
			await capture(prefix + "-first")
		if index == 1:
			await capture(prefix + "-next")
			await click_story_button("上一页")
			expect(story_page() == Vector2i(1, first.y) and story_text().text == pages[0], "Mouse previous restores the complete first page")
			await capture(prefix + "-previous")
			await click_at(root.get_visible_rect().size * Vector2(0.76, 0.30))
			expect(story_page() == Vector2i(2, first.y) and story_text().text == pages[1], "Returning to next page preserves the text")
		if index == first.y - 1:
			await capture(prefix + "-last")
		else:
			await click_at(root.get_visible_rect().size * Vector2(0.76, 0.30))
	expect("".join(pages).replace("\n", "") == expected.replace("\n", ""), "Captured pages preserve every word, including the final paragraph: " + prefix)
	return pages

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
	var bounds: AABB = occluder.global_transform * occluder.get_aabb()
	var sight: Vector3 = -view.camera.global_basis.z
	actor.global_position = bounds.get_center() + sight * 0.48 - Vector3.UP * 0.20
	view.set_process(false)
	await capture("terrain-forest-covered")
	view._update_occlusion(1.0)
	var targets: PackedVector3Array = view.fading_occluders.get(occluder, {}).get("targets", PackedVector3Array())
	expect(targets.size() == 1 and targets[0].is_equal_approx(actor.global_position + Vector3.UP * 0.20),
		"A tree covering the traveler fades around their position")
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
	expect(not forest_rest.is_empty() and not shops.is_empty(), "Node fixture seed has a forest supply stop and a shop")
	if forest_rest.is_empty() or shops.is_empty():
		return
	game.chosen_seed = str(seed_value)
	game._start_new()
	var rest: String = forest_rest[0]
	run.actor("hero").position = rest
	run.reveal(rest)
	game._select_actor("hero")
	game._node_dialog()
	await capture("node-forest-supply-stop")
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

func story_button(prefix: String) -> Button:
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text.begins_with(prefix):
			return button
	return null

func click_story_button(prefix: String) -> bool:
	var button = story_button(prefix)
	expect(not prefix.is_empty() and button != null and not button.disabled, "Rendered story button: " + prefix)
	if prefix.is_empty() or button == null or button.disabled:
		return false
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame
	await click_at(button.get_global_rect().get_center())
	return true

func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
	await process_frame

func await_story_choices() -> bool:
	for index in range(128):
		var stage = game.modal_layer.get_node_or_null("StoryScreen")
		if stage == null:
			expect(false, "Story stays open while advancing to choices")
			return false
		if stage.has_node("StoryChoices"):
			await process_frame
			inspect_story_layout()
			return true
		await advance_story()
	expect(false, "Rendered story reaches choices without unbounded clicks")
	return false

func quest_option_label(result: Dictionary, id: String) -> String:
	for option in result.get("options", []):
		if option.id == id:
			return str(option.text)
	expect(false, "Quest option has a visible label: " + id)
	return ""

func story_contains(text: String) -> bool:
	var label = story_text()
	return label != null and label.text.contains(text)

func capture_branch_examples() -> void:
	game._start_new()
	var run = game.run
	var person = run.actor("longroad")
	run.actor("hero").position = person.position
	run.data.tiles[person.position].enemies.clear()
	run.reveal(person.position)
	game._select_actor("hero")
	game._talk("longroad")
	if not await await_story_choices():
		return
	await click_story_button(quest_option_label(game.narrative.dialogue("hero", "longroad"), "join"))
	await advance_story()
	if not await await_story_choices():
		return
	await click_story_button(quest_option_label(game.narrative.dialogue("hero", "longroad"), "quest"))
	await advance_story()
	var quest = game.narrative.personal_quest("hero", "longroad")
	await capture_story_body("story-personal", quest.text)
	if not await await_story_choices():
		return
	var first = quest_option_label(quest, "personal_a")
	var second = quest_option_label(quest, "personal_b")
	expect(story_button(first) != null and story_button(second) != null, "Both personal decisions are rendered")
	await capture("story-personal-choices")
	inspect_story_layout()
	await click_story_button(second)
	await capture("story-personal-player-reply")
	await advance_story()
	await capture_story_body("story-personal-conclusion", Story.PERSONAL_QUESTS.longroad.personal_b.response)
	game._close_modal()
	var haunts = run.data.nodes.keys().filter(func(cell): return run.node_at(cell).kind == "haunt")
	expect(not haunts.is_empty(), "Visual fixture includes a haunting")
	if haunts.is_empty():
		return
	var cell: String = haunts[0]
	var event = Nodes.story(run.node_at(cell))
	run.actor("hero").position = cell
	run.reveal(cell)
	game._select_actor("hero")
	game._node_dialog()
	if not await await_story_choices():
		return
	await click_story_button(event.investigation_label)
	await capture_story_body("node-haunt-investigation", event.investigation)
	expect(run.node_at(cell).get("investigated", false) and run.node_at(cell).result == ""
		and not run.data.peace.has(cell) and game.modal_layer.has_node("StoryScreen/StoryChoices"),
		"Reading the full investigation exposes settlement once without resolving it")
	if not await await_story_choices():
		return
	await click_story_button(event.alternative)
	await capture_story_body("node-haunt-alternative-conclusion",
		"送别时，旅人伸出手，给亡魂指了条离开这里的路。\n\n" + event.alternative_resolved)
	expect(not game.modal_layer.has_node("StoryScreen/StoryChoices"), "The narrative is separate from the action result")
	await advance_story()
	await capture_story_body("node-haunt-action-result", "你送别了这里的亡者。")
	expect(game.modal_layer.has_node("StoryScreen/StoryChoices"), "The action result offers the return after the full conclusion")
	expect(run.node_at(cell).result == "settle_alternative", "Haunting screenshot follows the actual second settlement click")
	game._close_modal()
	run.data.status = "won"
	game._refresh()
	await capture("story-epilogue-record")
	for button in game.ui.find_children("*", "Button", true, false):
		if button.text in ["查看结局剧情", "返回主菜单"]:
			expect(root.get_visible_rect().encloses(button.get_global_rect()), "Ending record keeps its action visible: " + button.text)
	var ending: String = game.narrative.main_ending().text
	var epilogue: String = game.narrative.character_ending("longroad").text
	for label in game.ui.find_children("*", "Label", true, false):
		expect(not label.text.contains(ending) and not label.text.contains(epilogue), "Summary screenshot does not embed long ending prose")
	game._ending_story()
	var ending_pages = await capture_story_body("story-main-ending", ending)
	expect(ending_pages.size() >= 2 and "".join(ending_pages).ends_with(ending.split("\n\n")[-1]),
		"Ending screenshots reach the final paragraph across multiple pages")
	await click_at(root.get_visible_rect().size * Vector2(0.76, 0.30))
	await capture_story_body("story-companion-ending", epilogue)
	await click_story_button("返回远征记录")

func inspect_portrait_silhouette(portrait: Texture2D, key: String) -> void:
	if portrait == null:
		return
	var pixels = portrait.get_image()
	var size = pixels.get_size()
	var has_head = false
	var has_hem = false
	for y in range(0, size.y, 4):
		var height = float(y) / size.y
		if height >= 0.18 and height <= 0.91:
			continue
		var opaque = 0
		for x in range(0, size.x, 4):
			if pixels.get_pixel(x, y).a > 0.65:
				opaque += 1
		if opaque >= 4:
			has_head = has_head or height < 0.18
			has_hem = has_hem or height > 0.91
	expect(has_head and has_hem, "The visible silhouette reaches both framing bands: " + key)

func inspect_character_poses() -> void:
	var ids = Catalog.COMPANIONS.keys() + ["hero", "war_god"]
	for id in ids:
		var portrait = game._story_portrait(id)
		expect(portrait is Texture2D, "Normal portrait is available " + id)
		inspect_portrait_silhouette(portrait, id)
		var regions: Array[Rect2] = []
		for pose in ["serious", "friendly", "grief", "anger", "surprise", "battle"]:
			var posed = game._story_portrait(id, pose)
			expect(posed is AtlasTexture, "Pose loads from a distinct cell " + id + "/" + pose)
			if posed is AtlasTexture:
				expect(not regions.has(posed.region), "Pose is a separate illustration " + id + "/" + pose)
				regions.append(posed.region)
				inspect_portrait_silhouette(posed, id + "/" + pose)
	for group in ["human", "elf", "dwarf"]:
		for pose in ["", "concerned", "serious", "farewell", "grief", "battle"]:
			var portrait = game._story_portrait("villager_" + group, pose)
			expect(portrait is AtlasTexture, "Village pose is available " + group + "/" + pose)
			inspect_portrait_silhouette(portrait, group + "/" + pose)

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
	await advance_until_text("都留在我身后")
	await capture("story-final-before-river")
	await advance_until_text("冥河在卡德兰脚下涌出")
	await capture("story-final-river")
	await finish_linear_story()
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
	var test_save = "user://visual-test-run-%d.json" % OS.get_process_id()
	game.run.save_path = test_save
	game.chosen_seed = "20261104"
	var menu_state = game.screen_state
	game._refresh()
	await create_timer(1.0).timeout
	await capture("01-menu")
	game._begin_opening_story()
	await capture("story-world-intro")
	await advance_until_text("战神卡德兰")
	await capture("story-world-gods")
	await advance_until_text("运粮的车过不来")
	await capture("story-world-war")
	await advance_until_text("你醒了")
	await capture("story-village-waking")
	await advance_until_text("一点也想不起来")
	await capture("story-village-traveler")
	await advance_until_text("那我出去走走")
	await capture("story-village-decision")
	await advance_until_text("一路平安")
	await capture("story-village-farewell")
	await click_story_button("历史对话")
	expect(game.modal_layer.has_node("StoryHistory/HistoryPanel"), "Story history opens over the village illustration")
	await capture("story-dialogue-history")
	await click_story_button("关闭")
	await finish_linear_story()
	game._show_opening(menu_state)
	await capture("01-menu-with-save")
	var resume: Button
	for button in game.ui.find_children("*", "Button", true, false):
		if button.text == "继续上次远征":
			resume = button
			break
	expect(resume != null and not resume.disabled, "A saved expedition has an enabled resume button")
	if resume != null:
		await click_at(resume.get_global_rect().get_center())
	await create_timer(0.5).timeout
	await capture("02-exploration")
	var arrival_run = game.run
	var first_tile: String = Hex.neighbors(arrival_run.data.start, arrival_run.data.tiles).filter(func(cell):
		return Hex.is_land(arrival_run.data.tiles, cell) and arrival_run.data.tiles[cell].enemies.is_empty())[0]
	game._select_cell(first_tile)
	game._select_cell(first_tile)
	var arrival_deadline = Time.get_ticks_msec() + 5000
	while game.map_traveling and Time.get_ticks_msec() < arrival_deadline:
		await process_frame
	expect(game.modal_layer.has_node("StoryScreen"), "First-arrival story appears after the walk")
	await capture("node-first-arrival")
	await click_story_button("返回地图")
	await create_timer(0.9).timeout
	await capture("map-visited-locations")
	game.crew_collapsed = true
	game._refresh()
	await capture("02-exploration-folded")
	game.crew_collapsed = false
	game._refresh()
	await inspect_board()
	await capture_node_examples()
	# Inspect every biome through the exact same battle view used in the playable game.
	game.set_process(false)
	await capture_branch_examples()
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
	game._inventory_dialog("hero", 0, "salve")
	await capture("inventory-seven-members")
	game._inventory_dialog("hero", 1, str(game.run.actor("hero").equipment.weapon))
	await capture("inventory-gear")
	game._transfer_dialog("hero", "salve")
	await capture("transfer-seven-members")
	game._close_modal()
	game._show_character_codex()
	var codex = game.modal_layer.get_node("CharacterCodex")
	codex._set_tab(1)
	await capture("codex-list")
	var grid_view = codex.find_child("CodexGridView", true, false) as Button
	await click_at(grid_view.get_global_rect().get_center())
	expect(game.character_codex_state.grid, "The joined grid segment opens the card layout")
	await capture("codex-grid")
	game._close_character_codex()
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
	await await_story_choices()
	inspect_story_layout()
	await click_story_button(quest_option_label(game.narrative.dialogue("hero", "lorne"), "join"))
	await advance_story()
	await capture("story-lorne-joins")
	await await_story_choices()
	await capture("story-courier-joined-choices")
	await click_story_button(quest_option_label(game.narrative.dialogue("hero", "lorne"), "quest"))
	await advance_story()
	await await_story_choices()
	await capture("story-lorne-personal-choices")
	game._close_modal()
	# Recruit Eve for the first time, without the earlier battle fixtures' relic rewards.
	game._start_new()
	game.run.actor("hero").position = game.run.actor("eve").position
	game.run.data.tiles[game.run.actor("eve").position].enemies.clear()
	game._talk("eve")
	await capture("story-eve-first-meeting")
	await await_story_choices()
	await capture("story-eve-decision")
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event, true)
	expect(game.modal_layer.get_child_count() == 0 and game.view.visible, "Escape returns from a conversation to the map")
	game._talk("eve")
	await await_story_choices()
	await click_story_button(quest_option_label(game.narrative.dialogue("hero", "eve"), "join"))
	await advance_story()
	expect(story_contains(Story.CHARACTER_BEHAVIOR.eve[1]), "A companion replies before opening the recruitment relic")
	await advance_until_text(Relics.DATA.tender_gauze.story)
	expect(story_contains(Relics.DATA.tender_gauze.story), "The recruitment relic follows the companion's reply")
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
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(test_save + suffix):
			DirAccess.remove_absolute(test_save + suffix)
	print("VISUAL FIXTURES: %d checks; failed=%s; captures=%s" % [checks, failed, ProjectSettings.globalize_path(destination)])
	quit(1 if failed else 0)
