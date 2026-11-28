extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")

const STOPS = 7
# Encounter keys are stable so existing routes keep their order when loaded.
const FINAL = "war_camp"
const STAKES = ["低赌注", "中赌注", "高赌注"]
const SCALES = [0.6, 1.0, 1.6]
const POOLS = [
	{"rest": 35, "event": 30, "chest": 20, "shop": 15},
	{"battle": 35, "chest": 25, "shop": 20, "event": 20},
	{"elite": 40, "battle": 30, "chest": 30},
]
const LABELS = {"battle": "战斗", "elite": "精英战斗", "chest": "宝箱", "shop": "商店",
	"rest": "休整", "event": "事件", "boss": "终点 · 捕鲸机"}
const BATTLES = ["battle", "elite", "boss"]

const CHAPTERS = [
	["valley", "kiln", "ford", "woods"],
	["ridge", "belltower", "quarry", "reedbed"],
	["camp", "aqueduct", "breach", "burial_road"],
]
const ENCOUNTERS = {
	"valley": ["翻倒的桌子", "tavern", "桌脚泡在水里。门外漂着几块木板。", ["沿吧台走", "踩着桌子过去", "跳上漂走的木板"]],
	"kiln": ["酒窖漏水", "tavern", "水从酒窖门缝里往外冒。", ["沿楼梯上去", "拉开酒窖门", "钻进送酒的滑道"]],
	"ford": ["漂走的酒桶", "belly", "几只空桶碰在一起，最大的那只正漂走。", ["踩稳木板", "拉住酒桶", "跳上最大的桶"]],
	"woods": ["柜子在响", "tavern", "一只泡湿的柜子里传来敲门声。", ["绕过柜子", "把柜门打开", "撬开底板"]],
	"ridge": ["斜着的甲板", "belly", "一艘断成两截的船斜靠在旁边。", ["沿船舷绕行", "翻上甲板", "滑进破船舱"]],
	"belltower": ["旧船铃", "belly", "水一晃，船铃就响一声。", ["从铃下走过", "拉一下铃绳", "顺着桅杆往上爬"]],
	"quarry": ["泡烂的货箱", "belly", "一排箱子挡住了路，里面有东西在动。", ["绕过箱子", "撬开一只箱子", "踩着箱盖往前跳"]],
	"reedbed": ["打结的渔网", "belly", "渔网挂在断桅上，网里的东西还在扑腾。", ["绕过渔网", "割开一个口", "从网底钻过去"]],
	"camp": ["浮板上的锅", "belly", "有人在浮板上煮汤，锅盖跟着水声打拍子。", ["沿着浮板走", "过去问路", "抢在水涌来前跳过去"]],
	"aqueduct": ["绷紧的缆绳", "belly", "一根缆绳通向亮处，另一头看不清。", ["贴着残船走", "沿缆绳往前拉", "松开绳结跟着水走"]],
	"breach": ["漏光的缝", "winch", "前面漏进一道光，水流一下比一下急。", ["等水流变慢", "抓着断桨过去", "顺水冲进亮处"]],
	"burial_road": ["拖着走的铁链", "winch", "铁链擦过船板，前面传来绞盘声。", ["避开铁链", "踩着链环过去", "抓住铁链顺势滑行"]],
	FINAL: ["卡住的捕鲸机", "winch", "老捕鲸机卡在鲸嘴边，绞盘还在转。", ["打断绞盘"]],
}

static func begin(run: RefCounted) -> void:
	var seed_key := str(int(run.data.seed))
	var roller := _roller(seed_key, "route")
	var route := []
	for chapter in CHAPTERS:
		var candidates: Array = chapter.duplicate()
		for i in 2:
			route.append(candidates.pop_at(roller.randi_range(0, candidates.size() - 1)))
	route.append(FINAL)
	run.data.journey = {"seed": seed_key, "route": route, "step": 0, "history": []}
	run.data.pending_battle = {}
	run.data.erase("pending_arrival")
	run.close_battle_shop()
	run.data.erase("pending_victory")
	if run.data.status == "exploring":
		run.retreat_party(run.data.start)
		if run.actor("hero").hp <= 0 and not run.check_global_failure():
			run.actor("hero").hp = 1

static func encounter(data: Dictionary) -> Dictionary:
	var journey: Dictionary = data.journey
	var id: String = journey.route[int(journey.step)]
	var story: Array = ENCOUNTERS[id]
	var choices := []
	for i in story[3].size():
		choices.append({"label": story[3][i], "stakes": 2 if id == FINAL else i})
	return {"title": story[0], "scene": story[1], "text": story[2], "choices": choices}

static func current(data: Dictionary) -> Dictionary:
	var journey: Dictionary = data.get("journey", {})
	var history: Array = journey.get("history", [])
	var step: int = int(journey.get("step", -1))
	return history[step] if step >= 0 and step < history.size() else {}

static func choose(run: RefCounted, step: int, index: int) -> Dictionary:
	var data: Dictionary = run.data
	if data.status != "exploring" or step != int(data.journey.step) or not current(data).is_empty() 			or data.has("pending_story_rewards"):
		return run.fail("这一段旅途已经选定。")
	var choices: Array = encounter(data).choices
	if index < 0 or index >= choices.size():
		return run.fail("这个选项不可用。")
	var previous := data.duplicate(true)
	var choice: Dictionary = choices[index]
	var stakes: int = choice.stakes
	var roller := _roller(data.journey.seed, "result:%d:%d" % [step, index])
	var kind := "boss" if step == STOPS - 1 else _draw(stakes, roller)
	var entry := {"choice": index, "kind": kind, "settled": false, "text": "",
		"hp_before": int(run.actor("hero").hp), "coins_before": int(data.lamp_coins)}
	data.journey.history.append(entry)
	var cell: String = run.actor("hero").position
	match kind:
		"battle", "elite", "boss":
			data.pending_battle = {"position": cell, "origin": cell, "ambush": false, "npc": "", "journey_step": step}
		"shop":
			run.open_battle_shop()
		_:
			_resolve(run, kind, roller, stakes)
	return _checkpoint(run, previous)

static func advance(run: RefCounted, step: int) -> Dictionary:
	var data: Dictionary = run.data
	if data.status != "exploring" or step != int(data.journey.step) or step >= STOPS - 1 			or not current(data).get("settled", false) or data.has("pending_victory") or data.has("pending_story_rewards"):
		return run.fail("请先结算这一段旅途。")
	var previous := data.duplicate(true)
	data.journey.step = step + 1
	return _checkpoint(run, previous)

static func abandon(run: RefCounted) -> Dictionary:
	var data: Dictionary = run.data
	var previous := data.duplicate(true)
	run.close_battle_shop()
	data.pending_battle = {}
	data.erase("pending_story_rewards")
	data.status = "failed"
	data.flags.failure_reason = "你主动结束了本次远征。"
	var entry := current(data)
	if not entry.is_empty() and not entry.settled:
		settle(run, data.flags.failure_reason)
	return _checkpoint(run, previous)

static func close_shop(run: RefCounted) -> Dictionary:
	if not shop_active(run.data) or run.data.has("pending_story_rewards"):
		return run.fail("请先完成当前交易。")
	var previous: Dictionary = run.data.duplicate(true)
	run.close_battle_shop()
	settle(run, "商贩收起货箱。")
	return _checkpoint(run, previous)

static func shop_active(data: Dictionary) -> bool:
	var entry := current(data)
	return data.status == "exploring" and entry.get("kind") == "shop" and not entry.get("settled", false)

static func shop_key(data: Dictionary, cell: String) -> String:
	return "journey:%d" % int(data.journey.step) if data.has("journey") else cell

static func battle_enemies(data: Dictionary, pending: Dictionary) -> Array:
	if not pending.has("journey_step"):
		return data.tiles[pending.position].enemies
	var kind: String = current(data).get("kind", "")
	if kind not in BATTLES:
		return []
	if kind == "boss":
		return ["war_god"]
	var groups := [["hunter_elite", "spider", "archer"], ["furnace_elite", "furnace", "apothecary"]] 		if kind == "elite" else [["boar", "swarm", "archer"], ["archer", "canal", "apothecary"], ["furnace", "spider", "lurker"]]
	var roller := _roller(data.journey.seed, "enemies:%d" % int(pending.journey_step))
	return groups[roller.randi_range(0, groups.size() - 1)]

static func scale(data: Dictionary, amount: int) -> int:
	return _scaled(amount, encounter(data).choices[int(current(data).choice)].stakes)

static func settle(run: RefCounted, message: String) -> void:
	var data: Dictionary = run.data
	var entry := current(data)
	if data.status == "exploring" and int(data.journey.step) == 2 and not data.relic_seen.has("life_seed"):
		var relic := _grant_relic(run, "journey:milestone:3", "life_seed")
		if not relic.is_empty():
			message += "\n获得遗器「生命之种」。"
	entry.text = message
	entry.hp_change = int(run.actor("hero").hp) - int(entry.hp_before)
	entry.coins_change = int(data.lamp_coins) - int(entry.coins_before)
	entry.settled = true
	run.note(message)

static func valid(data: Dictionary) -> bool:
	var journey: Variant = data.get("journey")
	if not journey is Dictionary or not journey.get("seed") is String or not journey.seed.is_valid_int() 			or not journey.get("route") is Array or journey.route.size() != STOPS or journey.route.back() != FINAL 			or not _integer(journey.get("step"), 0, STOPS - 1) or not journey.get("history") is Array:
		return false
	for i in CHAPTERS.size():
		var first: Variant = journey.route[i * 2]
		var second: Variant = journey.route[i * 2 + 1]
		if first not in CHAPTERS[i] or second not in CHAPTERS[i] or first == second:
			return false
	var step: int = int(journey.step)
	if journey.history.size() not in [step, step + 1]:
		return false
	for i in journey.history.size():
		var entry: Variant = journey.history[i]
		if not entry is Dictionary or not _integer(entry.get("choice"), 0, 0 if i == STOPS - 1 else 2) 				or not LABELS.has(entry.get("kind")) or (entry.kind == "boss") != (i == STOPS - 1) 				or not entry.get("settled") is bool or not entry.get("text") is String 				or not _integer(entry.get("hp_before"), 0, 2147483647) or not _integer(entry.get("coins_before"), 0, 2147483647):
			return false
		if entry.settled and (not _integer(entry.get("hp_change"), -2147483647, 2147483647) 				or not _integer(entry.get("coins_change"), -2147483647, 2147483647)):
			return false
		if i < STOPS - 1 and not POOLS[int(entry.choice)].has(entry.kind):
			return false
		if not entry.settled and (i != step or data.status != "exploring" or entry.kind not in BATTLES + ["shop"]):
			return false
	var active := current(data)
	var awaiting_battle: bool = not active.get("settled", true) and active.get("kind") in BATTLES
	if awaiting_battle != (not data.pending_battle.is_empty()):
		return false
	if awaiting_battle and (data.pending_battle.get("journey_step") != step 			or data.pending_battle.position != data.actors.hero.position or data.pending_battle.npc != ""):
		return false
	if shop_active(data) != data.has("battle_shop"):
		return false
	if data.status == "won" and not journey.history.is_empty() and (step != STOPS - 1 or not active.get("settled", false)):
		return false
	if data.status == "exploring" and active.get("kind") == "boss" and active.get("settled", false):
		return false
	return not data.has("pending_victory") or (active.get("settled", false) and active.get("kind") in BATTLES)

static func _resolve(run: RefCounted, kind: String, roller: RandomNumberGenerator, stakes: int) -> void:
	var data: Dictionary = run.data
	var hero: Dictionary = run.actor("hero")
	var message := ""
	match kind:
		"rest":
			var restoration := _scaled(roundi(hero.hp_max * 0.25), stakes)
			hero.hp = mini(int(hero.hp_max), int(hero.hp) + restoration)
			message = "你扶正两张湿椅子，坐下歇了一会儿。"
		"chest":
			data.lamp_coins += _scaled(roller.randi_range(7, 11), stakes)
			message = "湿货箱里有一袋灯铢。"
			var source := "journey:chest:%d" % int(data.journey.step)
			var relic := _grant_relic(run, source, run.relic_offer(source, Relics.DATA.keys(), 0.25 * SCALES[stakes]))
			if not relic.is_empty():
				message += " 箱底还有「%s」。" % Relics.DATA[relic].name
		"event":
			message = _event(run, roller, stakes)
	settle(run, message)

static func _event(run: RefCounted, roller: RandomNumberGenerator, stakes: int) -> String:
	var data: Dictionary = run.data
	var hero: Dictionary = run.actor("hero")
	match roller.randi_range(0, 3):
		0:
			var allies := Catalog.COMPANIONS.keys().filter(func(id): return not run.actor(id).joined and run.actor(id).hp > 0)
			allies.sort()
			if not allies.is_empty():
				var id: String = allies[roller.randi_range(0, allies.size() - 1)]
				var companion: Dictionary = run.actor(id)
				companion.position = hero.position
				var result: Dictionary = run.join_companion(id, "hero")
				run.add_companion_card(id)
				data.item_revision += 1
				var message := "你拉起落水的%s。对方决定一起找出口。" % companion.name
				if not result.relic.is_empty():
					_dismiss_intro(data, result.relic)
					message += " 你还获得了遗器「%s」。" % Relics.DATA[result.relic].name
				return message
		1:
			hero.hp = maxi(0, int(hero.hp) - _scaled(roundi(hero.hp_max * 0.16), stakes))
			if hero.hp == 0:
				data.status = "failed"
				data.flags.failure_reason = "你落了水，没能爬回木筏。"
				return data.flags.failure_reason
			return "浮板翻了，你撞伤了胳膊。"
		2:
			data.lamp_coins = maxi(0, int(data.lamp_coins) - _scaled(5, stakes))
			return "钱袋落水，几枚灯铢沉了下去。"
	data.lamp_coins += _scaled(5, stakes)
	return "你捞起一桶酒，桶主给了你几枚灯铢。"

static func _grant_relic(run: RefCounted, source: String, offer: String) -> String:
	var relic: String = run.claim_relic_reward(source, offer, "hero", run.actor("hero").position)
	_dismiss_intro(run.data, relic)
	return relic

static func _dismiss_intro(data: Dictionary, id: String) -> void:
	data.relic_intros = data.relic_intros.filter(func(entry): return entry.id != id)

static func _draw(stakes: int, roller: RandomNumberGenerator) -> String:
	var pool: Dictionary = POOLS[stakes]
	var roll := roller.randi_range(1, 100)
	for kind in pool:
		roll -= int(pool[kind])
		if roll <= 0:
			return kind
	assert(false, "Journey stake weights must sum to 100.")
	return "event"

static func _scaled(base: int, stakes: int) -> int:
	return roundi(base * SCALES[stakes])

static func _roller(seed_key: String, source: String) -> RandomNumberGenerator:
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("journey:%s:%s" % [seed_key, source])
	return roller

static func _checkpoint(run: RefCounted, previous: Dictionary) -> Dictionary:
	var saved: Dictionary = run.save_game()
	if not saved.ok:
		run.data = previous
	else:
		run.changed.emit()
	return saved

static func _integer(value: Variant, lowest: int, highest: int) -> bool:
	return (value is int or value is float) and value >= lowest and value <= highest and value == floor(value)
