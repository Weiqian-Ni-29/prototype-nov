class_name Expedition
extends RefCounted
## Authoritative state: renderers never own or regenerate resources.
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
const SAVE_VERSION = 3
signal changed
var data: Dictionary = {}
var rng = RandomNumberGenerator.new()
var save_path = "user://expedition.json"
var relic_sites: Dictionary = {}

func new_run(seed_value: int, profession: String) -> void:
	assert(Catalog.PROFESSIONS.has(profession))
	var generated = Hex.generate(seed_value)
	rng.seed = seed_value ^ 0x5eed123
	data = {"version": SAVE_VERSION, "seed": seed_value, "profession": profession, "day": 1, "weather": "sun", "tiles": generated.tiles, "start": generated.start, "boss": generated.boss, "leads": {}, "peace": {}, "chapter": 0, "actors": {}, "explored": {}, "visited": {}, "flags": {}, "knowledge": {}, "story": {}, "rewards": {}, "choices": [], "status": "exploring", "log": [], "last_day_settled": 0, "battles": 0, "transaction": 0, "pending_battle": {}}
	var hero_def = Catalog.PROFESSIONS[profession].duplicate(true)
	hero_def["title"] = "旅人"
	hero_def["name"] = "旅人"
	hero_def["element"] = "none"
	hero_def["portrait"] = "hero"
	hero_def["skill"] = "gravity"
	hero_def["ultimate"] = "gravity_drift"
	data.actors["hero"] = _actor("hero", hero_def, generated.start, true)
	data.actors.hero.inventory.merge({"trail_food": 2, "trail_blade": 1, "padded_coat": 1, "lamp_charm": 1})
	data.actors.hero.equipment = {"weapon": "trail_blade", "armor": "padded_coat", "accessory": "lamp_charm"}
	for id in Catalog.COMPANIONS:
		var location = ""
		for k in data.tiles:
			if data.tiles[k].npc == id:
				location = k
		data.actors[id] = _actor(id, Catalog.COMPANIONS[id], location, false)
		data.story[id] = {"relation": "unmet", "result": "E0", "met": false}
	_initialize_relics()
	_initialize_nodes()
	_ensure_squads()
	reveal(generated.start)
	note("村民送来了疗伤药、澄露和干粮。你想找到结束战争的办法。")

func _actor(id: String, definition: Dictionary, position: String, joined: bool) -> Dictionary:
	var result = definition.duplicate(true)
	result.merge({"id": id, "position": position, "joined": joined, "hp_max": definition.hp, "mp_max": definition.mp, "ap_max": definition.ap, "energy": 0, "inventory": {"salve": 3 if id == "hero" else 1, "ether": 2 if id == "hero" else 1}, "equipment": {"weapon": "", "armor": "", "accessory": ""}, "ap_initialized_day": 1 if joined else -1, "shield": 0, "slow": 0, "guard": false}, true)
	return result

func actor(id: String) -> Dictionary:
	return data.actors.get(id, {})

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

# Squad identity is persistent: co-location alone must not undo an explicit split.
func _new_squad() -> String:
	var index = int(data.next_squad_id)
	data.next_squad_id = index + 1
	var id = "squad_%d" % index
	data.squad_colors[id] = index
	return id

func _ensure_squads() -> void:
	if data.is_empty():
		return
	if not data.has("squad_colors"):
		data.squad_colors = {}
	if not data.has("next_squad_id"):
		data.next_squad_id = 0
	var cells: Dictionary = {}
	var by_cell: Dictionary = {}
	# Existing identities win over newly recruited or legacy actors.
	for id in joined_ids():
		var a = actor(id)
		var squad = str(a.get("squad_id", ""))
		if squad == "" or not data.squad_colors.has(squad):
			continue
		if cells.has(squad) and cells[squad] != a.position:
			# Retreat/story relocation may move only part of a squad.
			var relocated = squad + "@" + a.position
			if not cells.has(relocated):
				cells[relocated] = _new_squad()
			a.squad_id = cells[relocated]
			squad = a.squad_id
		cells[squad] = a.position
		if not by_cell.has(a.position):
			by_cell[a.position] = squad
	for id in joined_ids():
		var a = actor(id)
		if str(a.get("squad_id", "")) != "" and data.squad_colors.has(a.squad_id):
			continue
		if not by_cell.has(a.position):
			by_cell[a.position] = _new_squad()
		a.squad_id = by_cell[a.position]

func squad_groups() -> Array:
	_ensure_squads()
	var groups: Dictionary = {}
	for id in joined_ids():
		var a = actor(id)
		if not groups.has(a.squad_id):
			groups[a.squad_id] = {"id": a.squad_id, "members": [], "color_index": int(data.squad_colors[a.squad_id]), "cell": a.position}
		groups[a.squad_id].members.append(id)
	var result = groups.values()
	result.sort_custom(func(a, b): return a.color_index < b.color_index)
	return result

func squad_members(actor_id: String) -> Array:
	for group in squad_groups():
		if actor_id in group.members:
			return group.members.duplicate()
	return []

func split_squad(ids: Array) -> Dictionary:
	if data.is_empty() or data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("战斗或结算期间不能拆分小队。")
	if ids.is_empty():
		return fail("请勾选要组成新小队的角色。")
	var members = squad_members(str(ids[0]))
	var seen: Dictionary = {}
	for id in ids:
		if id not in members or seen.has(id):
			return fail("只能拆分同一小队的不同成员。")
		seen[id] = true
	if ids.size() >= members.size():
		return fail("原小队至少需要留下一位成员。")
	var squad = _new_squad()
	for id in ids:
		actor(id).squad_id = squad
	note("已将勾选成员拆分为独立小队；同格时仍保持分队。")
	changed.emit()
	return {"ok": true, "squad_id": squad}

func _prepare_squad_move(ids: Array, destination: String) -> void:
	var groups = squad_groups()
	var target = ""
	# Arrival joins all occupants, including previously split squads at the target.
	for group in groups:
		if group.cell == destination:
			target = group.id
			break
	if target == "":
		for group in groups:
			if group.members.size() == ids.size() and group.members.all(func(id): return id in ids):
				target = group.id
				break
		if target == "":
			target = _new_squad()
	for id in joined_ids():
		if id in ids or actor(id).position == destination:
			actor(id).squad_id = target

func retreat_squad(ids: Array, destination: String) -> void:
	if ids.is_empty():
		return
	# Detach movers before relocation so stationary residents retain their color.
	# Returning to an occupied origin follows the normal arrival merge rule.
	_prepare_squad_move(ids, destination)
	for id in ids:
		actor(id).position = destination

func stat(id: String, field: String) -> int:
	var a = actor(id)
	var value = int(a.get(field, 0))
	for slot in a.equipment:
		var item = Catalog.ITEMS.get(a.equipment[slot], {})
		value += int(item.get(field, 0))
	if field == "attack" and a.joined and has_relic("ranged_sight") and a.skill in ["trail_shot", "snare", "ember", "torrent", "heal", "gravity", "frost_arrow", "thunderbolt", "windblade"]:
		value = roundi(value * 1.15)
	return value

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
	data.merge({"relics": {}, "relic_checks": {}, "relic_intros": []})
	relic_sites = Relics.exploration_sites(data.tiles, int(data.seed))

func _initialize_nodes() -> void:
	data.merge({"lamp_coins": Nodes.STARTING_COINS})
	if not data.has("nodes"):
		data.nodes = Nodes.generate(data.tiles, int(data.seed), relic_sites, data.rewards, data.relic_checks)

func node_at(cell: String) -> Dictionary:
	return data.nodes.get(cell, {})

func _node_access(id: String, cost: int) -> Dictionary:
	var check = _map_action(id, cost)
	if not check.ok:
		return check
	var tile = data.tiles[actor(id).position]
	if not tile.enemies.is_empty():
		return fail("需要先处理这个地块的危险。")
	return success()

func trade(id: String, item: String, buying: bool) -> Dictionary:
	var check = _node_access(id, 0)
	if not check.ok:
		return check
	var trader = actor(id)
	var node = node_at(trader.position)
	if node.get("kind") != "trade":
		return fail("这里的商摊无法交易。")
	if not Nodes.PRICES.has(item):
		return fail("商摊只收普通补给和装备。")
	var price: int = Nodes.PRICES[item]
	var owned = int(trader.inventory.get(item, 0))
	if buying:
		if int(node.stock.get(item, 0)) <= 0:
			return fail("这件货已经售完。")
		if data.lamp_coins < price:
			return fail("灯铢不足。")
		node.stock[item] -= 1
		trader.inventory[item] = owned + 1
		data.lamp_coins -= price
	else:
		if owned <= int(item in trader.equipment.values()):
			return fail("没有可出售的物品。")
		price = floori(price / 2.0)
		trader.inventory[item] = owned - 1
		data.lamp_coins += price
	var message = "%s%s「%s」，%s %d 灯铢。" % [
		trader.name, "买下" if buying else "卖出", Catalog.item_name(item), "花费" if buying else "获得", price]
	note(message)
	changed.emit()
	return {"ok": true, "message": message}

func recovery_percent(cell: String, resource: String) -> int:
	var percent = Nodes.REST_HP if resource == "hp" else Nodes.REST_MP
	if data.tiles[cell].terrain == "forest" and data.weather == "rain":
		percent -= 5
	if "eve" in same_cell(cell, true):
		percent += 10
	return percent

func use_node(id: String, option: String) -> Dictionary:
	var cost = 1 if option in ["work", "work_alternative", "search"] else 0
	var check = _node_access(id, cost)
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
			return fail("先核实眼前的证据，不能把未经确认的消息告诉亡者。")
	if option in ["work_alternative", "settle_alternative"] and not event.has("alternative"):
		return fail("这里没有这种处理方式。")
	if node.kind == "haunt" and option == "inspect":
		if node.get("investigated", false):
			return fail("此处证据已经核实，可在手记中回看。")
		node["investigated"] = true
		record_story_progress(cell, false)
		note("核实见闻：" + str(event.title))
		changed.emit()
		return {"ok": true, "message": event.investigation}
	var message = ""
	match [node.kind, option]:
		["supply", "collect"]:
			return collect(id)
		["rest", "hp"], ["rest", "mp"]:
			var maximum = option + "_max"
			var percent = recovery_percent(cell, option)
			var recovered: Array[String] = []
			for member in same_cell(cell, true):
				var target = actor(member)
				var gain = mini(int(target[maximum] - target[option]), ceili(target[maximum] * percent / 100.0))
				if gain > 0:
					target[option] += gain
					recovered.append("%s +%d" % [target.name, gain])
			if recovered.is_empty():
				return fail("在场可行动的队员已经全满，可以留待下次。")
			message = "%s恢复 · %s" % ["生命" if option == "hp" else "魔力", "、".join(recovered)]
		["rest", "pack"], ["cache", "search"]:
			var relic = ""
			if option == "search" and relic_sites.has(cell):
				relic = str(investigate_relic(id).get("relic", ""))
			if relic.is_empty():
				var item: String = node.item
				visitor.inventory[item] = int(visitor.inventory.get(item, 0)) + 1
				message = "%s 取得%s ×1。" % [visitor.name, Catalog.item_name(item)]
			else:
				message = "发现遗器「%s」。" % Relics.DATA[relic].name
		["choice", "work"], ["choice", "work_alternative"]:
			data.lamp_coins += int(node.coins)
			message = "%s 完成委托，得到 %d 灯铢。" % [visitor.name, node.coins]
		["clue", "record"], ["haunt", "settle"], ["haunt", "settle_alternative"]:
			message = "已将核实的见闻写进旅途手记。" if option == "record" else "亡者的告别与留下的安排已记入手记。"
			record_story_progress(cell, node.kind == "haunt")
		_:
			return fail("当前节点没有这个选项。")
	visitor.ap -= cost
	node.result = option
	if option in ["work", "work_alternative"]:
		record_story_progress(cell, true)
	note(message)
	changed.emit()
	return {"ok": true, "message": message}

func has_relic(id: String) -> bool:
	return data.relics.has(id)

func relic_intro() -> Dictionary:
	return data.relic_intros[0] if not data.relic_intros.is_empty() else {}

func investigate_relic(id: String) -> Dictionary:
	var check = _map_action(id, 0)
	if not check.ok:
		return check
	var position: String = actor(id).position
	var source = "site:" + position
	if not relic_sites.has(position) or data.relic_checks.has(source) or not data.tiles[position].enemies.is_empty():
		return fail("这里没有尚待调查的遗器线索。")
	var relic = roll_relic(source, [relic_sites[position]], 0.25, id, position)
	return {"ok": true, "relic": relic, "message": "你查看了旧物，能辨认的痕迹已经记录在路册里。"}

func roll_relic(source: String, candidates: Array, chance: float, finder: String, position: String) -> String:
	if data.relic_checks.has(source):
		return ""
	var available = candidates.filter(func(id): return not has_relic(id))
	var roller = RandomNumberGenerator.new()
	roller.seed = hash("relic:%d:%s" % [int(data.seed), source])
	var id = ""
	if not available.is_empty() and roller.randf() < chance:
		id = available[roller.randi_range(0, available.size() - 1)]
		grant_relic(id, finder, position)
	data.relic_checks[source] = id
	return id

func grant_relic(id: String, finder: String, position: String, npc: String = "", lead: String = "") -> bool:
	if not Relics.DATA.has(id) or has_relic(id):
		return false
	data.relics[id] = true
	var new_sight: Array = []
	if id == "telescope":
		var previous = data.explored.duplicate()
		for member in joined_ids():
			if actor(member).hp > 0:
				_reveal_sight(actor(member).position)
		new_sight = data.explored.keys().filter(func(cell): return not previous.has(cell))
	elif id == "life_seed":
		for member in joined_ids():
			var a = actor(member)
			a.hp_max = roundi(a.hp_max * 1.20)
	elif id == "road_hourglass" or id == "stillwater_stone":
		for member in joined_ids():
			var a = actor(member)
			if a.hp <= 0:
				continue
			if id == "road_hourglass":
				a.ap = mini(a.ap_max, a.ap + 2)
			else:
				a.mp = mini(a.mp_max, a.mp + roundi(a.mp_max * 0.40))
	elif id == "rain_bell":
		data.weather = "rain"
	data.relic_intros.append({"id": id, "finder": finder, "position": position, "npc": npc, "lead": lead, "stage": 0, "new_sight": new_sight})
	note("远征队获得遗器「%s」。" % Relics.DATA[id].name)
	return true

func has_visited(position: String) -> bool:
	return data.visited.has(position)

func knows_encounter(position: String) -> bool:
	var tile = data.tiles[position]
	return (has_visited(position) or (position == data.boss and boss_known())) and tile.discovered_enemy and not tile.enemies.is_empty()

func move_cost(id: String, destination: String) -> int:
	var cost = int(Catalog.TERRAIN[data.tiles[destination].terrain].cost)
	if id == "lorne" and data.tiles[destination].terrain == "mountain":
		cost = 1
	if cost > 0 and has_relic("trail_boots"):
		cost = maxi(1, cost - 1)
	return cost

func movement_preview(ids: Array, destination: String) -> Dictionary:
	if data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("战斗或结算期间不能移动。")
	if ids.is_empty() or not data.tiles.has(destination):
		return fail("请选择角色和有效地块。")
	if not Hex.is_land(data.tiles, destination):
		return fail("湖面无法通行，请沿湖岸绕行。")
	var source = actor(str(ids[0])).get("position", "")
	if not data.tiles.has(source):
		return fail("角色位置无效。")
	if not data.tiles[source].enemies.is_empty() and source != data.boss:
		return fail("敌人阻挡此处；需交战，或在战斗中撤退。")
	if destination not in Hex.neighbors(source, data.tiles):
		return fail("每次移动一格；可点击远处地块查看路径。")
	var known_encounter = knows_encounter(destination)
	if destination == data.boss and known_encounter:
		var hero = actor("hero")
		var can_enter = ("hero" in ids and hero.ap >= move_cost("hero", destination) + Catalog.BATTLE_AP) or (hero.position == destination and hero.ap >= Catalog.BATTLE_AP)
		if hero.hp <= 0 or not can_enter:
			return fail("需要旅人亲自前往，并留出 2 点精力迎战。")
	var costs = {}
	for id in ids:
		if costs.has(id):
			return fail("同行名单不能重复。")
		var a = actor(id)
		if a.is_empty() or not a.joined or a.hp <= 0 or a.position != source:
			return fail("只能让同格、可行动的己方角色一起移动。")
		costs[id] = move_cost(id, destination)
		if int(a.ap) < int(costs[id]):
			return fail("%s 精力不足（需要 %d）。" % [a.name, costs[id]])
	if known_encounter:
		var available = 0
		for id in ids:
			if int(actor(id).ap) - int(costs[id]) >= Catalog.BATTLE_AP:
				available += 1
		for id in same_cell(destination, true):
			if actor(id).ap >= Catalog.BATTLE_AP:
				available += 1
		if available == 0:
			return fail("进入已知遭遇需要至少一名角色能支付移动和参战费。")
	return {"ok": true, "costs": costs, "encounter": known_encounter, "source": source}

func move(ids: Array, destination: String) -> Dictionary:
	var preview = movement_preview(ids, destination)
	if not preview.ok:
		return preview
	_prepare_squad_move(ids, destination)
	for id in ids:
		actor(id).ap -= preview.costs[id]
		actor(id).position = destination
	reveal(destination)
	var t = data.tiles[destination]
	var encounter = not t.enemies.is_empty()
	if encounter:
		var surprise = not preview.encounter
		var ambush = t.hidden and surprise
		t.discovered_enemy = true
		data.pending_battle = {"position": destination, "ambush": ambush, "surprise": surprise, "origin": preview.source, "movers": ids.duplicate(), "npc": ""}
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
		return fail("对方重伤，需要同地实际救援后再交谈。")
	var local_crew = same_cell(a.position, true)
	if local_crew.is_empty() or (not recruiter_id.is_empty() and recruiter_id not in local_crew):
		return fail("需要同格交谈。")
	if a.joined:
		return fail("已经同行。")
	a.joined = true
	_ensure_squads()
	if not recruiter_id.is_empty():
		a.squad_id = actor(recruiter_id).squad_id
	if has_relic("life_seed"):
		a.hp_max = roundi(a.hp_max * 1.20)
	if has_relic("telescope"):
		_reveal_sight(a.position)
	if a.ap_initialized_day != data.day:
		a.ap = a.ap_max
		a.ap_initialized_day = data.day
	data.story[id].relation = "joined"
	data.story[id].met = true
	note("%s 加入远征队。" % a.name)
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
		return fail("需要同地可行动的角色协助整理物品。")
	if amount <= 0 or int(source.inventory.get(item, 0)) < amount:
		return fail("持有数量不足。")
	if item in source.equipment.values():
		return fail("请先卸下装备。")
	source.inventory[item] -= amount
	target.inventory[item] = int(target.inventory.get(item, 0)) + amount
	note("%s 将 %s ×%d 交给 %s。" % [source.name, Catalog.item_name(item), amount, target.name])
	changed.emit()
	return success()

func use_item(user_id: String, target_id: String, item: String, during_battle: bool = false) -> Dictionary:
	var user = actor(user_id)
	var target = actor(target_id)
	if user.is_empty() or target.is_empty() or not user.joined or user.hp <= 0 or user.position != target.position:
		return fail("使用者须可行动，并和目标在同一地块。")
	if not target.joined and not data.story.get(target_id, {}).get("met", false):
		return fail("尚未接触这位角色。")
	if data.status != "exploring" and not during_battle:
		return fail("请在战斗正常行动窗口使用。")
	var definition = Catalog.ITEMS.get(item, {})
	if int(user.inventory.get(item, 0)) <= 0 or not (definition.has("hp") or definition.has("mp")):
		return fail("没有可用的恢复道具。")
	if definition.has("mp") and target.hp <= 0:
		return fail("恢复魔力不能解除重伤。")
	var healing = int(definition.get("hp", 0))
	if has_relic("herbal_case"):
		healing = roundi(healing * 1.25)
	var hp_gain = mini(healing, int(target.hp_max) - int(target.hp))
	var mp_gain = mini(int(definition.get("mp", 0)), int(target.mp_max) - int(target.mp))
	if hp_gain <= 0 and mp_gain <= 0:
		return fail("没有可恢复的资源，不消耗物品。")
	target.hp += hp_gain
	target.mp += mp_gain
	user.inventory[item] -= 1
	note("%s 对 %s 使用%s：HP +%d，MP +%d。" % [user.name, target.name, definition.name, hp_gain, mp_gain])
	changed.emit()
	return success()

func equip(id: String, item: String) -> Dictionary:
	if data.status != "exploring":
		return fail("只能在战斗外换装。")
	var a = actor(id)
	var definition = Catalog.ITEMS.get(item, {})
	if a.is_empty() or not a.joined or a.hp <= 0 or not definition.has("slot") or int(a.inventory.get(item, 0)) <= 0:
		return fail("没有可装备的物品或角色无法行动。")
	a.equipment[definition.slot] = "" if a.equipment[definition.slot] == item else item
	changed.emit()
	return success()

func collect(id: String) -> Dictionary:
	var check = _map_action(id, 1)
	if not check.ok:
		return check
	var a = actor(id)
	var t = data.tiles[a.position]
	if not t.enemies.is_empty() or t.quantity <= 0:
		return fail("这里没有安全可采集的道具。")
	a.ap -= 1
	var amount = int(t.quantity) + (1 if id == "cen" and t.terrain == "forest" else 0)
	a.inventory[t.resource] = int(a.inventory.get(t.resource, 0)) + amount
	t.quantity = 0
	var message = "%s 收集了%s ×%d。" % [a.name, Catalog.item_name(t.resource), amount]
	note(message)
	changed.emit()
	return {"ok": true, "message": message}

func heal_skill(user_id: String, target_id: String) -> Dictionary:
	var check = _map_action(user_id, 1)
	if not check.ok:
		return check
	var a = actor(user_id)
	var target = actor(target_id)
	if a.skill != "heal" or a.mp < 12 or target.is_empty() or a.position != target.position:
		return fail("需要同地医者及 12 MP。")
	if target.hp >= target.hp_max:
		return fail("生命已满。")
	a.ap -= 1
	a.mp -= 12
	target.hp = mini(int(target.hp_max), int(target.hp) + 38)
	note("伊芙为 %s 治疗。" % target.name)
	changed.emit()
	return success()

func end_day() -> Dictionary:
	if data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("先结束当前遭遇。")
	var new_day = int(data.day) + 1
	data.weather = "rain" if rng.randf() < rain_chance() else "sun"
	data.day = new_day
	for id in joined_ids():
		var a = actor(id)
		a.ap = a.ap_max
		a.ap_initialized_day = new_day
	data.last_day_settled = new_day - 1
	check_global_failure()
	note("第 %d 天，%s。精力回到各自上限。" % [data.day, "雨" if data.weather == "rain" else "晴"])
	changed.emit()
	return success()

func next_weather() -> String:
	var forecast = RandomNumberGenerator.new()
	forecast.state = rng.state
	return "rain" if forecast.randf() < rain_chance() else "sun"

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

func _map_action(id: String, cost: int) -> Dictionary:
	var a = actor(id)
	if data.is_empty() or data.status != "exploring" or not data.pending_battle.is_empty():
		return fail("当前不能执行探索行动。")
	if a.is_empty() or not a.joined or a.hp <= 0:
		return fail("该角色无法行动。")
	if a.ap < cost:
		return fail("需要 %d 精力。" % cost)
	return success()

func save_game(path: String = "") -> Dictionary:
	if path.is_empty():
		path = save_path
	if data.is_empty() or data.status == "battle":
		return fail("只写入稳定检查点。")
	_ensure_squads()
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
		return fail("存档替换失败，旧存档已保留。")
	return success()

func load_game(path: String = "") -> Dictionary:
	if path.is_empty():
		path = save_path
	if not FileAccess.file_exists(path):
		return fail("还没有远征存档。")
	var json = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return fail("存档损坏；旧文件没有被覆盖。")
	var loaded: Dictionary = json.data
	if not _whole_number(loaded.get("version", -1)) or int(loaded.version) != SAVE_VERSION or not loaded.has_all(["actors", "tiles", "rng_state", "day", "explored", "status"]):
		return fail("存档版本不兼容或缺少字段。")
	var invalid = _validate_save(loaded)
	if invalid != "":
		return fail("存档内容无效：" + invalid + "。旧文件没有被覆盖。")
	data = loaded
	_remove_legacy_map_effects()
	_ensure_squads()
	if not data.has("visited"):
		_restore_legacy_visits()
	if not data.has("choices"):
		data.choices = []
	_initialize_relics()
	_initialize_nodes()
	rng.state = int(data.rng_state)
	changed.emit()
	return success()

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
		return "缺少进度字段"
	for key in ["actors", "tiles", "flags", "story", "knowledge", "rewards", "pending_battle", "explored", "leads", "peace"]:
		if not loaded[key] is Dictionary:
			return "字段类型不符"
	if loaded.tiles.size() != 217 or not loaded.tiles.has(loaded.start) or not loaded.tiles.has(loaded.boss):
		return "地图不完整"
	if loaded.status not in ["exploring", "won", "failed"] or loaded.weather not in ["sun", "rain"] or not Catalog.PROFESSIONS.has(loaded.profession):
		return "状态或职业无效"
	if not _whole_number(loaded.chapter) or loaded.chapter < 0 or loaded.chapter > 4:
		return "剧情进度无效"
	if not loaded.log is Array or not _whole_number(loaded.day) or int(loaded.day) < 1 or not str(loaded.rng_state).is_valid_int():
		return "日期或随机状态无效"
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
				or (result.relic != "" and not loaded.get("relics", {}).has(result.relic)):
			return "胜利结算无效"
		if result.has("coins") and (not _whole_number(result.coins) or result.coins < 0):
			return "胜利报酬无效"
	for id in loaded.get("relics", {}):
		if not Relics.DATA.has(id) or loaded.relics[id] != true:
			return "未知遗器"
	for entry in loaded.get("relic_intros", []):
		if not entry is Dictionary or not entry.has_all(["id", "finder", "position", "npc", "lead", "stage", "new_sight"]):
			return "遗器剧情无效"
		if not loaded.get("relics", {}).has(entry.id) or not loaded.actors.has(entry.finder) or not loaded.tiles.has(entry.position) \
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
	var coordinate = RegEx.new()
	coordinate.compile("^-?[0-9]+,-?[0-9]+$")
	for k in loaded.tiles:
		if coordinate.search(str(k)) == null or Hex.distance(Hex.coord(k), Vector2i.ZERO) > 8:
			return "六边形坐标无效"
		var tile = loaded.tiles[k]
		if not tile is Dictionary or not tile.has_all(["terrain", "base_terrain", "enemies", "site", "npc", "resource", "quantity", "height", "hidden", "discovered_enemy"]):
			return "地块字段不完整"
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
	for id in ["hero"] + Catalog.COMPANIONS.keys():
		if not loaded.actors.has(id) or not loaded.actors[id] is Dictionary:
			return "角色缺失"
		var a = loaded.actors[id]
		if not a.has_all(["id", "name", "color", "element", "attack", "defense", "speed", "ap_initialized_day", "shield", "slow", "guard", "position", "joined", "hp", "hp_max", "mp", "mp_max", "ap", "ap_max", "energy", "equipment", "inventory", "skill", "ultimate"]):
			return "角色字段不完整"
		if a.id != id or not a.name is String or not a.color is String or not a.element is String or not a.joined is bool:
			return "角色标识无效"
		if not Hex.is_land(loaded.tiles, a.position) or not a.inventory is Dictionary or not a.equipment is Dictionary:
			return "角色位置或背包无效"
		if not Catalog.SKILLS.has(a.skill) or not Catalog.SKILLS.has(a.ultimate):
			return "角色技能无效"
		for resource in ["hp", "mp", "ap"]:
			if not _whole_number(a[resource]) or not _whole_number(a[resource + "_max"]) or a[resource + "_max"] <= 0 or a[resource] < 0 or a[resource] > a[resource + "_max"]:
				return "角色资源越界"
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
			if item != "" and (not Catalog.ITEMS.has(item) or Catalog.ITEMS[item].get("slot", "") != slot or a.inventory.get(item, 0) < 1):
				return "装备持有状态无效"
		if id != "hero":
			if not loaded.story.has(id) or not loaded.story[id] is Dictionary or not loaded.story[id].has_all(["met", "relation", "result"]):
				return "故事状态缺失"
			if loaded.story[id].has("personal_choice") and loaded.story[id].personal_choice not in ["personal_a", "personal_b"]:
				return "个人抉择记录无效"
	if loaded.has("squad_colors") or loaded.has("next_squad_id"):
		if not loaded.get("squad_colors") is Dictionary or not _whole_number(loaded.get("next_squad_id")) or loaded.next_squad_id < 0:
			return "小队记录无效"
		var used_colors: Dictionary = {}
		for squad in loaded.squad_colors:
			var color = loaded.squad_colors[squad]
			if not squad is String or not _whole_number(color) or color < 0 or color >= loaded.next_squad_id or used_colors.has(int(color)):
				return "小队颜色记录无效"
			used_colors[int(color)] = true
		for id in loaded.actors:
			var a = loaded.actors[id]
			if a.joined and (not a.get("squad_id") is String or not loaded.squad_colors.has(a.squad_id)):
				return "小队成员记录无效"
	if not loaded.pending_battle.is_empty():
		var pending = loaded.pending_battle
		if not pending.has_all(["position", "origin", "ambush", "movers", "npc"]) or not loaded.tiles.has(pending.position) or not loaded.tiles.has(pending.origin) or not pending.movers is Array:
			return "遭遇检查点无效"
		if pending.has("surprise") and not pending.surprise is bool:
			return "遭遇检查点无效"
		for id in pending.movers:
			if not loaded.actors.has(id):
				return "遭遇角色无效"
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
				if not Nodes.PRICES.has(item) or not _whole_number(node.stock[item]) or node.stock[item] < 0:
					return false
		if node.kind in ["rest", "cache"] and not Nodes.PRICES.has(node.get("item")):
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
