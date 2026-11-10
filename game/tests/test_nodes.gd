extends SceneTree

const Run = preload("res://scripts/domain/expedition.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func execute() -> void:
	check_catalog()
	check_generation()
	check_exhausted_haunts()
	check_haunt_branches()
	check_choice_branches()
	check_investigated_validation()
	check_trade_and_recovery()
	print("MAP NODES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_generation() -> void:
	var run = Run.new()
	var duplicate = Run.new()
	var kinds = {}
	for seed_value in range(24):
		run.new_run(seed_value, "wayfarer")
		duplicate.new_run(seed_value, "guardian")
		expect(run.data.nodes == duplicate.data.nodes, "Seed fixes node placement, stories, rewards and stock")
		expect(not Hex.path(run.data.tiles, run.data.start, run.data.boss, true).is_empty(), "Safe boss approach remains reachable")
		var coverage = true
		var compatible = true
		var haunt_ids = {}
		for cell in run.data.tiles:
			var tile = run.data.tiles[cell]
			var node = run.node_at(cell)
			coverage = coverage and (not node.is_empty()) == Hex.is_land(run.data.tiles, cell)
			if node.is_empty():
				continue
			kinds[node.kind] = true
			if node.kind == "haunt":
				expect(not haunt_ids.has(node.event), "Haunt id appears once in seed %d: %s" % [seed_value, node.event])
				haunt_ids[node.event] = true
			if node.kind != "story":
				var event = Nodes.story(node)
				compatible = compatible and not event.is_empty() and tile.base_terrain in event.terrains
		expect(coverage and compatible, "Every land tile has a compatible story and lakes have none")
	expect(kinds.size() == Nodes.LABELS.size(), "Seeds exercise all node kinds")

func check_trade_and_recovery() -> void:
	var run = Run.new()
	run.save_path = "user://test-nodes.json"
	run.new_run(20261104, "wayfarer")
	var shop = find_node(run, "trade")
	var rest = find_node(run, "rest")
	var work = find_node(run, "choice")
	if shop.is_empty() or rest.is_empty() or work.is_empty():
		expect(false, "Fixture seed has a shop, work and recovery")
		return
	var hero = run.actor("hero")
	var lorne = run.actor("lorne")
	hero.position = shop
	lorne.position = shop
	run.join_companion("lorne")
	var stock = run.node_at(shop).stock
	var original_stock = int(stock.salve)
	var original_salve = int(hero.inventory.salve)
	expect(run.trade("hero", "salve", true).ok and run.data.lamp_coins == 2
		and hero.inventory.salve == original_salve + 1 and stock.salve == original_stock - 1,
		"Buying updates the shared wallet, stock and buyer's inventory")
	var before = JSON.stringify(run.data)
	expect(not run.trade("lorne", "ether", true).ok and not run.trade("hero", "trail_blade", false).ok
		and JSON.stringify(run.data) == before, "Unfunded purchases and equipped sales have no side effects")
	expect(run.trade("lorne", "salve", false).ok and run.data.lamp_coins == 4 and stock.salve == original_stock,
		"A companion sells from its own bag into the same wallet")
	expect(not run.trade("hero", "Q-T", false).ok, "Story documents cannot be sold")

	hero.position = work
	expect(run.use_node("hero", "work").ok and run.data.lamp_coins == 4 + run.node_at(work).coins
		and not run.use_node("hero", "work").ok, "A local commission pays once")
	hero.position = rest
	lorne.position = rest
	hero.hp = 20
	hero.mp = 5
	lorne.hp = 0
	expect(not run.use_node("hero", "hp").ok and not run.use_node("hero", "mp").ok,
		"Supply stop does not offer recovery")
	var item: String = run.node_at(rest).item
	var count = int(hero.inventory.get(item, 0))
	expect(run.use_node("hero", "pack").ok and hero.inventory[item] == count + 1
		and hero.hp == 20 and hero.mp == 5 and lorne.hp == 0, "Supply stop grants a finite item")
	expect(not run.use_node("hero", "pack").ok, "Supply can only be claimed once")
	expect(run.save_game().ok, "Save resolved nodes and wallet")
	var continued = Run.new()
	expect(continued.load_game(run.save_path).ok, "Load the expedition with node state")
	expect(continued.node_at(shop).stock.salve == stock.salve and continued.node_at(rest).result == "pack"
		and continued.node_at(work).result == "work" and continued.data.lamp_coins == run.data.lamp_coins
		and not continued.use_node("hero", "pack").ok, "Stock and claimed supply survive reload")
	var recorded_save = run.data.duplicate(true)
	var biome: String = recorded_save.tiles[rest].base_terrain
	recorded_save.nodes[rest] = {"kind": "clue", "event": biome + "_clue_1", "result": "record"}
	recorded_save.leads = {rest: true}
	var old_file = FileAccess.open(run.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(recorded_save))
	old_file.close()
	expect(continued.load_game(run.save_path).ok and continued.node_at(rest).kind in ["choice", "rest"]
		and continued.node_at(rest).result == "" and not continued.data.has("leads")
		and continued.node_at(work).result == "work" and continued.data.lamp_coins == run.data.lamp_coins,
		"A legacy clue becomes a playable local event without changing other progress")
	var legacy = run.data.duplicate(true)
	legacy.version = 3
	legacy.relic_checks = {}
	legacy.relics = {}
	legacy.relic_intros = []
	for field in ["gear_instances", "next_gear_uid", "relic_seen", "relic_inventory", "relic_attunement", "relic_claims", "relic_effect_flags"]:
		legacy.erase(field)
	for actor in legacy.actors.values():
		for slot in actor.equipment:
			actor.equipment[slot] = ""
	legacy.erase("nodes")
	legacy.erase("lamp_coins")
	for cell in run.relic_sites:
		if run.node_at(cell).kind != "cache":
			continue
		legacy.relic_checks["site:" + cell] = ""
		var file = FileAccess.open(run.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(legacy))
		file.close()
		expect(continued.load_game(run.save_path).ok and continued.data.lamp_coins == 8
			and continued.node_at(cell).result == "search" and continued.actor("hero").hp == hero.hp,
			"Legacy saves gain seeded nodes and preserve prior relic investigations and actor health")
		break

func check_catalog() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/node_events.json"))
	expect(source is Dictionary and source.size() == 8, "Eight themed catalog kinds retain 96 events")
	if not source is Dictionary:
		return
	var ids = {}
	for kind in ["trade", "supply", "rest", "choice", "cache", "battle", "elite", "haunt"]:
		var entries: Array = source.get(kind, [])
		expect(entries.size() == 12, "Twelve events for " + kind)
		for event in entries:
			expect(not ids.has(event.id), "Catalog id remains unique: " + event.id)
			ids[event.id] = true
			var fields = ["location", "title", "intro", "resolved"]
			if kind == "haunt":
				fields.append_array(["investigation_label", "investigation", "evidence", "work", "alternative", "alternative_resolved"])
			elif kind == "choice":
				fields.append_array(["work", "alternative", "alternative_resolved"])
			for field in fields:
				expect(event.get(field) is String and not str(event.get(field, "")).strip_edges().is_empty(), event.id + " has " + field)
			if kind in ["haunt", "choice"]:
				expect(event.get("work") != event.get("alternative") and event.get("resolved") != event.get("alternative_resolved"), event.id + " has distinct decisions and conclusions")
				for option in (["settle", "settle_alternative"] if kind == "haunt" else ["work", "work_alternative"]):
					var expected = event.get("alternative_resolved", "") if option.ends_with("_alternative") else event.get("resolved", "")
					expect(Nodes.resolution({"event": event.id, "result": option}) == expected, event.id + " resolves " + option)
			if kind == "rest":
				var endings = {}
				for option in ["hp", "mp", "pack"]:
					var text = str(event.get("resolved_by_option", {}).get(option, ""))
					expect(not text.is_empty() and Nodes.resolution({"event": event.id, "result": option}) == text, event.id + " resolves recovery " + option)
					endings[text] = true
				expect(endings.size() == 3, event.id + " distinguishes all recovery conclusions")
		for terrain in ["plains", "forest", "mountain", "ruins", "desert", "swamp"]:
			for index in [1, 2]:
				var id = "%s_%s_%d" % [terrain, kind, index]
				expect(entries.any(func(event): return event.id == id and terrain in event.terrains), "Original compatible event id retained: " + id)
	expect(ids.size() == 96, "All 96 themed event ids remain")

func check_exhausted_haunts() -> void:
	for terrain in ["plains", "forest", "mountain", "ruins", "desert", "swamp"]:
		var tiles = {}
		for index in range(128):
			tiles[Hex.key(Vector2i(index, 0))] = {"terrain": terrain, "base_terrain": terrain, "site": "", "resource": "", "enemies": []}
		var before = tiles.duplicate(true)
		var nodes = Nodes.generate(tiles, 91, {}, {}, {})
		var haunt_ids = {}
		var fallbacks = 0
		for cell in nodes:
			var roller = RandomNumberGenerator.new()
			roller.seed = hash("node:%d:%s" % [91, cell])
			var roll = roller.randi_range(0, 99)
			if roll >= 45 and roll < 72:
				if nodes[cell].kind in ["choice", "rest"]:
					fallbacks += 1
				else:
					expect(nodes[cell].kind == "haunt" and not haunt_ids.has(nodes[cell].event), "Unused haunt precedes a local event in " + terrain)
					haunt_ids[nodes[cell].event] = true
			expect(terrain in Nodes.story(nodes[cell]).get("terrains", []), "Exhaustion keeps event terrain " + terrain)
		expect(haunt_ids.size() == 2 and fallbacks > 0 and tiles == before, "Exhausted haunts become local events in " + terrain)

func event_run(event: Dictionary, kind: String) -> RefCounted:
	var run = Run.new()
	run.save_path = "user://test-node-branches.json"
	run.new_run(41, "wayfarer")
	for cell in run.data.nodes:
		if cell in [run.data.start, run.data.boss] or run.data.tiles[cell].base_terrain not in event.terrains:
			continue
		var replaced: Dictionary = run.node_at(cell)
		if replaced.has("gear_uid"):
			run.data.gear_instances.erase(replaced.gear_uid)
		for uid in run.gear_owned("shop", cell):
			run.data.gear_instances.erase(uid)
		run.data.nodes[cell] = {"kind": kind, "event": event.id, "result": ""}
		if kind == "choice":
			run.data.nodes[cell].coins = 4
		run.data.tiles[cell].enemies.clear()
		run.actor("hero").position = cell
		return run
	expect(false, "Compatible fixture cell for " + event.id)
	return run

func check_haunt_branches() -> void:
	Nodes._load_events()
	var covered = 0
	for event in Nodes.events.values():
		if not str(event.id).contains("_haunt_"):
			continue
		covered += 1
		for branch in ["settle", "settle_alternative"]:
			var run = event_run(event, "haunt")
			var cell: String = run.actor("hero").position
			var node = run.node_at(cell)
			var before = run.data.duplicate(true)
			for option in ["settle", "settle_alternative"]:
				expect(not run.use_node("hero", option).ok and run.data == before, event.id + " requires investigation before " + option)
			run.actor("lorne").position = cell
			expect(run.join_companion("lorne").ok, "Recruit investigator")
			run.actor("hero").hp = 0
			var actors = run.data.actors.duplicate(true)
			var coins = run.data.lamp_coins
			var peace = run.data.peace.duplicate(true)
			var inspected = run.use_node("lorne", "inspect")
			expect(inspected.ok and str(inspected.get("message", "")) == event.investigation, event.id + " companion reads the actual investigation")
			expect(node.get("investigated", false) and node.result == ""
				and run.data.peace == peace and run.data.lamp_coins == coins and run.data.actors == actors,
				event.id + " investigation records evidence without completion, peace or resource changes")
			before = run.data.duplicate(true)
			for option in ["inspect", "settle", "settle_alternative"]:
				expect(not run.use_node("lorne", option).ok and run.data == before, event.id + " no repeated investigation or wounded-hero settlement: " + option)
			expect(run.save_game().ok, event.id + " save investigated checkpoint")
			var loaded = Run.new()
			expect(loaded.load_game(run.save_path).ok and loaded.node_at(cell).get("investigated", false)
				and loaded.node_at(cell).result == "" and not loaded.data.peace.has(cell), event.id + " reload preserves unfinished investigation")
			loaded.save_path = run.save_path
			loaded.actor("hero").position = cell
			loaded.actor("hero").hp = 0
			before = loaded.data.duplicate(true)
			for option in ["settle", "settle_alternative"]:
				expect(not loaded.use_node("lorne", option).ok and loaded.data == before, event.id + " wounded hero cannot authorize " + option)
			loaded.actor("hero").hp = loaded.actor("hero").hp_max
			actors = loaded.data.actors.duplicate(true)
			var peace_count = loaded.data.peace.size()
			expect(loaded.use_node("hero" if branch == "settle" else "lorne", branch).ok, event.id + " completes " + branch + " with local healthy hero")
			var expected = event.resolved if branch == "settle" else event.alternative_resolved
			expect(loaded.node_at(cell).result == branch and Nodes.resolution(loaded.node_at(cell)) == expected
				and loaded.data.peace.has(cell) and loaded.data.peace.size() == peace_count + 1
				and loaded.data.lamp_coins == coins and loaded.data.actors == actors, event.id + " applies one peaceful branch with unchanged actor resources")
			before = loaded.data.duplicate(true)
			for option in ["inspect", "settle", "settle_alternative"]:
				expect(not loaded.use_node("hero", option).ok and loaded.data == before, event.id + " cannot repeat or switch " + branch)
			expect(loaded.save_game().ok, event.id + " save settled branch")
			var resumed = Run.new()
			expect(resumed.load_game(loaded.save_path).ok and resumed.node_at(cell).get("investigated", false)
				and resumed.node_at(cell).result == branch and Nodes.resolution(resumed.node_at(cell)) == expected
				and resumed.data.peace.size() == peace_count + 1, event.id + " reload retains " + branch)
			before = resumed.data.duplicate(true)
			for option in ["settle", "settle_alternative"]:
				expect(not resumed.use_node("hero", option).ok and resumed.data == before, event.id + " reloading cannot repay settlement")
	expect(covered == 12, "Both branches exercised for all twelve haunts")

func check_choice_branches() -> void:
	Nodes._load_events()
	var covered = 0
	for event in Nodes.events.values():
		if not str(event.id).contains("_choice_"):
			continue
		covered += 1
		for branch in ["work", "work_alternative"]:
			var run = event_run(event, "choice")
			var hero = run.actor("hero")
			var node = run.node_at(hero.position)
			var expected_actor = hero.duplicate(true)
			var steps = run.remaining_steps()
			var coins = run.data.lamp_coins
			expect(run.use_node("hero", branch).ok and hero == expected_actor and run.data.lamp_coins == coins + node.coins
				and node.result == branch and run.remaining_steps() == steps, event.id + " pays once without spending a step for " + branch)
			var expected = event.resolved if branch == "work" else event.alternative_resolved
			expect(Nodes.resolution(node) == expected, event.id + " chosen commission conclusion")
			var before = run.data.duplicate(true)
			for option in ["work", "work_alternative"]:
				expect(not run.use_node("hero", option).ok and run.data == before, event.id + " cannot repay or switch commission")
			expect(run.save_game().ok, event.id + " save commission branch")
			var loaded = Run.new()
			expect(loaded.load_game(run.save_path).ok and loaded.node_at(hero.position).result == branch
				and Nodes.resolution(loaded.node_at(hero.position)) == expected and loaded.data.lamp_coins == coins + node.coins, event.id + " commission survives reload")
			before = loaded.data.duplicate(true)
			for option in ["work", "work_alternative"]:
				expect(not loaded.use_node("hero", option).ok and loaded.data == before, event.id + " saved commission cannot repay")
	expect(covered == 12, "Both branches exercised for all twelve commissions")

func check_investigated_validation() -> void:
	var run = Run.new()
	run.save_path = "user://test-node-investigated-validation.json"
	run.new_run(41, "wayfarer")
	var cell = find_node(run, "haunt")
	expect(not cell.is_empty(), "Validation fixture has a haunt")
	if cell.is_empty():
		return
	run.node_at(cell).erase("investigated")
	expect(run.save_game().ok, "Save old uninvestigated node")
	var loaded = Run.new()
	expect(loaded.load_game(run.save_path).ok and not loaded.node_at(cell).get("investigated", false), "Missing investigation flag remains a valid unchosen legacy state")
	var valid = run.data.duplicate(true)
	var before = loaded.data.duplicate(true)
	for invalid in [0, 1, "true", [], {}, null]:
		var corrupt = valid.duplicate(true)
		corrupt.nodes[cell].investigated = invalid
		var file = FileAccess.open(run.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(corrupt))
		file.close()
		expect(not loaded.load_game(run.save_path).ok and loaded.data == before, "Reject non-boolean investigation without replacing current run: " + str(invalid))

func find_node(run: RefCounted, kind: String) -> String:
	for cell in run.data.nodes:
		if run.node_at(cell).kind == kind:
			return cell
	return ""
