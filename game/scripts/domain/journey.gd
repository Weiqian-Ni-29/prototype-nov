extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")

const CAMP = "camp"
const STOPS = 7
const FINAL = "war_camp"
const STAKES = ["低赌注", "中赌注", "高赌注"]
const SCALES = [0.6, 1.0, 1.6]
const POOLS = [
	{"rest": 35, "event": 30, "chest": 20, "shop": 15},
	{"battle": 35, "chest": 25, "shop": 20, "event": 20},
	{"elite": 40, "battle": 30, "chest": 30},
]
const LABELS = {"battle": "战斗", "elite": "精英战斗", "chest": "宝箱", "shop": "商店",
	"rest": "休整", "event": "事件", "boss": "终点 · 卡德兰"}
const BATTLES = ["battle", "elite", "boss"]

const CHAPTERS = [
	["valley", "kiln", "ford", "woods"],
	["ridge", "belltower", "quarry", "reedbed"],
	["camp", "aqueduct", "breach", "burial_road"],
]
const ENCOUNTERS = {
	"valley": ["风过谷口", "highland", "谷口的枯松倒了，雾还没散。", ["绕开枯松", "跨过树干", "下到谷底"]],
	"kiln": ["废窑余温", "ruins", "废窑的门歪了，摸上去还暖。", ["沿窑墙走", "穿过窑院", "爬上窑坡"]],
	"ford": ["无名渡口", "wetlands", "河面那根麻绳快被水淹没了。", ["沿岸绕行", "拉绳涉水", "跳石过河"]],
	"woods": ["林里的回声", "woodland", "树林深处传来三声敲击。", ["走林边", "循声进林", "拨开藤条"]],
	"ridge": ["鹿脊山道", "highland", "窄山道外，谷底响起一声闷响。", ["贴着山壁走", "翻过矮脊", "滑下碎石坡"]],
	"belltower": ["半截钟楼", "ruins", "半截钟楼横在路中。", ["沿街绕行", "穿过门洞", "翻过断梁"]],
	"quarry": ["断石坡", "drylands", "石粉盖住了坡下的脚印。", ["绕过石坡", "循脚印下坡", "钻过石缝"]],
	"reedbed": ["白苇滩", "wetlands", "水中的木桩只露出半截。", ["绕过苇滩", "踩木桩过水", "沿水道穿苇丛"]],
	"camp": ["荒营的火盆", "drylands", "荒营只剩冷火盆，前方还有鼓声。", ["绕过营墙", "穿过营门", "跑下土坡"]],
	"aqueduct": ["高渠之下", "ruins", "破石渠在头顶漏水，鼓声盖住了水声。", ["沿渠边走", "穿过石拱", "爬上石渠"]],
	"breach": ["缺口里的灯", "road", "外墙缺口里有一盏快熄的灯。", ["沿墙绕行", "提灯进缺口", "踩木板翻墙"]],
	"burial_road": ["埋旗的路", "woodland", "路边插着一排旧旗，林尽头有红光。", ["走林边", "沿车道走", "穿林去看红光"]],
	FINAL: ["战鼓台", "finale", "卡德兰敲响战鼓，伤兵重新举刀。",
		["走上鼓台，迎战卡德兰"]],
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
	if data.status != "exploring" or step != int(data.journey.step) or not current(data).is_empty() \
			or data.has("pending_story_rewards"):
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
			data.pending_battle.enemies = battle_enemies(data, data.pending_battle)
		"shop":
			run.open_battle_shop()
		_:
			_resolve(run, kind, roller, stakes)
	return _checkpoint(run, previous)

static func advance(run: RefCounted, step: int) -> Dictionary:
	var data: Dictionary = run.data
	if data.status != "exploring" or step != int(data.journey.step) or step >= STOPS - 1 \
			or not current(data).get("settled", false) or data.has("pending_victory") or data.has("pending_story_rewards"):
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

static func shop_key(data: Dictionary) -> String:
	return "journey:%d" % int(data.journey.step)

static func battle_enemies(data: Dictionary, pending: Dictionary) -> Array:
	if pending.has("enemies"):
		return pending.enemies
	if not pending.has("journey_step"):
		return []
	var kind: String = current(data).get("kind", "")
	if kind not in BATTLES:
		return []
	if kind == "boss":
		return ["war_god"]
	var groups := [["hunter_elite", "spider", "archer"], ["furnace_elite", "furnace", "apothecary"]] 		if kind == "elite" else [["boar", "swarm", "archer"], ["archer", "canal", "apothecary"], ["furnace", "spider", "lurker"]]
	var roller := _roller(data.journey.seed, "enemies:%d" % int(pending.journey_step))
	return groups[roller.randi_range(0, groups.size() - 1)]

static func is_elite(enemies: Array) -> bool:
	return enemies.any(func(id): return str(id).ends_with("_elite") or id == "lamp_boss")

static func battle_coins(seed_value: int, source: String, elite: bool, finale: bool) -> int:
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("battle-coins:%d:%s" % [seed_value, source])
	if finale:
		return roller.randi_range(16, 20)
	return roller.randi_range(8, 12) if elite else roller.randi_range(4, 7)

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
	if not journey is Dictionary or not journey.get("seed") is String or not journey.seed.is_valid_int() \
			or not journey.get("route") is Array or journey.route.size() != STOPS or journey.route.back() != FINAL \
			or not _integer(journey.get("step"), 0, STOPS - 1) or not journey.get("history") is Array:
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
		if not entry is Dictionary or not _integer(entry.get("choice"), 0, 0 if i == STOPS - 1 else 2) \
				or not LABELS.has(entry.get("kind")) or (entry.kind == "boss") != (i == STOPS - 1) \
				or not entry.get("settled") is bool or not entry.get("text") is String \
				or not _integer(entry.get("hp_before"), 0, 2147483647) or not _integer(entry.get("coins_before"), 0, 2147483647):
			return false
		if entry.settled and (not _integer(entry.get("hp_change"), -2147483647, 2147483647) \
				or not _integer(entry.get("coins_change"), -2147483647, 2147483647)):
			return false
		if i < STOPS - 1 and not POOLS[int(entry.choice)].has(entry.kind):
			return false
		if not entry.settled and (i != step or data.status != "exploring" or entry.kind not in BATTLES + ["shop"]):
			return false
	var active := current(data)
	var awaiting_battle: bool = not active.get("settled", true) and active.get("kind") in BATTLES
	if awaiting_battle != (not data.pending_battle.is_empty()):
		return false
	if awaiting_battle:
		var pending: Dictionary = data.pending_battle
		if pending.get("journey_step") != step or pending.position != CAMP or pending.origin != CAMP \
				or pending.npc != "":
			return false
		var enemies: Variant = pending.get("enemies")
		if not enemies is Array or enemies.is_empty() or not enemies.all(func(id): return Catalog.ENEMIES.has(id)) \
				or ("war_god" in enemies) != (active.kind == "boss") or is_elite(enemies) != (active.kind == "elite"):
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
			message = "队伍在背风处休息。"
		"chest":
			data.lamp_coins += _scaled(roller.randi_range(7, 11), stakes)
			message = "箱里有一袋灯铢。"
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
				data.card_deck = run.card_deck() + [id]
				data.item_revision += 1
				var message := "%s决定与你同行。伙伴牌已加入卡组。" % companion.name
				if not result.relic.is_empty():
					_dismiss_intro(data, result.relic)
					message += " 你还获得了遗器「%s」。" % Relics.DATA[result.relic].name
				return message
		1:
			hero.hp = maxi(0, int(hero.hp) - _scaled(roundi(hero.hp_max * 0.16), stakes))
			if hero.hp == 0:
				data.status = "failed"
				data.flags.failure_reason = "旅人在途中跌伤，再也没能站起来。"
				return data.flags.failure_reason
			return "脚下落石，你摔伤了。"
		2:
			data.lamp_coins = maxi(0, int(data.lamp_coins) - _scaled(5, stakes))
			return "钱袋破了，漏掉几枚灯铢。"
	data.lamp_coins += _scaled(5, stakes)
	return "你捡回孩子的布鞋，他家人给了几枚灯铢。"

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
