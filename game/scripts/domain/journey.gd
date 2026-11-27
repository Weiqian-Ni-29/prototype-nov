extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")

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
	"valley": ["风过谷口", "highland", "谷口横着一根枯松，折断的树梢还在晃。谷里起了风，湿冷的雾正沿着石壁退去。",
		["沿石壁绕过去", "踩着树干跨过去", "下到雾里的谷底"]],
	"kiln": ["废窑余温", "ruins", "窑门歪在门轴上，摸上去还暖。风从烟道灌进来，吹起一阵细灰。",
		["顺着窑墙走", "推门穿过窑院", "爬上烟道旁的坡"]],
	"ford": ["无名渡口", "wetlands", "一条麻绳从河这边牵到对岸，水里的半截时沉时浮。岸上留着两道车辙，已经被雨冲得很浅。",
		["沿车辙绕一段", "拉着麻绳涉水", "从河心的石头上跳过去"]],
	"woods": ["林里的回声", "woodland", "林子深处传来三声敲击，停了一会儿才又响起。你抬头看时，枝头的水正滴到脚边。",
		["走林边的宽路", "朝回声走过去", "拨开藤条抄近路"]],
	"ridge": ["鹿脊山道", "highland", "山道窄得只容一人，迎面飘来烧木柴的气味。谷里回荡着一声闷响，过了许久又响一声。",
		["贴山壁慢走", "翻过路边的矮脊", "沿碎石坡直下"]],
	"belltower": ["半截钟楼", "ruins", "钟楼倒了半边，钟绳垂在路中央。一块旧木牌上写着撤往南门，最下面几个字已被水泡开。",
		["循木牌沿街走", "钻过钟楼的门洞", "从倒下的梁上翻过去"]],
	"quarry": ["断石坡", "drylands", "采石场里还留着几根撬杠，谁也没来收。风把石粉吹上斜坡，坡脚的脚印一转眼就淡了。",
		["沿山坡外侧绕行", "循旧脚印过石场", "穿过石缝下坡"]],
	"reedbed": ["白苇滩", "wetlands", "芦苇倒向河心，几缕白絮贴在水面上。露出水的木桩排成一线，走到一半便断了。",
		["绕着苇滩走", "踩木桩渡过去", "循水道穿过苇丛"]],
	"camp": ["荒营的火盆", "drylands", "营地里的几只火盆早凉了，灰里还埋着烧卷的征兵令。天快暗时，远处有人跟着鼓点喊号子。",
		["绕过营地外墙", "穿过旧营门", "沿营后的土坡下去"]],
	"aqueduct": ["高渠之下", "ruins", "缺了一角的石渠还悬在头顶，水从裂缝一线线落下。渠那边灯火成排，鼓声盖住了流水。",
		["走渠边的缓坡", "从石拱下穿过", "攀上石渠直走"]],
	"breach": ["缺口里的灯", "road", "外墙的缺口里落了一盏灯，风吹得火快灭了。缺口内侧铺着木板，板缝里不断有砂石落下。",
		["沿墙寻找缓坡", "拾起灯穿过缺口", "踩着木板翻进去"]],
	"burial_road": ["埋旗的路", "woodland", "有人把旗杆插在土堆前，旗上的字被泥盖住了。再往前，林子尽头每隔一阵便透出一道暗红的光。",
		["沿林边寻路", "顺车道向前", "直穿林子往红光走"]],
	FINAL: ["战鼓台", "finale", "鼓槌落下，四周的伤兵一齐伸手去够散落的兵器。卡德兰站在鼓台前，见你走近，便放下鼓槌去取武器。",
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
	settle(run, "商贩收起货箱，朝你来时的方向走去。")
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
			message += "\n走过前三段路，你获得了遗器「生命之种」。"
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
			message = "队伍找了个避风的地方休息，等有了力气才起身。"
		"chest":
			data.lamp_coins += _scaled(roller.randi_range(7, 11), stakes)
			message = "你找到一只旧木箱，里面有一袋灯铢。"
			var source := "journey:chest:%d" % int(data.journey.step)
			var relic := _grant_relic(run, source, run.relic_offer(source, Relics.DATA.keys(), 0.25 * SCALES[stakes]))
			if not relic.is_empty():
				message += " 袋子下面还压着遗器「%s」。" % Relics.DATA[relic].name
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
			return "一块石头在脚下松脱，你摔了一跤，带着伤继续走。"
		2:
			data.lamp_coins = maxi(0, int(data.lamp_coins) - _scaled(5, stakes))
			return "系钱袋的绳子磨断了。拾回钱袋时，里面已经掉出去几枚灯铢。"
	data.lamp_coins += _scaled(5, stakes)
	return "你捡回一个孩子掉的布鞋。他的家人赶过来，留了几枚灯铢道谢。"

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
