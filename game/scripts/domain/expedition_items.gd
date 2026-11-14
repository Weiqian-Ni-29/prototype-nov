extends RefCounted

const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")

static func initialize(data: Dictionary) -> void:
	data.merge({"gear_instances": {}, "next_gear_uid": 1, "item_revision": 0,
		"last_item_operation": {}, "relic_inventory": {}, "relic_attunement": [],
		"relic_seen": {}, "relic_effect_flags": {}, "relic_claims": {}, "relic_intros": [],
		"battle_offers": {}, "item_effect_counts": {}, "map_intel": {}, "route_records": {}})

static func add_gear(data: Dictionary, definition: String, quality: String, kind: String, owner: String) -> String:
	var uid = str(int(data.next_gear_uid))
	data.next_gear_uid = int(data.next_gear_uid) + 1
	data.gear_instances[uid] = {"definition_id": definition, "quality": quality,
		"enhance_level": 0, "upgrade_paid": 0, "owner": {"kind": kind, "id": owner}}
	return uid

static func stock(data: Dictionary, legacy: bool) -> void:
	var cells = data.nodes.keys()
	cells.sort()
	for cell in cells:
		var node = data.nodes[cell]
		var roller = RandomNumberGenerator.new()
		roller.seed = hash("%s:items:%s" % [str(int(data.seed)), cell])
		var terrain: String = data.tiles[cell].terrain
		if node.kind == "trade":
			if node.has("relic_stock"):
				continue
			node.relic_stock = _shop_relics(roller)
			for id in node.stock.keys():
				if not Gear.LEGACY_PRICES.has(id):
					continue
				if legacy:
					for i in int(node.stock[id]):
						add_gear(data, id, "common", "shop", cell)
				node.stock.erase(id)
			if not legacy:
				_stock_shop_gear(data, cell, terrain, roller)
		elif node.kind == "cache" and node.result.is_empty() and not node.has("gear_uid"):
			var definition: String = node.item
			if not legacy:
				definition = Gear.roll_definition(terrain, roller, Gear.SLOTS, ["trail_food", "trail_food"])
			node.item = definition
			if Gear.DATA.has(definition):
				node.gear_uid = add_gear(data, definition, "common" if legacy else Gear.roll_quality(roller), "source", "field_cache:" + cell)

static func refresh_shop(data: Dictionary, cell: String, old_gear: Array, refresh_count: int) -> void:
	var node: Dictionary = data.battle_shop
	var terrain: String = data.tiles[cell].terrain
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("%d:shop_refresh:%s:%d" % [int(data.seed), cell, refresh_count])
	node.stock = Nodes.shop_supplies(roller)
	node.relic_stock = _shop_relics(roller, node.relic_stock.keys())
	for uid in old_gear:
		data.gear_instances.erase(uid)
	_stock_shop_gear(data, cell, terrain, roller)
	node.refresh_count = refresh_count
	node.erase("spell_sold")

static func open_battle_shop(data: Dictionary, cell: String) -> void:
	var terrain: String = data.tiles[cell].terrain
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("%d:battle-shop:%s:%d" % [int(data.seed), cell, int(data.battles)])
	data.battle_shop = {"cell": cell, "stock": Nodes.shop_supplies(roller),
		"relic_stock": _shop_relics(roller), "refresh_count": 0}
	_stock_shop_gear(data, cell, terrain, roller)

static func _shop_relics(roller: RandomNumberGenerator, previous: Array = []) -> Dictionary:
	var active := Relics.DATA.keys().filter(Relics.is_active)
	var pool := active.filter(func(id): return id not in previous)
	if pool.size() < 2:
		pool = active
	pool.sort()
	var stock := {}
	for i in 2:
		stock[pool.pop_at(roller.randi_range(0, pool.size() - 1))] = 1
	return stock

static func _stock_shop_gear(data: Dictionary, cell: String, terrain: String, roller: RandomNumberGenerator) -> void:
	var slots := Gear.SLOTS.duplicate()
	for i in 2:
		var id := Gear.roll_definition(terrain, roller, slots)
		add_gear(data, id, Gear.roll_quality(roller), "shop", cell)
		slots.erase(Gear.DATA[id].slot)

static func migrate(data: Dictionary) -> void:
	initialize(data)
	var actors = data.actors.keys()
	actors.sort()
	for actor_id in actors:
		var actor = data.actors[actor_id]
		for id in Gear.LEGACY_PRICES:
			var slot: String = Gear.DATA[id].slot
			for i in int(actor.inventory.get(id, 0)):
				var uid = add_gear(data, id, "common", "actor", actor_id)
				if i == 0 and actor.equipment[slot] == id:
					actor.equipment[slot] = uid
			actor.inventory.erase(id)
	for id in Relics.DATA:
		if not data.get("relics", {}).has(id):
			continue
		data.relic_seen[id] = true
		if Relics.DATA[id].type == "P":
			data.relic_inventory[id] = 1
			data.relic_attunement.append(id)
		elif id == "life_seed":
			data.relic_effect_flags.life_seed_applied = true
	for key in data.get("relic_checks", {}):
		var id = str(data.relic_checks[key])
		data.relic_claims[key] = {"success": not id.is_empty(), "relic_id": id, "delivered": true}
	for cell in data.get("nodes", {}):
		var node = data.nodes[cell]
		if node.result.is_empty():
			continue
		var source: String = {"choice": "commission", "haunt": "spirit_farewell", "cache": "field_cache"}.get(node.kind, "")
		if not source.is_empty():
			mark_historical(data, source + ":" + cell)
	for id in actors:
		if id != "hero" and data.actors[id].joined:
			mark_historical(data, "recruit:" + id)
	for threshold in [20, 60, 100]:
		if data.get("visited", {}).size() >= threshold:
			mark_historical(data, "explore:" + str(threshold))
	stock(data, true)
	data.erase("relics")
	data.erase("relic_checks")
	data.version = 4

static func mark_historical(data: Dictionary, source: String) -> void:
	if not data.relic_claims.has(source):
		data.relic_claims[source] = {"success": false, "relic_id": "", "delivered": true}

static func whole(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and floor(float(value)) == float(value)

static func validate(data: Dictionary) -> bool:
	for field in ["gear_instances", "last_item_operation", "relic_inventory", "relic_seen", "relic_effect_flags",
			"relic_claims", "battle_offers", "item_effect_counts", "map_intel", "route_records"]:
		if not data.get(field) is Dictionary:
			return false
	if not whole(data.get("next_gear_uid"), 1) or not whole(data.get("item_revision")):
		return false
	var shop: Variant = data.get("battle_shop", {})
	if not shop is Dictionary:
		return false
	if data.has("battle_shop"):
		if not data.has("pending_victory") or shop.get("cell") != data.actors.hero.position \
				or data.status not in ["exploring", "won"] or not data.pending_battle.is_empty() \
				or not shop.get("stock") is Dictionary or not shop.get("relic_stock") is Dictionary \
				or not whole(shop.get("refresh_count")) or not shop.get("spell_sold", false) is bool:
			return false
		for id in shop.stock:
			if id != "trail_food" or not whole(shop.stock[id]):
				return false
		for id in shop.relic_stock:
			if not Relics.is_active(id) or not whole(shop.relic_stock[id]):
				return false
	for uid in data.gear_instances:
		var instance = data.gear_instances[uid]
		if not uid.is_valid_int() or int(uid) < 1 or str(int(uid)) != uid or int(uid) >= data.next_gear_uid \
				or not instance is Dictionary or not Gear.DATA.has(instance.get("definition_id")) \
				or instance.get("quality") not in Gear.QUALITIES or not whole(instance.get("enhance_level")) \
				or instance.enhance_level > Gear.MAX_LEVEL or not whole(instance.get("upgrade_paid")) or not instance.get("owner") is Dictionary:
			return false
		var owner = instance.owner
		match owner.get("kind"):
			"actor":
				if not data.actors.has(owner.get("id")):
					return false
			"shop":
				if (shop.is_empty() or owner.get("id") != shop.cell) \
						and data.get("nodes", {}).get(owner.get("id"), {}).get("kind") != "trade":
					return false
			"source":
				var cell = str(owner.get("id", "")).trim_prefix("field_cache:")
				var node = data.get("nodes", {}).get(cell, {})
				if owner.id != "field_cache:" + cell or node.get("kind") != "cache" or node.get("gear_uid") != uid \
						or node.get("item") != instance.definition_id or not node.result.is_empty():
					return false
			_:
				return false
	for actor_id in data.actors:
		var actor = data.actors[actor_id]
		for id in actor.inventory:
			if Gear.DATA.has(id):
				return false
		for slot in actor.equipment:
			var uid = actor.equipment[slot]
			if not uid is String or slot not in Gear.SLOTS:
				return false
			if uid.is_empty():
				continue
			var instance = data.gear_instances.get(uid, {})
			if instance.is_empty() or instance.owner != {"kind": "actor", "id": actor_id} or Gear.DATA[instance.definition_id].slot != slot:
				return false
	for id in data.relic_seen:
		if not Relics.DATA.has(id) or data.relic_seen[id] != true:
			return false
	for id in data.relic_inventory:
		if not data.relic_seen.has(id) or not whole(data.relic_inventory[id], 1):
			return false
	var seen: Dictionary = {}
	if not data.get("relic_attunement") is Array or data.relic_attunement.size() > 6:
		return false
	for id in data.relic_attunement:
		if seen.has(id) or not data.relic_inventory.has(id) or not Relics.is_active(id) or Relics.DATA[id].type != "P":
			return false
		seen[id] = true
	for id in data.relic_effect_flags:
		if id not in ["life_seed_applied", "last_battle_wounded_victory", "chess_survey_elite", "chess_survey_ordinary",
				"chess_survey_bonus", "chess_workshop_credit", "chess_spell_discount"] or data.relic_effect_flags[id] != true:
			return false
	for claim in data.relic_claims.values():
		if not claim is Dictionary or not claim.get("delivered") is bool or not claim.get("success") is bool \
				or not claim.get("relic_id") is String or claim.success != (not claim.relic_id.is_empty()) \
				or (claim.success and not data.relic_seen.has(claim.relic_id)):
			return false
	for id in data.battle_offers:
		if not data.battle_offers[id] is String or (data.battle_offers[id] != "" and not Relics.DATA.has(data.battle_offers[id])):
			return false
	for node in data.get("nodes", {}).values():
		if node.kind == "trade":
			if not node.get("relic_stock") is Dictionary or not whole(node.get("refresh_count", 0)):
				return false
			for id in node.relic_stock:
				if not Relics.is_active(id) or not whole(node.relic_stock[id]):
					return false
		elif node.has("gear_uid") and not data.gear_instances.has(node.gear_uid):
			return false
	return true
