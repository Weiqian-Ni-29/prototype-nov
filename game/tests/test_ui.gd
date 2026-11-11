extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const InventoryPage = preload("res://scripts/presentation/inventory_page.gd")
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

func consumable_slot(item_name: String) -> Button:
	var tabs = game.modal_layer.find_child("InventoryTabs", true, false)
	if tabs != null:
		for slot in tabs.get_child(0).grid.get_children():
			if slot is Button and slot.tooltip_text == item_name:
				return slot
	return null

func use_from_backpack(item_name: String) -> void:
	await select_consumable(item_name)
	var use = find_button(game.modal_layer, "使用")
	expect(use != null and not use.disabled, "Backpack can use " + item_name)
	if use != null and not use.disabled:
		use.pressed.emit()
	await process_frame

func select_consumable(item_name: String) -> void:
	var slot = consumable_slot(item_name)
	expect(slot != null, "Consumable appears in the backpack: " + item_name)
	if slot != null:
		var scroll: ScrollContainer = slot.get_parent().get_parent()
		scroll.ensure_control_visible(slot)
		await process_frame
		for pressed in [true, false]:
			var event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = slot.get_global_rect().get_center()
			root.push_input(event, true)
	await process_frame

func click(prefix: String) -> bool:
	var button = find_button(game.modal_layer if game.modal_layer.get_child_count() > 0 else game.ui, prefix)
	expect(not prefix.is_empty() and button != null and not button.disabled, "Clickable UI control: " + prefix)
	if prefix.is_empty() or button == null or button.disabled:
		return false
	await click_button(button)
	return true

func click_button(button: Button) -> void:
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

func check_reward_art() -> void:
	var pictures := {}
	for catalog in [Relics.DATA, Gear.DATA]:
		for id in catalog:
			var texture := InventoryPage.icon(id)
			expect(texture != null and not str(catalog[id].story).is_empty(), id + " has a picture and story")
			if texture == null:
				continue
			var key := str(texture.region) if texture is AtlasTexture else texture.resource_path
			expect(not pictures.has(key), id + " uses its own illustration")
			pictures[key] = true
	for level in range(1, Gear.MAX_LEVEL + 1):
		var art := InventoryPage.item_image(InventoryPage.icon("trail_blade"), level)
		expect(art.material is ShaderMaterial and int(art.material.get_shader_parameter("level")) == level,
			"Equipment illustration receives its enhancement level")
		art.free()

func select_story_reward(title: String) -> void:
	var rewards = game.modal_layer.find_child("RewardItems", true, false)
	expect(rewards != null, "The reward list is visible")
	if rewards == null:
		return
	for child in rewards.find_children("*", "Button", true, false):
		var button := child as Button
		if button.accessibility_name.begins_with(title + " ×"):
			await click_button(button)
			expect(button.button_pressed, "Reward selection stays highlighted")
			return
	expect(false, "The reward list contains " + title)

func wait_for_map_arrival() -> void:
	var deadline = Time.get_ticks_msec() + 5000
	while game.map_traveling and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(not game.map_traveling, "Map travel finishes")

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
	run.data.steps_today = run.STEPS_PER_DAY - 1
	var previous_volume: float = game.sound.volume
	game.sound.set_volume(0.65, false)
	game._select_cell(cell)
	expect(game.modal_layer.get_child_count() == 0, "Previewing movement cannot open a story")
	game._select_cell(cell)
	expect(game.view.dolls.hero.is_moving() and game.view.visible and game.modal_layer.get_child_count() == 0,
		"Confirming the move leaves the map visible while the hero is walking")
	game._select_cell(start)
	expect(game.selected_cell == cell and game.move_target.is_empty(), "A click during travel cannot replace the arrival")
	await wait_for_map_arrival()
	expect(not game.view.dolls.hero.is_moving() and game.modal_layer.has_node("StoryScreen") and contains_text(game.modal_layer, title),
		"The first-arrival story opens once the hero has finished moving")
	expect(run.data.day == 2 and game.day_transition.get_child_count() == 0 and not game.sound.cache.has("day"),
		"The last step advances the day without a notice or chime in the arrival story")
	var marker: Label3D = game.view.tile_nodes[cell].get_node("LocationName")
	expect(marker.text == title and marker.position.x == 0 and marker.position.z == 0,
		"The same name appears at the visited tile's center")
	await click("返回地图")
	expect(game.day_transition.has_node("MapNotice") and contains_text(game.day_transition, "精力已恢复")
		and game.sound.cache.get("day") == game.sound.DAY_CHIME,
		"Returning to the map shows the full notice and plays the selected chime")
	var sound_count: int = game.sound.voice_index
	game._refresh()
	await process_frame
	expect(game.sound.voice_index == sound_count, "Refreshing the map does not replay the day chime")
	game.sound.set_volume(previous_volume, false)
	village = game.view.tile_nodes[start].get_node("LocationName")
	for label in [village, marker]:
		expect(label.is_visible_in_tree() and label.outline_render_priority > game.view.FOG_REVEAL_PRIORITY
			and label.render_priority > label.outline_render_priority,
			"Visited map name and outline draw above the transparent terrain and fog: " + label.text)
	game._continue_run()
	expect(game.view.tile_nodes[cell].get_node("LocationName").text == title and not game.modal_layer.has_node("StoryScreen"),
		"Loading preserves the visited name without reopening its story")
	game._select_cell(start)
	game._select_cell(start)
	await wait_for_map_arrival()
	game._select_cell(cell)
	game._select_cell(cell)
	await wait_for_map_arrival()
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
	var event = Nodes.story(run.node_at(cell))
	var from: String = Hex.neighbors(cell, run.data.tiles).filter(func(id): return Hex.is_land(run.data.tiles, id))[0]
	run.data.tiles[cell].hidden = true
	run.data.tiles[cell].discovered_enemy = false
	run.actor("hero").position = from
	run.data.steps_today = run.STEPS_PER_DAY - 1
	run.reveal(from)
	game._select_actor("hero")
	game._select_cell(cell)
	game._select_cell(cell)
	expect(game.modal_layer.get_child_count() == 0, "The encounter does not interrupt movement")
	await wait_for_map_arrival()
	expect(game.modal_layer.has_node("StoryScreen") and find_button(game.modal_layer, "开始战斗") == null
		and run.data.get("pending_arrival", {}).get("cell") == cell,
		"Arriving at an encounter opens its story before formation and remembers the new tile")
	expect(run.data.day == 2 and game.day_transition.get_child_count() == 0,
		"A day change on an encounter leaves the story clear")
	var pending: Dictionary = run.data.pending_battle.duplicate(true)
	expect(pending.origin == from and pending.ambush, "The encounter records the original retreat tile and ambush")
	game._continue_run()
	expect(game.day_transition.get_child_count() == 0, "Loading does not replay a prior day change")
	var introduction = await read_to_choices(func(): return game.combat == null and run.data.pending_battle == pending)
	expect(compact(introduction).contains(compact(event.intro)) and introduction.contains("抢先扑了出来"),
		"Resuming an encounter presents its complete node introduction and ambush before formation")
	await click("选择出战阵容")
	expect(not game.modal_layer.has_node("StoryScreen") and run.data.pending_battle == pending,
		"Confirming the introduction preserves the encounter and opens formation")
	await press("开始战斗")
	game.combat._finish("victory")
	game._finish_battle()
	game._continue_run()
	await press("继续远征")
	expect(game.modal_layer.has_node("StoryScreen") and contains_text(game.modal_layer, run.location_name(cell)),
		"After resuming from victory, continuing opens the arrival story")
	await click("返回地图")
	expect(game.day_transition.get_child_count() == 0, "Returning to the map after loading does not replay the day notice")

func check_manual_encounter_intro() -> void:
	game._start_new()
	var run = game.run
	var cells = run.data.nodes.keys().filter(func(cell):
		return run.node_at(cell).kind == "elite" and not run.data.tiles[cell].enemies.is_empty())
	expect(not cells.is_empty(), "Manual encounter fixture has an elite node")
	if cells.is_empty():
		return
	var cell: String = cells[0]
	var event = Nodes.story(run.node_at(cell))
	run.actor("hero").position = cell
	run.reveal(cell)
	run.data.tiles[cell].discovered_enemy = true
	game._select_actor("hero")
	await click("行动")
	await click("查看遭遇剧情")
	var introduction = await read_to_choices()
	expect(compact(introduction).contains(compact(event.intro)) and find_button(game.modal_layer, "开始战斗") == null,
		"Opening a known elite encounter from the action menu reads its story first")
	await click("选择出战阵容")
	expect(find_button(game.modal_layer, "开始战斗") != null, "The elite introduction opens formation")

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
	expect(node.get("investigated", false) and node.result == ""
		and not run.data.peace.has(cell), "Real investigation click opens the next stage without resolving the haunt")
	expect(not game.modal_layer.has_node("StoryScreen/StoryChoices"), "Evidence is presented before settlement choices")
	var investigation = await read_to_choices(func(): return node.result == "" and not run.data.peace.has(cell))
	expect(investigation.contains(event.investigation), "The complete investigation is readable before deciding")
	expect(saved_run().get("nodes", {}).get(cell, {}).get("investigated", false), "Investigation click is saved")
	await click(event.alternative)
	var found_relic: bool = not run.relic_intro().is_empty()
	var conclusion: String
	if found_relic:
		conclusion = "".join(await read_current_body())
		await advance_story()
		expect(game.modal_layer.has_node("StoryRewards"), "The reward screen follows the completed haunting story")
	else:
		conclusion = await read_to_choices()
	expect(node.result == "settle_alternative" and run.data.peace.has(cell)
		and conclusion.contains(event.alternative_resolved), "Second settlement click shows its own conclusion")
	expect(find_button(game.modal_layer, event.work) == null and find_button(game.modal_layer, event.alternative) == null,
		"Resolved haunting cannot be switched through the UI")
	await click("返回地图")
	if found_relic:
		expect(run.relic_intro().is_empty(), "The reward details acknowledge the relic introduction")

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
	var initial = game.narrative.dialogue("hero", "lorne")
	var join_line = option_label(initial, "join")
	expect((find_button(game.modal_layer, join_line) != null) == (story_page().x == story_page().y),
		"Recruitment choices only appear with the final introduction page")
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
	game._story_choice("unavailable_reply")
	expect(contains_text(game.modal_layer, "现在无法这样做"), "A rejected reply shows a separate gameplay notice")
	await click("知道了")
	var introduction_text = await read_to_choices()
	expect(compact(introduction_text) == compact(initial.text) and story_speaker() == "洛恩",
		"Choices appear beside the NPC's final line without an extra prompt")
	await click(join_line)
	expect(story_speaker() == "旅人" and dialogue_contains(join_line) and not person.joined,
		"The player speaks the selected line before the recruitment is applied")
	await click("历史对话")
	expect(contains_text(game.modal_layer.get_node("StoryHistory"), join_line), "The selected reply appears in dialogue history")
	await click("关闭")
	await click_story_blank()
	expect(person.joined and person.position == run.actor("hero").position, "Actual recruitment adds the companion to the party")
	var acceptance = await read_to_choices()
	expect(story_speaker() == "洛恩" and acceptance.contains(Story.CHARACTER_BEHAVIOR.lorne[1]), "Recruitment receives an answer from the companion")
	var before_past = run.data.duplicate(true)
	await click(option_label(game.narrative.dialogue("hero", "lorne"), "past"))
	expect(story_speaker() == "旅人", "The player asks about the past before receiving it")
	await click_story_blank()
	var past = await read_to_choices()
	expect(compact(past).contains(compact(Story.BACKGROUNDS.lorne)) and story_speaker() == "洛恩",
		"The background is readable in its own paginated response")
	before_past.story.lorne.codex_past_read = true
	before_past.transaction = run.data.transaction
	expect(run.data == before_past and saved_run().story.lorne.codex_past_read,
		"Reading the background records it without spending resources or choosing a branch")
	var save_after_past = saved_run()
	await click(option_label(game.narrative.dialogue("hero", "lorne"), "leave"))
	await click_story_blank()
	expect(game.modal_layer.get_child_count() == 0, "The spoken farewell closes the background conversation")
	expect(run.data == before_past and saved_run() == save_after_past, "Leaving the completed background dialogue changes nothing further")
	game._begin_dialogue("lorne")
	await read_to_choices()
	var quest = game.narrative.personal_quest("hero", "lorne")
	var second = option_label(quest, "personal_b")
	var first = option_label(quest, "personal_a")
	await click(option_label(game.narrative.dialogue("hero", "lorne"), "quest"))
	await click_story_blank()
	expect(story_page().x == 1 and story_speaker() == "洛恩", "The personal conversation opens with the NPC's first page")
	var personal_text = await read_to_choices(func():
		return str(run.data.story.lorne.get("personal_choice", "")).is_empty() and str(saved_run().get("story", {}).get("lorne", {}).get("personal_choice", "")).is_empty())
	expect(compact(personal_text).contains(compact(quest.text)), "Complete personal quest precedes both options")
	expect(find_button(game.modal_layer, first) != null and find_button(game.modal_layer, second) != null,
		"Both personal decisions are available after reading")
	var actors = run.data.actors.duplicate(true)
	var coins = run.data.lamp_coins
	await click(second)
	expect(story_speaker() == "旅人" and dialogue_contains(second) and str(run.data.story.lorne.get("personal_choice", "")).is_empty(),
		"The chosen personal reply is spoken before its outcome")
	await click_story_blank()
	var response: String = Story.PERSONAL_QUESTS.lorne.personal_b.response
	var aftermath = await read_to_choices()
	expect(story_speaker() == "洛恩" and aftermath.contains(response) and run.data.actors == actors and run.data.lamp_coins == coins,
		"Personal choice gives its response without changing resources or actor state")
	var choice = run.data.story.lorne.get("personal_choice", "")
	expect(not str(choice).is_empty() and saved_run().get("story", {}).get("lorne", {}).get("personal_choice", "") == choice,
		"Personal choice is automatically saved without assuming its encoding")
	await click("结束交谈")
	game._personal_quest()
	await read_to_choices()
	await story_key(KEY_ESCAPE)
	expect(game.modal_layer.get_child_count() == 0, "Escape can close a completed personal conversation")
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
	expect(not recalled.contains(response), "Normal conversation does not replay the completed decision")
	await click(option_label(game.narrative.dialogue("hero", "lorne"), "quest"))
	await click_story_blank()
	var review = await read_to_choices()
	expect(review.contains(response), "The separate review keeps the decision after reopening")
	expect(find_button(game.modal_layer, first) == null and find_button(game.modal_layer, second) == null,
		"Reopened conversation cannot select either branch again")
	var farewell = option_label(game.narrative.personal_quest("hero", "lorne"), "leave")
	var review_transaction = game.run.data.transaction
	await click(farewell)
	expect(story_speaker() == "旅人" and dialogue_contains(farewell), "Farewell is the player's line")
	await click_story_blank()
	expect(game.modal_layer.get_child_count() == 0, "Finishing a farewell returns to the map")
	expect(game.run.data.transaction == review_transaction, "Finishing a review of a saved personal decision does not save again")
	var saved_story = saved_run()
	await click("角色")
	await click("洛恩")
	await click("故事")
	expect(find_button(game.modal_layer, "阅读 · 过去的事") != null, "The read background is available after reloading")
	await click("阅读 · 同行以后")
	var archive_pages = await read_current_body(true)
	expect(compact("".join(archive_pages)) == compact(response), "The codex records only the selected branch")
	await click("返回角色图鉴")
	expect(game.character_codex_state.actor == "lorne" and game.character_codex_state.tab == 3,
		"Closing the reader returns to the same character and tab")
	await story_key(KEY_ESCAPE)
	expect(game.modal_layer.get_child_count() == 0 and saved_run() == saved_story, "Reading a codex entry does not modify the save")

func check_character_codex() -> void:
	game._start_new()
	var run = game.run
	var source: String = run.actor("hero").position
	var neighbor: String = Hex.neighbors(source, run.data.tiles).filter(func(cell): return Hex.is_land(run.data.tiles, cell))[0]
	game._select_cell(neighbor)
	var map_selection: String = game.selected_cell
	var original_plan: String = game.move_target
	var old_transaction: int = run.data.transaction
	await click("角色")
	var codex = game.modal_layer.get_node_or_null("CharacterCodex")
	expect(codex != null and codex.find_child("CodexActor_hero", true, false) != null
		and codex.find_children("CodexUnknown*", "Button", true, false).size() == 25,
		"At the start the codex displays the traveler and 25 anonymous slots")
	expect(not contains_text(codex, "死神") and not contains_text(codex, "伊文洛"), "The traveler profile hides the final revelation")
	await click("见过未加入")
	expect(contains_text(codex, "暂无角色"), "An empty filter displays its own empty state")
	var list_view = codex.find_child("CodexListView", true, false) as Button
	var grid_view = codex.find_child("CodexGridView", true, false) as Button
	expect(list_view.text.is_empty() and grid_view.text.is_empty() and list_view.icon != null and grid_view.icon != null
		and list_view.get_parent() == grid_view.get_parent()
		and is_equal_approx(list_view.get_global_rect().end.x, grid_view.get_global_rect().position.x),
		"The view switch is icon-only and the segments share a seam")
	await click_button(grid_view)
	expect(grid_view.button_pressed and not list_view.button_pressed and game.character_codex_state.filter == 2
		and codex.roster_empty.visible, "Switching to the grid preserves the empty filter and selects one segment")
	await click("全部")
	var grid = codex.find_child("CodexRoster", true, false) as GridContainer
	var unknown = grid.find_child("CodexUnknown", false, false) as Button
	expect(grid.columns == 5 and grid.find_children("CodexUnknown*", "Button", false, false).size() == 25,
		"The five-column grid shows all anonymous slots")
	await click_button(unknown)
	var background = codex.find_child("CodexPortraitBackdrop", true, false) as TextureRect
	expect(not contains_text(codex, "洛恩") and codex.find_child("CodexPortrait", true, false).disabled,
		"An unknown entry never exposes an identity or opens a real portrait")
	expect(list_view.button_pressed and not grid_view.button_pressed and background.texture == null,
		"Opening an anonymous grid card returns to list details without revealing a backdrop")
	await click("旅人")
	var traveler_background = background.texture
	expect(traveler_background != null and background.get_global_rect().is_equal_approx(background.get_parent().get_global_rect()),
		"The known character backdrop covers the portrait frame")
	await click("技能")
	expect(contains_text(codex, "重力魔法"), "The traveler profile uses the current skills")
	await click("战斗")
	expect(game.character_codex_state.pose == "battle", "Battle pose changes the displayed art")
	var portrait = codex.find_child("CodexPortrait", true, false) as TextureButton
	expect(background.texture == traveler_background and portrait.get_global_rect().end.y >= background.get_global_rect().end.y,
		"The battle pose reaches the bottom edge without replacing the character backdrop")
	portrait.pressed.emit()
	expect(game.modal_layer.has_node("CodexPortraitZoom"), "Known portraits can be enlarged")
	await story_key(KEY_ESCAPE)
	expect(not game.modal_layer.has_node("CodexPortraitZoom") and game.modal_layer.has_node("CharacterCodex"),
		"Escape closes the enlargement before the codex")
	await click("装备")
	expect(contains_text(codex, "巡路短刃") and contains_text(codex, "旧灯护符"), "Equipment comes from the equipped slots")
	expect(run.data.transaction == old_transaction, "Inspecting the codex does not save or change the expedition")
	await click("管理装备")
	var inventory_tabs = game.modal_layer.find_child("InventoryTabs", true, false) as TabContainer
	var weapon: Button
	for slot in inventory_tabs.get_current_tab_control().grid.get_children():
		if slot is Button and slot.tooltip_text.begins_with("巡路短刃 · 普通"):
			weapon = slot
			break
	expect(inventory_tabs.current_tab == 1 and weapon != null, "Managing equipment opens the backpack equipment grid")
	if weapon != null:
		await click_button(weapon)
	await press("强化至 +1")
	await click("返回角色图鉴")
	codex = game.modal_layer.get_node("CharacterCodex")
	expect(game.character_codex_state.tab == 1 and contains_text(codex, "普通 +1"), "Returning from equipment management refreshes the same tab")
	await click("×")
	expect(game.selected_id == "hero" and game.selected_cell == map_selection and game.move_target == original_plan
		and game.move_preview.visible, "Closing the codex restores the original map selection and route preview")

	run.actor("lorne").position = source
	game._begin_dialogue("lorne")
	await read_to_choices()
	await click("结束交谈")
	await click("角色")
	await click("见过未加入")
	expect(game.character_codex_state.actor == "lorne", "Meeting a companion makes that character appear in the filter")
	codex = game.modal_layer.get_node("CharacterCodex")
	background = codex.find_child("CodexPortraitBackdrop", true, false)
	expect(background.texture != null and background.texture != traveler_background, "Selecting another character changes the illustrated setting")
	await click("装备")
	expect(contains_text(game.modal_layer, "尚未加入远征队。"), "A known but unjoined character has no player equipment")
	await click("×")
	expect(run.join_companion("lorne", "hero").ok, "Fixture recruits the known companion")
	await click("角色")
	await click("洛恩")
	await click("技能")
	expect(contains_text(game.modal_layer, "巡路连射") and game.selected_id == "hero", "Recruitment exposes the skills without switching the map actor")
	await click("×")
	run.data.flags.hero_identity_revealed = true
	await click("角色")
	expect(contains_text(game.modal_layer, "伊文洛"), "The traveler profile shows the true name after the revelation")
	await click("×")

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
	expect(not rest_cells.is_empty() and not shop_cells.is_empty(), "This seed has supply stops and trade nodes")
	if rest_cells.is_empty() or shop_cells.is_empty():
		return
	var rest_cell: String = rest_cells[0]
	hero.position = rest_cell
	run.reveal(rest_cell)
	game._select_actor("hero")
	var action = find_button(game.ui, "行动")
	expect(action != null and action.text == "行动", "A supply stop uses the plain action button label")
	await press("行动")
	await press("查看节点剧情")
	var stage = game.modal_layer.get_node("StoryScreen")
	var scene: TextureRect = stage.get_child(0)
	expect(scene.texture.resource_path.ends_with("/" + game._story_scene_at(rest_cell) + ".png"),
		"The node story uses the occupied tile's terrain art")
	expect(stage.get_node("Dialogue").get_children().filter(func(control): return control.visible) == [story_text()],
		"Map narration shows only its body text")
	await read_to_choices()
	expect(find_button(game.modal_layer, "记入旅途手记") == null, "Node dialogue has no travel journal action")
	expect(find_button(game.modal_layer, "在此休整") == null and find_button(game.modal_layer, "在此调息") == null,
		"The node offers supplies without recovery options")
	var supply: String = run.node_at(rest_cell).item
	var quantity = int(hero.inventory.get(supply, 0))
	await click("带走一份")
	expect(hero.hp == 1 and hero.mp == 0 and hero.inventory[supply] == quantity + 1,
		"The node grants a finite supply item")
	expect(find_button(game.modal_layer, "带走一份") == null, "Supply cannot be claimed twice")
	await finish_linear_story()
	expect(game.modal_layer.has_node("StoryRewards") and contains_text(game.modal_layer, run.location_name(rest_cell))
		and contains_text(game.modal_layer, Catalog.ITEMS[supply].description), "Node rewards show their source and the actual item")
	game._continue_run()
	expect(game.modal_layer.has_node("StoryRewards") and run.actor("hero").inventory[supply] == quantity + 1,
		"Continuing restores the pending receipt without granting the item again")
	await click("返回地图")
	game._continue_run()
	expect(not game.modal_layer.has_node("StoryRewards"), "An acknowledged node receipt stays closed after reloading")
	game._close_modal()
	hero = run.actor("hero")

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
	var steps = run.remaining_steps()
	var hero_salves = hero.inventory.salve
	game._select_actor("lorne")
	await press("背包")
	var slot = consumable_slot("疗伤药")
	expect(slot != null and slot.icon != null and is_equal_approx(slot.size.x, slot.size.y)
		and slot.get_parent().columns == 5 and slot.get_parent().get_child_count() == 15
		and contains_text(slot, "2"), "Consumables use square icon slots with a stack count")
	expect(contains_text(game.modal_layer, "洛恩 · 背包") and not contains_text(game.modal_layer, "终结技")
		and find_button(game.modal_layer, "使用") == null, "Backpack shows the holder and waits for a selection before offering actions")
	await select_consumable("疗伤药")
	expect(slot != null and slot.button_pressed and find_button(game.modal_layer, "交接") != null
		and contains_text(game.modal_layer, Catalog.ITEMS.salve.description) and lorne.inventory.salve == 2,
		"Clicking a slot selects it and shows its description and handoff without consuming it")
	await select_consumable("澄露")
	expect(slot != null and not slot.button_pressed
		and contains_text(game.modal_layer, Catalog.ITEMS.ether.description), "Selecting another consumable replaces the highlight and description")
	await use_from_backpack("疗伤药")
	var target = game.modal_layer.find_children("*", "OptionButton", true, false)[0]
	expect(target.get_item_text(target.selected).begins_with("洛恩") and target.item_count == 2,
		"Backpack use defaults to the holder and only offers local characters")
	await press("确认使用 疗伤药")
	expect(lorne.hp == 46 and lorne.inventory.salve == 1 and hero.inventory.salve == hero_salves and run.remaining_steps() == steps,
		"Using from Lorne's bag heals him and consumes only his item without spending effort")
	slot = consumable_slot("疗伤药")
	expect(saved_run().get("actors", {}).get("lorne", {}).get("hp") == 46 and slot != null and contains_text(slot, "1"),
		"Successful use auto-saves and returns to the refreshed backpack")
	expect(slot != null and slot.button_pressed and contains_text(game.modal_layer, Catalog.ITEMS.salve.description),
		"The item remains selected after using it when another remains")
	hero.hp = 0
	await use_from_backpack("疗伤药")
	target = game.modal_layer.find_children("*", "OptionButton", true, false)[0]
	for i in target.item_count:
		if target.get_item_text(i).begins_with("旅人"):
			target.select(i)
			break
	await press("确认使用 疗伤药")
	expect(hero.hp == 45 and lorne.inventory.salve == 0, "The same backpack flow rescues a downed local ally")
	expect(consumable_slot("疗伤药") == null and find_button(game.modal_layer, "使用") == null,
		"Using the final item clears the slot and removes its actions")
	await use_from_backpack("澄露")
	await press("确认使用 澄露")
	expect(contains_text(game.modal_layer, "没有可恢复的资源") and lorne.inventory.ether == 1,
		"An ineligible target gives visible feedback and keeps the consumable")
	await press("返回背包")
	lorne.mp = 5
	await use_from_backpack("澄露")
	await press("确认使用 澄露")
	expect(lorne.mp == 35 and lorne.inventory.ether == 0 and run.remaining_steps() == steps,
		"Backpack ether restores magic from the holder's inventory without spending effort")
	await press("关闭")
	game._select_actor("hero")
	await press("背包")
	expect(consumable_slot("营地木料") == null, "New expeditions have no construction material")
	await select_consumable("旅途干粮")
	expect(contains_text(game.modal_layer, Catalog.ITEMS.trail_food.description)
		and find_button(game.modal_layer, "使用") == null, "Food shows its purpose without a use button")
	var hero_food: int = hero.inventory.trail_food
	var lorne_food: int = lorne.inventory.get("trail_food", 0)
	await press("交接")
	await press("交给洛恩")
	slot = consumable_slot("旅途干粮")
	expect(hero.inventory.trail_food == hero_food - 1 and lorne.inventory.trail_food == lorne_food + 1
		and slot != null and slot.button_pressed and contains_text(slot, str(hero_food - 1)),
		"Handoff returns to the selected item and updates the stack and recipient")
	await press("关闭")

func saved_run() -> Dictionary:
	var checkpoint = JSON.parse_string(FileAccess.get_file_as_string(game.run.save_path))
	return checkpoint if checkpoint is Dictionary else {}

func story_owns_focus() -> bool:
	var story = game.modal_layer.get_node_or_null("StoryScreen")
	var focused = root.gui_get_focus_owner()
	return not game.ui.visible and story != null and focused != null and (story == focused or story.is_ancestor_of(focused))

func story_speaker() -> String:
	var label = game.modal_layer.get_node_or_null("StoryScreen/Dialogue/StorySpeaker") as Label
	return label.text if label != null else ""

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

func check_familiarity_dialogue() -> void:
	game._start_new()
	var run = game.run
	var person = run.actor("ember")
	run.actor("hero").position = person.position
	run.data.tiles[person.position].enemies.clear()
	run.reveal(person.position)
	game._select_actor("hero")
	game._begin_dialogue("ember")
	await read_to_choices()
	await click(option_label(game.narrative.dialogue("hero", "ember"), "join"))
	await finish_linear_story()
	expect(person.joined and game.modal_layer.has_node("StoryRewards")
		and contains_text(game.modal_layer, Relics.DATA.opening_flint.story),
		"The companion's reply ends with an illustrated receipt for their gift")
	await click("返回地图")
	game._begin_dialogue("ember")
	var idle = await read_to_choices()
	expect(run.relic_intro().is_empty(), "The gift story is acknowledged before optional conversation")
	expect(not idle.contains(Story.HERO_LINES.ember), "Idle conversation does not volunteer the protagonist hint")
	var before = run.data.duplicate(true)
	await click(option_label(game.narrative.dialogue("hero", "ember"), "echo"))
	expect(story_speaker() == "旅人", "Only the present hero asks about their lost identity")
	await click_story_blank()
	var answer = await read_to_choices()
	expect(answer.contains(Story.HERO_LINES.ember) and not answer.contains("伊文洛") and story_speaker() == "弥烬",
		"The explicit identity question shows the complete hint without the final reveal")
	expect(run.data == before, "Reading familiarity changes no resources or personal choice")
	await click("结束交谈")
	run.actor("lorne").position = person.position
	expect(game.narrative.choose("hero", "lorne", "join").ok, "Recruit a local ordinary visitor")
	game._select_actor("lorne")
	game._begin_dialogue("ember")
	var ordinary = await read_to_choices()
	expect(not ordinary.contains(Story.HERO_LINES.ember)
		and find_button(game.modal_layer, "你认得我吗？我想不起以前的事了。") == null,
		"A teammate cannot ask the hero-only identity question")
	await click("结束交谈")

func check_final_reveal() -> void:
	game._start_new()
	var run = game.run
	for cell in run.data.tiles:
		run.data.explored[cell] = true
	for stage in range(1, 5):
		run.finish_chapter(stage)
	run.actor("hero").position = run.data.boss
	var battle = Combat.new()
	var encounter = {"position": run.data.boss, "origin": run.data.boss, "movers": [], "npc": "", "ambush": false}
	expect(battle.begin(run, encounter, ["hero"]).ok, "Final revelation fixture begins at the actual boss")
	game.combat = battle
	battle.unit("enemy_0").hp = 1
	battle.check_end()
	expect(battle.reveal_pending and not battle.river, "The old strike opens the memory before awakening")
	game._final_battle_page(0)
	var complete = ""
	var river_shown = false
	var river_portrait = game._story_portrait("war_god", "surprise") as AtlasTexture
	for index in range(128):
		if not game.modal_layer.has_node("StoryScreen"):
			break
		await process_frame
		check_story_layout()
		expect(battle.reveal_pending and not battle.river and run.actor("hero").name == "旅人",
			"Reading and reviewing the final memory cannot awaken the hero early")
		var body = story_text().text
		river_shown = river_shown or body.contains("冥河在卡德兰脚下涌出")
		var screen = game.modal_layer.get_node("StoryScreen")
		var background = screen.get_child(0) as TextureRect
		expect((background.texture.resource_path == "res://assets/story/finale.png") == river_shown,
			"The river backdrop starts with the river narration and stays for the rest of that beat")
		var war_god = screen.find_child("StoryActor1", true, false) as TextureRect
		if war_god != null:
			var portrait = war_god.texture as AtlasTexture
			expect((portrait.region == river_portrait.region) == river_shown,
				"The war god's portrait does not show river water ahead of the narration")
		complete += body
		if story_page().x > 1:
			await click("上一页")
			expect(not battle.river, "Previous page does not apply the final power")
			await click_story_blank()
			expect(story_text().text == body, "Final memory returns to exactly the same text")
		await click_story_blank()
	expect(not game.modal_layer.has_node("StoryScreen") and battle.river and not battle.reveal_pending
		and run.actor("hero").name == "伊文洛", "Only the completed revelation awakens Ivenlo and returns to battle")
	for phrase in ["是你杀了我", "没有一个亡魂被接走", "我是伊文洛", "掉进去也一样"]:
		expect(complete.contains(phrase), "The full final confrontation is readable: " + phrase)
	expect(not complete.contains("路上那些恶魔认出的"), "A run without a demon encounter does not invent one")
	game.combat = null
	game._close_modal()

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
	expect(dialogue_contains("维洛丹这片土地，比任何人的记性都老") and not dialogue_contains("后来，几位神打了起来"), "Opening starts with life before the war")
	var opening_dialogue = game.modal_layer.get_node("StoryScreen/Dialogue")
	expect(opening_dialogue.get_children().filter(func(control): return control.visible) == [story_text()],
		"Opening narration has only its body text")
	expect(story_owns_focus(), "Opening retains the story interface and focus")
	await story_key(KEY_ESCAPE)
	expect(dialogue_contains("维洛丹"), "Escape leaves an opening scene without an End Conversation action in place")
	var world_text = ""
	var world_scenes: Array[String] = []
	for index in range(128):
		if story_text() == null or story_speaker() != "旁白":
			break
		world_text += story_text().text
		var background: TextureRect = game.modal_layer.get_node("StoryScreen").get_child(0)
		var scene = background.texture.resource_path.get_file().get_basename()
		if world_scenes.is_empty() or world_scenes.back() != scene:
			world_scenes.append(scene)
		await advance_story()
	expect(world_scenes == ["world_intro", "dragon", "demon", "elves", "dwarves", "humans", "market",
		"world_intro", "kadran", "mevenna", "dorank", "levensor", "world_intro"],
		"Opening switches to the approved illustrations in narrative order")
	var last_topic = -1
	for topic in ["趴着睡的大兽", "最老的，是龙", "是恶魔", "精灵住在林子里", "矮人把家安进山", "人类生在平原上", "赶上开集", "卡德兰", "梅文娜", "多兰克", "莱文索", "运粮的车过不来", "已经下了葬"]:
		var position = world_text.find(topic)
		expect(position > last_topic, "Opening introduces this topic in order: " + topic)
		last_topic = position
	expect(not world_text.contains("伊文洛") and not world_text.contains("死神"), "World introduction keeps the protagonist's identity for the final battle")
	expect(world_text.contains("对方还会再来一趟") and not world_text.contains("它的账"), "The demon bargain uses a personal reference")
	expect(dialogue_contains("你醒了"), "Reading reaches the hero waking without assuming a page count")
	var village_dialogue = game.modal_layer.get_node("StoryScreen/Dialogue")
	expect(story_speaker() == "村民" and village_dialogue.get_children().filter(func(control): return control.visible).size() == 3,
		"Spoken dialogue retains the speaker and separator")
	await click("历史对话")
	var history = game.modal_layer.get_node("StoryHistory")
	expect(contains_text(history, "维洛丹这片土地，比任何人的记性都老") and contains_text(history, "你醒了"),
		"History carries over from the world introduction into the village")
	await click("关闭")
	await advance_until_text("那我出去走走")
	expect(dialogue_contains("那我出去走走"), "The traveler accepts the walk in plain words")
	await click("历史对话")
	expect(contains_text(game.modal_layer.get_node("StoryHistory"), "那我出去走走"),
		"History shows the same traveler dialogue as the story screen")
	await click("关闭")
	await advance_until_text("一路平安")
	expect(dialogue_contains("一路平安"), "The villager sends off the traveler with supplies")
	await finish_linear_story()
	expect(game.modal_layer.has_node("StoryRewards") and contains_text(game.modal_layer, "疗伤药")
		and contains_text(game.modal_layer, "澄露") and contains_text(game.modal_layer, "巡路短刃"), "Departure lists all village gifts")
	for item in ["ether", "salve"]:
		await select_story_reward(Catalog.ITEMS[item].name)
		var detail = game.modal_layer.find_child("RewardDetails", true, false)
		expect(detail != null and contains_text(detail, Catalog.ITEMS[item].description)
			and contains_text(detail, Catalog.ITEMS[item].story), "Clicking a consumable shows its use and description")
	await click("返回地图")
	expect(game.modal_layer.get_child_count() == 0 and game.run.actor("hero").name == "旅人", "Departure enters the map as the fixed traveler")
	expect(saved_run().get("actors", {}).get("hero", {}).get("inventory", {}).get("salve") == 3, "Village supplies are saved on departure")
	check_reward_art()
	await check_story_history()
	await check_story_pagination()
	await check_personal_dialogue()
	await check_character_codex()
	await check_backpack_use()
	await check_node_dialogs()
	await check_node_arrival()
	await check_arrival_after_victory()
	await check_manual_encounter_intro()
	await check_familiarity_dialogue()
	await check_final_reveal()
	await check_haunt_dialogue()
	expect(game._expedition_objective() == "踏出旅程的第一步", "HUD shows the departure objective")
	var chapter_run = game.run
	var pages: Array = game._chapter_pages()
	expect(pages.size() == 4, "Main story retains four chapters")
	expect(find_button(game.ui, "旅途手记") == null and find_button(game.ui, "定位战神") == null,
		"Exploration has no travel journal and keeps the boss locator hidden until the reveal")
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
	await click("定位战神")
	expect(game.selected_cell == chapter_run.data.boss, "Revealed boss can be located directly from the map header")
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
