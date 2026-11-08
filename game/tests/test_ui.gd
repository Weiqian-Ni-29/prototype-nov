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

func consumable_row(item_name: String) -> Node:
	for label in game.modal_layer.find_children("*", "Label", true, false):
		if label.text.begins_with(item_name + " ×"):
			return label.get_parent()
	return null

func use_from_backpack(item_name: String) -> void:
	var row = consumable_row(item_name)
	var use = find_button(row, "使用") if row != null else null
	expect(use != null and not use.disabled, "Backpack can use " + item_name)
	if use != null and not use.disabled:
		use.pressed.emit()
	await process_frame

func select_consumable(item_name: String) -> void:
	var row = consumable_row(item_name)
	expect(row != null, "Consumable appears in the backpack: " + item_name)
	if row != null:
		var scroll: ScrollContainer = row.get_parent().get_parent().get_parent()
		scroll.ensure_control_visible(row)
		await process_frame
		for pressed in [true, false]:
			var event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = row.get_global_rect().get_center()
			root.push_input(event, true)
	await process_frame

func check_node_dialogs() -> void:
	game._start_new()
	var run = game.run
	var hero = run.actor("hero")
	hero.hp = 1
	hero.mp = 0
	await press("行动")
	expect(find_button(game.modal_layer, "休整") == null, "Ordinary tiles have no general rest command")
	await press("关闭")

	var rest_cells = run.data.nodes.keys().filter(func(cell): return run.node_at(cell).kind == "rest")
	var shop_cells = run.data.nodes.keys().filter(func(cell): return run.node_at(cell).kind == "trade")
	expect(not rest_cells.is_empty() and not shop_cells.is_empty(), "This seed has rest and trade nodes")
	if rest_cells.is_empty() or shop_cells.is_empty():
		return
	var rest_cell: String = rest_cells[0]
	hero.position = rest_cell
	run.reveal(rest_cell)
	game._select_actor("hero")
	await press("行动")
	await press("查看节点剧情")
	var stage = game.modal_layer.get_node("StoryScreen")
	var scene: TextureRect = stage.get_child(0)
	expect(scene.texture.resource_path.ends_with("/" + game._story_scene_at(rest_cell) + ".png"),
		"The node story uses the occupied tile's terrain art")
	await press("在此休整")
	expect(hero.hp == 1 + ceili(hero.hp_max * 0.25) and hero.mp == 0,
		"The node recovers the chosen resource")
	expect(find_button(game.modal_layer, "在此调息") == null and find_button(game.modal_layer, "带走一份") == null,
		"The other uses disappear after the shared supplies are spent")
	await press("返回地图")

	var shop_cell: String = shop_cells[0]
	hero.position = shop_cell
	run.reveal(shop_cell)
	game._select_actor("hero")
	var salves: int = int(hero.inventory.salve)
	await press("行动")
	await press("查看节点剧情")
	await press("查看货物")
	await press("疗伤药 · 6 灯铢")
	expect(run.data.lamp_coins == 2 and hero.inventory.salve == salves + 1, "The shop UI buys into the trader's inventory")
	expect(saved_run().get("lamp_coins") == 2, "The shop UI saves the transaction")
	await press("返回节点")
	await press("返回地图")

func check_backpack_use() -> void:
	game._start_new()
	var run = game.run
	var hero = run.actor("hero")
	var lorne = run.actor("lorne")
	var tide = run.actor("tide")
	var away: String = tide.position
	lorne.position = hero.position
	tide.position = hero.position
	run.join_companion("lorne")
	run.join_companion("tide")
	tide.position = away
	lorne.inventory.salve = 2
	lorne.hp = 1
	var effort = lorne.ap
	var hero_salves = hero.inventory.salve
	game._select_actor("lorne")
	await press("背包")
	var row = consumable_row("疗伤药")
	expect(row != null and contains_text(row, "持有者 · 洛恩") and find_button(row, "交接") != null,
		"Consumable row labels the actual holder and retains handoff")
	await select_consumable("疗伤药")
	expect(row.get_parent().get_theme_stylebox("panel").border_color == game.gold
		and contains_text(game.modal_layer, "恢复 45 HP") and lorne.inventory.salve == 2,
		"Clicking the item row highlights it and explains its use without consuming it")
	await select_consumable("澄露")
	expect(row.get_parent().get_theme_stylebox("panel").border_color != game.gold
		and contains_text(game.modal_layer, "恢复 30 MP"), "Selecting another consumable replaces the highlight and description")
	await use_from_backpack("疗伤药")
	var target = game.modal_layer.find_children("*", "OptionButton", true, false)[0]
	expect(target.get_item_text(target.selected).begins_with("洛恩") and target.item_count == 2,
		"Backpack use defaults to the holder and only offers local characters")
	await press("确认使用 疗伤药")
	expect(lorne.hp == 46 and lorne.inventory.salve == 1 and hero.inventory.salve == hero_salves and lorne.ap == effort,
		"Using from Lorne's bag heals him and consumes only his item without spending effort")
	expect(saved_run().get("actors", {}).get("lorne", {}).get("hp") == 46 and consumable_row("疗伤药") != null,
		"Successful use auto-saves and returns to the refreshed backpack")
	expect(contains_text(game.modal_layer, "恢复 45 HP"), "The item remains selected after using it when another remains")
	hero.hp = 0
	await use_from_backpack("疗伤药")
	target = game.modal_layer.find_children("*", "OptionButton", true, false)[0]
	for i in target.item_count:
		if target.get_item_text(i).begins_with("旅人"):
			target.select(i)
			break
	await press("确认使用 疗伤药")
	expect(hero.hp == 45 and lorne.inventory.salve == 0, "The same backpack flow rescues a downed local ally")
	await use_from_backpack("澄露")
	await press("确认使用 澄露")
	expect(contains_text(game.modal_layer, "没有可恢复的资源") and lorne.inventory.ether == 1,
		"An ineligible target gives visible feedback and keeps the consumable")
	await press("返回背包")
	lorne.mp = 5
	await use_from_backpack("澄露")
	await press("确认使用 澄露")
	expect(lorne.mp == 35 and lorne.inventory.ether == 0 and lorne.ap == effort,
		"Backpack ether restores magic from the holder's inventory without spending effort")
	await press("关闭")
	game._select_actor("hero")
	await press("背包")
	expect(consumable_row("营地木料") == null, "New expeditions have no construction material")
	await select_consumable("旅途干粮")
	expect(contains_text(game.modal_layer, "可用于分享与任务"), "Food can be selected and inspected like every consumable")
	await press("关闭")

func saved_run() -> Dictionary:
	var checkpoint = JSON.parse_string(FileAccess.get_file_as_string(game.run.save_path))
	return checkpoint if checkpoint is Dictionary else {}

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

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.run.save_path = "user://veylodan-ui.json"
	game.chosen_seed = "20261104"
	await press("开始新远征")
	expect(dialogue_contains("维洛丹") and not dialogue_contains("伊文洛"), "Opening introduces only the public gods")
	expect(story_owns_focus(), "Opening retains the story interface and focus")
	await advance_story()
	await advance_story()
	expect(dialogue_contains("你醒了"), "The next page begins when the hero opens his eyes")
	for i in range(6):
		await advance_story()
	expect(dialogue_contains("愿你一路平安"), "The villager sends off the traveler with supplies")
	await advance_story()
	expect(game.modal_layer.get_child_count() == 0 and game.run.actor("hero").name == "旅人", "Departure enters the map as the fixed traveler")
	expect(saved_run().get("actors", {}).get("hero", {}).get("inventory", {}).get("salve") == 3, "Village supplies are saved on departure")
	var run = game.run
	var lorne = run.actor("lorne")
	run.actor("hero").position = lorne.position
	run.reveal(lorne.position)
	game._show_npc_encounter("hero")
	if find_button(game.modal_layer, "和洛恩交谈") == null:
		await advance_story()
	await press("和洛恩交谈")
	expect(find_button(game.modal_layer, "邀请一起上路") == null, "Choices wait for the encounter introduction")
	await advance_story()
	await press("邀请一起上路")
	expect(lorne.joined and "lorne" in game.moving_ids, "The recruited character is checked into the current squad")
	game._close_modal()
	await check_backpack_use()
	await check_node_dialogs()
	expect(game._expedition_objective() == "踏出旅程的第一步", "HUD shows the departure objective")
	var chapter_run = game.run
	for cell in chapter_run.data.tiles:
		chapter_run.data.explored[cell] = true
	expect(game._show_chapter() and game._expedition_objective() == "踏出旅程的第一步", "Current objective is stable while a chapter is displayed")
	var next_objectives = ["帮助被亡灵困扰的地方", "查清谁在延长战争", "找到亡军的集结地", "击败战神卡德兰"]
	for objective in next_objectives:
		await advance_story()
		expect(game._expedition_objective() == objective, "HUD changes after each main story scene")
	await create_timer(0.25).timeout
	print("UI INTEGRATION: %d checks, %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
