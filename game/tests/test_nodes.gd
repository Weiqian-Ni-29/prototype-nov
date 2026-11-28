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
	check_migration()
	check_shop_migration()
	print("LEGACY MAP SAVE MIGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

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

func check_shop_migration() -> void:
	var run := Run.new()
	run.save_path = "user://test-shop-node-migration.json"
	run.new_run(41, "wayfarer")
	var cell: String = run.data.nodes.keys().filter(func(id):
		return id != run.data.start and id != run.data.boss and run.node_at(id).kind == "supply")[0]
	var tile: Dictionary = run.data.tiles[cell]
	run.data.version = 9
	run.data.nodes[cell] = {"kind": "trade", "event": tile.base_terrain + "_trade_1", "result": "",
		"stock": {"salve": 1}, "relic_stock": {}, "starter_shop": true}
	var item = preload("res://scripts/domain/expedition_items.gd").add_gear(run.data, "trail_blade", "common", "shop", cell)
	run.data.lamp_coins = 37
	run.actor("hero").inventory.merge({"salve": 2, "ether": 1})
	run.data.pending_story_rewards = {"source": "旧奖励", "items": [
		{"kind": "item", "id": "salve", "count": 2}, {"kind": "item", "id": "trail_food", "count": 1}]}
	var neighbors := Hex.neighbors(cell, run.data.tiles)
	expect(run.save_game().ok, "Write a version nine save with an opening shop")
	var restored := Run.new()
	expect(restored.load_game(run.save_path).ok and restored.node_at(cell).kind == "battle"
		and not restored.data.tiles[cell].enemies.is_empty() and restored.shop_at(cell).is_empty(),
		"The old shop now hosts an ordinary battle and has no inventory")
	expect(not restored.data.gear_instances.has(item) and restored.data.lamp_coins == 37
		and restored.actor("hero").equipment == run.actor("hero").equipment and Hex.neighbors(cell, restored.data.tiles) == neighbors,
		"Migration removes stock and preserves owned equipment, wallet and map coordinates")
	expect(not restored.actor("hero").inventory.has("salve") and not restored.actor("hero").inventory.has("ether")
		and restored.data.pending_story_rewards.items.size() == 1 and restored.data.pending_story_rewards.items[0].id == "trail_food",
		"Migration removes both retired supplies from inventory and pending rewards")
