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
	check_generation()
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
		for cell in run.data.tiles:
			var tile = run.data.tiles[cell]
			var node = run.node_at(cell)
			coverage = coverage and (not node.is_empty()) == Hex.is_land(run.data.tiles, cell)
			if node.is_empty():
				continue
			kinds[node.kind] = true
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
	run.split_squad(["lorne"])
	var stock = run.node_at(shop).stock
	var original_stock = int(stock.salve)
	var original_salve = int(hero.inventory.salve)
	expect(run.trade("hero", "salve", true).ok and run.data.lamp_coins == 2
		and hero.inventory.salve == original_salve + 1 and stock.salve == original_stock - 1,
		"Buying updates the shared wallet, stock and buyer's inventory")
	var before = JSON.stringify(run.data)
	expect(not run.trade("lorne", "ether", true).ok and not run.trade("hero", "trail_blade", false).ok
		and JSON.stringify(run.data) == before, "Unfunded purchases and equipped sales have no side effects")
	expect(run.trade("lorne", "salve", false).ok and run.data.lamp_coins == 5 and stock.salve == original_stock - 1,
		"Another squad sells from its own bag into the same wallet")
	expect(not run.trade("hero", "Q-T", false).ok, "Story documents cannot be sold")

	hero.position = work
	expect(run.use_node("hero", "work").ok and run.data.lamp_coins == 5 + run.node_at(work).coins
		and not run.use_node("hero", "work").ok, "A local commission pays once")
	hero.position = rest
	lorne.position = rest
	hero.hp = 20
	hero.mp = 5
	lorne.hp = 0
	hero.ap = 0
	for day in range(3):
		expect(run.end_day().ok, "Days can still advance")
	expect(hero.hp == 20 and hero.mp == 5 and hero.ap == hero.ap_max, "Repeated days restore effort only")
	var percent = run.recovery_percent(rest, "hp")
	expect(run.use_node("hero", "hp").ok and hero.hp == 20 + ceili(hero.hp_max * percent / 100.0)
		and hero.mp == 5 and lorne.hp == 0, "Rest treats only the chosen resource of living people here")
	expect(not run.use_node("hero", "mp").ok and not run.use_node("hero", "pack").ok,
		"All recovery choices spend the same supply")
	expect(run.save_game().ok, "Save resolved nodes and wallet")
	var continued = Run.new()
	expect(continued.load_game(run.save_path).ok, "Load the expedition with node state")
	expect(continued.node_at(shop).stock.salve == stock.salve and continued.node_at(rest).result == "hp"
		and continued.node_at(work).result == "work" and continued.data.lamp_coins == run.data.lamp_coins
		and not continued.use_node("hero", "hp").ok, "Stock and spent recovery survive reload")
	var legacy = run.data.duplicate(true)
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

func find_node(run: RefCounted, kind: String) -> String:
	for cell in run.data.nodes:
		if run.node_at(cell).kind == kind:
			return cell
	return ""
