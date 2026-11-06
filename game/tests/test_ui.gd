extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
var game: Node
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func find_button(parent: Node, prefix: String) -> Button:
	for child in parent.get_children():
		if child is Button and str(child.text).begins_with(prefix):
			return child
		var found = find_button(child, prefix)
		if found != null:
			return found
	return null

func press(prefix: String) -> void:
	var button = find_button(game.modal_layer if game.modal_layer.get_child_count() > 0 else game.ui, prefix)
	expect(button != null, "UI button exists: " + prefix)
	if button != null:
		expect(not button.disabled, "UI button enabled: " + prefix)
		if not button.disabled:
			button.pressed.emit()
	await process_frame

func dialogue_contains(fragment: String) -> bool:
	var dialogue = game.modal_layer.get_node_or_null("StoryScreen/Dialogue")
	return dialogue != null and contains_text(dialogue, fragment)

func contains_text(parent: Node, fragment: String) -> bool:
	for label in parent.find_children("*", "Label", true, false):
		if fragment in label.text:
			return true
	return false

func check_discovery() -> void:
	game._start_new()
	var run = game.run
	var target = Hex.neighbors(run.data.start, run.data.tiles)[0]
	var tile: Dictionary = run.data.tiles[target]
	var terrain = tile.terrain
	tile.terrain = "forest"
	tile.site = "herb"
	tile.npc = "eve"
	tile.enemies = []
	tile.resource = "salve"
	tile.quantity = 1
	run.actor("eve").position = target
	run.data.explored[run.data.exit] = true
	game.view.cell_clicked.emit(target)
	expect(run.data.explored.has(target) and not run.has_visited(target) and game.view.tile_nodes.has(target), "Revealed neighbor renders terrain before arrival")
	expect(game.ui.get_child_count() == 2 and game.move_preview.visible and game.move_preview.costs == ["1 精力"],
		"First click previews only the map arrow and the effort label")
	expect(not contains_text(game.ui, "药箱树荫") and not contains_text(game.ui, "伊芙") and not contains_text(game.ui, "可采集"),
		"Neighbor inspection hides the site's name, NPC and items")
	expect(game.view.tile_nodes[target].find_children("*", "Label3D", true, false).is_empty() and not game.view.dolls.has("eve"),
		"No early landmark label or NPC on the map")
	for alternative in Hex.neighbors(run.data.start, run.data.tiles):
		if alternative != target and Hex.is_land(run.data.tiles, alternative):
			var ap = run.actor("hero").ap
			game.view.cell_clicked.emit(alternative)
			expect(game.move_target == alternative and run.actor("hero").position == run.data.start and run.actor("hero").ap == ap,
				"Changing the selected neighbor replaces the preview without spending effort")
			break
	await press("旅途手记")
	expect(not game.move_preview.visible, "Opening a dialog clears the movement preview")
	expect(find_button(game.modal_layer, "在地图上定位归航站") == null, "Revealing ferry terrain does not unlock its exact location")
	await press("合上手记")
	game.view.cell_clicked.emit(target)
	game.view.cell_clicked.emit(target)
	expect(not game.move_preview.visible and game.move_target.is_empty(), "The confirmation clears the arrow and cost")
	await press("当前地块行动")
	expect(run.has_visited(target) and contains_text(game.modal_layer, "药箱树荫") and contains_text(game.modal_layer, "伊芙") and contains_text(game.modal_layer, "可采集"),
		"Real arrival reveals site, NPC and items together")
	expect(game.view.dolls.eve.visible and game.view.tile_nodes[target].find_children("*", "Label3D", true, false).size() == 1, "Visited landmark and NPC are rendered")
	await press("采集")
	expect(tile.quantity == 0, "Discovered loot is collectible through the action dialog")
	await press("当前地块行动")
	await press("交谈 / 个人故事")
	expect(dialogue_contains("药瓶") and not run.data.story.eve.met, "Eve first appears in a narrated meeting")
	for i in range(3):
		await advance_story()
	var choices = game.modal_layer.get_node("StoryScreen/StoryChoices")
	expect(find_button(choices, "接取药箱") != null and find_button(choices, "邀请同行") == null
		and find_button(choices, "说明应急分药") == null and find_button(choices, "交回真实回执") == null,
		"Eve only offers currently possible choices")
	await press("接取药箱")
	await advance_story()
	choices = game.modal_layer.get_node("StoryScreen/StoryChoices")
	expect(find_button(choices, "接取药箱") == null and find_button(choices, "说明应急分药") != null,
		"Response ends before newly available choices appear")

	game._start_new()
	tile = run.data.tiles[target]
	tile.terrain = terrain
	tile.enemies = ["boar"]
	tile.hidden = false
	tile.discovered_enemy = true # Old saves premarked open-terrain encounters.
	run.actor("hero").ap = run.move_cost("hero", target)
	game.view.cell_clicked.emit(target)
	expect(not contains_text(game.ui, "驻守敌人") and not contains_text(game.ui, "危险迹象"), "Even a premarked encounter stays secret before visiting")
	expect(game.view.tile_nodes[target].find_children("*", "Label3D", true, false).is_empty(), "No encounter icon on the map")
	game.view.cell_clicked.emit(target)
	expect(run.data.pending_battle.get("surprise", false) and not run.data.pending_battle.ambush and run.actor("hero").ap == 0,
		"Open-terrain surprise occurs on arrival without turning into an ambush")
	await press("开始战斗")
	expect(game.combat != null and run.actor("hero").ap == 0, "Surprise encounter can deploy at zero AP")
	if game.combat != null:
		game.combat.retreat()

func has_opening_choice(id: String) -> bool:
	return game.run.data.choices.any(func(choice):
		return choice.get("subject") == "opening" and choice.get("option") == id)

func story_owns_focus() -> bool:
	var story = game.modal_layer.get_node_or_null("StoryScreen")
	var focused = root.gui_get_focus_owner()
	return not game.ui.visible and story != null and focused != null and (story == focused or story.is_ancestor_of(focused))

func advance_story(at: Vector2 = Vector2(0.76, 0.30)) -> void:
	var story = game.modal_layer.get_node_or_null("StoryScreen")
	expect(story != null and not story.has_node("StoryChoices") and find_button(story, "继续") == null,
		"Linear story page has no choice column or continue button")
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = root.get_visible_rect().size * at
		root.push_input(event, true)
	await process_frame

func reach_opening_shelter() -> void:
	await press("开始远征")
	await advance_story()
	await advance_story(Vector2(0.25, 0.87))

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-ui.json"
	expect(find_button(game.ui, "◆ 巡路客") == null and not game.view.visible, "Title screen has no class selection or live map")
	game.run.data.erase("choices")
	game.run.data.erase("visited")
	expect(game.run.save_game().ok, "Existing expedition fixture saves")
	var original_save = FileAccess.get_file_as_string(game.run.save_path)
	await press("开始新远征")
	expect(game.ui.get_node("ProfessionPortrait").texture.resource_path.ends_with("/hero.png"), "Wayfarer opens with its own portrait")
	await press("◇ 烛纹师")
	expect(game.ui.get_node("ProfessionPortrait").texture.resource_path.ends_with("/hero-arcanist.png"), "Arcanist switches to its own portrait")
	await press("返回主菜单")
	expect(FileAccess.get_file_as_string(game.run.save_path) == original_save, "Backing out of class selection preserves the save")
	expect(game.ui.get_node_or_null("ProfessionPortrait") == null, "Returning to title removes the standalone portrait")
	await press("开始新远征")
	await press("◇ 守灯卫")
	expect(game.chosen_profession == "guardian", "Profession selection updates")
	expect(game.ui.get_node("ProfessionPortrait").texture.resource_path.ends_with("/hero-guardian.png"), "Guardian switches to its own portrait")
	await press("开始远征")
	expect(dialogue_contains("随商队进入白栎边境") and not game.view.visible, "Opening shows the story before the map")
	expect(story_owns_focus(), "Opening hides the underlying interface and owns keyboard focus")
	await press("返回职业选择")
	expect(game.ui.get_node_or_null("ProfessionPortrait") != null and game.chosen_profession == "guardian", "Returning restores the selected profession")
	expect(FileAccess.get_file_as_string(game.run.save_path) == original_save, "Leaving the opening preserves the previous save")
	await press("返回主菜单")
	await press("继续上次远征")
	expect(game.view.visible and game.run.data.profession == "wayfarer" and game.run.data.choices.is_empty(), "Legacy saves with no choice history continue directly to the map")
	expect(game.run.data.visited.size() == 1 and game.run.has_visited(game.run.data.start), "Legacy saves recover the start without treating nearby revealed tiles as visited")
	await press("主菜单")
	original_save = FileAccess.get_file_as_string(game.run.save_path)
	await press("开始新远征")
	await reach_opening_shelter()
	await press("先看看登记副本")
	expect(dialogue_contains("接应船照常往来"), "Reading the commission explains the ferry destination")
	expect(FileAccess.get_file_as_string(game.run.save_path) == original_save, "Opening choices do not save an expedition before departure")
	await advance_story()
	expect(has_opening_choice("order"), "The commission branch is recorded on departure")
	expect(game.run.actor("hero").hp_max == 145 and game.run.actor("hero").ap == 5, "Profession affects actual character")
	expect(game.run.joined_ids() == ["hero"] and game.view.dolls.keys() == ["hero"], "Starting view shows only the lone protagonist")
	await press("主菜单")
	await press("继续上次远征")
	expect(game.view.dolls.keys() == ["hero"], "Continuing at the starting camp still shows only the protagonist")
	expect(has_opening_choice("order") and game.modal_layer.get_child_count() == 0, "Continue loads the choice without replaying the opening")
	await press("主菜单")
	await press("开始新远征")
	await reach_opening_shelter()
	await press("看看外面还有没有灯")
	expect(dialogue_contains("石路有新脚印"), "Looking for lights gives a distinct clue")
	await advance_story()
	expect(has_opening_choice("lamps") and not has_opening_choice("order"), "A separate expedition records only its own opening decision")
	await press("主菜单")
	await press("开始新远征")
	await press("开始远征")
	await press("跳过剧情")
	expect(game.view.visible and game.modal_layer.get_child_count() == 0 and game.run.data.choices.is_empty(), "Skipping opens the map without fabricating an opening choice")
	var path = Hex.path(game.run.data.tiles, game.run.actor("hero").position, game.run.actor("lorne").position)
	var cost = 0
	for destination in path.slice(1):
		cost += game.run.move_cost("hero", destination)
		game.view.cell_clicked.emit(destination)
		game.view.cell_clicked.emit(destination)
	expect(game.run.actor("hero").ap == 5 - cost, "Native UI movement pays exact AP")
	expect(game.view.dolls.has("lorne") and game.view.dolls.lorne.visible and not game.run.actor("lorne").joined, "The courier appears as an NPC on reaching his tile")
	await press("当前地块行动")
	await press("交谈 / 个人故事")
	expect(dialogue_contains("旧路牌") and not game.run.data.story.lorne.met, "The first scene introduces the encounter without committing it")
	expect(story_owns_focus(), "The first scene owns keyboard focus")
	await press("结束交谈")
	expect(not game.run.data.story.lorne.met, "Closing before the choices does not consume the introduction")
	await press("当前地块行动")
	await press("交谈 / 个人故事")
	await advance_story()
	expect(dialogue_contains("渡桥已经断了"), "A second beat gives the visitor a line")
	await advance_story()
	expect(dialogue_contains("我叫洛恩"), "A third beat introduces the courier")
	await advance_story()
	var choices = game.modal_layer.get_node_or_null("StoryScreen/StoryChoices")
	expect(choices != null and find_button(choices, "暂缓决定") != null, "Courier dialogue puts branches in the shared story choices region")
	expect(story_owns_focus(), "Courier dialogue hides the map interface and owns keyboard focus")
	await press("暂缓决定")
	expect(game.run.data.story.lorne.relation == "later" and dialogue_contains("继续这场谈话"), "The defer branch updates relationship and visible response")
	await advance_story()
	await press("邀请同行")
	expect(game.run.actor("lorne").joined and game.run.actor("lorne").ap == 10, "Native UI companion joins with individual AP")
	expect(game.run.actor("hero").ap == 5 - cost, "Native UI recruitment free")
	await advance_story()
	await press("接过原信")
	expect(game.run.actor("hero").inventory.get("Q-L", 0) == 1 and game.run.actor("lorne").inventory.get("Q-L", 0) == 0, "Native UI original letter transferred once")
	await press("结束交谈")
	await press("结束一天")
	await press("确认")
	expect(game.run.data.day == 2 and game.run.actor("hero").ap == 5 and game.run.actor("lorne").ap == 10, "Native UI daily settlement")
	await press("主菜单")
	await press("继续上次远征")
	expect(game.run.data.day == 2 and game.run.actor("lorne").joined, "Native UI continue restores state")
	await press("个人背包与装备")
	var salves = game.run.actor("hero").inventory.salve
	# Loaded JSON may order inventory differently; choose the visible item label, not row zero.
	var item_button: Button
	for label in game.modal_layer.find_children("*", "Label", true, false):
		if label.text.begins_with("疗伤药 ×"):
			item_button = find_button(label.get_parent(), "交接")
	expect(item_button != null and not item_button.disabled, "Salve handoff action exists")
	if item_button != null: item_button.pressed.emit()
	await process_frame
	expect(find_button(game.modal_layer, "交给洛恩") != null, "Same-cell inventory transfer exposed")
	await press("交给洛恩")
	expect(game.run.actor("hero").inventory.salve == salves - 1 and game.run.actor("lorne").inventory.salve == 2, "Native inventory handoff changes both real owners")
	await press("关闭")
	await press("旅途手记")
	expect(find_button(game.modal_layer, "合上手记") != null, "Journal opens")
	await press("合上手记")
	# Put the hero at the ferry to exercise the UI for the real extraction result.
	game.run.actor("hero").position = game.run.data.exit
	game.run.reveal(game.run.data.exit)
	game.selected_cell = game.run.data.exit
	game._refresh()
	await press("当前地块行动")
	await press("调查与交谈")
	await advance_story()
	await advance_story()
	await press("交付本次测绘副本")
	expect(game.run.data.submitted.has("Q-T"), "The ferry story submits the actual opening commission")
	await advance_story()
	await press("查看归航名单")
	await press("确认")
	expect(game.run.data.status == "extracted" and dialogue_contains("归航站的灯映在水面上"), "Confirming the ferry list plays the resulting main ending")
	await advance_story()
	expect(dialogue_contains("洛恩"), "Ending advances to the known companion's epilogue")
	await advance_story()
	expect(game.modal_layer.get_child_count() == 0 and find_button(game.ui, "查看结局剧情") != null, "Ending returns to the expedition record and can be replayed")
	await check_discovery()
	# Allow the last short audio cue to finish before testing scene teardown.
	await create_timer(0.25).timeout
	print("UI INTEGRATION: %d checks, %d failures (opening branches, legacy saves, movement, dialogue, recruitment, inventory, ending)" % [checks, failures.size()])
	game.queue_free()
	await create_timer(0.05).timeout
	quit(0 if failures.is_empty() else 1)
