extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const Story = preload("res://scripts/domain/narrative.gd")
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

func click(prefix: String) -> bool:
	var button = find_button(game.modal_layer if game.modal_layer.get_child_count() > 0 else game.ui, prefix)
	expect(not prefix.is_empty() and button != null and not button.disabled, "Clickable UI control: " + prefix)
	if prefix.is_empty() or button == null or button.disabled:
		return false
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame
	var point = button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
	await process_frame
	return true

func option_label(result: Dictionary, id: String) -> String:
	for option in result.get("options", []):
		if option.id == id:
			return str(option.text)
	expect(false, "Domain option is available: " + id)
	return ""

func compact(text: String) -> String:
	return text.replace("\n", "").replace("\r", "")

func story_text() -> Label:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	return stage.find_child("StoryText", true, false) as Label if stage != null else null

func story_page() -> Vector2i:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	var counter = stage.find_child("PageCounter", true, false) as Label if stage != null else null
	expect(counter != null and counter.is_visible_in_tree(), "Story has a visible page counter")
	if counter == null:
		return Vector2i.ZERO
	var pattern = RegEx.new()
	pattern.compile("^第 ([0-9]+) / ([0-9]+) 页$")
	var matched = pattern.search(counter.text)
	expect(matched != null, "Page counter uses 第 n / m 页")
	if matched == null:
		return Vector2i.ZERO
	var page = Vector2i(int(matched.get_string(1)), int(matched.get_string(2)))
	expect(page.x >= 1 and page.x <= page.y, "Page counter is in range")
	return page

func check_label_fit(label: Label, available: Vector2) -> void:
	var lines = label.get_line_count()
	var height = 0.0
	for line in lines:
		height += label.get_line_height(line)
	height += maxi(0, lines - 1) * label.get_theme_constant("line_spacing")
	expect(height <= available.y and height <= label.size.y, "Every body line fits its real allotted height")
	expect(label.size.x <= available.x and label.size.y <= available.y, "Body cannot grow beyond its allotted rectangle")
	expect(label.lines_skipped == 0 and label.visible_characters == -1
		and (label.max_lines_visible == -1 or label.max_lines_visible >= lines), "No body characters or lines are hidden")
	var font = label.get_theme_font("font")
	var measured = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, label.size.x,
		label.get_theme_font_size("font_size"), -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	expect(measured.x <= available.x, "Wrapped body glyphs fit the actual width")

func check_story_layout() -> void:
	var stage = game.modal_layer.get_node_or_null("StoryScreen")
	var label = story_text()
	expect(stage != null and label != null, "Story has its named body Label")
	if stage == null or label == null:
		return
	var dialogue = stage.get_node("Dialogue") as Control
	expect(dialogue != null and not dialogue is Container, "Dialogue is a fixed Control, not a growing container")
	if dialogue == null:
		return
	expect(dialogue.find_children("*", "ScrollContainer", true, false).is_empty(), "Body never uses a scroll container")
	var frame = dialogue.get_global_rect()
	expect(frame.position.y > stage.size.y * 0.65 and root.get_visible_rect().encloses(frame), "Dialogue stays within the bottom of the viewport")
	expect(frame.encloses(label.get_global_rect()), "Actual StoryText rectangle remains inside Dialogue")
	check_label_fit(label, label.size)
	var counter = stage.find_child("PageCounter", true, false) as Label
	expect(counter != null and not dialogue.is_ancestor_of(counter)
		and counter.get_global_rect().end.y < frame.position.y, "Page counter stays in the header")
	var page = story_page()
	var previous = find_button(stage, "上一页")
	var choices = stage.get_node_or_null("StoryChoices") as Control
	expect((previous != null) == (page.x > 1), "Only subsequent pages offer previous page")
	expect(find_button(stage, "下一页") == null and find_button(stage, "继续") == null, "Story advances without redundant forward buttons")
	if page.x < page.y:
		expect(choices == null, "Intermediate pages expose no decisions")
	if choices != null:
		expect(not frame.intersects(choices.get_global_rect()), "Choice column does not overlap dialogue")
	var exit = find_button(stage, "返回主菜单")
	if exit != null:
		expect(exit.get_global_rect().end.x >= stage.size.x * 0.94 and exit.position.y < stage.size.y * 0.10,
			"Return to main menu sits at the upper right")
	var leaves: Array[Control] = []
	for control in stage.find_children("*", "Control", true, false):
		if (control is Label or control is Button) and control.is_visible_in_tree():
			expect(root.get_visible_rect().encloses(control.get_global_rect()), "Story text and controls stay on screen: " + control.name)
			for other in leaves:
				if not control.is_ancestor_of(other) and not other.is_ancestor_of(control):
					expect(not control.get_global_rect().intersects(other.get_global_rect()), "Story controls do not overlap: %s / %s" % [control.name, other.name])
			leaves.append(control)

func read_to_choices(unchanged: Callable = Callable()) -> String:
	var pages = ""
	for index in range(128):
		var stage = game.modal_layer.get_node_or_null("StoryScreen")
		if stage == null:
			expect(false, "Story remains open until its choices")
			return pages
		await process_frame
		check_story_layout()
		if unchanged.is_valid():
			expect(unchanged.call(), "Reading pages does not complete a task or choose a branch")
		var label = story_text()
		if label == null:
			return pages
		pages += label.text
		if stage.has_node("StoryChoices"):
			return pages
		await advance_story()
	expect(false, "Story choices appear within the bounded page count")
	return pages

func read_current_body(revisit: bool = false, unchanged: Callable = Callable()) -> PackedStringArray:
	await process_frame
	var first = story_page()
	expect(first.x == 1 and first.y <= 128, "Body opens on page one with a bounded page count")
	var pages = PackedStringArray()
	for index in range(mini(first.y, 128)):
		check_story_layout()
		expect(story_page() == Vector2i(index + 1, first.y), "Mouse next advances exactly one page")
		if unchanged.is_valid():
			expect(unchanged.call(), "Neither page display nor navigation fires the completion callback")
		var label = story_text()
		if label == null:
			return pages
		pages.append(label.text)
		if revisit and index > 0:
			await click("上一页")
			check_story_layout()
			expect(story_page() == Vector2i(index, first.y) and story_text().text == pages[index - 1], "Previous page restores the exact earlier text")
			if unchanged.is_valid():
				expect(unchanged.call(), "Previous page cannot complete the story")
			await click_story_blank()
			check_story_layout()
			expect(story_page() == Vector2i(index + 1, first.y) and story_text().text == pages[index], "Re-reading neither loses nor changes text")
		if index + 1 < first.y:
			await click_story_blank()
	return pages

func advance_until_text(fragment: String) -> void:
	for index in range(128):
		if dialogue_contains(fragment):
			return
		if not game.modal_layer.has_node("StoryScreen"):
			break
		await advance_story()
	expect(false, "Bounded reading reaches: " + fragment)

func finish_linear_story() -> void:
	for index in range(128):
		if not game.modal_layer.has_node("StoryScreen"):
			return
		await advance_story()
	expect(false, "Linear story closes within the bounded page count")

func check_node_arrival() -> void:
	game._start_new()
	var run = game.run
	var start: String = run.data.start
	var cells = Hex.neighbors(start, run.data.tiles).filter(func(cell):
		return Hex.is_land(run.data.tiles, cell) and run.data.tiles[cell].enemies.is_empty() and run.data.tiles[cell].npc.is_empty())
	expect(not cells.is_empty(), "Arrival fixture has a safe neighboring land tile")
	if cells.is_empty():
		return
	var cell: String = cells[0]
	var title: String = run.location_name(cell)
	var names: Array = run.location_names.values()
	expect(names.size() == run.data.nodes.size() and names.size() == names.reduce(func(unique, item):
		unique[item] = true
		return unique, {}).size(), "Each land tile has its own name")
	expect(run.data.explored.has(cell) and not game.view.tile_nodes[cell].has_node("LocationName"),
		"Visible land stays unnamed before arrival")
	var village: Label3D = game.view.tile_nodes[start].get_node("LocationName")
	expect(village.text == "村庄" and village.position.x == 0 and village.position.z == 0,
		"Village name is centered on the village tile")
	game._select_cell(cell)
	expect(game.modal_layer.get_child_count() == 0, "Previewing movement cannot open a story")
	game._select_cell(cell)
	expect(game.modal_layer.has_node("StoryScreen") and contains_text(game.modal_layer, title),
		"Confirmed first arrival opens this tile's story immediately")
	var marker: Label3D = game.view.tile_nodes[cell].get_node("LocationName")
	expect(marker.text == title and marker.position.x == 0 and marker.position.z == 0,
		"The same name appears at the visited tile's center")
	await click("返回地图")
	game._continue_run()
	expect(game.view.tile_nodes[cell].get_node("LocationName").text == title and not game.modal_layer.has_node("StoryScreen"),
		"Loading preserves the visited name without reopening its story")
	run.actor("hero").ap = run.actor("hero").ap_max
	game._select_cell(start)
	game._select_cell(start)
	run.actor("hero").ap = run.actor("hero").ap_max
	game._select_cell(cell)
	game._select_cell(cell)
	expect(run.actor("hero").position == cell and not game.modal_layer.has_node("StoryScreen"),
		"Returning to an already visited tile does not reopen its story")

func check_arrival_after_victory() -> void:
	game._start_new()
	var run = game.run
	var cells = run.data.nodes.keys().filter(func(cell):
		return run.node_at(cell).kind == "battle" and not run.data.tiles[cell].enemies.is_empty())
	expect(not cells.is_empty(), "Battle arrival fixture has an ordinary encounter")
	if cells.is_empty():
		return
	var cell: String = cells[0]
	var from: String = Hex.neighbors(cell, run.data.tiles).filter(func(id): return Hex.is_land(run.data.tiles, id))[0]
	run.actor("hero").position = from
	run.reveal(from)
	game._select_actor("hero")
	game._select_cell(cell)
	game._select_cell(cell)
	expect(find_button(game.modal_layer, "开始战斗") != null and run.data.get("pending_arrival", {}).get("cell") == cell,
		"An encounter takes precedence and remembers the new tile")
	game._continue_run()
	await press("开始战斗")
	game.combat._finish("victory")
	game._finish_battle()
	game._continue_run()
	await press("继续远征")
	expect(game.modal_layer.has_node("StoryScreen") and contains_text(game.modal_layer, run.location_name(cell)),
		"After resuming from victory, continuing opens the arrival story")
	await click("返回地图")

func check_haunt_dialogue() -> void:
	game._start_new()
	var run = game.run
	var cells = run.data.nodes.keys().filter(func(cell): return run.node_at(cell).kind == "haunt")
	expect(not cells.is_empty(), "UI fixture has an unresolved haunting")
	if cells.is_empty():
		return
	var cell: String = cells[0]
	var node = run.node_at(cell)
	var event = Nodes.story(node)
	run.actor("hero").position = cell
	run.reveal(cell)
	game._select_actor("hero")
	await click("行动")
	await click("查看节点剧情")
	var introduction = await read_to_choices(func(): return not node.get("investigated", false) and node.result == "" and not run.data.peace.has(cell))
	expect(introduction.contains(event.intro), "Haunting introduction is read before investigation")
	expect(find_button(game.modal_layer, event.work) == null and find_button(game.modal_layer, event.alternative) == null,
		"Neither settlement is offered before investigation")
	await click(event.investigation_label)
	expect(node.get("investigated", false) and node.result == "" and run.data.leads.has(cell)
		and not run.data.peace.has(cell), "Real investigation click records evidence without completion or peace")
	expect(not game.modal_layer.has_node("StoryScreen/StoryChoices"), "Evidence is presented before settlement choices")
	var investigation = await read_to_choices(func(): return node.result == "" and not run.data.peace.has(cell))
	expect(investigation.contains(event.investigation), "The complete investigation is readable before deciding")
	expect(saved_run().get("nodes", {}).get(cell, {}).get("investigated", false), "Investigation click is saved")
	await click(event.alternative)
	var conclusion = await read_to_choices()
	expect(node.result == "settle_alternative" and run.data.peace.has(cell)
		and conclusion.contains(event.alternative_resolved), "Second settlement click shows its own conclusion")
	expect(find_button(game.modal_layer, event.work) == null and find_button(game.modal_layer, event.alternative) == null,
		"Resolved haunting cannot be switched through the UI")
	var found_relic: bool = not run.relic_intro().is_empty()
	await click("返回地图")
	if found_relic:
		expect(game.modal_layer.has_node("StoryScreen"), "The relic introduction follows the node conclusion")
		await finish_linear_story()
		expect(run.relic_intro().is_empty(), "Reading the relic returns to the map")
	await click("旅途手记")
	expect(contains_text(game.modal_layer, event.evidence) and contains_text(game.modal_layer, event.alternative_resolved)
		and not contains_text(game.modal_layer, event.resolved), "Journal contains actual evidence and only the chosen branch conclusion")
	await click("合上手记")

func check_personal_dialogue() -> void:
	var run = game.run
	var person = run.actor("lorne")
	run.actor("hero").position = person.position
	run.data.tiles[person.position].enemies.clear()
	run.reveal(person.position)
	game._select_actor("hero")
	game._show_npc_encounter("hero")
	await read_to_choices()
	await click("和洛恩交谈")
	expect(find_button(game.modal_layer, "邀请一起上路") == null, "Recruitment waits for the encounter introduction")
	var introduction = game.modal_layer.get_node("StoryScreen")
	await click("历史对话")
	await story_key(KEY_ESCAPE)
	expect(not game.modal_layer.has_node("StoryHistory") and game.modal_layer.get_node_or_null("StoryScreen") == introduction,
		"Escape first closes history and returns to the same conversation")
	await story_key(KEY_ESCAPE, true)
	expect(game.modal_layer.has_node("StoryScreen"), "Holding Escape cannot close a second layer")
	await story_key(KEY_ESCAPE)
	expect(game.modal_layer.get_child_count() == 0 and game.ui.visible and game.view.is_processing_unhandled_input(),
		"Escape activates End Conversation and restores map input")
	game._begin_dialogue("lorne")
	await read_to_choices()
	await click("邀请一起上路")
	expect(person.joined and "lorne" in game.moving_ids, "Actual recruitment checks the companion into the squad")
	await read_to_choices()
	var quest = game.narrative.personal_quest("hero", "lorne")
	var second = option_label(quest, "personal_b")
	var first = option_label(quest, "personal_a")
	await click(option_label(game.narrative.dialogue("hero", "lorne"), "quest"))
	expect(not game.modal_layer.has_node("StoryScreen/StoryChoices") and find_button(game.modal_layer, first) == null
		and find_button(game.modal_layer, second) == null, "Personal quest opens on full text, not choices")
	var personal_text = await read_to_choices(func():
		return str(run.data.story.lorne.get("personal_choice", "")).is_empty() and str(saved_run().get("story", {}).get("lorne", {}).get("personal_choice", "")).is_empty())
	expect(compact(personal_text).contains(compact(quest.text)), "Complete personal quest precedes both options")
	expect(find_button(game.modal_layer, first) != null and find_button(game.modal_layer, second) != null,
		"Both personal decisions are available after reading")
	var actors = run.data.actors.duplicate(true)
	var coins = run.data.lamp_coins
	await click(second)
	var response: String = Story.PERSONAL_QUESTS.lorne.personal_b.response
	var aftermath = await read_to_choices()
	expect(aftermath.contains(response) and run.data.actors == actors and run.data.lamp_coins == coins,
		"Personal choice gives its response without changing resources or actor state")
	var choice = run.data.story.lorne.get("personal_choice", "")
	expect(not str(choice).is_empty() and saved_run().get("story", {}).get("lorne", {}).get("personal_choice", "") == choice,
		"Personal choice is automatically saved without assuming its encoding")
	await click("结束交谈")
	game._personal_quest()
	await read_to_choices()
	await story_key(KEY_ESCAPE)
	expect(game.modal_layer.get_child_count() == 0, "Escape also works when End Conversation is a dialogue choice")
	await click("旅途手记")
	expect(contains_text(game.modal_layer, "洛恩 · 已同行 · 已作出个人抉择"), "Journal indicates the companion's personal decision")
	await click("合上手记")
	var path: String = run.save_path
	game.queue_free()
	await process_frame
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.run.save_path = path
	game.chosen_seed = "20261104"
	game._refresh()
	await click("继续上次远征")
	expect(game.run.data.story.lorne.get("personal_choice", "") == choice, "Reopened UI loads the saved personal decision")
	await click("行动")
	await click("查看节点剧情")
	await read_to_choices()
	await click("和洛恩交谈")
	var recalled = await read_to_choices()
	expect(recalled.contains(response), "Normal conversation recalls the decision after reopening")
	expect(find_button(game.modal_layer, first) == null and find_button(game.modal_layer, second) == null,
		"Reopened conversation cannot select either branch again")
	await click("结束交谈")

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
	await read_to_choices()
	await click("在此休整")
	expect(hero.hp == 1 + ceili(hero.hp_max * 0.25) and hero.mp == 0,
		"The node recovers the chosen resource")
	expect(find_button(game.modal_layer, "在此调息") == null and find_button(game.modal_layer, "带走一份") == null,
		"The other uses disappear after the shared supplies are spent")
	await read_to_choices()
	await click("返回地图")

	var shop_cell: String = shop_cells[0]
	hero.position = shop_cell
	run.reveal(shop_cell)
	game._select_actor("hero")
	var balance = game.ui.find_child("LampCoinBalance", true, false) as Label
	expect(balance != null and balance.text == "8", "The header displays the starting wallet balance")
	var salves: int = int(hero.inventory.salve)
	await press("行动")
	await press("查看节点剧情")
	await read_to_choices()
	await click("查看货物")
	await press("疗伤药 · 6 灯铢")
	await press("确认 · 6 灯铢")
	expect(run.data.lamp_coins == 2 and hero.inventory.salve == salves + 1, "The shop UI buys into the trader's inventory")
	expect(saved_run().get("lamp_coins") == 2, "The shop UI saves the transaction")
	balance = game.ui.find_child("LampCoinBalance", true, false) as Label
	expect(balance != null and balance.text == "2", "The header balance updates after a purchase")
	await press("返回节点")
	await read_to_choices()
	await click("返回地图")

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

func advance_story() -> void:
	await process_frame
	var story = game.modal_layer.get_node_or_null("StoryScreen")
	expect(story != null and not story.has_node("StoryChoices"), "Reading cannot skip a decision")
	if story == null or story.has_node("StoryChoices"):
		return
	check_story_layout()
	await click_story_blank()

func click_story_blank(relative_position: Vector2 = Vector2(0.76, 0.30)) -> void:
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = root.get_visible_rect().size * relative_position
		root.push_input(event, true)
	await process_frame

func story_key(key: Key, echo_event: bool = false) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		event.echo = echo_event and pressed
		root.push_input(event, true)
	await process_frame

func check_pagination_helpers() -> void:
	var bodies = ["", "短句。", "无换行的长句".repeat(160),
		"他问：‘还走吗？’她答：‘走！’雨停了；路还很长。".repeat(55),
		"  首段保留空格。\n\n" + "超长段落不能丢字，也不能靠裁剪隐藏文字。".repeat(80) + "\n\n末段必须完整保留。  ",
		"unbrokenword".repeat(90)]
	for bounds in [Vector2(240, 104), Vector2(420, 156), Vector2(720, 224)]:
		for font_size in [18, 24]:
			var label = Label.new()
			label.add_theme_font_override("font", game.ui.get_theme_font("font", "Label"))
			label.add_theme_font_size_override("font_size", font_size)
			label.add_theme_constant_override("line_spacing", 3)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.position = Vector2(-2000, -2000)
			root.add_child(label)
			for body in bodies:
				label.text = ""
				label.size = bounds
				var pages: PackedStringArray = game._story_text_pages(body, label)
				expect(not pages.is_empty() and "".join(pages) == body, "Helper preserves every character, space and newline")
				if body.is_empty():
					expect(pages == PackedStringArray([""]), "Empty text is one navigable empty page")
				elif body == "短句。":
					expect(pages.size() == 1, "A short sentence needs one page at every tested size")
				else:
					expect(pages.size() >= 2, "Long helper fixture actually exercises pagination")
				for page in pages:
					expect(body.is_empty() or not page.is_empty(), "Nonempty bodies do not gain empty pages")
					label.text = page.strip_edges()
					label.size = bounds
					check_label_fit(label, bounds)
			label.free()

func check_story_history() -> void:
	var completed = func(_choice: String): expect(false, "History cannot finish the active story")
	for index in range(12):
		game._show_story("旧对话 %d" % index, "村民", "这是先前读到的内容。".repeat(3), "road", [], [], completed, {})
	var body = "这一句话只有第一页能看到。\n\n" + "这是一段需要分多页阅读的正文。".repeat(50) + "\n\n尚未阅读的最后一句。"
	game._show_story("当前对话", "旅人", body, "road", [], [], completed, {})
	await process_frame
	var first_page = story_text().text
	var page = story_page()
	expect(page.y >= 3, "History fixture contains multiple unread pages")
	await click("历史对话")
	var history = game.modal_layer.get_node_or_null("StoryHistory")
	expect(history != null, "The story button opens a history overlay")
	if history == null:
		game._close_modal()
		return
	var history_labels = history.find_children("*", "Label", true, false).map(func(label): return label.text)
	expect("村民" in history_labels and "旅人" in history_labels
		and not contains_text(history, "旧对话 0") and not contains_text(history, "当前对话"),
		"History headings show just the speaker's name")
	expect(contains_text(history, first_page) and not contains_text(history, "尚未阅读的最后一句"),
		"History only shows pages that have appeared in the reader")
	expect(not story_text().is_visible_in_tree(), "Current dialogue does not show through the translucent history")
	var panel: PanelContainer = history.get_node("HistoryPanel")
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	expect(style.bg_color.a < 1.0 and absf(style.bg_color.r - style.bg_color.b) < 0.04,
		"History uses a translucent gray background")
	var scroll = panel.find_child("HistoryScroll", true, false) as ScrollContainer
	var bar = scroll.get_v_scroll_bar()
	var latest = scroll.scroll_vertical
	expect(latest > 0 and is_equal_approx(float(latest), bar.max_value - bar.page), "Opening history scrolls to the latest dialogue")
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = scroll.get_global_rect().get_center()
	root.push_input(wheel, true)
	await process_frame
	expect(scroll.scroll_vertical < latest, "Scrolling can move back to older dialogue")
	await click_story_blank(Vector2(0.96, 0.30))
	await story_key(KEY_TAB)
	expect(story_page() == page and history.is_ancestor_of(root.gui_get_focus_owner()),
		"Mouse and keyboard stay in the history overlay")
	await story_key(KEY_ESCAPE)
	expect(not game.modal_layer.has_node("StoryHistory") and story_page() == page and story_text().text == first_page
		and story_text().is_visible_in_tree(),
		"Escape closes history and restores the same story page")

	await click_story_blank()
	var second_page = story_text().text
	await click("上一页")
	await click("历史对话")
	history = game.modal_layer.get_node("StoryHistory")
	var current_entries = history.find_children("*", "Label", true, false).filter(func(label):
		return first_page in label.text)
	expect(current_entries.size() == 1 and second_page in current_entries[0].text,
		"Rereading an earlier page leaves one entry with both viewed pages")
	await click("关闭")
	expect(not game.modal_layer.has_node("StoryHistory") and story_page() == page,
		"The close button also keeps the reader on its current page")
	game._close_modal()

func check_story_pagination() -> void:
	var calls = {"count": 0, "choice": ""}
	var completed = func(choice: String):
		calls.count += 1
		calls.choice = choice
		game._close_modal()
	game._show_story("单页", "旁白", "短句。", "road", [], [], completed, {})
	await process_frame
	check_story_layout()
	expect(story_page() == Vector2i(1, 1) and story_text().text == "短句。", "Short story is a complete single page")
	await story_key(KEY_ENTER, true)
	expect(calls.count == 0, "Key repeat cannot advance or complete a story")
	await story_key(KEY_ENTER)
	expect(calls.count == 1 and calls.choice == "" and not game.modal_layer.has_node("StoryScreen"), "Enter completes a single-page story exactly once")

	var old_status = game.run.data.status
	game.run.data.status = "won"
	var body: String = game.narrative.main_ending().text
	game.run.data.status = old_status
	var before = game.run.data.duplicate(true)
	calls.count = 0
	game._show_story("长文", "不会混入正文的说话者", body, "road", [], [], completed, {})
	var pages = await read_current_body(true, func(): return calls.count == 0 and game.run.data == before)
	expect(pages.size() >= 2 and compact("".join(pages)) == compact(body), "Every long-story word is read in order without repeating the speaker")
	if pages.size() >= 2:
		await click("上一页")
		await story_key(KEY_ENTER)
		check_story_layout()
		expect(story_page() == Vector2i(pages.size(), pages.size()) and story_text().text == pages[-1]
			and calls.count == 0, "Enter turns one page without completing the story")
	await click_story_blank()
	expect(calls.count == 1, "Only explicit completion on the last page invokes the linear callback")

	calls.count = 0
	game._show_story("空白点击", "旁白", "短句。", "road", [], [], completed, {})
	await process_frame
	await click_story_blank()
	expect(calls.count == 1, "Blank-space click still completes a final linear page")

	calls.count = 0
	var options = [{"id": "finish", "text": "确认完成"}, {"id": "wait", "text": "暂不完成"}]
	game._show_story("长文选项", "旁白", body, "road", [], options, completed, {})
	await process_frame
	await click_story_blank()
	expect(story_page().x == 2 and calls.count == 0 and find_button(game.modal_layer, "确认完成") == null,
		"Blank click turns a non-final page without exposing or selecting a choice")
	await click("上一页")
	var choice_pages = await read_current_body(true, func(): return calls.count == 0 and game.run.data == before)
	expect(choice_pages.size() >= 2 and compact("".join(choice_pages)) == compact(body), "Choice story preserves its full body before decisions")
	expect(game.modal_layer.has_node("StoryScreen/StoryChoices") and find_button(game.modal_layer, "确认完成") != null
		and find_button(game.modal_layer, "暂不完成") != null and calls.count == 0, "Only the final page exposes both choices, without choosing")
	await click("上一页")
	expect(not game.modal_layer.has_node("StoryScreen/StoryChoices") and find_button(game.modal_layer, "确认完成") == null,
		"Returning from the final page hides and removes actionable choices")
	await click_story_blank()
	await click_story_blank()
	expect(calls.count == 0, "Blank click on a decision page cannot skip its options")
	var choice_position = find_button(game.modal_layer, "确认完成").get_global_rect().get_center()
	await click("历史对话")
	await click_story_blank(choice_position / root.get_visible_rect().size)
	expect(calls.count == 0 and game.modal_layer.has_node("StoryHistory"), "A click cannot select a story choice through history")
	await click("关闭")
	await click("确认完成")
	expect(calls.count == 1 and calls.choice == "finish", "Actual choice click invokes exactly its callback")

	calls.count = 0
	game._show_story("续读", "旁白", body, "road", [], [], completed, {}, Color.WHITE, 1)
	await process_frame
	check_story_layout()
	expect(story_page().x == 2 and story_text().text == pages[1] and calls.count == 0, "Optional final page_index argument resumes the requested page")
	game._close_modal()
	await check_pagination_helpers()

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var test_save = "user://veylodan-ui-%d.json" % OS.get_process_id()
	game.run.save_path = test_save
	game.chosen_seed = "20261104"
	game._refresh()
	expect(find_button(game.ui, "继续上次远征") == null, "A main menu with no save does not show a resume button")
	await press("开始新远征")
	expect(dialogue_contains("维洛丹") and not dialogue_contains("伊文洛"), "Opening introduces only the public gods")
	expect(story_owns_focus(), "Opening retains the story interface and focus")
	await story_key(KEY_ESCAPE)
	expect(dialogue_contains("维洛丹"), "Escape leaves an opening scene without an End Conversation action in place")
	await advance_until_text("你醒了")
	expect(dialogue_contains("你醒了"), "Reading reaches the hero waking without assuming a page count")
	await click("历史对话")
	var history = game.modal_layer.get_node("StoryHistory")
	expect(contains_text(history, "维洛丹的人们") and contains_text(history, "你醒了"),
		"History carries over from the world introduction into the village")
	await click("关闭")
	await advance_until_text("愿你一路平安")
	expect(dialogue_contains("愿你一路平安"), "The villager sends off the traveler with supplies")
	await finish_linear_story()
	expect(game.modal_layer.get_child_count() == 0 and game.run.actor("hero").name == "旅人", "Departure enters the map as the fixed traveler")
	expect(saved_run().get("actors", {}).get("hero", {}).get("inventory", {}).get("salve") == 3, "Village supplies are saved on departure")
	await check_story_history()
	await check_story_pagination()
	await check_personal_dialogue()
	await check_backpack_use()
	await check_node_dialogs()
	await check_node_arrival()
	await check_arrival_after_victory()
	await check_haunt_dialogue()
	expect(game._expedition_objective() == "踏出旅程的第一步", "HUD shows the departure objective")
	var chapter_run = game.run
	var pages: Array = game._chapter_pages()
	expect(pages.size() == 4, "Main story retains four chapters")
	await click("旅途手记")
	for page in pages:
		expect(not contains_text(game.modal_layer, page[0]), "Unread chapter is absent from the journal: " + page[0])
	await click("合上手记")
	for cell in chapter_run.data.tiles:
		chapter_run.data.explored[cell] = true
	chapter_run.actor("lorne").position = chapter_run.actor("hero").position
	expect(chapter_run.join_companion("lorne").ok, "Recruit a non-hero chapter visitor")
	game.selected_id = "lorne"
	var before = chapter_run.data.duplicate(true)
	expect(not game._show_chapter() and chapter_run.data == before and game.modal_layer.get_child_count() == 0,
		"Selected companion cannot trigger the hero's chapter even beside him")
	game.selected_id = "hero"
	chapter_run.actor("hero").hp = 0
	before = chapter_run.data.duplicate(true)
	expect(not game._show_chapter() and chapter_run.data == before and game.modal_layer.get_child_count() == 0,
		"Selected wounded hero cannot trigger a chapter")
	chapter_run.actor("hero").hp = chapter_run.actor("hero").hp_max
	expect(game._show_chapter() and game._expedition_objective() == "踏出旅程的第一步", "Current objective is stable while a chapter is displayed")
	var next_objectives = ["帮助被亡灵困扰的地方", "查清谁在延长战争", "找到战神的驻地", "击败战神卡德兰"]
	for index in next_objectives.size():
		var objective: String = game._expedition_objective()
		var chapter_pages = await read_current_body(true, func():
			return int(chapter_run.data.chapter) == index and game._expedition_objective() == objective and int(saved_run().get("chapter", 0)) == index)
		expect(compact("".join(chapter_pages)) == compact(pages[index][1]), "Chapter reading preserves its entire body before completion")
		await click_story_blank()
		expect(int(chapter_run.data.chapter) == index + 1 and game._expedition_objective() == next_objectives[index],
			"HUD changes only after confirming the final chapter page")
	game._close_modal()
	game._refresh()
	await click("旅途手记")
	for page in pages:
		expect(contains_text(game.modal_layer, page[0]) and contains_text(game.modal_layer, page[1]),
			"Journal preserves the read chapter and its witness record: " + page[0])
	await click("合上手记")
	chapter_run.data.status = "won"
	game._refresh()
	await process_frame
	var ending: String = game.narrative.main_ending().text
	var epilogue: String = game.narrative.character_ending("lorne").text
	expect(not contains_text(game.ui, ending) and not contains_text(game.ui, epilogue), "Summary is an overview, not long ending or companion prose")
	var summary_action = find_button(game.ui, "查看结局剧情")
	expect(summary_action != null, "Summary offers the story reader")
	if summary_action != null:
		expect(summary_action.get_parent().find_children("*", "ScrollContainer", true, false).is_empty(), "Summary has no long-text scrolling record")
	for label in ["查看结局剧情", "返回主菜单"]:
		var button = find_button(game.ui, label)
		expect(button != null and root.get_visible_rect().encloses(button.get_global_rect()), "Ending keeps summary action in view: " + label)
	await click("查看结局剧情")
	var ending_before = chapter_run.data.duplicate(true)
	var ending_pages = await read_current_body(true, func(): return chapter_run.data == ending_before)
	expect(ending_pages.size() >= 2 and compact("".join(ending_pages)) == compact(ending), "Main ending is read completely across at least two pages")
	expect("".join(ending_pages).ends_with(ending.split("\n\n")[-1]), "The main ending's final paragraph is actually reached")
	await click_story_blank()
	var epilogue_pages = await read_current_body(true, func(): return chapter_run.data == ending_before)
	expect(compact("".join(epilogue_pages)) == compact(epilogue), "The companion's complete epilogue is read in the same paginated reader")
	await click_story_blank()
	expect(not game.modal_layer.has_node("StoryScreen") and game.ui.visible, "Completing the last epilogue returns to the summary")
	await click("查看结局剧情")
	expect(story_page().x == 1, "Reopening the ending starts on its first page")
	await click("返回远征记录")
	await create_timer(0.25).timeout
	print("UI INTEGRATION: %d checks, %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(test_save + suffix):
			DirAccess.remove_absolute(test_save + suffix)
	quit(0 if failures.is_empty() else 1)
