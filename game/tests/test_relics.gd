extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/domain/expedition.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Battle = preload("res://tests/legacy/realtime_battle.gd")
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
	var later = run.actor("lorne")
	var later_max = later.hp_max
	var initial_attack = run.stat("hero", "attack")
	expect(not run.grant_relic("trail_boots", "hero", start)
		and run.relic_offer("retired-only", ["trail_boots"], 1.0).is_empty(), "Retired effort relics cannot drop")
	run.grant_relic("ranged_sight", "hero", start)
	expect(run.stat("hero", "attack") == initial_attack, "Ranged relic modifies battle damage, not the attack stat")
	hero.hp = 18
	run.grant_relic("life_seed", "hero", start)
	expect(hero.hp_max == 95 and run.use_relic("hero", "life_seed").ok and hero.hp_max == 114 and hero.hp == 18,
		"Life seed waits for explicit use and keeps current HP")
	run.grant_relic("life_seed", "hero", start)
	expect(not run.use_relic("hero", "life_seed").ok and run.data.relic_inventory.life_seed == 1, "A duplicate seed cannot reapply permanent growth")
	later.position = start
	run.join_companion("lorne")
	expect(later.hp_max == roundi(later_max * 1.20), "Later recruits inherit the team max HP bonus")
	var grit = run.actor("grit")
	grit.position = start
	run.join_companion("grit")
	expect(run.stat("grit", "attack") == grit.attack, "Melee recruits do not receive the ranged bonus")
	grit.hp = 0
	hero.mp = 0
	grit.mp = 0
	run.grant_relic("stillwater_stone", "hero", start)
	expect(run.use_relic("hero", "stillwater_stone").ok
		and hero.mp == roundi(hero.mp_max * 0.40) and grit.mp == 0, "Finite restoration only applies to able allies")
	run.grant_relic("herbal_case", "hero", start)
	expect(run.use_item("hero", "hero", "salve").ok and hero.hp == 74, "Health items use the relic multiplier")
	run.grant_relic("rainstone", "hero", start)
	var weather = run.next_weather()
	run._advance_day()
	expect(is_equal_approx(run.rain_chance(), 0.48) and run.data.weather == weather, "Forecast and day settlement use the adjusted rain probability")
	run.grant_relic("rain_bell", "hero", start)
	run.data.weather = "sun"
	expect(run.use_relic("hero", "rain_bell").ok and run.data.weather == "rain", "Rain bell changes the current weather when used")
	run.grant_relic("lamp_badge", "hero", start)
	run.data.tiles[start].enemies = ["boar"]
	var combat = Battle.new()
	var encounter = {"position": start, "origin": start, "ambush": false, "npc": "", "movers": []}
	expect(combat.begin(run, encounter, ["hero"]).ok and hero.shield == roundi(hero.hp_max * 0.12), "Badge grants a shield on deployment")
	combat.current = "hero"
	expect(combat.swap("lorne").ok and later.shield == roundi(later.hp_max * 0.12), "First reserve deployment gets the same shield")
	later.shield = 0
	combat._deploy("lorne")
	expect(later.shield == 0, "A returning combatant does not regain the badge shield")
	combat.retreat()

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
	expect(combat.begin(run, {"position": "0,0", "origin": "0,0", "ambush": false, "npc": "", "movers": []}, ["hero"]).ok, "Archer encounter begins")
	combat.enemies.enemy_0.hp = 0
	combat.check_end()
	expect(combat.outcome == "victory" and not expected.is_empty() and run.data.relic_inventory.has(expected) and run.relic_intro().id == expected, "Victory rolls once from the shared pool")
	expect(run.load_game().ok and run.data.relic_claims["battle:0,0:"].relic_id == expected
		and run.roll_relic("battle:0,0:", ["lamp_badge"], 1.0, "hero", "0,0").is_empty(), "Battle settlement and reward are saved together without a reroll")

func check_victory_receipt(save_path: String) -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = save_path
	game._continue_run()
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
		for button in result.find_children("*", "Button", true, false):
			if button.text == "继续远征":
				button.pressed.emit()
				break
		expect(game.run.relic_intro().is_empty(), "Acknowledging victory clears the earned relic introduction")
	game.queue_free()

func click_story() -> void:
	for pressed in [true, false]:
		var input = InputEventMouseButton.new()
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = pressed
		input.position = root.get_visible_rect().size * Vector2(0.76, 0.30)
		root.push_input(input, true)
	await process_frame

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
	run.actor("hero").position = site
	run.data.tiles[site].enemies = []
	run.reveal(site)
	game.selected_cell = site
	game._refresh()
	game._cell_actions()
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text == "查看节点剧情":
			button.pressed.emit()
			break
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text.begins_with("搜寻旧物"):
			button.pressed.emit()
			break
	var intro = run.relic_intro()
	expect(run.has_relic("telescope") and intro.get("id") == "telescope" and game.modal_layer.has_node("StoryScreen"), "Investigating an eligible tile opens the relic story")
	if intro.is_empty():
		game.queue_free()
		return
	var new_sight: Array = intro.new_sight
	var sight_is_hidden = new_sight.all(func(id):
		return run.data.explored.has(id) and not run.has_visited(id) and not game.view.tile_nodes.has(id))
	expect(not new_sight.is_empty() and sight_is_hidden, "Telescope adds shared sight, deferring map presentation until after the story")
	for page in range(16):
		if not game.modal_layer.has_node("StoryScreen"):
			break
		await click_story()
	expect(game.modal_layer.has_node("StoryRewards"), "The cache conclusion opens its item receipt")
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
			func(label): return label.text == Relics.DATA.telescope.effect), "Selecting the relic shows its effect beside the grid")
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
