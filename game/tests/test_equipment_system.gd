extends SceneTree

const Run = preload("res://scripts/domain/expedition.gd")
const Items = preload("res://scripts/domain/expedition_items.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Battle = preload("res://tests/legacy/realtime_battle.gd")
const Main = preload("res://scenes/main.tscn")

var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func fixture() -> RefCounted:
	var run = Run.new()
	run.save_path = "user://test-equipment-system.json"
	run.new_run(41, "wayfarer")
	return run

func position_for(run, kind: String) -> String:
	for cell in run.data.nodes:
		if run.node_at(cell).kind == kind and run.data.tiles[cell].enemies.is_empty():
			return cell
	return ""

func add_gear(run, actor: String, id: String, quality: String = "common") -> String:
	return Items.add_gear(run.data, id, quality, "actor", actor)

func equip_set(run, actor: String, set_id: String, pieces: int = 3) -> void:
	for slot in Gear.SLOTS.slice(0, pieces):
		var uid = add_gear(run, actor, set_id + "_" + slot)
		expect(run.equip(actor, uid).ok, "Equip fixture piece " + set_id + "_" + slot)

func check_catalogs() -> void:
	expect(Gear.DATA.size() == 39 and Gear.SETS.size() == 12 and Relics.DATA.size() == 100, "Complete catalog sizes")
	var counts = {"P": 0, "C": 0, "L": 0}
	for id in Relics.DATA:
		var definition = Relics.DATA[id]
		counts[definition.type] += 1
		expect(not definition.effect.is_empty() and not definition.story.is_empty() and (definition.params.has("limit") or not Relics.is_active(id)),
			"Relic has effect parameters and player text: " + id)
	expect(counts == {"P": 80, "C": 19, "L": 1}, "Relic categories")
	for id in Gear.SETS:
		for slot in Gear.SLOTS:
			var item = Gear.DATA[id + "_" + slot]
			expect(item.slot == slot and item.set_id == id and not item.story.is_empty(), "Complete suite entry " + id)
	for i in Gear.QUALITIES.size():
		var instance = {"definition_id": "trail_blade", "quality": Gear.QUALITIES[i], "enhance_level": 0, "upgrade_paid": 0}
		var total = 0
		for j in 5:
			instance.enhance_level = j
			total += Gear.upgrade_price(instance)
		expect(total == [220, 275, 330, 385, 440][i], "All five enhancement costs for " + instance.quality)

func check_equipment() -> void:
	var run = fixture()
	var duplicate = fixture()
	expect(run.data.gear_instances == duplicate.data.gear_instances, "Stock quality and instances are seed-stable")
	var shop = position_for(run, "trade")
	var hero: Dictionary = run.actor("hero")
	hero.position = shop
	run.actor("lorne").position = shop
	run.join_companion("lorne")
	var stocked: Array = run.gear_owned("shop", shop)
	expect(stocked.size() == 2 and Gear.DATA[run.data.gear_instances[stocked[0]].definition_id].slot != Gear.DATA[run.data.gear_instances[stocked[1]].definition_id].slot,
		"Every shop starts with distinct equipment slots")
	expect(run.node_at(shop).relic_stock.size() == 2, "Relic stock is independently generated")
	var spare = add_gear(run, "hero", "trail_blade", "rare")
	var primary: String = hero.equipment.weapon
	run.data.lamp_coins = 1000
	var revision = int(run.data.item_revision)
	var enhance = run.enhance.bind("hero", spare)
	var result: Dictionary = run.commit_item_operation("test-enhance", revision, enhance)
	expect(result.ok and run.commit_item_operation("test-enhance", revision, enhance) == result
		and not run.commit_item_operation("stale", revision, enhance).ok, "Repeated or stale enhancement confirmations are harmless")
	expect(run.data.gear_instances[spare].enhance_level == 1 and run.data.gear_instances[primary].enhance_level == 0
		and run.data.lamp_coins == 994 and run.remaining_steps() == 5, "Only the selected instance is strengthened")
	expect(run.gear_transfer("hero", "lorne", spare).ok and not run.gear_transfer("hero", "lorne", primary).ok,
		"An unmounted copy can be transferred while the worn copy remains equipped")
	var sale: Dictionary = run.gear_trade("lorne", spare, false)
	expect(sale.ok and spare in run.gear_owned("shop", shop), "Sale moves the original instance into stock")
	expect(run.gear_trade("hero", spare, true).ok and spare in run.gear_owned("actor", "hero")
		and run.data.gear_instances[spare].enhance_level == 1, "Buying back preserves ID and enhancement")
	expect(run.equip("hero", spare).ok and run.stat("hero", "attack") == hero.attack + 6, "Enhanced weapon is reflected in stats")
	equip_set(run, "hero", "frontier_guard", 2)
	expect(run.set_count("hero", "frontier_guard") == 2 and run.set_count("lorne", "frontier_guard") == 0,
		"Only slots actually worn by one character are counted")
	expect(run.save_game().ok and duplicate.load_game(run.save_path).ok, "Gear save loads successfully")
	var saved_copy: Dictionary = duplicate.data.gear_instances.get(spare, {})
	expect(saved_copy.get("enhance_level") == 1 and saved_copy.get("definition_id") == "trail_blade"
		and saved_copy.get("owner") == {"kind": "actor", "id": "hero"} and duplicate.data.gear_instances.size() == run.data.gear_instances.size(),
		"Saving and loading preserves gear identity")

func check_shop_refresh() -> void:
	var run = fixture()
	var shops: Array = run.data.nodes.keys().filter(func(cell):
		return run.node_at(cell).kind == "trade" and run.data.tiles[cell].enemies.is_empty())
	expect(shops.size() >= 2, "Refresh fixture includes independent shops")
	if shops.size() < 2:
		return
	var first: String = shops[0]
	var second: String = shops[1]
	run.actor("hero").position = first
	var purchased: String = run.gear_owned("shop", first)[0]
	run.data.lamp_coins = 1000
	expect(run.gear_trade("hero", purchased, true).ok, "Buy gear before refreshing")
	var wallet: int = run.data.lamp_coins
	var old_gear: Array = run.gear_owned("shop", first)
	var old_relics: Dictionary = run.node_at(first).relic_stock.duplicate()
	var other_stock: Dictionary = run.node_at(second).duplicate(true)
	run.node_at(first).stock.salve = 0
	var revision: int = run.data.item_revision
	var refresh: Callable = run.refresh_shop.bind("hero")
	expect(run.shop_refresh_cost(first) == 1 and run.commit_item_operation("first-refresh", revision, refresh).ok,
		"The first refresh costs one lamp coin")
	expect(run.commit_item_operation("first-refresh", revision, refresh).ok and run.data.lamp_coins == wallet - 1
		and run.shop_refresh_cost(first) == 2, "A duplicate confirmation cannot refresh or charge twice")
	expect(run.node_at(first).stock.salve > 0 and run.gear_owned("shop", first).size() == 2
		and old_gear.all(func(uid): return not run.data.gear_instances.has(uid))
		and old_relics.keys().all(func(id): return not run.node_at(first).relic_stock.has(id)),
		"Refresh replenishes supplies and replaces shop-owned equipment and relics")
	expect(purchased in run.gear_owned("actor", "hero") and run.node_at(second) == other_stock
		and run.shop_refresh_cost(second) == 1, "Refresh preserves purchases and other merchants")
	expect(run.refresh_shop("hero").ok and run.data.lamp_coins == wallet - 3 and run.shop_refresh_cost(first) == 3,
		"The second refresh costs two lamp coins")
	run.data.lamp_coins = 2
	var before: Dictionary = run.data.duplicate(true)
	expect(not run.refresh_shop("hero").ok and run.data == before, "A failed refresh leaves currency, goods and cost intact")
	var saved: bool = run.save_game().ok and run.load_game().ok
	var stock: Dictionary = run.node_at(first).relic_stock
	var previous_stock: Dictionary = before.nodes[first].relic_stock
	expect(saved and run.shop_refresh_cost(first) == 3 and run.shop_refresh_cost(second) == 1
		and stock.size() == previous_stock.size()
		and stock.keys().all(func(id): return int(stock[id]) == int(previous_stock.get(id, 0))),
		"Save and load preserve the refreshed stock and each shop's price")

func check_bulk_trade() -> void:
	var run = fixture()
	var cell := position_for(run, "trade")
	run.actor("hero").position = cell
	run.grant_relic("survey_bonus_stamp", "hero", cell)
	run.grant_relic("modest_trade_coupon", "hero", cell)
	for visited in run.data.tiles.keys().slice(0, 61):
		run.data.visited[visited] = true
	run.node_at(cell).relic_stock.lamp_badge = 2
	run.data.lamp_coins = 199
	var quote: Dictionary = run.shop_quote(100, true, 2)
	var before: Dictionary = run.data.duplicate(true)
	expect(quote.price == 200 and quote.unit_price == 100 and quote.additional_unit_price == 100,
		"Bulk quote charges both units at the shown price")
	expect(not run.trade("hero", "lamp_badge", true, "", 2).ok and run.data == before,
		"An unaffordable bulk order never partially changes the inventory")
	run.data.lamp_coins += 1
	expect(run.trade("hero", "lamp_badge", true, "", 2).ok and run.data.lamp_coins == 0
		and run.data.relic_inventory.lamp_badge == 2 and run.node_at(cell).relic_stock.lamp_badge == 0
		and run.data.relic_inventory.modest_trade_coupon == 1, "Bulk purchase charges the quote and preserves battle preparations")
	expect(run.trade("hero", "lamp_badge", false, "", 2).ok and run.data.lamp_coins == 80
		and not run.has_relic("lamp_badge") and run.node_at(cell).relic_stock.lamp_badge == 2,
		"Bulk sale restores stock and removes attunement only after selling the last copy")

func check_relics() -> void:
	var run = fixture()
	var hero: Dictionary = run.actor("hero")
	var first: Array = ["telescope", "uphill_kneepad", "ranged_sight", "lamp_badge", "herbal_case", "rainstone"]
	for id in first:
		run.grant_relic(id, "hero", hero.position)
	run.grant_relic("opening_flint", "hero", hero.position)
	run.grant_relic("telescope", "hero", hero.position)
	expect(run.data.relic_attunement == first and run.data.relic_inventory.telescope == 2,
		"Only six distinct passives auto-attune")
	expect(not run.attune_relic("hero", "opening_flint").ok and run.attune_relic("hero", "rainstone").ok
		and run.attune_relic("hero", "opening_flint").ok, "Full slots require deliberate replacement")
	var shop = position_for(run, "trade")
	hero.position = shop
	expect(run.trade("hero", "telescope", false).ok and run.has_relic("telescope") and run.trade("hero", "telescope", false).ok
		and not run.has_relic("telescope") and run.data.relic_seen.has("telescope"),
		"Only selling the last copy removes attunement; discovery is retained")
	run.grant_relic("stillwater_stone", "hero", shop)
	expect(not run.use_relic("hero", "stillwater_stone").ok and run.data.relic_inventory.stillwater_stone == 1,
		"An inapplicable consumable is not spent")
	hero.mp = 0
	expect(not run.use_relic("hero", "stillwater_stone").ok and "stillwater_stone" in run.preparation_options(),
		"Consumable is available for the next battle without changing map resources")
	var successes = 0
	for seed in 10000:
		run.data.seed = seed
		successes += int(not run.relic_offer("battle:test:", ["life_seed", "telescope"], 0.30).is_empty())
	expect(successes >= 2700 and successes <= 3300, "Ten thousand seeds keep ordinary drop rate near 30%%")
	run.data.relic_seen.clear()
	run.data.relic_seen["life_seed"] = true
	expect(run.relic_offer("battle:test:", ["life_seed", "telescope"], 1.0) == "telescope", "Prefer a new relic")
	run.data.relic_seen["telescope"] = true
	expect(not run.relic_offer("battle:test:", ["life_seed", "telescope"], 1.0).is_empty(), "An exhausted pool yields a duplicate")

func check_migration() -> void:
	var run = fixture()
	var legacy: Dictionary = run.data.duplicate(true)
	legacy.version = 3
	legacy.relics = {"telescope": true, "life_seed": true, "rain_bell": true}
	legacy.relic_checks = {"battle:0,0:": ""}
	legacy.erase("gear_instances")
	legacy.erase("relic_seen")
	legacy.erase("relic_claims")
	legacy.erase("relic_inventory")
	legacy.erase("relic_attunement")
	legacy.erase("relic_effect_flags")
	var hero = legacy.actors.hero
	hero.hp = 21
	hero.hp_max = 114
	hero.inventory.merge({"trail_blade": 2, "padded_coat": 1, "lamp_charm": 1})
	hero.equipment = {"weapon": "trail_blade", "armor": "padded_coat", "accessory": "lamp_charm"}
	for node in legacy.nodes.values():
		node.erase("gear_uid")
		if node.kind == "trade":
			node.erase("relic_stock")
			node.stock["trail_blade"] = 1
		elif node.kind == "cache":
			node.item = "ether"
	run.save_game()
	legacy.rng_state = run.data.rng_state
	var file = FileAccess.open(run.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var loaded = Run.new()
	expect(loaded.load_game(run.save_path).ok, "Load version 3 with legacy inventory and relics")
	if loaded.data.is_empty():
		return
	var a = loaded.actor("hero")
	expect(loaded.data.version == Run.SAVE_VERSION and loaded.gear_owned("actor", "hero").size() == 5
		and loaded.equipped_definition("hero", "weapon") == "trail_blade" and not a.inventory.has("trail_blade"),
		"Migration does not create an extra copy for the worn weapon")
	expect(a.hp == 21 and a.hp_max == 114 and loaded.data.relic_effect_flags.life_seed_applied
		and loaded.has_relic("telescope") and not loaded.data.relic_inventory.has("rain_bell"),
		"Migration preserves resources, passive attunement and consumed relic history")
	expect(loaded.data.relic_claims["battle:0,0:"].delivered and not loaded.data.relic_claims["battle:0,0:"].success,
		"Previously failed sources are not redrawn")

func check_battle() -> void:
	var run = fixture()
	var hero: Dictionary = run.actor("hero")
	var position: String = hero.position
	hero.skill = "frost_arrow"
	equip_set(run, "hero", "rime_path", 2)
	run.grant_relic("copper_rain_comb", "hero", position)
	run.grant_relic("field_water_sponge", "hero", position)
	run.data.tiles[position].terrain = "forest"
	run.data.tiles[position].enemies = ["hunter_elite"]
	var combat = Battle.new()
	var encounter = {"position": position, "origin": position, "ambush": false, "npc": "", "movers": [], "reward_tier": "elite"}
	expect(combat.begin(run, encounter, ["hero"]).ok, "Start an elite encounter")
	var offer: String = combat.pending.relic_offer
	expect(not offer.is_empty() and not run.data.relic_inventory.has(offer), "Elite reward is frozen before combat without being granted")
	combat.unit("enemy_0").hp = 1000
	combat.unit("enemy_0").hp_max = 1000
	combat._apply_field_effect("wet")
	var preview: int = combat.damage_preview("hero", "enemy_0", "frost_arrow")
	var counters = run.data.item_effect_counts.duplicate()
	expect(combat.damage_preview("hero", "enemy_0", "frost_arrow") == preview and run.data.item_effect_counts == counters,
		"Damage preview does not spend a field allowance")
	expect(combat._cast("hero", "frost_arrow", "enemy_0").ok and combat.field_view().fields.has("frozen")
		and combat.unit("enemy_0").hp == 1000 - preview, "An ice hit over wet creates frozen and applies the previewed hit")
	combat.items.fields.clear()
	combat.wet = false
	combat._apply_field_effect("ignite")
	expect(combat._cast("hero", "torrent", "enemy_0").ok and combat.burning and combat.wet
		and combat.items.fields.wet == combat.items.index + 7, "Water creates wet without extinguishing fire; sponge extends only wet")
	expect(combat._cast("hero", "thunderbolt", "enemy_0").ok and not combat.items.present("charged"),
		"An already burning field cannot gain the proposed conductive layer")
	combat.unit("enemy_0").hp = 0
	combat.check_end()
	expect(run.data.relic_inventory.get(offer) == 1 and run.data.relic_claims[combat.pending.battle_uid].delivered
		and run.data.tiles[position].terrain == "forest" and not run.data.tiles[position].has("burning"), "Victory commits one drop and never rewrites terrain")

func find_button(parent: Node, prefix: String) -> Button:
	for button in parent.find_children("*", "Button", true, false):
		if button.text.begins_with(prefix):
			return button
	return null

func check_ui() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-equipment-ui.json"
	game._start_new()
	game.run.data.lamp_coins = 100
	game._inventory_dialog("hero", 1)
	await process_frame
	var tabs := game.modal_layer.find_child("InventoryTabs", true, false) as TabContainer
	var grid: GridContainer = tabs.get_child(1).grid
	var item: Button
	for slot in grid.get_children():
		if slot is Button and slot.tooltip_text.begins_with("巡路短刃 · 普通"):
			item = slot
			break
	expect(item != null and item.icon != null and is_equal_approx(item.size.x, item.size.y),
		"Gear grid exposes the existing weapon instance in a square icon slot")
	if item != null:
		item.pressed.emit()
		await process_frame
		var enhance = find_button(game.modal_layer, "强化至 +1")
		expect(enhance != null and not enhance.disabled, "Gear detail exposes the real enhancement quote")
		if enhance != null:
			enhance.pressed.emit()
			await process_frame
			var uid: String = game.run.actor("hero").equipment.weapon
			tabs = game.modal_layer.find_child("InventoryTabs", true, false) as TabContainer
			expect(game.run.data.gear_instances[uid].enhance_level == 1 and game.run.data.lamp_coins == 96
				and tabs.current_tab == 1 and tabs.get_child(1).selected_id == uid,
				"UI enhancement updates both the instance and wallet and keeps the gear selected")
	game.queue_free()
	await create_timer(0.3).timeout

func execute() -> void:
	check_catalogs()
	check_equipment()
	check_shop_refresh()
	check_bulk_trade()
	check_relics()
	check_migration()
	check_battle()
	await check_ui()
	print("EQUIPMENT SYSTEM: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
