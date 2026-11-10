class_name Expedition
extends RefCounted
## Authoritative state: renderers never own or regenerate resources.
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Items = preload("res://scripts/domain/expedition_items.gd")
const SAVE_VERSION = 5
const STEPS_PER_DAY = 5
signal changed
var data: Dictionary = {}
var rng = RandomNumberGenerator.new()
var save_path = "user://expedition.json"
var relic_sites: Dictionary = {}
var location_names: Dictionary = {}

func new_run(seed_value: int, profession: String) -> void:
	assert(Catalog.PROFESSIONS.has(profession))
	var generated = Hex.generate(seed_value)
	rng.seed = seed_value ^ 0x5eed123
	data = {"version": SAVE_VERSION, "seed": seed_value, "profession": profession, "day": 1, "steps_today": 0, "weather": "sun", "tiles": generated.tiles, "start": generated.start, "boss": generated.boss, "leads": {}, "peace": {}, "chapter": 0, "actors": {}, "explored": {}, "visited": {}, "flags": {}, "knowledge": {}, "story": {}, "rewards": {}, "choices": [], "status": "exploring", "log": [], "battles": 0, "transaction": 0, "pending_battle": {}}
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
	for id in Catalog.COMPANIONS:
		var location = ""
		for k in data.tiles:
			if data.tiles[k].npc == id:
				location = k
		data.actors[id] = _actor(id, Catalog.COMPANIONS[id], location, false)
		data.story[id] = {"relation": "unmet", "result": "E0", "met": false}
	_initialize_relics()
	_initialize_nodes()
	Items.stock(data, false)
	reveal(generated.start)
	note("村民送来了疗伤药、澄露和干粮。你想找到结束战争的办法。")

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
	if not buying and uid in a.equipment.values():
		return fail("请先卸下选中的装备。")
	var quote = item_quote(Gear.price(instance), "shop_buy" if buying else "shop_sell", uid, voucher)
	if not quote.ok:
		return quote
	if buying and data.lamp_coins < quote.price:
		return fail("灯铢不足。")
	data.lamp_coins += -quote.price if buying else quote.price
	instance.owner = {"kind": "actor" if buying else "shop", "id": id if buying else a.position}
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

func item_quote(base: int, channel: String, uid: String = "", voucher: String = "") -> Dictionary:
	var pp = 0
	var claims: Array = []
	for id in data.relic_attunement:
		var entry = Relics.DATA[id]
		var params = entry.params
		if channel == "shop_sell" and entry.hook == "economy_sale":
			pp += params.bonus_pp
		if entry.hook != "economy_discount" or params.channel != channel:
			continue
		var key = ""
		match params.get("when"):
			"visited_count_gte_60":
				if data.visited.size() < 60:
					continue
				key = "%s:day:%d" % [id, data.day]
			"first_discounted_enhancement_per_equipment_instance":
				key = "%s:gear:%s" % [id, uid]
		if not key.is_empty():
			if data.item_effect_counts.has(key):
				continue
			claims.append(key)
		pp += params.reduce_pp
	var price = maxi(1, ceili(base * (1.0 - mini(25, pp) / 100.0)))
	if channel == "shop_sell":
		return {"ok": true, "price": mini(floori(base * 0.4 * (1.0 + mini(25, pp) / 100.0)), floori(base * 0.5)), "claims": [], "voucher": ""}
	if price == base:
		claims.clear()
	if not voucher.is_empty():
		var entry = Relics.DATA.get(voucher, {})
		if int(data.relic_inventory.get(voucher, 0)) <= 0 or entry.get("hook") != "transaction_use" or entry.params.channel != channel:
			return fail("没有可用的对应凭券。")
		var discounted = maxi(ceili(base * 0.75), price - int(entry.params.reduce_flat))
		if discounted >= price:
			return fail("该凭券不会进一步降低费用。")
		price = discounted
	if channel == "shop_buy":
		price = maxi(price, floori(base * 0.5) + 1)
	return {"ok": true, "price": price, "claims": claims, "voucher": voucher}

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

func _initialize_nodes() -> void:
	data.merge({"lamp_coins": Nodes.STARTING_COINS})
	if not data.has("nodes"):
		data.nodes = Nodes.generate(data.tiles, int(data.seed), relic_sites, data.rewards, {})
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

func trade(id: String, item: String, buying: bool, voucher: String = "") -> Dictionary:
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
	var quote = item_quote(base, "shop_buy" if buying else "shop_sell", "", voucher)
	if not quote.ok:
		return quote
	if buying:
		if int(stock.get(item, 0)) <= 0:
			return fail("这件货已经售完。")
		if data.lamp_coins < quote.price:
			return fail("灯铢不足。")
		stock[item] -= 1
		data.lamp_coins -= quote.price
		if is_relic:
			grant_relic(item, id, trader.position)
		else:
			inventory[item] = owned + 1
	else:
		if owned <= 0:
			return fail("没有可出售的物品。")
		if is_relic:
			_remove_relic(item)
		else:
			inventory[item] = owned - 1
		if not is_relic or Relics.is_active(item):
			stock[item] = int(stock.get(item, 0)) + 1
		data.lamp_coins += quote.price
	_commit_price(quote)
	var name: String = Relics.DATA[item].name if is_relic else Catalog.item_name(item)
	return _item_result("%s「%s」，%d 灯铢。" % ["买入" if buying else "卖出", name, quote.price])

func reward_coins(source: String, base: int) -> int:
	if base <= 0:
		return base
	var result = base
	for id in data.relic_attunement:
		var entry = Relics.DATA[id]
		if entry.hook == "economy_reward" and entry.params.source == source:
			result += ceili(base * int(entry.params.get("bonus_pp", 0)) / 100.0) + int(entry.params.get("bonus_flat", 0))
	return result

func use_node(id: String, option: String) -> Dictionary:
	var check = _node_access(id)
	if not check.ok:
		return check
	var visitor = actor(id)
	var cell: String = visitor.position
	var node = node_at(cell)
	if node.is_empty() or not node.result.is_empty():
		return fail("这里的事件已经处理完毕。")
	var event = Nodes.story(node)
	if option in ["settle", "settle_alternative"]:
		if "hero" not in same_cell(cell, true):
			return fail("等旅人到场，再一起处理这里的事。")
		if not node.get("investigated", false):
			return fail("先问清亡者为什么留在这里，别急着劝他离开。")
	if option in ["work_alternative", "settle_alternative"] and not event.has("alternative"):
		return fail("这里没有这种处理方式。")
	if node.kind == "haunt" and option == "inspect":
		if node.get("investigated", false):
			return fail("这里已经问过了，经过记在手记里。")
		node["investigated"] = true
		record_story_progress(cell, false)
		note("问清经过：" + str(event.title))
		changed.emit()
		return {"ok": true, "message": event.investigation}
	var message = ""
	var gear_reward = false
	match [node.kind, option]:
		["supply", "collect"]:
			return collect(id)
		["rest", "pack"], ["cache", "search"]:
			var relic = ""
			if option == "search" and relic_sites.has(cell):
				relic = str(investigate_relic(id).get("relic", ""))
			elif option == "search":
				relic = roll_relic("field_cache:" + cell, Relics.DATA.keys(), 0.20, id, cell)
			var uid: String = node.get("gear_uid", "")
			if not uid.is_empty():
				gear_reward = true
				var instance = data.gear_instances[uid]
				instance.owner = {"kind": "actor", "id": id}
				node.erase("gear_uid")
				message = "%s 取得「%s」。" % [visitor.name, Gear.label(instance)]
			else:
				var item: String = node.item
				visitor.inventory[item] = int(visitor.inventory.get(item, 0)) + 1
				message = "%s 取得%s ×1。" % [visitor.name, Catalog.item_name(item)]
			if not relic.is_empty():
				message += " 发现遗器「%s」。" % Relics.DATA[relic].name
		["choice", "work"], ["choice", "work_alternative"]:
			var coins = reward_coins("commission", int(node.coins))
			data.lamp_coins += coins
			roll_relic("commission:" + cell, Relics.DATA.keys(), 0.25, id, cell)
			message = "%s 完成委托，得到 %d 灯铢。" % [visitor.name, coins]
		["clue", "record"], ["haunt", "settle"], ["haunt", "settle_alternative"]:
			message = "这段见闻已记入手记。" if option == "record" else "这次送别已记入手记。"
			record_story_progress(cell, node.kind == "haunt")
			if node.kind == "haunt":
				roll_relic("spirit_farewell:" + cell, Relics.DATA.keys(), 0.50, id, cell)
				var key = "farewell_receipt:day:%d" % data.day
				if has_relic("farewell_receipt") and not data.item_effect_counts.has(key) and _restore_map(id, "mp", 6):
					data.item_effect_counts[key] = 1
		_:
			return fail("这里现在做不了这件事。")
	if option == "search":
		_after_cache(id, gear_reward)
	node.result = option
	data.item_revision += 1
	if option in ["work", "work_alternative"]:
		record_story_progress(cell, true)
	note(message)
	changed.emit()
	return {"ok": true, "message": message}

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

func grant_relic(id: String, finder: String, position: String, npc: String = "", lead: String = "") -> bool:
	if not Relics.is_active(id):
		return false
	var first = not data.relic_seen.has(id)
	data.relic_seen[id] = true
	data.relic_inventory[id] = int(data.relic_inventory.get(id, 0)) + 1
	data.item_revision += 1
	var new_sight: Array = []
	if Relics.DATA[id].type == "P" and not has_relic(id) and data.relic_attunement.size() < 6:
		data.relic_attunement.append(id)
		if id == "telescope":
			new_sight = _refresh_relic_sight()
	if first:
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

func _remove_relic(id: String) -> void:
	data.relic_inventory[id] -= 1
	if data.relic_inventory[id] == 0:
		data.relic_inventory.erase(id)
		_unattune(id)

func _unattune(id: String) -> void:
	data.relic_attunement.erase(id)
	if id == "uphill_kneepad":
		for key in data.item_effect_counts.keys():
			if str(key).begins_with("uphill_ready:"):
				data.item_effect_counts.erase(key)

func use_relic(user: String, id: String, target: String = "") -> Dictionary:
	var check = _node_access(user)
	if not check.ok:
		return check
	var entry = Relics.DATA.get(id, {})
	if not Relics.is_active(id) or int(data.relic_inventory.get(id, 0)) <= 0 or entry.get("type") == "P":
		return fail("没有可使用的遗器。")
	var a = actor(user)
	var params: Dictionary = entry.params
	match entry.hook:
		"run_growth_use":
			if data.relic_effect_flags.has(params.run_flag):
				return fail("生命之种在本局已使用。")
			for member in joined_ids():
				var recipient = actor(member)
				recipient.hp_max = roundi(recipient.hp_max * params.multiplier)
			data.relic_effect_flags[params.run_flag] = true
		"weather_use":
			if data.weather == params.set:
				return fail("今天已经下雨。")
			data.weather = params.set
			data.route_records.clear()
		"resource_use":
			var recipients: Array = [user]
			if params.targets == "all_healthy_joined_global":
				recipients = joined_ids()
			elif params.targets == "selected_other_healthy_joined_same_cell":
				if target == user or target not in same_cell(a.position, true):
					return fail("请选择同地另一位可行动队员。")
				recipients = [target]
			var costs = _resource_changes(a, params.get("cost", {}), id == "stillwater_stone")
			for resource in costs:
				if int(a[resource]) < costs[resource] or (resource == "hp" and int(a.hp) <= costs.hp):
					return fail("使用这件遗器需要花费的生命或魔力不够。")
			var gains: Dictionary = {}
			for member in recipients:
				var recipient = actor(member)
				if recipient.hp <= 0:
					continue
				var proposed = _resource_changes(recipient, params.restore, id == "stillwater_stone")
				for resource in proposed.keys():
					proposed[resource] = mini(proposed[resource], int(recipient[resource + "_max"] - recipient[resource]))
					if proposed[resource] <= 0:
						proposed.erase(resource)
				if not proposed.is_empty():
					gains[member] = proposed
			if gains.is_empty():
				return fail("没有可恢复的资源。")
			for resource in costs:
				a[resource] -= costs[resource]
			for member in gains:
				for resource in gains[member]:
					actor(member)[resource] += gains[member][resource]
		"map_reveal_use":
			if not _use_reveal_relic(a.position, params):
				return fail("附近没有新的公开信息。")
		"encounter_info_use":
			var tile = data.tiles.get(target, {})
			if target not in Hex.neighbors(a.position, data.tiles) or not data.visited.has(target) \
					or not tile.get("discovered_enemy", false) or tile.enemies.is_empty() or target == data.boss \
					or data.map_intel.has("encounter:" + target):
				return fail("请选一个相邻、已经去过、能查看敌情的地块。")
			var elements: Array = []
			for enemy in tile.enemies:
				var definition = Catalog.ENEMIES.get(enemy, {})
				elements.append(definition.get("element", "normal"))
			data.map_intel["encounter:" + target] = {"count": tile.enemies.size(), "elements": elements}
		"route_use":
			var route = _known_route(user, target)
			if route.is_empty() or data.route_records.get(user, {}) == route:
				return fail("请选一个发现了、能走到、还没记过路线的地块。")
			data.route_records[user] = route
		"transaction_use":
			return fail("在买入或强化的确认界面选择这张凭券。")
		_:
			return fail("此遗器无法在这里使用。")
	_remove_relic(id)
	var route: Dictionary = data.route_records.get(user, {}) if entry.hook == "route_use" else {}
	var result = _item_result("已使用「%s」。" % entry.name)
	if not route.is_empty():
		data.route_records[user] = route
	return result

static func _resource_changes(a: Dictionary, params: Dictionary, rounded: bool = false) -> Dictionary:
	var amounts: Dictionary = {}
	for resource in ["hp", "mp"]:
		var ratio = float(params.get(resource + "_max_pp", 0)) / 100.0
		var scaled: float = a[resource + "_max"] * ratio
		var value = int(params.get(resource + "_flat", 0)) + (roundi(scaled) if rounded else floori(scaled))
		value = maxi(value, int(params.get(resource + "_min_flat", 0)))
		if resource == "mp":
			value += int(params.get("user_mp_flat", 0))
		if value > 0:
			amounts[resource] = value
	return amounts

func _use_reveal_relic(origin: String, params: Dictionary) -> bool:
	var cells = data.tiles.keys()
	cells.sort_custom(func(a, b):
		var left = Hex.distance(Hex.coord(origin), Hex.coord(a))
		var right = Hex.distance(Hex.coord(origin), Hex.coord(b))
		return left < right if left != right else a < b)
	var revealed = false
	for cell in cells:
		if Hex.distance(Hex.coord(origin), Hex.coord(cell)) > params.radius:
			break
		var node = node_at(cell)
		if params.mode == "nearest_unclaimed_public_cache_marker":
			if node.get("kind") != "cache" or not node.result.is_empty() or data.tiles[cell].hidden or data.map_intel.has("cache:" + cell):
				continue
			data.map_intel["cache:" + cell] = true
			return true
		if not data.explored.has(cell):
			data.explored[cell] = true
			revealed = true
	return revealed

func _known_route(user: String, destination: String) -> Dictionary:
	var origin: String = actor(user).position
	if destination == origin or not data.explored.has(destination) or not Hex.is_land(data.tiles, destination):
		return {}
	var known_tiles: Dictionary = {}
	for cell in data.explored:
		known_tiles[cell] = data.tiles[cell]
	var path = Hex.path(known_tiles, origin, destination)
	return {"path": path} if not path.is_empty() else {}

func has_visited(position: String) -> bool:
	return data.visited.has(position)

func knows_encounter(position: String) -> bool:
	var tile = data.tiles[position]
	return (has_visited(position) or (position == data.boss and boss_known())) and tile.discovered_enemy and not tile.enemies.is_empty()

func _day_gear_keys(id: String, effect: String, gear: String) -> Array:
	var prefix = "day:%d:%s:" % [data.day, effect]
	var keys = [prefix + id]
	for slot in Gear.SLOTS:
		var definition = equipped_definition(id, slot)
		if definition == gear or Gear.DATA.get(definition, {}).get("set_id") == gear:
			keys.append(prefix + "uid:" + str(actor(id).equipment[slot]))
	return keys

func _map_limit(keys: Array, maximum: int) -> bool:
	return keys.all(func(key): return int(data.item_effect_counts.get(key, 0)) < maximum)

func _map_count(keys: Array) -> void:
	for key in keys:
		data.item_effect_counts[key] = int(data.item_effect_counts.get(key, 0)) + 1

func _restore_map(id: String, resource: String, amount: int) -> bool:
	var a = actor(id)
	var gain = mini(amount, int(a[resource + "_max"] - a[resource]))
	if a.hp <= 0 or gain <= 0:
		return false
	a[resource] += gain
	return true

func _after_move(id: String, terrain: String) -> void:
	var uphill = "uphill_kneepad:day:%d:%s" % [data.day, id]
	if terrain == "mountain" and actor(id).hp > 0 and has_relic("uphill_kneepad") and not data.item_effect_counts.has(uphill):
		data.item_effect_counts["uphill_ready:" + id] = 1

func _after_cache(id: String, gear_reward: bool) -> void:
	if has_relic("unpacking_mat"):
		_restore_map(id, "ap", 1)
	if not gear_reward:
		return
	if equipped_definition(id, "accessory") == "road_surveyor_accessory":
		var keys = _day_gear_keys(id, "cache:mp", "road_surveyor_accessory")
		if _map_limit(keys, 2) and _restore_map(id, "mp", 3):
			_map_count(keys)

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
	for id in joined_ids():
		_after_move(id, data.tiles[destination].terrain)
	reveal(destination)
	data.route_records.clear()
	for threshold in [20, 60, 100]:
		if data.visited.size() >= threshold:
			var reward = roll_relic("explore:" + str(threshold), Relics.DATA.keys(), 1.0, "hero", destination)
			if not reward.is_empty() and has_relic("milestone_waterbag"):
				for member in joined_ids():
					_restore_map(member, "mp", floori(actor(member).mp_max * 0.15))
	var t = data.tiles[destination]
	var encounter = not t.enemies.is_empty()
	if encounter:
		var surprise = not preview.encounter
		var ambush = t.hidden and surprise
		t.discovered_enemy = true
		data.pending_battle = {"position": destination, "ambush": ambush, "surprise": surprise, "origin": preview.source, "npc": ""}
		note("隐蔽处的敌人发动伏击！" if ambush else "抵达遭遇地点，请选择出战角色。")
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
	if data.relic_effect_flags.has("life_seed_applied"):
		a.hp_max = roundi(a.hp_max * 1.20)
	if has_relic("telescope"):
		_reveal_sight(a.position)
	data.story[id].relation = "joined"
	data.story[id].met = true
	note("%s 加入远征队。" % a.name)
	var source = "recruit:" + id
	for relic in Relics.DATA:
		if Relics.is_active(relic) and Relics.DATA[relic].source == source:
			claim_relic_reward(source, relic, id, a.position)
			break
	changed.emit()
	return success()

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
	if has_relic("herbal_case"):
		healing = roundi(healing * 1.25)
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
	if not t.enemies.is_empty() or t.quantity <= 0:
		return fail("这里没有安全可采集的道具。")
	var amount = int(t.quantity) + (1 if id == "cen" and t.terrain == "forest" else 0)
	a.inventory[t.resource] = int(a.inventory.get(t.resource, 0)) + amount
	t.quantity = 0
	data.item_revision += 1
	var message = "%s 收集了%s ×%d。" % [a.name, Catalog.item_name(t.resource), amount]
	note(message)
	changed.emit()
	return {"ok": true, "message": message}

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
	return 0.48 if has_relic("rainstone") else 0.28

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

func pending_chapter() -> int:
	var chapter = int(data.chapter)
	if data.status == "exploring" and chapter < 4 and data.explored.size() * 100 >= (chapter + 1) * 20 * data.tiles.size():
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

func record_story_progress(cell: String, peaceful: bool) -> void:
	if cell == data.boss:
		return
	data.leads[cell] = true
	if peaceful:
		data.peace[cell] = true

func _map_action(id: String) -> Dictionary:
	if data.is_empty() or data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("当前不能执行探索行动。")
	var a = actor(id)
	if a.is_empty() or not a.joined or a.hp <= 0:
		return fail("该角色无法行动。")
	return success()

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
	if not _whole_number(loaded.get("version", -1)) or int(loaded.version) not in [3, 4, SAVE_VERSION] or not loaded.has_all(["actors", "tiles", "rng_state", "day", "explored", "status"]):
		return fail("存档版本不兼容，或者进度记录不完整。")
	if int(loaded.version) >= 4 and (not loaded.get("relic_seen") is Dictionary or not loaded.get("nodes") is Dictionary):
		return fail("遗器发现记录无效。")
	var invalid = _validate_save(loaded)
	if invalid != "":
		return fail("存档内容无效：" + invalid + "。旧文件没有被覆盖。")
	if int(loaded.version) == 3:
		if not loaded.has("nodes"):
			var sites = Relics.exploration_sites(loaded.tiles, int(loaded.seed))
			loaded.nodes = Nodes.generate(loaded.tiles, int(loaded.seed), sites, loaded.rewards, loaded.get("relic_checks", {}))
			loaded.merge({"lamp_coins": Nodes.STARTING_COINS})
		Items.migrate(loaded)
	if int(loaded.version) < SAVE_VERSION:
		_migrate_travel(loaded)
	if not Items.validate(loaded):
		return fail("存档中的装备或遗器记录无效。")
	data = loaded
	_remove_legacy_map_effects()
	for id in data.actors:
		actor(id).attack_delivery = "ranged" if id == "hero" else Catalog.COMPANIONS[id].attack_delivery
	if not data.has("visited"):
		_restore_legacy_visits()
	if not data.has("choices"):
		data.choices = []
	_initialize_relics()
	_initialize_nodes()
	rng.state = int(data.rng_state)
	changed.emit()
	return success()

func _migrate_travel(loaded: Dictionary) -> void:
	loaded.version = SAVE_VERSION
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
	if not loaded.has_all(["flags", "story", "knowledge", "rewards", "log", "pending_battle", "start", "boss", "leads", "peace", "chapter", "profession", "explored", "transaction", "battles", "weather"]):
		return "进度记录不完整"
	for key in ["actors", "tiles", "flags", "story", "knowledge", "rewards", "pending_battle", "explored", "leads", "peace"]:
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
	if int(loaded.version) == SAVE_VERSION and (not _whole_number(loaded.get("steps_today")) or loaded.steps_today < 0 or loaded.steps_today >= STEPS_PER_DAY):
		return "当日步数无效"
	if loaded.has("choices") and not loaded.choices is Array:
		return "选择记录无效"
	if loaded.has("lamp_coins") and (not _whole_number(loaded.lamp_coins) or loaded.lamp_coins < 0):
		return "灯铢记录无效"
	if not loaded.get("relics", {}) is Dictionary or not loaded.get("relic_checks", {}) is Dictionary or not loaded.get("relic_intros", []) is Array:
		return "遗器记录无效"
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
		if int(loaded.version) == SAVE_VERSION and a.joined and a.position != loaded.actors.hero.position:
			return "队员与旅人不在同一地块"
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
		if not Nodes.LABELS.has(node.kind) or not node.event is String or not node.result is String:
			return false
		if node.kind != "story" and Nodes.story(node).is_empty():
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
