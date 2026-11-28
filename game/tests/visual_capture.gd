extends SceneTree
## Presentation fixtures, deliberately separate from no-cheat end-to-end journeys.
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
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
	var background = stage.get_child(0) as TextureRect
	expect(background != null and background.texture != null
		and background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED
		and background.get_global_rect().is_equal_approx(root.get_visible_rect()),
		"Story art covers the viewport at its original aspect ratio")
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
	var forward := story_button("继续")
	expect(story_button("下一页") == null and (forward == null or forward.text != "继续"), "Story has no redundant forward buttons")
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

func open_recruitment_shop(id: String) -> bool:
	var run = game.run
	var cell: String = run.actor(id).position
	run.retreat_party(cell)
	run.data.tiles[cell].enemies.clear()
	run.data.tiles[cell].npc = id
	run.data.pending_victory = {"enemies": 1, "members": ["hero"], "revived": [], "relic": ""}
	run.open_battle_shop()
	game.selected_id = "hero"
	game._refresh()
	game._shop_dialog("", {"category": "companion", "id": id})
	return true

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
	var ids = Catalog.COMPANIONS.keys() + ["hero"]
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

func capture_finale() -> void:
	game._close_modal()
	game._start_new(false)
	var run = game.run
	var hero = run.actor("hero")
	hero.position = run.data.boss
	run.data.tiles[hero.position].enemies = ["war_god"]
	var battle := Chess.new()
	var encounter = {"position": hero.position, "origin": hero.position, "npc": "", "ambush": false}
	expect(battle.begin(run, encounter, run.card_deck()).ok, "Finale starts the actual boss battle")
	game.combat = battle
	game._refresh()
	await capture("battle-winch")
	expect(battle.commanders[Chess.ENEMY].name == "捕鲸机", "The finale fights the whaling winch")
	battle.commanders[Chess.ENEMY].hp = 0
	expect(battle._check_outcome() and battle.outcome == "victory", "Breaking the winch resolves combat directly")
	game.combat = null
	game._ending_story()
	await capture("story-surface")
	expect(story_page() == Vector2i(1, 1) and "刚才那杯" in story_text().text, "The ending is one short line")
	game._close_modal()

func capture_journey_reveal() -> void:
	var option := game.ui.find_child("JourneyChoice2", true, false) as Button
	expect(option != null and option.text.ends_with("高赌注") and root.get_visible_rect().encloses(option.get_global_rect()),
		"The journey displays an on-screen action with its stake.")
	if option != null:
		await click_at(option.get_global_rect().get_center())
		expect(game.ui.find_child("JourneyChoice2", true, false) == null, "Revealing the result closes all choices.")
		await capture("journey-revealed")

func execute() -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	var test_save = "user://visual-test-run-%d.json" % OS.get_process_id()
	game.run.save_path = test_save
	game.chosen_seed = "20261104"
	if "--journey-only" in OS.get_cmdline_user_args():
		game._begin_opening_story()
		await capture("story-opening")
		await click_story_button("出发")
		await click_story_button("踏上旅途")
		await capture("journey-choice")
		await capture_journey_reveal()
		await capture_finale()
		game.run.data.status = "won"
		game._ending_story()
		await capture("story-ending")
		expect(story_page() == Vector2i(1, 1), "The main ending fits on one screen")
		finish(test_save)
		return
	var menu_state = game.screen_state
	game._refresh()
	await create_timer(1.0).timeout
	await capture("01-menu")
	game._begin_opening_story()
	await capture("story-opening")
	expect(story_page() == Vector2i(1, 1), "The opening fits on one screen")
	var history_button = game.modal_layer.find_child("StoryHistoryButton", true, false) as Button
	expect(history_button != null and history_button.icon != null and history_button.text.is_empty(),
		"History is presented as an icon in the rendered header")
	if history_button != null:
		await click_at(history_button.get_global_rect().get_center())
	expect(game.modal_layer.has_node("StoryHistory/HistoryPanel"), "Story history opens over the village illustration")
	await capture("story-dialogue-history")
	await click_story_button("关闭")
	await click_story_button("出发")
	expect(game.modal_layer.has_node("StoryRewards"), "The village departure shows the starter deck reward")
	await capture("story-starter-deck-reward")
	await click_story_button("查看卡组")
	await capture("story-starter-deck-editor")
	await click_story_button("返回奖励")
	await click_story_button("踏上旅途")
	await capture("journey-choice")
	game._close_modal()
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
	await capture("journey-resumed")
	await capture_journey_reveal()
	# Inspect every biome through the exact same battle view used in the playable game.
	game.set_process(false)
	for biome in ["plains", "forest", "mountain", "ruins", "desert", "swamp"]:
		game._start_new(false)
		var run = game.run
		var position = run.actor("hero").position
		run.data.tiles[position].terrain = biome
		run.data.tiles[position].site = ""
		for id in ["lorne", "cen", "eve", "grit", "ember", "tide"]:
			run.actor(id).position = position
			run.join_companion(id)
		run.data.tiles[position].enemies = ["spider", "furnace", "swarm", "canal"]
		var battle := Chess.new()
		var pending = {"position": position, "origin": position, "npc": "", "ambush": false}
		expect(battle.begin(run, pending, run.card_deck()).ok, "Chess battle fixture begins " + biome)
		game.combat = battle
		game._refresh()
		await process_frame
		expect(game.chess_view != null and game.chess_view.is_visible_in_tree(),
			"The playable chess board is shown over this biome")
		await capture("chess-battle-" + biome)
		expect(battle.retreat(), "Retreat from chess battle " + biome)
		game._finish_battle()
	# Seven-person inventory and portrait dialogue layout use explicit presentation fixtures.
	game.run.data.status = "exploring"
	game.run.data.pending_battle = {}
	game._inventory_dialog("hero", 0, "trail_food")
	await capture("inventory-seven-members")
	game._inventory_dialog("hero", 1, str(game.run.actor("hero").equipment.weapon))
	await capture("inventory-gear")
	game._transfer_dialog("hero", "trail_food")
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
	game.run.data.tiles[game.run.actor("lorne").position].enemies.clear()
	game.run.data.lamp_coins = 8
	if not open_recruitment_shop("lorne"):
		quit(1)
		return
	await capture("courier-recruitment")
	game.modal_layer.find_child("ConfirmTrade", true, false).pressed.emit()
	if game.modal_layer.has_node("StoryRewards"):
		await click_story_button("返回商店")
	await click_story_button("返回远征")
	game._show_character_codex()
	var companion_codex = game.modal_layer.get_node("CharacterCodex")
	companion_codex._select_character("lorne")
	companion_codex._set_tab(3)
	await capture("companion-profile")
	game._close_character_codex()
	# Recruit Eve for the first time, without the earlier battle fixtures' relic rewards.
	game._start_new(false)
	game.run.actor("hero").position = game.run.actor("eve").position
	game.run.data.tiles[game.run.actor("eve").position].enemies.clear()
	if not open_recruitment_shop("eve"):
		quit(1)
		return
	await capture("eve-recruitment")
	expect(game.modal_layer.find_child("ShopView", true, false) != null, "Companion recruitment appears inside the shop")
	game._close_modal()
	expect(game.modal_layer.get_child_count() == 0 and game.ui.visible, "Closing the shop returns to the expedition")
	open_recruitment_shop("eve")
	game.modal_layer.find_child("ConfirmTrade", true, false).pressed.emit()
	expect(game.modal_layer.has_node("StoryRewards"), "Recruitment opens the illustrated relic receipt")
	await capture("eve-recruitment-reward")
	game._close_modal()
	# Instantiate every remaining enemy art family and verify its skeleton in the tree.
	for id in Catalog.ENEMIES:
		var definition = Catalog.ENEMIES[id].duplicate(true)
		definition.id = "visual_" + id
		definition.type = id
		var doll = load("res://scripts/presentation/doll.gd").new()
		game.add_child(doll)
		doll.configure(definition)
		expect(doll.skeleton.get_bone_count() >= 6, "Enemy has rig " + id)
		doll.queue_free()
	inspect_character_poses()
	await capture_finale()
	finish(test_save)

func finish(test_save: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(test_save + suffix):
			DirAccess.remove_absolute(test_save + suffix)
	print("VISUAL FIXTURES: %d checks; failed=%s; captures=%s" % [checks, failed, ProjectSettings.globalize_path(destination)])
	quit(1 if failed else 0)
