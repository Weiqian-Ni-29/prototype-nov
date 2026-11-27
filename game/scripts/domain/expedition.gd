class_name Expedition
extends RefCounted
## Authoritative state: renderers never own or regenerate resources.
const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Items = preload("res://scripts/domain/expedition_items.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const Journey = preload("res://scripts/domain/journey.gd")
const Opening = preload("res://scripts/domain/opening_story.gd")
const SAVE_VERSION = 15
const REMOVED_WEATHER_CARDS = ["rain", "sun", "fog_spell"]
const REMOVED_SUPPLIES = ["salve", "ether"]
signal changed
var data: Dictionary = {}
var rng = RandomNumberGenerator.new()
var save_path = "user://expedition.json"
var prepared_relic := ""
const SPELL_RELICS = {"banked_ember_box": "ember_spell", "rime_thimble": "ice_spell",
	"herbal_case": "mend_spell"}

func new_run(seed_value: int, profession: String) -> void:
	assert(Catalog.PROFESSIONS.has(profession))
	prepared_relic = ""
	rng.seed = seed_value ^ 0x5eed123
	data = {"version": SAVE_VERSION, "seed": seed_value, "profession": profession, "day": 1,
		"start": Journey.CAMP, "village": Opening.terrain(seed_value), "boss_relief": 0, "actors": {},
		"flags": {}, "story": {}, "rewards": {}, "status": "exploring", "log": [], "battles": 0,
		"transaction": 0, "pending_battle": {}, "lamp_coins": Items.STARTING_COINS}
	var hero_def = Catalog.PROFESSIONS[profession].duplicate(true)
	hero_def["title"] = "旅人"
	hero_def["name"] = "旅人"
	hero_def["portrait"] = "hero"
	hero_def["skill"] = "gravity"
	hero_def["attack_delivery"] = "ranged"
	hero_def["ultimate"] = "gravity_drift"
	data.actors["hero"] = _actor("hero", hero_def, Journey.CAMP, true)
	Items.initialize(data)
	data.actors.hero.inventory.trail_food = 2
	for id in Gear.LEGACY_PRICES:
		data.actors.hero.equipment[Gear.DATA[id].slot] = Items.add_gear(data, id, "common", "actor", "hero")
	Items.add_gear(data, "frontier_guard_weapon", "common", "actor", "hero")
	data.spell_collection = Cards.STARTER_SPELLS.duplicate()
	for id in Catalog.COMPANIONS:
		data.actors[id] = _actor(id, Catalog.COMPANIONS[id], Journey.CAMP, false)
		data.story[id] = {"relation": "unmet", "result": "E0", "met": false}
	Journey.begin(self)
	note("村民交给你一副牌。你沿着鼓声出发。")

func _actor(id: String, definition: Dictionary, position: String, joined: bool) -> Dictionary:
	var result = definition.duplicate(true)
	result.merge({"id": id, "position": position, "joined": joined, "hp_max": definition.hp, "mp_max": definition.mp, "energy": 0, "inventory": {}, "equipment": {"weapon": "", "armor": "", "accessory": ""}, "shield": 0, "slow": 0, "guard": false}, true)
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
	var check = _shop_access(id)
	if not check.ok:
		return check
	var a = actor(id)
	var instance = data.gear_instances.get(uid, {})
	var kind = "shop" if buying else "actor"
	var owner: String = a.position if buying else id
	if instance.get("owner") != {"kind": kind, "id": owner}:
		return fail("这件装备当前无法交易。")
	var quote = item_quote(Gear.price(instance), "shop_buy" if buying else "shop_sell", uid, voucher)
	if not quote.ok:
		return quote
	if buying and data.lamp_coins < quote.price:
		return fail("灯铢不足。")
	var card_id := "gear:" + uid
	# Read the default deck before the new equipment becomes available.
	if buying:
		data.card_deck = card_deck() + [card_id]
	data.lamp_coins += -quote.price if buying else quote.price
	instance.owner = {"kind": "actor" if buying else "shop", "id": id if buying else a.position}
	if not buying:
		if data.has("card_deck"):
			data.card_deck.erase(card_id)
		for slot in a.equipment:
			if a.equipment[slot] == uid:
				a.equipment[slot] = ""
	_commit_price(quote)
	var message := "%s「%s」，%d 灯铢。" % ["买入" if buying else "卖出", Gear.label(instance), quote.price]
	return _item_result(message + ("已加入卡组。" if buying else ""))

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
	var check = _party_action(id)
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

func shop_refresh_cost(cell: String) -> int:
	return int(shop_at(cell).get("refresh_count", 0)) + 1

func shop_at(cell: String) -> Dictionary:
	var shop: Dictionary = data.get("battle_shop", {})
	return shop if shop.get("cell") == cell else {}

func _shop_access(id: String) -> Dictionary:
	var trader := actor(id)
	if trader.is_empty() or not trader.joined or trader.hp <= 0 or not Journey.shop_active(data) \
			or shop_at(trader.position).is_empty():
		return fail("商店当前不可用。")
	return success()

func open_battle_shop() -> void:
	if not data.has("battle_shop") and Journey.shop_active(data):
		Items.open_battle_shop(data, actor("hero").position)

func close_battle_shop() -> void:
	if not data.has("battle_shop"):
		return
	for uid in gear_owned("shop", data.battle_shop.cell):
		data.gear_instances.erase(uid)
	data.erase("battle_shop")

func refresh_shop(id: String) -> Dictionary:
	var check := _shop_access(id)
	if not check.ok:
		return check
	var cell: String = actor(id).position
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
	var check = _shop_access(id)
	if not check.ok:
		return check
	var trader = actor(id)
	var node := shop_at(trader.position)
	if Gear.DATA.has(item):
		return fail("请选择具体装备。")
	var is_relic = Relics.DATA.has(item)
	if (is_relic and buying and not Relics.is_active(item)) or (not is_relic and not Items.SUPPLY_PRICES.has(item)):
		return fail("商摊无法交易这种物品。")
	var stock: Dictionary = node.relic_stock if is_relic else node.stock
	var inventory: Dictionary = data.relic_inventory if is_relic else trader.inventory
	var owned: int = int(inventory.get(item, 0))
	var base: int = Relics.DATA[item].price if is_relic else Items.SUPPLY_PRICES[item]
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

func has_relic(id: String) -> bool:
	return int(data.relic_inventory.get(id, 0)) > 0 and Relics.is_active(id) and Relics.DATA[id].type == "P"

func passive_relic_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in data.relic_inventory:
		if has_relic(id):
			ids.append(id)
	ids.sort()
	return ids

func relic_intro() -> Dictionary:
	return data.relic_intros[0] if not data.relic_intros.is_empty() else {}

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

func grant_relic(id: String, finder: String, _position: String = "", _npc: String = "", _lead: String = "", amount: int = 1) -> bool:
	if not Relics.is_active(id):
		return false
	var first = not data.relic_seen.has(id)
	data.relic_seen[id] = true
	data.relic_inventory[id] = int(data.relic_inventory.get(id, 0)) + amount
	data.item_revision += 1
	if first:
		var spell: String = SPELL_RELICS.get(id, "")
		if not spell.is_empty():
			unlock_spell(spell)
		data.relic_intros.append({"id": id, "finder": finder})
	note("远征队获得遗器「%s」。" % Relics.DATA[id].name)
	return true

func _remove_relic(id: String, amount: int = 1) -> void:
	data.relic_inventory[id] -= amount
	if data.relic_inventory[id] == 0:
		data.relic_inventory.erase(id)
		if id == "uphill_kneepad":
			for key in data.item_effect_counts.keys():
				if str(key).begins_with("uphill_ready:"):
					data.item_effect_counts.erase(key)

func use_relic(user: String, id: String, _target: String = "") -> Dictionary:
	var check := _party_action(user)
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

func join_companion(id: String, recruiter_id: String = "") -> Dictionary:
	if not data.actors.has(id) or id == "hero":
		return fail("没有这位伙伴。")
	var a = actor(id)
	if a.hp <= 0:
		return fail("对方伤得很重。暂时无法同行。")
	var local_crew = same_cell(a.position, true)
	if local_crew.is_empty() or (not recruiter_id.is_empty() and recruiter_id not in local_crew):
		return fail("队伍目前无法招募。")
	if a.joined:
		return fail("已经同行。")
	a.joined = true
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
	if shop_at(cell).is_empty():
		return []
	var roster := Catalog.COMPANIONS.keys()
	var priority := {}
	for id in roster:
		priority[id] = hash("recruits:%s:%s" % [data.journey.seed, id])
	roster.sort_custom(func(a, b): return a < b if priority[a] == priority[b] else priority[a] < priority[b])
	var offset := int(data.journey.step) * 3
	var stock := []
	for i in roster.size():
		var id: String = roster[posmod(offset + i, roster.size())]
		if not actor(id).joined and actor(id).hp > 0:
			stock.append(id)
			if stock.size() == 3:
				break
	return stock

func recruit_shop_price(cell: String) -> int:
	return 6 if not shop_at(cell).is_empty() and joined_ids().size() == 1 else Cards.RECRUIT_PRICE

func recruit_quote(id: String) -> Dictionary:
	var check := _shop_access("hero")
	if not check.ok:
		return check
	var cell: String = actor("hero").position
	if id not in recruit_shop_offers(cell):
		return fail("这位伙伴当前不在战后招募名单里。")
	if data.has("pending_story_rewards"):
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
	data.card_deck = card_deck() + [id]
	if not result.relic.is_empty():
		data.pending_story_rewards = {"source": "招募 · " + actor(id).name,
			"items": [{"kind": "relic", "id": result.relic, "count": 1}]}
	var saved := _save_companion_purchase(previous)
	if saved.ok:
		saved.message = "%s已入队，伙伴牌已加入卡组。" % actor(id).name
	return saved

func breakthrough_quote(id: String) -> Dictionary:
	var check := _party_action("hero")
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

func equip(id: String, uid: String) -> Dictionary:
	var check = _party_action(id)
	if not check.ok:
		return check
	var a = actor(id)
	var item = data.gear_instances.get(uid, {})
	if item.get("owner") != {"kind": "actor", "id": id}:
		return fail("该角色不持有此装备。")
	var slot: String = Gear.DATA[item.definition_id].slot
	a.equipment[slot] = "" if a.equipment[slot] == uid else uid
	return _item_result("已更新装备。")

func check_global_failure() -> bool:
	for id in joined_ids():
		if actor(id).hp > 0:
			return false
	data.status = "failed"
	data.flags["failure_reason"] = "全体重伤，已没有可行动的救援者。"
	return true

func war_god_stats() -> Dictionary:
	var result = Catalog.ENEMIES.war_god.duplicate(true)
	var calm = int(data.boss_relief)
	result.hp -= calm * 3
	result.attack -= calm
	return result

func exploration_percent() -> int:
	return 100 if data.status == "won" else floori(100.0 * int(data.journey.step) / (Journey.STOPS - 1))

func _party_action(id: String) -> Dictionary:
	if data.is_empty() or data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("当前不能执行探索行动。")
	var a = actor(id)
	if a.is_empty() or not a.joined or a.hp <= 0:
		return fail("该角色无法行动。")
	return success()

func card_deck() -> Array:
	return data.card_deck.duplicate() if data.has("card_deck") else starter_card_deck()

func starter_card_deck() -> Array:
	return _convert_gear_cards(Cards.DEFAULT_DECK)

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
	var node := shop_at(cell)
	var restocks := int(node.get("refresh_count", 0))
	if node.is_empty() or node.get("spell_sold", false):
		return []
	var available: Array = Cards.UNLOCKABLE_SPELLS.filter(func(id): return id not in data.spell_collection)
	if available.is_empty():
		return []
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("spell_shop:%d:%s:%d" % [int(data.seed), Journey.shop_key(data), restocks])
	var first: Variant = available.pop_at(roller.randi_range(0, available.size() - 1))
	return [first, available[roller.randi_range(0, available.size() - 1)]] if has_relic("market_window") and not available.is_empty() else [first]

func spell_shop_price() -> int:
	var base := 6 if has_relic("bargaining_counter") else 8
	return floori(base / 2.0) if data.relic_effect_flags.has("chess_spell_discount") else base

func buy_spell(id: String, spell: String) -> Dictionary:
	var check := _shop_access(id)
	if not check.ok:
		return check
	var cell: String = actor(id).position
	var price := spell_shop_price()
	if spell.is_empty() or spell not in spell_shop_offers(cell) or data.lamp_coins < price:
		return fail("这张法术牌谱当前无法购买。")
	unlock_spell(spell)
	data.card_deck = card_deck() + [spell]
	data.lamp_coins -= price
	data.relic_effect_flags.erase("chess_spell_discount")
	shop_at(cell).spell_sold = true
	return _item_result("已解锁「%s」并加入卡组。" % Cards.ACTIONS[spell].name)

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
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return fail("存档损坏了，原来的文件还在。")
	var loaded: Dictionary = json.data
	var version: Variant = loaded.get("version")
	if not _whole_number(version) or int(version) < 3 or int(version) > SAVE_VERSION:
		return fail("存档版本不兼容。")
	var legacy := int(version) < SAVE_VERSION
	var old_map := legacy and not loaded.has("journey")
	if int(version) < 11:
		_remove_battle_weather(loaded)
	var invalid := _validate_save(loaded)
	if not invalid.is_empty():
		return fail("存档内容无效：" + invalid + "。旧文件没有被覆盖。")
	var previous := data
	var previous_rng: int = rng.state
	data = loaded
	if legacy:
		_upgrade_save(int(version))
	if not Journey.valid(data) or not Items.validate(data) \
			or (data.has("card_deck") and not Cards.valid_deck(data.card_deck, data.actors, false, data)):
		data = previous
		return fail("途中抉择、卡组或物品记录无效，原来的存档还在。")
	if old_map:
		var archive := path + ".legacy-map.bak"
		if not FileAccess.file_exists(archive) and DirAccess.copy_absolute(path, archive) != OK:
			data = previous
			return fail("无法备份旧地图存档，请检查存档目录后重试。")
	rng.state = int(data.rng_state)
	if legacy:
		var saved := save_game(path)
		if not saved.ok:
			data = previous
			rng.state = previous_rng
			return saved
	prepared_relic = ""
	changed.emit()
	return success()

func _upgrade_save(version: int) -> void:
	if version == 3:
		Items.migrate(data)
	if version < 10:
		_remove_old_supplies(data)
	if version < 6 and data.get("card_deck") is Array:
		data.card_deck = Cards.migrate_deck(data.card_deck, data.actors)
	data.merge({"spell_collection": [], "lamp_coins": Items.STARTING_COINS})
	if version < 8:
		for relic in SPELL_RELICS:
			if data.relic_seen.has(relic):
				unlock_spell(SPELL_RELICS[relic])
		if not gear_owned("actor", "hero").any(func(uid): return data.gear_instances[uid].definition_id == "frontier_guard_weapon"):
			Items.add_gear(data, "frontier_guard_weapon", "common", "actor", "hero")
		if data.has("card_deck"):
			data.card_deck = _convert_gear_cards(data.card_deck)
	if version < 9:
		for spell in Cards.STARTER_SPELLS:
			if spell not in data.spell_collection:
				data.spell_collection.append(spell)
		if data.has("card_deck"):
			_replace_old_support_cards()

	var old_start: String = str(data.get("start", ""))
	var tiles: Dictionary = data.get("tiles", {})
	var biome: String = tiles.get(old_start, {}).get("base_terrain", "plains")
	data.village = biome if Opening.VILLAGES.has(biome) else "plains"
	data.boss_relief = mini(12, data.get("peace", {}).size())

	if not data.has("journey"):
		close_battle_shop()
		data.erase("pending_victory")
		data.pending_battle = {}
		Journey.begin(self)
		if data.status == "exploring" and actor("hero").hp <= 0 and not check_global_failure():
			actor("hero").hp = 1
	for id in data.actors:
		var person := actor(id)
		person.position = Journey.CAMP
		person.erase("element")
		person.erase("ap")
		person.erase("ap_max")
		person.erase("ap_initialized_day")
		person.erase("squad_id")
		person.attack_delivery = "ranged" if id == "hero" else Catalog.COMPANIONS[id].attack_delivery
	for uid in data.gear_instances.keys():
		var item: Variant = data.gear_instances[uid]
		if not item is Dictionary or not item.get("owner") is Dictionary:
			continue
		var owner: Dictionary = item.owner
		if owner.kind == "shop" and data.has("battle_shop") and owner.id == data.battle_shop.cell:
			owner.id = Journey.CAMP
		elif owner.kind != "actor":
			data.gear_instances.erase(uid)
	if data.has("battle_shop"):
		data.battle_shop.cell = Journey.CAMP
	if not data.pending_battle.is_empty():
		data.pending_battle.position = Journey.CAMP
		data.pending_battle.origin = Journey.CAMP
	data.relic_intros = data.get("relic_intros", []).map(func(entry): return {"id": entry.id, "finder": entry.finder})
	if not data.pending_battle.is_empty() and data.pending_battle.has("journey_step") \
			and data.journey is Dictionary and data.journey.get("history") is Array \
			and _whole_number(data.journey.get("step")) and data.journey.get("seed") is String:
		var index: int = int(data.journey.step)
		if index >= 0 and index < data.journey.history.size() and data.journey.history[index] is Dictionary:
			data.pending_battle.enemies = Journey.battle_enemies(data, data.pending_battle)
	for index in data.log.size():
		var line: Variant = data.log[index]
		if line is String and line.begins_with("第 ") and (line.ends_with("，雨。") or line.ends_with("，晴。")):
			data.log[index] = line.trim_suffix("，雨。").trim_suffix("，晴。") + "。"
	data.start = Journey.CAMP
	data.version = SAVE_VERSION
	for field in ["tiles", "nodes", "visited", "explored", "pending_arrival", "boss", "peace",
			"chapter", "steps_today", "knowledge", "choices", "map_intel", "route_records",
			"last_move_windows", "next_move_uid", "last_day_settled", "squad_colors", "next_squad_id",
			"relic_attunement", "weather", "leads", "relics", "relic_checks"]:
		data.erase(field)
	data.flags.erase("player_ignitions")

func _remove_battle_weather(loaded: Dictionary) -> void:
	if loaded.get("card_deck") is Array:
		loaded.card_deck = loaded.card_deck.filter(func(id): return id not in REMOVED_WEATHER_CARDS)
	if loaded.get("spell_collection") is Array:
		loaded.spell_collection.erase("fog_spell")
	var removed := Relics.REMOVED_WEATHER_RELICS
	for field in ["relics", "relic_seen", "relic_inventory"]:
		if loaded.get(field) is Dictionary:
			for id in removed:
				loaded[field].erase(id)
	if loaded.get("relic_intros") is Array:
		loaded.relic_intros = loaded.relic_intros.filter(func(entry): return not entry is Dictionary or entry.get("id") not in removed)
	var shops: Array = [loaded.get("battle_shop")]
	if loaded.get("nodes") is Dictionary:
		shops.append_array(loaded.nodes.values())
	for shop in shops:
		if shop is Dictionary and shop.get("relic_stock") is Dictionary:
			for id in removed:
				shop.relic_stock.erase(id)
	for field in ["relic_checks", "battle_offers"]:
		if loaded.get(field) is Dictionary:
			for key in loaded[field]:
				if loaded[field][key] in removed:
					loaded[field][key] = ""
	if loaded.get("relic_claims") is Dictionary:
		for key in loaded.relic_claims:
			var claim = loaded.relic_claims[key]
			if claim is Dictionary and claim.get("relic_id") in removed:
				loaded.relic_claims[key] = {"success": false, "relic_id": "", "delivered": true}
	if loaded.get("pending_battle") is Dictionary and loaded.pending_battle.get("relic_offer") in removed:
		loaded.pending_battle.relic_offer = ""
	if loaded.get("pending_victory") is Dictionary and loaded.pending_victory.get("relic") in removed:
		loaded.pending_victory.relic = ""
	var receipt = loaded.get("pending_story_rewards")
	if receipt is Dictionary and receipt.get("items") is Array:
		var items: Array = receipt.items.filter(func(item):
			return not item is Dictionary or item.get("kind") != "relic" or item.get("id") not in removed)
		if items.size() != receipt.items.size():
			receipt.items = items
			if items.is_empty() and receipt.get("kind") != "starter_deck":
				loaded.erase("pending_story_rewards")

func _remove_old_supplies(loaded: Dictionary) -> void:
	for person in loaded.actors.values():
		for id in REMOVED_SUPPLIES:
			person.inventory.erase(id)
	if loaded.has("pending_story_rewards"):
		var receipt: Dictionary = loaded.pending_story_rewards
		receipt.items = receipt.items.filter(func(item): return item.kind != "item" or item.id not in REMOVED_SUPPLIES)
		if receipt.items.is_empty() and receipt.get("kind") != "starter_deck":
			loaded.erase("pending_story_rewards")
	if loaded.has("pending_victory"):
		loaded.pending_victory.erase("salve_receiver")

func _validate_save(loaded: Dictionary) -> String:
	if not loaded.has_all(["actors", "flags", "story", "rewards", "log", "pending_battle",
			"profession", "transaction", "battles", "seed", "day", "status", "rng_state"]):
		return "进度记录不完整"
	for key in ["actors", "flags", "story", "rewards", "pending_battle"]:
		if not loaded[key] is Dictionary:
			return "进度记录格式有误"
	if loaded.status not in ["exploring", "won", "failed"] or not Catalog.PROFESSIONS.has(loaded.profession):
		return "状态或职业无效"
	if not loaded.log is Array or not Items.whole(loaded.day, 1) or not str(loaded.rng_state).is_valid_int() \
			or not _whole_number(loaded.seed) or not Items.whole(loaded.transaction) or not Items.whole(loaded.battles):
		return "日期或随机状态无效"
	if int(loaded.version) >= 4 and (not loaded.get("relic_seen") is Dictionary or not loaded.get("gear_instances") is Dictionary):
		return "物品记录无效"
	if int(loaded.version) == SAVE_VERSION:
		if loaded.get("start") != Journey.CAMP or not Opening.VILLAGES.has(loaded.get("village")) \
				or not Items.whole(loaded.get("lamp_coins")) \
				or not Items.whole(loaded.get("boss_relief")) or int(loaded.boss_relief) > 12 or not loaded.has("journey"):
			return "旅途记录无效"
	else:
		for key in ["tiles", "peace"]:
			if not loaded.get(key) is Dictionary:
				return "旧远征记录不完整"
		var start: Variant = loaded.tiles.get(loaded.get("start"))
		if not start is Dictionary or not start.get("base_terrain") is String:
			return "旧远征的出发点无效"
		if loaded.has("battle_shop") and (not loaded.battle_shop is Dictionary or not loaded.battle_shop.get("cell") is String):
			return "旧商店记录无效"
		for instance in loaded.get("gear_instances", {}).values():
			if not instance is Dictionary or not Gear.DATA.has(instance.get("definition_id")) \
					or not instance.get("owner") is Dictionary or not instance.owner.get("id") is String or instance.owner.get("kind") not in ["actor", "shop", "source"]:
				return "旧装备归属无效"
	var spells: Variant = loaded.get("spell_collection", [])
	if not spells is Array or spells.any(func(spell): return spell not in Cards.UNLOCKABLE_SPELLS) or spells.any(func(spell): return spells.count(spell) > 1):
		return "法术牌谱无效"
	if loaded.has("card_deck") and not (loaded.card_deck is Array
			and (int(loaded.version) <= 6 or int(loaded.version) >= 8 or Cards.valid_deck(loaded.card_deck, loaded.actors, false, {}, true))):
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
				or not receipt.get("items") is Array \
				or (receipt.items.is_empty() and receipt.get("kind") != "starter_deck"):
			return "剧情奖励记录无效"
		for item in receipt.items:
			if not item is Dictionary or not item.get("id") is String \
					or not _whole_number(item.get("count")) or item.count <= 0:
				return "剧情奖励记录无效"
			match item.get("kind"):
				"item":
					if not Catalog.ITEMS.has(item.id) and (int(loaded.version) >= 10 or item.id not in REMOVED_SUPPLIES):
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
		if not result is Dictionary or not result.has_all(["enemies", "members", "revived", "relic"]) \
				or not _whole_number(result.enemies) or result.enemies < 1 or not result.members is Array or result.members.is_empty() \
				or not result.revived is Array or not result.relic is String:
			return "胜利结算无效"
		if not result.members.all(func(id): return loaded.actors.has(id)) or not result.revived.all(func(id): return id in result.members) \
				or (result.relic != "" and not loaded.get("relic_seen", loaded.get("relics", {})).has(result.relic)):
			return "胜利结算无效"
		if result.has("coins") and (not _whole_number(result.coins) or result.coins < 0):
			return "胜利报酬无效"
	for id in loaded.get("relics", {}):
		if not Relics.DATA.has(id) or loaded.relics[id] != true:
			return "未知遗器"
	for entry in loaded.get("relic_intros", []):
		if not entry is Dictionary or not loaded.get("relic_seen", loaded.get("relics", {})).has(entry.get("id")) \
				or not loaded.actors.has(entry.get("finder")):
			return "遗器剧情无效"
	if loaded.actors.size() != Catalog.COMPANIONS.size() + 1:
		return "角色数量无效"
	for id in ["hero"] + Catalog.COMPANIONS.keys():
		if not loaded.actors.has(id) or not loaded.actors[id] is Dictionary:
			return "角色缺失"
		var a = loaded.actors[id]
		if not a.has_all(["id", "name", "color", "attack", "defense", "speed", "shield", "slow", "guard", "position", "joined", "hp", "hp_max", "mp", "mp_max", "energy", "equipment", "inventory", "skill", "ultimate"]):
			return "角色记录不完整"
		if a.id != id or not a.name is String or not a.color is String or not a.joined is bool:
			return "角色标识无效"
		if not a.position is String or not a.inventory is Dictionary or not a.equipment is Dictionary:
			return "队伍或背包无效"
		if int(loaded.version) == SAVE_VERSION and a.position != Journey.CAMP:
			return "队伍记录无效"
		var rank: Variant = a.get("breakthrough", 0)
		if not _whole_number(rank) or rank < 0 or rank > Cards.BREAKTHROUGH_PRICES.size() or (rank > 0 and (id == "hero" or not a.joined)):
			return "伙伴突破记录无效"
		if not Catalog.SAVE_SKILL_IDS.has(a.skill) or not Catalog.SAVE_SKILL_IDS.has(a.ultimate):
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
		if not pending.has_all(["position", "origin", "ambush", "npc"]) or not pending.ambush is bool \
				or not pending.npc is String or not pending.position is String or not pending.origin is String:
			return "遭遇检查点无效"
		if pending.has("surprise") and not pending.surprise is bool:
			return "遭遇检查点无效"
	return ""

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
