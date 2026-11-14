extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/domain/expedition.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Battle = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func roll(seed_value: int, source: String) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("relic:4:%d:%s" % [seed_value, source])
	return rng.randf()

func check_effects(run: RefCounted) -> void:
	run.new_run(20261104, "wayfarer")
	var hero = run.actor("hero")
	var start: String = hero.position
	expect(not run.grant_relic("trail_boots", "hero", start)
		and run.relic_offer("retired-only", ["trail_boots"], 1.0).is_empty(), "Retired effort relics cannot drop")
	run.grant_relic("life_seed", "hero", start)
	expect(run.use_relic("hero", "life_seed").ok and hero.hp_max == 95, "Life seed grows chess pieces")
	run.grant_relic("life_seed", "hero", start)
	expect(not run.use_relic("hero", "life_seed").ok and run.data.relic_inventory.life_seed == 1, "A duplicate seed cannot reapply growth")
	run.grant_relic("rime_thimble", "hero", start)
	expect("ice_spell" in Cards.collection(run.data.actors, run.data), "Finding a relic unlocks its spell in the collection")
	run.grant_relic("rain_bell", "hero", start)
	run.grant_relic("lamp_badge", "hero", start)
	run.grant_relic("rootbound_bracelet", "hero", start)
	expect(not run.use_relic("hero", "rain_bell").ok, "Consumables are prepared for battle")
	run.prepared_relic = "rain_bell"
	run.data.weather = "sun"
	run.data.tiles[start].enemies = ["boar"]
	var combat = Battle.new()
	var encounter = {"position": start, "origin": start, "ambush": false, "npc": ""}
	expect(combat.begin(run, encounter, run.card_deck()).ok and combat.weather == "rain"
		and not run.data.relic_inventory.has("rain_bell") and run.data.weather == "sun", "The bell changes only battle weather and is spent once")
	expect(combat.board[10].hp_max == 14 and combat.board[10].armor == 3, "Life seed and lamp badge modify the actual commander")
	combat.hands[0] = ["support_vanguard"]
	expect(combat.play(0, 6) and combat.board[6].hp_max == 8 and combat.board[6].armor == 4,
		"The seeded earth partner gets its starting armor and the rain deployment bonus")
	for id in Relics.DATA:
		if Relics.is_active(id):
			expect(not Relics.current_effect(id).is_empty(), "Every active relic has a chess effect: " + id)

func check_battle_drop(run: RefCounted) -> void:
	var seed_value = 1
	while roll(seed_value, "battle:0,0:") >= 0.30:
		seed_value += 1
	run.new_run(seed_value, "wayfarer")
	run.actor("hero").position = "0,0"
	run.reveal("0,0")
	run.data.tiles["0,0"].enemies = ["archer"]
	var expected: String = run.relic_offer("battle:0,0:", Relics.DATA.keys(), 0.30)
	var combat = Battle.new()
	expect(combat.begin(run, {"position": "0,0", "origin": "0,0", "ambush": false, "npc": "", "movers": []}, run.card_deck()).ok, "Archer encounter begins")
	combat.commanders[Battle.ENEMY].hp = 0
	combat._check_outcome()
	expect(combat.outcome == "victory" and not expected.is_empty() and run.data.relic_inventory.has(expected) and run.relic_intro().id == expected, "Victory rolls once from the shared pool")
	expect(run.load_game().ok and run.data.relic_claims["battle:0,0:"].relic_id == expected
		and run.roll_relic("battle:0,0:", ["lamp_badge"], 1.0, "hero", "0,0").is_empty(), "Battle settlement and reward are saved together without a reroll")

func check_victory_receipt(save_path: String) -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = save_path
	game._continue_run()
	expect(game.modal_layer.find_child("ShopView", true, false) != null, "Reload opens the post-battle shop")
	game._victory_dialog()
	var result = game.modal_layer.get_node_or_null("VictoryScreen")
	expect(result != null and not game.modal_layer.has_node("StoryScreen"), "Battle loot opens the settlement")
	if result != null:
		var relic: String = game.run.data.pending_victory.relic
		var rows = result.find_child("RewardItems", true, false)
		expect(rows != null, "The settlement shows inspectable loot")
		if rows != null:
			for button in rows.find_children("*", "Button", true, false):
				if button.accessibility_name.begins_with(Relics.DATA[relic].name):
					button.pressed.emit()
					break
			expect(rows.details.find_children("*", "Label", true, false).any(
				func(label): return label.text == Relics.DATA[relic].story), "The earned relic story is readable before leaving")
		game._leave_battle_shop()
		expect(game.run.relic_intro().is_empty(), "Acknowledging victory clears the earned relic introduction")
	game.queue_free()

func check_exploration() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-relic-exploration.json"
	var run = game.run
	game._start_new()
	var site = ""
	for id in run.relic_sites:
		if run.relic_sites[id] == "telescope" and run.node_at(id).kind == "cache" and roll(int(run.data.seed), "site:" + id) < 0.25:
			site = id
			break
	if site.is_empty():
		# Select a deterministic seed with a successful telescope investigation.
		for seed_value in range(1, 30):
			game.chosen_seed = str(seed_value)
			game._start_new()
			for id in run.relic_sites:
				if run.relic_sites[id] == "telescope" and run.node_at(id).kind == "cache" and roll(seed_value, "site:" + id) < 0.25:
					site = id
					break
			if not site.is_empty():
				break
	expect(not site.is_empty(), "A map seed offers a successful investigation")
	if site.is_empty():
		game.queue_free()
		return
	var approach: String = Hex.neighbors(site, run.data.tiles).filter(func(cell): return Hex.is_land(run.data.tiles, cell))[0]
	run.data.tiles[approach].enemies.clear()
	run.actor("hero").position = approach
	run.reveal(approach)
	game._select_actor("hero")
	game._select_cell(site)
	game._select_cell(site)
	var deadline := Time.get_ticks_msec() + 5000
	while game.map_traveling and Time.get_ticks_msec() < deadline:
		await process_frame
	var intro = run.relic_intro()
	expect(run.has_relic("telescope") and intro.get("id") == "telescope" and game.modal_layer.has_node("StoryRewards"), "Investigating an eligible tile opens the item receipt directly")
	if intro.is_empty():
		game.queue_free()
		return
	var new_sight: Array = intro.new_sight
	var sight_is_hidden = new_sight.all(func(id):
		return run.data.explored.has(id) and not run.has_visited(id) and not game.view.tile_nodes.has(id))
	expect(not new_sight.is_empty() and sight_is_hidden, "Telescope adds shared sight, deferring map presentation until after the story")
	game._continue_run()
	expect(run.relic_intro().get("id") == "telescope" and game.modal_layer.has_node("StoryRewards"),
		"Continue resumes the saved cache receipt with the same relic")
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text.begins_with("返回地图"):
			button.pressed.emit()
			break
	expect(run.relic_intro().is_empty() and game.view.fog_reveals.get_child_count() > 0
		and not run.investigate_relic("hero").ok, "Acknowledging the receipt starts the fog dissolve and prevents a second investigation")
	game._inventory_dialog("hero", 2)
	var tabs = game.modal_layer.find_child("InventoryTabs", true, false)
	var page = tabs.get_child(2)
	var telescope: Button
	for slot in page.grid.get_children():
		if slot is Button and "望远镜" in slot.tooltip_text:
			telescope = slot
			break
	expect(tabs.get_tab_count() == 3 and tabs.get_tab_title(2) == "遗器" and telescope != null,
		"Backpack exposes the team relic as an icon in its own tab")
	if telescope != null:
		telescope.pressed.emit()
		expect(page.selected_id == "telescope" and page.details.find_children("*", "Label", true, false).any(
			func(label): return label.text == Relics.current_effect("telescope")), "Selecting the relic shows its effect beside the grid")
	game.queue_free()

func execute() -> void:
	var run = Run.new()
	run.save_path = "user://test-relic-domain.json"
	expect(Relics.DATA.size() == 100, "One hundred distinct relics are defined")
	check_effects(run)
	check_battle_drop(run)
	await check_victory_receipt(run.save_path)
	await check_exploration()
	await create_timer(0.3).timeout
	print("RELICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
