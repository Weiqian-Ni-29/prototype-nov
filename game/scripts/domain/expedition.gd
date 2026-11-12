class_name Expedition
extends RefCounted
## Authoritative state: renderers never own or regenerate resources.
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Items = preload("res://scripts/domain/expedition_items.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const SAVE_VERSION = 9
const STEPS_PER_DAY = 5
signal changed
var data: Dictionary = {}
var rng = RandomNumberGenerator.new()
var save_path = "user://expedition.json"
var relic_sites: Dictionary = {}
var prepared_relic := ""
var prepared_weather := ""
const SPELL_RELICS = {"banked_ember_box": "ember_spell", "rime_thimble": "ice_spell",
	"herbal_case": "mend_spell", "crossed_wind_chimes": "fog_spell"}
var location_names: Dictionary = {}

func new_run(seed_value: int, profession: String) -> void:
	assert(Catalog.PROFESSIONS.has(profession))
	prepared_relic = ""
	prepared_weather = ""
	var generated = Hex.generate(seed_value)
	rng.seed = seed_value ^ 0x5eed123
	data = {"version": SAVE_VERSION, "seed": seed_value, "profession": profession, "day": 1, "steps_today": 0, "weather": "sun", "tiles": generated.tiles, "start": generated.start, "boss": generated.boss, "peace": {}, "chapter": 0, "actors": {}, "explored": {}, "visited": {}, "flags": {}, "knowledge": {}, "story": {}, "rewards": {}, "choices": [], "status": "exploring", "log": [], "battles": 0, "transaction": 0, "pending_battle": {}}
	var hero_def = Catalog.PROFESSIONS[profession].duplicate(true)
	hero_def["title"] = "旅人"
	hero_def["name"] = "旅人"
	hero_def["element"] = "none"
	hero_def["portrait"] = "hero"
	hero_def["skill"] = "gravity"
	hero_def["attack_delivery"] = "ranged"
	hero_def["ultimate"] = "gravity_drift"
	data.actors["hero"] = _actor("hero", hero_def, generated.start, true)
	Items.initialize(data)
	data.actors.hero.inventory.trail_food = 2
	for id in Gear.LEGACY_PRICES:
		data.actors.hero.equipment[Gear.DATA[id].slot] = Items.add_gear(data, id, "common", "actor", "hero")
	Items.add_gear(data, "frontier_guard_weapon", "common", "actor", "hero")
	data.spell_collection = Cards.STARTER_SPELLS.duplicate()
	for id in Catalog.COMPANIONS:
		var location = ""
		for k in data.tiles:
			if data.tiles[k].npc == id:
				location = k
		data.actors[id] = _actor(id, Catalog.COMPANIONS[id], location, false)
		data.story[id] = {"relation": "unmet", "result": "E0", "met": false}
	_initialize_relics()
	_initialize_nodes(true, true)
	Items.stock(data, false)
	reveal(generated.start)
	note("村民送来了疗伤药、澄露和干粮。你想到附近走走，看有没有人认得你，能不能想起自己的名字。")

func _actor(id: String, definition: Dictionary, position: String, joined: bool) -> Dictionary:
	var result = definition.duplicate(true)
	result.merge({"id": id, "position": position, "joined": joined, "hp_max": definition.hp, "mp_max": definition.mp, "energy": 0, "inventory": {"salve": 3 if id == "hero" else 1, "ether": 2 if id == "hero" else 1}, "equipment": {"weapon": "", "armor": "", "accessory": ""}, "shield": 0, "slow": 0, "guard": false}, true)
	return result

func actor(id: String) -> Dictionary:
	return data.get("actors", {}).get(id, {})

func joined_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in data.actors:
		if data.actors[id].joined:
			ids.append(id)
	return ids

func same_cell(position: String, healthy: bool = false) -> Array[String]:
	var ids: Array[String] = []
	for id in joined_ids():
		if actor(id).position == position and (not healthy or actor(id).hp > 0):
			ids.append(id)
	return ids

func _relocate_party(destination: String) -> void:
	for id in joined_ids():
		actor(id).position = destination

func retreat_party(destination: String) -> void:
	_relocate_party(destination)
	data.route_records.clear()

func stat(id: String, field: String) -> int:
	var a = actor(id)
	var value = int(a.get(field, 0))
	for uid in a.equipment.values():
		if not uid.is_empty():
			value += Gear.bonus(data.gear_instances[uid], field)
	return value

func gear_owned(kind: String, id: String) -> Array:
	var result: Array = []
	for uid in data.gear_instances:
		if data.gear_instances[uid].owner == {"kind": kind, "id": id}:
			result.append(uid)
	return result

func equipped_definition(id: String, slot: String) -> String:
	var uid: String = actor(id).equipment.get(slot, "")
	return str(data.gear_instances.get(uid, {}).get("definition_id", ""))

func set_count(id: String, set_id: String) -> int:
	var count = 0
	for slot in Gear.SLOTS:
		var definition = Gear.DATA.get(equipped_definition(id, slot), {})
		if definition.get("set_id") == set_id:
			count += 1
	return count

func gear_trade(id: String, uid: String, buying: bool, voucher: String = "") -> Dictionary:
	var check = _node_access(id)
	if not check.ok:
		return check
	var a = actor(id)
	var instance = data.gear_instances.get(uid, {})
	var kind = "shop" if buying else "actor"
	var owner: String = a.position if buying else id
	if node_at(a.position).get("kind") != "trade" or instance.get("owner") != {"kind": kind, "id": owner}:
		return fail("这件装备当前无法交易。")
	var quote = item_quote(Gear.price(instance), "shop_buy" if buying else "shop_sell", uid, voucher)
	if not quote.ok:
		return quote
	if buying and data.lamp_coins < quote.price:
		return fail("灯铢不足。")
	data.lamp_coins += -quote.price if buying else quote.price
	instance.owner = {"kind": "actor" if buying else "shop", "id": id if buying else a.position}
	if not buying:
		if data.has("card_deck"):
			data.card_deck.erase("gear:" + uid)
		for slot in a.equipment:
			if a.equipment[slot] == uid:
				a.equipment[slot] = ""
	_commit_price(quote)
	return _item_result("%s「%s」，%d 灯铢。" % ["买入" if buying else "卖出", Gear.label(instance), quote.price])

func gear_transfer(id: String, target: String, uid: String) -> Dictionary:
	var a = actor(id)
	var b = actor(target)
	var instance = data.gear_instances.get(uid, {})
	if data.status != "exploring" or not data.pending_battle.is_empty() or a.is_empty() or b.is_empty() \
			or id == target or not a.joined or not b.joined or a.position != b.position or same_cell(a.position, true).is_empty():
		return fail("同一地块得有能行动的队员帮忙，才能交接装备。")
	if instance.get("owner") != {"kind": "actor", "id": id} or uid in a.equipment.values():
		return fail("只能交接自己持有且已卸下的装备。")
	instance.owner.id = target
	return _item_result("已交接「%s」。" % Gear.label(instance))

func enhance_card(id: String, uid: String) -> Dictionary:
	var previous := data.duplicate(true)
	var result := enhance(id, uid)
	if not result.ok:
		return result
	var saved := save_game()
	if not saved.ok:
		data = previous
		changed.emit()
		return saved
	return result

func enhancement_quote(id: String, uid: String, voucher: String = "") -> Dictionary:
	var check = _node_access(id)
	if not check.ok:
		return check
	var instance = data.gear_instances.get(uid, {})
	if instance.get("owner") != {"kind": "actor", "id": id}:
		return fail("该角色已不持有此装备。")
	if instance.enhance_level >= Gear.MAX_LEVEL:
		return fail("已经强化至 +5。")
	var quote = item_quote(Gear.upgrade_price(instance), "enhancement_fee", uid, voucher)
	if quote.ok and data.lamp_coins < quote.price:
		quote["message"] = "灯铢不足。"
	return quote

func enhance(id: String, uid: String, voucher: String = "") -> Dictionary:
	var quote = enhancement_quote(id, uid, voucher)
	if not quote.ok:
		return quote
	if data.lamp_coins < quote.price:
		return fail("灯铢不足。")
	var instance = data.gear_instances[uid]
	data.lamp_coins -= quote.price
	instance.enhance_level += 1
	instance.upgrade_paid += quote.price
	_commit_price(quote)
	return _item_result("已强化「%s」，花费 %d 灯铢。" % [Gear.label(instance), quote.price])

func item_quote(base: int, channel: String, _uid: String = "", voucher: String = "", _used_claims: Array = []) -> Dictionary:
	if not voucher.is_empty():
		return fail("这件遗器可在开战前携带。")
	var price := floori(base * 0.4) if channel == "shop_sell" else base
	return {"ok": true, "price": price, "claims": [], "voucher": ""}

func _commit_price(quote: Dictionary) -> void:
	for key in quote.claims:
		data.item_effect_counts[key] = 1
	if not quote.voucher.is_empty():
		_remove_relic(quote.voucher)

func _item_result(message: String) -> Dictionary:
	data.item_revision += 1
	data.route_records.clear()
	note(message)
	changed.emit()
	return {"ok": true, "message": message}

func commit_item_operation(operation_id: String, revision: int, action: Callable) -> Dictionary:
	if operation_id.is_empty():
		return fail("这次操作没能确认，请重新试一次。")
	var previous = data.last_item_operation
	if previous.get("id") == operation_id:
		return previous.result.duplicate(true)
	if revision != int(data.item_revision):
		return fail("物品或价格已变化，请重新确认。")
	var result: Dictionary = action.call()
	if result.ok:
		data.last_item_operation = {"id": operation_id, "result": result.duplicate(true)}
	return result

func reveal(position: String) -> void:
	data.visited[position] = true
	_reveal_sight(position)

func _reveal_sight(position: String) -> void:
	data.explored[position] = true
	for k in Hex.neighbors(position, data.tiles):
		data.explored[k] = true
		if has_relic("telescope"):
			for outer in Hex.neighbors(k, data.tiles):
				data.explored[outer] = true

func _initialize_relics() -> void:
	relic_sites = Relics.exploration_sites(data.tiles, int(data.seed))

func _initialize_nodes(rebalance: bool = false, opening_shop: bool = false) -> void:
	data.merge({"lamp_coins": Nodes.STARTING_COINS})
	if not data.has("nodes"):
		data.nodes = Nodes.generate(data.tiles, int(data.seed), relic_sites, data.rewards, {})
	Nodes.replace_retired_nodes(data)
	Nodes.merge_supplies(data)
	if opening_shop:
		Nodes.place_opening_shop(data, relic_sites)
	if rebalance:
		Nodes.raise_elite_share(data)
	location_names.clear()
	var by_title: Dictionary = {}
	var cells = data.nodes.keys()
	cells.sort()
	for cell in cells:
		var tile = data.tiles[cell]
		var title: String = "村庄" if tile.site == "start" else Nodes.story(node_at(cell)).get("location", Catalog.terrain_name(tile.base_terrain))
		if not by_title.has(title):
			by_title[title] = []
		by_title[title].append(cell)
	for title in by_title:
		var matches: Array = by_title[title]
		for index in matches.size():
			location_names[matches[index]] = title if matches.size() == 1 else "%s %d" % [title, index + 1]

func node_at(cell: String) -> Dictionary:
	return data.nodes.get(cell, {})

func location_name(cell: String) -> String:
	if cell == data.boss and boss_known():
		return "战神卡德兰"
	return location_names.get(cell, Catalog.terrain_name(data.tiles[cell].terrain))

func _node_access(id: String) -> Dictionary:
	var check = _map_action(id)
	if not check.ok:
		return check
	var tile = data.tiles[actor(id).position]
	if not tile.enemies.is_empty():
		return fail("这里还有危险，先清掉敌人。")
	return success()

func shop_refresh_cost(cell: String) -> int:
	return int(node_at(cell).get("refresh_count", 0)) + 1

func refresh_shop(id: String) -> Dictionary:
	var check := _node_access(id)
	if not check.ok:
		return check
	var cell: String = actor(id).position
	if node_at(cell).get("kind") != "trade":
		return fail("这里没有可以刷新的商店。")
	var cost := shop_refresh_cost(cell)
	if int(data.lamp_coins) < cost:
		return fail("灯铢不足，刷新需要 %d 灯铢。" % cost)
	data.lamp_coins -= cost
	Items.refresh_shop(data, cell, gear_owned("shop", cell), cost)
	return _item_result("货物已刷新，花费 %d 灯铢。" % cost)

func shop_quote(base: int, buying: bool, amount: int = 1, uid: String = "", voucher: String = "") -> Dictionary:
	if amount < 1:
		return fail("请选择有效的交易数量。")
	var channel := "shop_buy" if buying else "shop_sell"
	var quote := item_quote(base, channel, uid, voucher)
	if not quote.ok:
		return quote
	var next_price: int = item_quote(base, channel, uid, "", quote.claims).price
	quote.unit_price = quote.price
	quote.additional_unit_price = next_price
	quote.price += next_price * (amount - 1)
	return quote

func trade(id: String, item: String, buying: bool, voucher: String = "", amount: int = 1) -> Dictionary:
	var check = _node_access(id)
	if not check.ok:
		return check
	var trader = actor(id)
	var node = node_at(trader.position)
	if node.get("kind") != "trade":
		return fail("这里的商摊无法交易。")
	if Gear.DATA.has(item):
		return fail("请选择具体装备。")
	var is_relic = Relics.DATA.has(item)
	if (is_relic and buying and not Relics.is_active(item)) or (not is_relic and not Nodes.PRICES.has(item)):
		return fail("商摊无法交易这种物品。")
	var stock: Dictionary = node.relic_stock if is_relic else node.stock
	var inventory: Dictionary = data.relic_inventory if is_relic else trader.inventory
	var owned: int = int(inventory.get(item, 0))
	var base: int = Relics.DATA[item].price if is_relic else Nodes.PRICES[item]
	var quote := shop_quote(base, buying, amount, "", voucher)
	if not quote.ok:
		return quote
	if buying:
		if int(stock.get(item, 0)) < amount:
			return fail("库存不足。")
		if data.lamp_coins < quote.price:
			return fail("灯铢不足。")
		stock[item] -= amount
		data.lamp_coins -= quote.price
		if is_relic:
			grant_relic(item, id, trader.position, "", "", amount)
		else:
			inventory[item] = owned + amount
	else:
		if owned < amount:
			return fail("可出售的数量不足。")
		if is_relic:
			_remove_relic(item, amount)
		else:
			inventory[item] = owned - amount
		if not is_relic or Relics.is_active(item):
			stock[item] = int(stock.get(item, 0)) + amount
		data.lamp_coins += quote.price
	_commit_price(quote)
	var name: String = Relics.DATA[item].name if is_relic else Catalog.item_name(item)
	if amount > 1:
		name += " ×%d" % amount
	return _item_result("%s「%s」，%d 灯铢。" % ["买入" if buying else "卖出", name, quote.price])

func reward_coins(_source: String, base: int) -> int:
	return base

func use_node(id: String, option: String) -> Dictionary:
	var check = _node_access(id)
	if not check.ok:
		return check
	var visitor = actor(id)
	var cell: String = visitor.position
	var node = node_at(cell)
	if node.is_empty() or not node.result.is_empty():
		return fail("这里的事件已经处理完毕。")
	var message = ""
	var items: Array[Dictionary] = []
	match [node.kind, option]:
		["supply", "collect"]:
			var coins := int(node.coins)
			data.lamp_coins += coins
			items.append({"kind": "coins", "id": "lamp_coin", "count": coins})
			message = "%s取得 %d 灯铢。" % [visitor.name, coins]
			if node.has("gear_definition"):
				var equipment := Items.add_gear(data, node.gear_definition, node.gear_quality, "actor", id)
				items.append({"kind": "gear", "id": equipment, "count": 1})
			elif node.has("item"):
				var supply: String = node.item
				visitor.inventory[supply] = int(visitor.inventory.get(supply, 0)) + 1
				items.append({"kind": "item", "id": supply, "count": 1})
		["cache", "search"]:
			var relic = ""
			if relic_sites.has(cell):
				relic = str(investigate_relic(id).get("relic", ""))
			else:
				relic = roll_relic("field_cache:" + cell, Relics.DATA.keys(), 0.20, id, cell)
			var uid: String = node.get("gear_uid", "")
			if not uid.is_empty():
				var instance = data.gear_instances[uid]
				instance.owner = {"kind": "actor", "id": id}
				node.erase("gear_uid")
				items.append({"kind": "gear", "id": uid, "count": 1})
				message = "%s 取得「%s」。" % [visitor.name, Gear.label(instance)]
			else:
				var item: String = node.item
				visitor.inventory[item] = int(visitor.inventory.get(item, 0)) + 1
				items.append({"kind": "item", "id": item, "count": 1})
				message = "%s 取得%s ×1。" % [visitor.name, Catalog.item_name(item)]
			if not relic.is_empty():
				items.append({"kind": "relic", "id": relic, "count": 1})
				message += " 发现遗器「%s」。" % Relics.DATA[relic].name
		_:
			return fail("这里现在做不了这件事。")
	node.result = option
	data.item_revision += 1
	note(message)
	changed.emit()
	return {"ok": true, "message": message, "items": items}

func has_relic(id: String) -> bool:
	return id in data.relic_attunement

func relic_intro() -> Dictionary:
	return data.relic_intros[0] if not data.relic_intros.is_empty() else {}

func investigate_relic(id: String) -> Dictionary:
	var check = _node_access(id)
	if not check.ok:
		return check
	var position: String = actor(id).position
	var source = "site:" + position
	if not relic_sites.has(position) or data.relic_claims.has(source):
		return fail("这里没有新的遗器线索。")
	var relic = roll_relic(source, [relic_sites[position]], 0.25, id, position)
	return {"ok": true, "relic": relic, "message": "从旧物中找到了「%s」。" % Relics.DATA[relic].name if not relic.is_empty() else "检查过了，这里没有还能带走的遗器。"}

func relic_offer(source: String, candidates: Array, chance: float) -> String:
	var active = candidates.filter(Relics.is_active)
	var pool = active.filter(func(id): return not data.relic_seen.has(id))
	if pool.is_empty():
		pool = active
	if pool.is_empty():
		return ""
	pool.sort()
	var roller = RandomNumberGenerator.new()
	roller.seed = hash("relic:4:%d:%s" % [int(data.seed), source])
	if chance < 1.0 and roller.randf() >= chance:
		return ""
	return pool[roller.randi_range(0, pool.size() - 1)]

func roll_relic(source: String, candidates: Array, chance: float, finder: String, position: String) -> String:
	if data.relic_claims.has(source):
		return ""
	return claim_relic_reward(source, relic_offer(source, candidates, chance), finder, position)

func claim_relic_reward(source: String, relic: String, finder: String, position: String) -> String:
	if data.relic_claims.has(source):
		return ""
	var delivered = relic if grant_relic(relic, finder, position) else ""
	data.relic_claims[source] = {"success": not delivered.is_empty(), "relic_id": delivered, "delivered": true}
	return delivered

func grant_relic(id: String, finder: String, position: String, npc: String = "", lead: String = "", amount: int = 1) -> bool:
	if not Relics.is_active(id):
		return false
	var first = not data.relic_seen.has(id)
	data.relic_seen[id] = true
	data.relic_inventory[id] = int(data.relic_inventory.get(id, 0)) + amount
	data.item_revision += 1
	var new_sight: Array = []
	if Relics.DATA[id].type == "P" and not has_relic(id) and data.relic_attunement.size() < 6:
		data.relic_attunement.append(id)
		if id == "telescope":
			new_sight = _refresh_relic_sight()
	if first:
		var spell: String = SPELL_RELICS.get(id, "")
		if not spell.is_empty():
			unlock_spell(spell)
		data.relic_intros.append({"id": id, "finder": finder, "position": position, "npc": npc, "lead": lead, "stage": 0, "new_sight": new_sight})
	note("远征队获得遗器「%s」。" % Relics.DATA[id].name)
	return true

func _refresh_relic_sight() -> Array:
	var previous = data.explored.duplicate()
	for member in joined_ids():
		if actor(member).hp > 0:
			_reveal_sight(actor(member).position)
	return data.explored.keys().filter(func(cell): return not previous.has(cell))

func attune_relic(user: String, id: String) -> Dictionary:
	var check = _node_access(user)
	if not check.ok:
		return check
	if not Relics.is_active(id) or int(data.relic_inventory.get(id, 0)) <= 0 or Relics.DATA[id].type != "P":
		return fail("没有可共鸣的遗器。")
	if has_relic(id):
		_unattune(id)
		return _item_result("已解除「%s」的共鸣。" % Relics.DATA[id].name)
	if data.relic_attunement.size() >= 6:
		return fail("六个共鸣位已满，请先解除一件。")
	data.relic_attunement.append(id)
	if id == "telescope":
		_refresh_relic_sight()
	return _item_result("已共鸣「%s」。" % Relics.DATA[id].name)

func _remove_relic(id: String, amount: int = 1) -> void:
	data.relic_inventory[id] -= amount
	if data.relic_inventory[id] == 0:
		data.relic_inventory.erase(id)
		_unattune(id)

func _unattune(id: String) -> void:
	data.relic_attunement.erase(id)
	if id == "uphill_kneepad":
		for key in data.item_effect_counts.keys():
			if str(key).begins_with("uphill_ready:"):
				data.item_effect_counts.erase(key)

func use_relic(user: String, id: String, _target: String = "") -> Dictionary:
	var check := _node_access(user)
	if not check.ok:
		return check
	if not Relics.is_active(id) or int(data.relic_inventory.get(id, 0)) <= 0 or Relics.DATA[id].type == "P":
		return fail("没有可使用的遗器。")
	if id != "life_seed":
		return fail("请在开战前的卡组界面携带消耗遗器。")
	if data.relic_effect_flags.has("life_seed_applied"):
		return fail("生命之种在本局已使用。")
	data.relic_effect_flags.life_seed_applied = true
	_remove_relic(id)
	return _item_result("生命之种已启用：己方棋子的生命上限 +1。")

func has_visited(position: String) -> bool:
	return data.visited.has(position)

func knows_encounter(position: String) -> bool:
	var tile = data.tiles[position]
	return (has_visited(position) or (position == data.boss and boss_known())) and tile.discovered_enemy and not tile.enemies.is_empty()

func movement_preview(destination: String) -> Dictionary:
	if data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("战斗或结算期间不能移动。")
	var hero = actor("hero")
	if hero.hp <= 0:
		return fail("旅人重伤了，需要队友先用疗伤药救治。")
	var source: String = hero.position
	if not data.tiles[source].enemies.is_empty() and source != data.boss:
		return fail("敌人拦住了路。你可以迎战，也可以在战斗中撤退。")
	if not Hex.is_land(data.tiles, destination):
		return fail("湖面无法通行，请沿湖岸绕行。" if data.tiles.has(destination) else "请选择有效地块。")
	if destination not in Hex.neighbors(source, data.tiles):
		return fail("每次只能走一格。")
	return {"ok": true, "encounter": knows_encounter(destination), "source": source}

func remaining_steps() -> int:
	return STEPS_PER_DAY - int(data.steps_today)

func move(destination: String) -> Dictionary:
	var preview = movement_preview(destination)
	if not preview.ok:
		return preview
	_relocate_party(destination)
	data.steps_today += 1
	if data.steps_today == STEPS_PER_DAY:
		_advance_day()
	reveal(destination)
	data.route_records.clear()
	for threshold in [20, 60, 100]:
		if data.visited.size() >= threshold:
			roll_relic("explore:" + str(threshold), Relics.DATA.keys(), 1.0, "hero", destination)
	var t = data.tiles[destination]
	if not t.npc.is_empty() and actor(t.npc).position == destination:
		data.story[t.npc].met = true
	var encounter = not t.enemies.is_empty()
	if encounter:
		var surprise = not preview.encounter
		var ambush = t.hidden and surprise
		t.discovered_enemy = true
		data.pending_battle = {"position": destination, "ambush": ambush, "surprise": surprise, "origin": preview.source, "npc": ""}
		note("隐蔽处的敌人发动伏击！" if ambush else "抵达遭遇地点，可以准备卡组迎战。")
	else:
		note("抵达%s。" % Catalog.terrain_name(t.terrain))
	changed.emit()
	return {"ok": true, "battle": encounter, "pending": data.pending_battle.duplicate(true)}

func join_companion(id: String, recruiter_id: String = "") -> Dictionary:
	if not data.actors.has(id) or id == "hero":
		return fail("没有这位伙伴。")
	var a = actor(id)
	if a.hp <= 0:
		return fail("对方伤得很重。到他身边救治后，再跟他交谈。")
	var local_crew = same_cell(a.position, true)
	if local_crew.is_empty() or (not recruiter_id.is_empty() and recruiter_id not in local_crew):
		return fail("走到同一地块才能交谈。")
	if a.joined:
		return fail("已经同行。")
	a.joined = true
	if has_relic("telescope"):
		_reveal_sight(a.position)
	data.story[id].relation = "joined"
	data.story[id].met = true
	note("%s 加入远征队。" % a.name)
	var source = "recruit:" + id
	var gift := ""
	for relic in Relics.DATA:
		if Relics.is_active(relic) and Relics.DATA[relic].source == source:
			gift = claim_relic_reward(source, relic, id, a.position)
			break
	return {"ok": true, "relic": gift}

func recruit_shop_offers(cell: String) -> Array:
	var node := node_at(cell)
	if node.get("kind") != "trade":
		return []
	var stock: Array = ["grit", "lorne", "eve"]
	if not node.get("starter_shop", false):
		var roster := Catalog.COMPANIONS.keys()
		var priority := {}
		for id in roster:
			priority[id] = hash("recruits:%s:%s" % [data.seed, id])
		roster.sort_custom(func(a, b): return a < b if priority[a] == priority[b] else priority[a] < priority[b])
		var stores: Array = data.nodes.keys().filter(func(position):
			var location: Dictionary = data.nodes[position]
			return location.kind == "trade" and not location.get("starter_shop", false))
		stores.sort()
		var capacity := clampi(ceili(roster.size() / float(stores.size())), 3, roster.size())
		var offset := stores.find(cell) * capacity
		stock = []
		for i in capacity:
			stock.append(roster[(offset + i) % roster.size()])
	return stock.filter(func(id): return not actor(id).joined and actor(id).hp > 0)

func recruit_shop_price(cell: String) -> int:
	return 6 if node_at(cell).get("starter_shop", false) and joined_ids().size() == 1 else Cards.RECRUIT_PRICE

func recruit_quote(id: String) -> Dictionary:
	var check := _node_access("hero")
	if not check.ok:
		return check
	var cell: String = actor("hero").position
	if id not in recruit_shop_offers(cell):
		return fail("请在有这位伙伴的商店招募。")
	if data.has("pending_story_rewards") or data.has("pending_victory"):
		return fail("请先领取本次奖励。")
	var price := recruit_shop_price(cell)
	if data.lamp_coins < price:
		return fail("还差 %d 灯铢。" % (price - int(data.lamp_coins)))
	return {"ok": true, "price": price}

func recruit_companion(id: String) -> Dictionary:
	var quote := recruit_quote(id)
	if not quote.ok:
		return quote
	var previous := data.duplicate(true)
	data.lamp_coins -= quote.price
	actor(id).position = actor("hero").position
	var result := join_companion(id, "hero")
	if not result.ok:
		data = previous
		return result
	if not result.relic.is_empty():
		data.pending_story_rewards = {"source": "招募 · " + actor(id).name,
			"items": [{"kind": "relic", "id": result.relic, "count": 1}]}
	var saved := _save_companion_purchase(previous)
	if saved.ok:
		saved.message = "%s已入队，伙伴牌已解锁。可在卡组中更换一张牌。" % actor(id).name
	return saved

func breakthrough_quote(id: String) -> Dictionary:
	var check := _node_access("hero")
	if not check.ok:
		return check
	var person := actor(id)
	if id == "hero" or person.is_empty() or not person.joined:
		return fail("招募伙伴后可以突破。")
	var rank := int(person.get("breakthrough", 0))
	if rank >= Cards.BREAKTHROUGH_PRICES.size():
		return fail("已完成三次突破。")
	var price: int = Cards.BREAKTHROUGH_PRICES[rank] - (2 if data.relic_effect_flags.has("chess_workshop_credit") else 0)
	if data.lamp_coins < price:
		return fail("还差 %d 灯铢。" % (price - int(data.lamp_coins)))
	return {"ok": true, "price": price, "rank": rank}

func breakthrough_companion(id: String, expected_rank: int) -> Dictionary:
	var quote := breakthrough_quote(id)
	if not quote.ok:
		return quote
	if quote.rank != expected_rank:
		return fail("突破等级已变化。")
	var previous := data.duplicate(true)
	data.lamp_coins -= quote.price
	data.relic_effect_flags.erase("chess_workshop_credit")
	actor(id).breakthrough = quote.rank + 1
	note("%s 完成第 %d 次突破。" % [actor(id).name, quote.rank + 1])
	return _save_companion_purchase(previous)

func _save_companion_purchase(previous: Dictionary) -> Dictionary:
	data.item_revision += 1
	var saved := save_game()
	if not saved.ok:
		data = previous
		return saved
	changed.emit()
	return saved

func transfer(from_id: String, to_id: String, item: String, amount: int) -> Dictionary:
	if data.status != "exploring":
		return fail("战斗期间不能整理地图背包。")
	var source = actor(from_id)
	var target = actor(to_id)
	if source.is_empty() or target.is_empty() or not source.joined or not target.joined or source.position != target.position:
		return fail("只能在同一地块交接物品。")
	if same_cell(source.position, true).is_empty():
		return fail("同一地块得有能行动的队员帮忙，才能整理物品。")
	if amount <= 0 or int(source.inventory.get(item, 0)) < amount:
		return fail("持有数量不足。")
	if item in source.equipment.values():
		return fail("请先卸下装备。")
	source.inventory[item] -= amount
	target.inventory[item] = int(target.inventory.get(item, 0)) + amount
	data.item_revision += 1
	note("%s 将 %s ×%d 交给 %s。" % [source.name, Catalog.item_name(item), amount, target.name])
	changed.emit()
	return success()

func use_item(user_id: String, target_id: String, item: String, during_battle: bool = false, received_pp: int = 0) -> Dictionary:
	var user = actor(user_id)
	var target = actor(target_id)
	if user.is_empty() or target.is_empty() or not user.joined or user.hp <= 0 or user.position != target.position:
		return fail("只有还能行动的队员才能用道具，也只能给同一地块的人用。")
	if not target.joined and not data.story.get(target_id, {}).get("met", false):
		return fail("你还没见过这名角色。")
	if data.status != "exploring" and not during_battle:
		return fail("等轮到己方正常行动时再用。")
	var definition = Catalog.ITEMS.get(item, {})
	if int(user.inventory.get(item, 0)) <= 0 or not (definition.has("hp") or definition.has("mp")):
		return fail("没有可用的恢复道具。")
	if definition.has("mp") and target.hp <= 0:
		return fail("恢复魔力不能解除重伤。")
	var healing = int(definition.get("hp", 0))
	if during_battle and received_pp > 0:
		healing = floori(healing * (1.0 + received_pp / 100.0))
	var hp_gain = mini(healing, int(target.hp_max) - int(target.hp))
	var mp_gain = mini(int(definition.get("mp", 0)), int(target.mp_max) - int(target.mp))
	if hp_gain <= 0 and mp_gain <= 0:
		return fail("没有可恢复的资源，不消耗物品。")
	target.hp += hp_gain
	target.mp += mp_gain
	user.inventory[item] -= 1
	data.item_revision += 1
	note("%s 对 %s 使用%s：HP +%d，MP +%d。" % [user.name, target.name, definition.name, hp_gain, mp_gain])
	changed.emit()
	return {"ok": true, "hp_gain": hp_gain, "hp_over": healing - hp_gain}

func equip(id: String, uid: String) -> Dictionary:
	var check = _map_action(id)
	if not check.ok:
		return check
	var a = actor(id)
	var item = data.gear_instances.get(uid, {})
	if item.get("owner") != {"kind": "actor", "id": id}:
		return fail("该角色不持有此装备。")
	var slot: String = Gear.DATA[item.definition_id].slot
	a.equipment[slot] = "" if a.equipment[slot] == uid else uid
	return _item_result("已更新装备。")

func collect(id: String) -> Dictionary:
	var check = _map_action(id)
	if not check.ok:
		return check
	var a = actor(id)
	var t = data.tiles[a.position]
	if t.quantity <= 0 and node_at(a.position).kind == "supply":
		return use_node(id, "collect")
	if not t.enemies.is_empty() or t.quantity <= 0:
		return fail("这里没有安全可采集的道具。")
	var amount = int(t.quantity) + (1 if id == "cen" and t.terrain == "forest" else 0)
	a.inventory[t.resource] = int(a.inventory.get(t.resource, 0)) + amount
	t.quantity = 0
	data.item_revision += 1
	var message = "%s 收集了%s ×%d。" % [a.name, Catalog.item_name(t.resource), amount]
	note(message)
	changed.emit()
	return {"ok": true, "message": message, "items": [{"kind": "item", "id": t.resource, "count": amount}]}

func _advance_day() -> void:
	data.day += 1
	data.steps_today = 0
	data.weather = "rain" if rng.randf() < rain_chance() else "sun"
	for key in data.item_effect_counts.keys():
		if str(key).begins_with("uphill_ready:") or ":day:" in str(key) or str(key).begins_with("day:"):
			data.item_effect_counts.erase(key)
	note("第 %d 天，%s。" % [data.day, "雨" if data.weather == "rain" else "晴"])

func next_weather() -> String:
	return weather_forecast(1)[0]

func weather_forecast(days: int) -> Array[String]:
	var forecast = RandomNumberGenerator.new()
	forecast.state = rng.state
	var result: Array[String] = []
	for day in days:
		result.append("rain" if forecast.randf() < rain_chance() else "sun")
	return result

func rain_chance() -> float:
	return 0.28

func check_global_failure() -> bool:
	for id in joined_ids():
		if actor(id).hp > 0:
			return false
	data.status = "failed"
	data.flags["failure_reason"] = "全体重伤，已没有可行动的救援者。"
	return true

func war_god_stats() -> Dictionary:
	var result = Catalog.ENEMIES.war_god.duplicate(true)
	var calm = mini(12, data.peace.size())
	result.hp -= calm * 3
	result.attack -= calm
	return result

func boss_known() -> bool:
	return int(data.chapter) >= 4

func exploration_percent() -> int:
	return floori(100.0 * data.explored.size() / maxi(1, data.tiles.size()))

func pending_chapter() -> int:
	var chapter = int(data.chapter)
	if data.status == "exploring" and chapter < 4 and exploration_percent() >= (chapter + 1) * 20:
		return chapter + 1
	return 0

func finish_chapter(chapter: int) -> void:
	if chapter != pending_chapter():
		return
	data.chapter = chapter
	if chapter == 2:
		actor("hero").ultimate = "gravity_wave"
		note("你记起了怎样把周围的敌人一并压向地面。")
	if chapter == 4:
		data.tiles[data.boss].enemies = ["war_god"]
		data.tiles[data.boss].discovered_enemy = true
		data.explored[data.boss] = true
		note("战神的位置已标在地图上。")

func _map_action(id: String) -> Dictionary:
	if data.is_empty() or data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("当前不能执行探索行动。")
	var a = actor(id)
	if a.is_empty() or not a.joined or a.hp <= 0:
		return fail("该角色无法行动。")
	return success()

func card_deck() -> Array:
	return data.card_deck.duplicate() if data.has("card_deck") else _convert_gear_cards(Cards.DEFAULT_DECK)

func _convert_gear_cards(legacy_deck: Array) -> Array:
	var result: Array = []
	var used: Array = []
	for card in legacy_deck:
		if card not in ["blade", "pike", "coat"]:
			result.append(card)
			continue
		var definitions: Array = {"blade": ["trail_blade"], "pike": ["frontier_guard_weapon"],
			"coat": ["padded_coat", "lamp_charm"]}[card]
		var found := false
		for definition in definitions:
			for uid in gear_owned("actor", "hero"):
				if data.gear_instances[uid].definition_id == definition and uid not in used:
					used.append(uid)
					result.append("gear:" + uid)
					found = true
					break
			if found:
				break
	return result

func _replace_old_support_cards() -> void:
	var deck: Array = data.card_deck
	var slots := deck.size()
	data.card_deck = deck.filter(func(card): return not Cards.SUPPORT.has(card))
	if slots == data.card_deck.size():
		return
	for card in _convert_gear_cards(Cards.DEFAULT_DECK):
		if data.card_deck.size() == slots:
			break
		if data.card_deck.count(card) < Cards.limit(card):
			data.card_deck.append(card)

func unlock_spell(id: String) -> bool:
	if id not in Cards.UNLOCKABLE_SPELLS or id in data.spell_collection:
		return false
	data.spell_collection.append(id)
	note("牌库解锁「%s」。" % Cards.ACTIONS[id].name)
	return true

func spell_shop_offers(cell: String) -> Array:
	var node: Dictionary = node_at(cell)
	var restocks := int(node.get("refresh_count", 0))
	if node.get("kind") != "trade" or data.item_effect_counts.has("spell_shop:%s:%d" % [cell, restocks]):
		return []
	var available: Array = Cards.UNLOCKABLE_SPELLS.filter(func(id): return id not in data.spell_collection)
	if available.is_empty():
		return []
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("spell_shop:%d:%s:%d" % [int(data.seed), cell, restocks])
	var first: Variant = available.pop_at(roller.randi_range(0, available.size() - 1))
	return [first, available[roller.randi_range(0, available.size() - 1)]] if has_relic("market_window") and not available.is_empty() else [first]

func spell_shop_price() -> int:
	var base := 6 if has_relic("bargaining_counter") else 8
	return floori(base / 2.0) if data.relic_effect_flags.has("chess_spell_discount") else base

func buy_spell(id: String, spell: String) -> Dictionary:
	var check := _node_access(id)
	if not check.ok:
		return check
	var cell: String = actor(id).position
	var price := spell_shop_price()
	if spell.is_empty() or spell not in spell_shop_offers(cell) or data.lamp_coins < price:
		return fail("这张法术牌谱当前无法购买。")
	unlock_spell(spell)
	data.lamp_coins -= price
	data.relic_effect_flags.erase("chess_spell_discount")
	data.item_effect_counts["spell_shop:%s:%d" % [cell, int(node_at(cell).get("refresh_count", 0))]] = 1
	return _item_result("解锁法术「%s」，可编入卡组。" % Cards.ACTIONS[spell].name)

func preparation_options() -> Array[String]:
	var result: Array[String] = []
	for id in Relics.ChessRelics.PREPARATIONS:
		if int(data.relic_inventory.get(id, 0)) > 0:
			result.append(id)
	return result

func consume_prepared_relic(id: String) -> void:
	if not id.is_empty() and int(data.relic_inventory.get(id, 0)) > 0:
		_remove_relic(id)
		data.item_revision += 1
	prepared_relic = ""

func save_card_deck(deck: Array) -> Dictionary:
	if data.status != "exploring" or not Cards.valid_deck(deck, data.actors, false, data):
		return fail("这套牌组无法保存。")
	var previous: Variant = data.get("card_deck")
	data.card_deck = deck.duplicate()
	var saved := save_game()
	if not saved.ok:
		if previous == null:
			data.erase("card_deck")
		else:
			data.card_deck = previous
	return saved

func save_game(path: String = "") -> Dictionary:
	if path.is_empty():
		path = save_path
	if data.is_empty() or data.status == "battle":
		return fail("现在还不能存档，等当前操作结束后再试。")
	data.rng_state = str(rng.state)
	data.transaction += 1
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return fail("无法写入存档。")
	file.store_string(JSON.stringify(data))
	file.close()
	# Preserve a last known-good backup; replacement is on the same volume.
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	var error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		return fail("没能更新存档，旧存档还在。")
	return success()

func load_game(path: String = "") -> Dictionary:
	if path.is_empty():
		path = save_path
	if not FileAccess.file_exists(path):
		return fail("还没有远征存档。")
	var json = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return fail("存档损坏了，原来的文件还在。")
	var loaded: Dictionary = json.data
	if not _whole_number(loaded.get("version", -1)) or int(loaded.version) not in [3, 4, 5, 6, 7, 8, SAVE_VERSION] or not loaded.has_all(["actors", "tiles", "rng_state", "day", "explored", "status"]):
		return fail("存档版本不兼容，或者进度记录不完整。")
	if int(loaded.version) >= 4 and (not loaded.get("relic_seen") is Dictionary or not loaded.get("nodes") is Dictionary):
		return fail("遗器发现记录无效。")
	if int(loaded.version) < 6 and loaded.get("card_deck") is Array and loaded.actors is Dictionary:
		loaded.card_deck = Cards.migrate_deck(loaded.card_deck, loaded.actors)
	var invalid = _validate_save(loaded)
	if invalid != "":
		return fail("存档内容无效：" + invalid + "。旧文件没有被覆盖。")
	if int(loaded.version) == 3:
		if not loaded.has("nodes"):
			var sites = Relics.exploration_sites(loaded.tiles, int(loaded.seed))
			loaded.nodes = Nodes.generate(loaded.tiles, int(loaded.seed), sites, loaded.rewards, loaded.get("relic_checks", {}))
			loaded.merge({"lamp_coins": Nodes.STARTING_COINS})
		Items.migrate(loaded)
	if int(loaded.version) < 5:
		_migrate_travel(loaded)
	if not Items.validate(loaded):
		return fail("存档中的装备或遗器记录无效。")
	if int(loaded.version) >= 8 and loaded.has("card_deck") and not Cards.valid_deck(loaded.card_deck, loaded.actors, false, loaded, int(loaded.version) < 9):
		return fail("存档中的卡组记录无效。")
	Nodes.replace_legacy_clues(loaded.nodes, loaded.tiles, int(loaded.seed))
	loaded.erase("leads")
	if int(loaded.version) < 6 and not str(loaded.pending_battle.get("npc", "")).is_empty():
		loaded.pending_battle = {}
	var rebalance := int(loaded.version) < 7
	var old_cards := int(loaded.version) < 8
	var old_support := int(loaded.version) < 9
	loaded.version = SAVE_VERSION
	data = loaded
	data.merge({"spell_collection": []})
	prepared_relic = ""
	prepared_weather = ""
	if old_cards:
		for relic in SPELL_RELICS:
			if data.relic_seen.has(relic):
				unlock_spell(SPELL_RELICS[relic])
		if not gear_owned("actor", "hero").any(func(uid): return data.gear_instances[uid].definition_id == "frontier_guard_weapon"):
			Items.add_gear(data, "frontier_guard_weapon", "common", "actor", "hero")
		if data.has("card_deck"):
			data.card_deck = _convert_gear_cards(data.card_deck)
	if old_support:
		for spell in Cards.STARTER_SPELLS:
			if spell not in data.spell_collection:
				data.spell_collection.append(spell)
		if data.has("card_deck"):
			_replace_old_support_cards()
	_remove_legacy_map_effects()
	for id in data.actors:
		actor(id).attack_delivery = "ranged" if id == "hero" else Catalog.COMPANIONS[id].attack_delivery
	if not data.has("visited"):
		_restore_legacy_visits()
	if not data.has("choices"):
		data.choices = []
	_initialize_relics()
	_initialize_nodes(rebalance)
	rng.state = int(data.rng_state)
	changed.emit()
	return success()

func _migrate_travel(loaded: Dictionary) -> void:
	loaded.version = 5
	loaded.steps_today = 0
	for member in loaded.actors.values():
		for key in ["ap", "ap_max", "ap_initialized_day"]:
			member.erase(key)
	var position: String = loaded.pending_battle.get("position", loaded.actors.hero.position)
	for member in loaded.actors.values():
		member.erase("squad_id")
		if member.joined:
			member.position = position
	loaded.pending_battle.erase("movers")
	if loaded.has("pending_arrival"):
		if loaded.pending_arrival.cell == position:
			loaded.pending_arrival.actor = "hero"
		else:
			loaded.erase("pending_arrival")
	for key in ["last_move_windows", "next_move_uid", "last_day_settled", "squad_colors", "next_squad_id"]:
		loaded.erase(key)
	if loaded.get("route_records") is Dictionary:
		loaded.route_records.clear()
	if loaded.get("relic_attunement") is Array:
		loaded.relic_attunement = loaded.relic_attunement.filter(func(id): return not Relics.DATA.has(id) or Relics.is_active(id))
	for node in loaded.nodes.values():
		var stock = node.get("relic_stock")
		if stock is Dictionary:
			for id in stock.keys():
				if Relics.DATA.has(id) and not Relics.is_active(id):
					stock.erase(id)
	# Remove the old movement-based preparation. Future charges come from entering mountains.
	if loaded.get("item_effect_counts") is Dictionary:
		for key in loaded.item_effect_counts.keys():
			if str(key).begins_with("uphill_ready:"):
				loaded.item_effect_counts.erase(key)

func _remove_legacy_map_effects() -> void:
	# Saves made before field effects moved into battle may contain a burned forest.
	for tile in data.tiles.values():
		if tile.terrain == "scorched":
			tile.terrain = tile.base_terrain
		tile.erase("burning")
		tile.erase("fuel")
		tile.erase("wet_until")
	data.flags.erase("player_ignitions")
	for facts in data.knowledge.values():
		if facts is Dictionary:
			facts.erase("ignitions")

func _restore_legacy_visits() -> void:
	# Previous saves stored sight, but no route history. Recover only evidence of arrival.
	data.visited = {data.start: true}
	for id in joined_ids():
		data.visited[actor(id).position] = true
	for position in data.explored:
		var tile = data.tiles[position]
		if (tile.hidden and tile.discovered_enemy) or data.story.get(tile.npc, {}).get("met", false):
			data.visited[position] = true
	if not data.pending_battle.is_empty():
		data.visited[data.pending_battle.origin] = true
		data.visited[data.pending_battle.position] = true
	for position in data.visited:
		data.explored[position] = true

func _validate_save(loaded: Dictionary) -> String:
	if not loaded.has_all(["flags", "story", "knowledge", "rewards", "log", "pending_battle", "start", "boss", "peace", "chapter", "profession", "explored", "transaction", "battles", "weather"]):
		return "进度记录不完整"
	for key in ["actors", "tiles", "flags", "story", "knowledge", "rewards", "pending_battle", "explored", "peace"]:
		if not loaded[key] is Dictionary:
			return "进度记录格式有误"
	if loaded.tiles.size() != 217 or not loaded.tiles.has(loaded.start) or not loaded.tiles.has(loaded.boss):
		return "地图不完整"
	if loaded.status not in ["exploring", "won", "failed"] or loaded.weather not in ["sun", "rain"] or not Catalog.PROFESSIONS.has(loaded.profession):
		return "状态或职业无效"
	if not _whole_number(loaded.chapter) or loaded.chapter < 0 or loaded.chapter > 4:
		return "剧情进度无效"
	if not loaded.log is Array or not _whole_number(loaded.day) or int(loaded.day) < 1 or not str(loaded.rng_state).is_valid_int():
		return "日期或随机状态无效"
	if int(loaded.version) >= 5 and (not _whole_number(loaded.get("steps_today")) or loaded.steps_today < 0 or loaded.steps_today >= STEPS_PER_DAY):
		return "当日步数无效"
	var spells: Variant = loaded.get("spell_collection", [])
	if not spells is Array or spells.any(func(spell): return spell not in Cards.UNLOCKABLE_SPELLS) or spells.any(func(spell): return spells.count(spell) > 1):
		return "法术牌谱无效"
	if loaded.has("card_deck") and not (loaded.card_deck is Array and loaded.card_deck.size() <= Cards.DECK_SIZE
			and (int(loaded.version) >= 8 or Cards.valid_deck(loaded.card_deck, loaded.actors, false, {}, true))):
		return "卡组记录无效"
	if loaded.has("choices") and not loaded.choices is Array:
		return "选择记录无效"
	if loaded.has("lamp_coins") and (not _whole_number(loaded.lamp_coins) or loaded.lamp_coins < 0):
		return "灯铢记录无效"
	if not loaded.get("relics", {}) is Dictionary or not loaded.get("relic_checks", {}) is Dictionary or not loaded.get("relic_intros", []) is Array:
		return "遗器记录无效"
	if loaded.has("pending_story_rewards"):
		var receipt = loaded.pending_story_rewards
		if not receipt is Dictionary or not receipt.get("source") is String \
				or not receipt.get("items") is Array or receipt.items.is_empty():
			return "剧情奖励记录无效"
		for item in receipt.items:
			if not item is Dictionary or not item.get("id") is String \
					or not _whole_number(item.get("count")) or item.count <= 0:
				return "剧情奖励记录无效"
			match item.get("kind"):
				"item":
					if not Catalog.ITEMS.has(item.id):
						return "剧情奖励道具无效"
				"relic":
					if not Relics.DATA.has(item.id):
						return "剧情奖励遗器无效"
				"gear":
					if not loaded.get("gear_instances") is Dictionary or not loaded.gear_instances.has(item.id):
						return "剧情奖励装备无效"
				"coins":
					if item.id != "lamp_coin":
						return "剧情奖励灯铢无效"
				_:
					return "剧情奖励记录无效"
	if loaded.has("pending_victory"):
		var result = loaded.pending_victory
		if not result is Dictionary or not result.has_all(["enemies", "members", "revived", "salve_receiver", "relic"]) \
				or not _whole_number(result.enemies) or result.enemies < 1 or not result.members is Array or result.members.is_empty() \
				or not result.revived is Array or not result.salve_receiver is String or not result.relic is String:
			return "胜利结算无效"
		if not result.members.all(func(id): return loaded.actors.has(id)) or not result.revived.all(func(id): return id in result.members) \
				or (result.salve_receiver != "" and result.salve_receiver not in result.members) \
				or (result.relic != "" and not loaded.get("relic_seen", loaded.get("relics", {})).has(result.relic)):
			return "胜利结算无效"
		if result.has("coins") and (not _whole_number(result.coins) or result.coins < 0):
			return "胜利报酬无效"
	for id in loaded.get("relics", {}):
		if not Relics.DATA.has(id) or loaded.relics[id] != true:
			return "未知遗器"
	for entry in loaded.get("relic_intros", []):
		if not entry is Dictionary or not entry.has_all(["id", "finder", "position", "npc", "lead", "stage", "new_sight"]):
			return "遗器剧情无效"
		if not loaded.get("relic_seen", loaded.get("relics", {})).has(entry.id) or not loaded.actors.has(entry.finder) or not loaded.tiles.has(entry.position) \
				or not entry.npc is String or not entry.lead is String or not _whole_number(entry.stage) \
				or int(entry.stage) not in [0, 1] or not entry.new_sight is Array:
			return "遗器剧情无效"
		for cell in entry.new_sight:
			if not loaded.explored.has(cell) or not loaded.tiles.has(cell):
				return "遗器视野记录无效"
	for k in loaded.explored:
		if not loaded.tiles.has(k):
			return "探索记录越界"
	if loaded.has("visited"):
		if not loaded.visited is Dictionary:
			return "到访记录无效"
		for k in loaded.visited:
			if not loaded.explored.has(k):
				return "到访记录越界"
	if loaded.has("pending_arrival"):
		var arrival = loaded.pending_arrival
		if not arrival is Dictionary or not arrival.get("actor") is String or not arrival.get("cell") is String \
				or not loaded.actors.has(arrival.actor) or not loaded.get("visited", {}).has(arrival.cell):
			return "到达剧情记录无效"
	var coordinate = RegEx.new()
	coordinate.compile("^-?[0-9]+,-?[0-9]+$")
	for k in loaded.tiles:
		if coordinate.search(str(k)) == null or Hex.distance(Hex.coord(k), Vector2i.ZERO) > 8:
			return "六边形坐标无效"
		var tile = loaded.tiles[k]
		if not tile is Dictionary or not tile.has_all(["terrain", "base_terrain", "enemies", "site", "npc", "resource", "quantity", "height", "hidden", "discovered_enemy"]):
			return "地块记录不完整"
		var legacy_forest = tile.terrain == "scorched" and tile.base_terrain == "forest"
		if (not Catalog.TERRAIN.has(tile.terrain) and not legacy_forest) or not Catalog.TERRAIN.has(tile.base_terrain) or not tile.enemies is Array:
			return "地形或遭遇无效"
		if tile.terrain == "lake" and (tile.site != "" or tile.npc != "" or not tile.enemies.is_empty() or tile.quantity > 0 or loaded.get("visited", {}).has(k)):
			return "湖面包含陆地事件"
		for enemy in tile.enemies:
			if not Catalog.ENEMIES.has(enemy):
				return "未知敌人"
	if loaded.has("nodes") and not _valid_nodes(loaded):
		return "节点记录无效"
	if loaded.actors.size() != Catalog.COMPANIONS.size() + 1:
		return "角色数量无效"
	for id in ["hero"] + Catalog.COMPANIONS.keys():
		if not loaded.actors.has(id) or not loaded.actors[id] is Dictionary:
			return "角色缺失"
		var a = loaded.actors[id]
		if not a.has_all(["id", "name", "color", "element", "attack", "defense", "speed", "shield", "slow", "guard", "position", "joined", "hp", "hp_max", "mp", "mp_max", "energy", "equipment", "inventory", "skill", "ultimate"]):
			return "角色记录不完整"
		if a.id != id or not a.name is String or not a.color is String or not a.element is String or not a.joined is bool:
			return "角色标识无效"
		if not Hex.is_land(loaded.tiles, a.position) or not a.inventory is Dictionary or not a.equipment is Dictionary:
			return "角色位置或背包无效"
		if int(loaded.version) >= 5 and a.joined and a.position != loaded.actors.hero.position:
			return "队员与旅人不在同一地块"
		var rank: Variant = a.get("breakthrough", 0)
		if not _whole_number(rank) or rank < 0 or rank > Cards.BREAKTHROUGH_PRICES.size() or (rank > 0 and (id == "hero" or not a.joined)):
			return "伙伴突破记录无效"
		if not Catalog.SKILLS.has(a.skill) or not Catalog.SKILLS.has(a.ultimate):
			return "角色技能无效"
		for resource in ["hp", "mp"]:
			if not _whole_number(a[resource]) or not _whole_number(a[resource + "_max"]) or a[resource + "_max"] <= 0 or a[resource] < 0 or a[resource] > a[resource + "_max"]:
				return "队员的生命或魔力超出正常范围"
		for field in ["energy", "attack", "defense", "speed", "shield", "slow"]:
			if not _whole_number(a[field]) or a[field] < 0 or (field == "speed" and a[field] == 0) or (field == "energy" and a[field] > 100):
				return "角色数值无效"
		if not a.equipment.has_all(["weapon", "armor", "accessory"]):
			return "装备栏缺失"
		for item in a.inventory:
			if not _whole_number(a.inventory[item]) or a.inventory[item] < 0:
				return "物品数量无效"
		for slot in a.equipment:
			var item = a.equipment[slot]
			if int(loaded.version) == 3 and item != "" and (not Gear.DATA.has(item) or Gear.DATA[item].slot != slot or a.inventory.get(item, 0) < 1):
				return "装备持有状态无效"
		if id != "hero":
			if not loaded.story.has(id) or not loaded.story[id] is Dictionary or not loaded.story[id].has_all(["met", "relation", "result"]):
				return "故事状态缺失"
			if not loaded.story[id].get("codex_first_meeting", "") is String or not loaded.story[id].get("codex_past_read", false) is bool:
				return "角色图鉴记录无效"
			if loaded.story[id].has("personal_choice"):
				var choice = loaded.story[id].personal_choice
				var god_choice = Catalog.COMPANIONS[id].race == "神" and choice in ["god_a", "god_b"]
				if choice not in ["personal_a", "personal_b", "war_a", "war_b", "war2_a", "war2_b", "journey_a", "journey_b"] and not god_choice:
					return "个人抉择记录无效"
	if not loaded.pending_battle.is_empty():
		var pending = loaded.pending_battle
		if not pending.has_all(["position", "origin", "ambush", "npc"]) or not loaded.tiles.has(pending.position) or not loaded.tiles.has(pending.origin):
			return "遭遇检查点无效"
		if pending.has("surprise") and not pending.surprise is bool:
			return "遭遇检查点无效"
	return ""

func _valid_nodes(loaded: Dictionary) -> bool:
	if not loaded.nodes is Dictionary or not loaded.has("lamp_coins"):
		return false
	for cell in loaded.tiles:
		if Hex.is_land(loaded.tiles, cell) != loaded.nodes.has(cell):
			return false
	for cell in loaded.nodes:
		var node = loaded.nodes[cell]
		if not loaded.tiles.has(cell) or not node is Dictionary or not node.has_all(["kind", "event", "result"]):
			return false
		if not node.kind is String or not node.event is String or not node.result is String:
			return false
		if node.kind == "clue":
			if int(loaded.version) >= 6:
				return false
			var biome: String = loaded.tiles[cell].base_terrain
			if node.event not in [biome + "_clue_1", biome + "_clue_2"] or node.result not in ["", "record"] or node.has("investigated"):
				return false
			continue
		if node.kind in Nodes.RETIRED_KINDS:
			if int(loaded.version) >= 6 or node.event not in Nodes.legacy_event_ids(node.kind, loaded.tiles[cell].base_terrain):
				return false
		elif node.kind == "rest":
			if int(loaded.version) >= SAVE_VERSION or Nodes.story(node).is_empty():
				return false
		elif not Nodes.LABELS.has(node.kind) or (node.kind != "story" and Nodes.story(node).is_empty()):
			return false
		if node.kind == "supply" and int(loaded.version) >= 7:
			if not _whole_number(node.get("coins")) or node.coins < 1 or node.coins > 3 or node.result not in ["", "collect"]:
				return false
			if node.has("item") and (node.item not in ["salve", "ether", "trail_food"] or node.has("gear_definition")):
				return false
			if node.has("gear_definition") and (not Gear.DATA.has(node.gear_definition) or node.get("gear_quality") not in Gear.QUALITIES):
				return false
		if node.has("investigated") and (node.kind != "haunt" or not node.investigated is bool):
			return false
		if node.kind == "trade":
			if not node.get("stock") is Dictionary:
				return false
			for item in node.stock:
				if not Nodes.PRICES.has(item) or (int(loaded.version) >= 4 and Gear.DATA.has(item)) \
						or not _whole_number(node.stock[item]) or node.stock[item] < 0:
					return false
		if node.kind in ["rest", "cache"] and not Nodes.PRICES.has(node.get("item")) and not Gear.DATA.has(node.get("item")):
			return false
		if node.kind in ["choice", "battle", "elite"] and (not _whole_number(node.get("coins")) or node.coins <= 0):
			return false
	return true

static func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func note(message: String) -> void:
	data.log.append(message)
	if data.log.size() > 100:
		data.log.pop_front()

static func success() -> Dictionary:
	return {"ok": true}

static func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
