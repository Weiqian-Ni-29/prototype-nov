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
	check_migration()
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
		expect(not Hex.path(run.data.tiles, run.data.start, run.data.boss).is_empty(), "Boss remains reachable through the land routes")
		var coverage = true
		var compatible = true
		var original = Hex.generate(seed_value)
		var layout = Nodes.generate(original.tiles, seed_value, run.relic_sites, {}, {})
		for cell in run.data.tiles:
			var tile = run.data.tiles[cell]
			var node = run.node_at(cell)
			coverage = coverage and (not node.is_empty()) == Hex.is_land(run.data.tiles, cell)
			if node.is_empty():
				continue
			kinds[node.kind] = true
			if layout[cell].kind in ["haunt", "choice"] and cell != run.data.boss:
				expect(node.kind in ["battle", "elite"] and not tile.enemies.is_empty()
					and Nodes.is_elite(tile.enemies) == (node.kind == "elite"), "Retired cell becomes an encounter of the correct tier")
				if Hex.distance(Hex.coord(cell), Hex.coord(run.data.start)) <= 2:
					expect(node.kind == "battle" and tile.enemies == ["boar"] and not tile.hidden, "Replacement encounters near the village are ordinary and visible")
			elif layout[cell].kind not in ["haunt", "choice"]:
				expect(layout[cell].kind == node.kind, "Replacement preserves other node types")
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
	if shop.is_empty() or rest.is_empty():
		expect(false, "Fixture seed has a shop and supplies")
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
		and continued.data.lamp_coins == run.data.lamp_coins
		and not continued.use_node("hero", "pack").ok, "Stock and claimed supply survive reload")
	var recorded_save = run.data.duplicate(true)
	recorded_save.version = 5
	var biome: String = recorded_save.tiles[rest].base_terrain
	recorded_save.nodes[rest] = {"kind": "clue", "event": biome + "_clue_1", "result": "record"}
	recorded_save.leads = {rest: true}
	var old_file = FileAccess.open(run.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(recorded_save))
	old_file.close()
	expect(continued.load_game(run.save_path).ok and continued.node_at(rest).kind in ["battle", "elite", "rest"]
		and continued.node_at(rest).result == "" and not continued.data.has("leads")
		and continued.data.lamp_coins == run.data.lamp_coins,
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
	expect(source is Dictionary and source.size() == 6 and not source.has("haunt") and not source.has("choice"), "Six active kinds retain 72 events")
	if not source is Dictionary:
		return
	var ids = {}
	for kind in ["trade", "supply", "rest", "cache", "battle", "elite"]:
		var entries: Array = source.get(kind, [])
		expect(entries.size() == 12, "Twelve events for " + kind)
		for event in entries:
			expect(not ids.has(event.id), "Catalog id remains unique: " + event.id)
			ids[event.id] = true
			var fields = ["location", "title", "intro", "resolved"]
			for field in fields:
				expect(event.get(field) is String and not str(event.get(field, "")).strip_edges().is_empty(), event.id + " has " + field)
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
	expect(ids.size() == 72, "All 72 active event ids remain")

func check_migration() -> void:
	var run := Run.new()
	run.save_path = "user://test-retired-node-migration.json"
	run.new_run(41, "wayfarer")
	var original = Hex.generate(41)
	var layout := Nodes.generate(original.tiles, 41, run.relic_sites, {}, {})
	var retired := layout.keys().filter(func(cell): return cell != run.data.boss and layout[cell].kind in ["haunt", "choice"])
	var cleared: String = retired[0]
	var unplayed: String = retired[1]
	run.data.version = 5
	for cell in [cleared, unplayed]:
		run.data.nodes[cell] = layout[cell]
		run.data.tiles[cell] = original.tiles[cell]
	run.data.nodes[cleared].result = "settle" if layout[cleared].kind == "haunt" else "work"
	run.data.peace[cleared] = true
	run.data.lamp_coins = 31
	expect(run.save_game().ok, "Legacy fixture saves")
	var restored := Run.new()
	expect(restored.load_game(run.save_path).ok, "Legacy map migrates")
	expect(restored.node_at(cleared).kind in ["battle", "elite"] and restored.node_at(cleared).result == "cleared"
		and restored.data.tiles[cleared].enemies.is_empty() and restored.data.peace.has(cleared),
		"Cleared retired nodes preserve progress and stay cleared")
	expect(restored.node_at(unplayed).kind in ["battle", "elite"] and not restored.data.tiles[unplayed].enemies.is_empty()
		and restored.data.lamp_coins == 31 and restored.data.tiles[restored.data.boss].enemies.is_empty(),
		"Unplayed retired nodes become battles without granting rewards or revealing the boss")
	expect(restored.save_game(run.save_path).ok and run.load_game().ok
		and run.node_at(unplayed).event == restored.node_at(unplayed).event
		and run.data.tiles[unplayed].enemies == restored.data.tiles[unplayed].enemies,
		"Migrated encounter stays stable on the next reload")

func find_node(run: RefCounted, kind: String) -> String:
	for cell in run.data.nodes:
		if run.node_at(cell).kind == kind:
			return cell
	return ""
