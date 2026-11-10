extends RefCounted
## Node placement uses a separate seed stream from terrain, combat and weather.
const Hex = preload("res://scripts/domain/hex_map.gd")
const STARTING_COINS = 8
const PRICES = {"salve": 6, "ether": 7, "trail_food": 3, "trail_blade": 12, "padded_coat": 15, "lamp_charm": 18}
const GEAR = ["trail_blade", "padded_coat", "lamp_charm"]
const LABELS = {
	"story": "地点", "trade": "交易", "supply": "补给", "rest": "补给点",
	"choice": "委托", "haunt": "亡灵", "cache": "寻宝", "battle": "遭遇", "elite": "险地",
}
static var events: Dictionary = {}
static var pools: Dictionary = {}

static func _load_events() -> void:
	if not events.is_empty():
		return
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/story/node_events.json"))
	assert(source is Dictionary, "Map node story catalog is missing or invalid")
	for kind in source:
		for event in source[kind]:
			events[event.id] = event
			for terrain in event.terrains:
				var key: String = kind + ":" + terrain
				if not pools.has(key):
					pools[key] = []
				pools[key].append(event.id)

static func story(node: Dictionary) -> Dictionary:
	_load_events()
	return events.get(node.get("event", ""), {})

static func resolution(node: Dictionary) -> String:
	var event = story(node)
	if str(node.result).ends_with("_alternative"):
		return str(event.get("alternative_resolved", ""))
	return str(event.get("resolved_by_option", {}).get(node.result, event.get("resolved", "")))

static func label(kind: String) -> String:
	return LABELS.get(kind, "")

static func is_elite(types: Array) -> bool:
	return types.any(func(type): return str(type).ends_with("_elite") or type == "lamp_boss")

static func battle_coins(seed_value: int, cell: String, elite: bool) -> int:
	var roller = RandomNumberGenerator.new()
	roller.seed = hash("battle-coins:%d:%s" % [seed_value, cell])
	return roller.randi_range(8, 12) if elite else roller.randi_range(4, 7)

static func _kind(tile: Dictionary, has_relic: bool, defeated: bool, roll: int) -> String:
	if tile.site == "start":
		return "story"
	if not tile.enemies.is_empty() or defeated:
		return "elite" if is_elite(tile.enemies) else "battle"
	if has_relic:
		return "cache"
	if not tile.resource.is_empty():
		return "supply"
	if roll < 7:
		return "trade"
	if roll < 19:
		return "rest"
	if roll < 27:
		return "cache"
	if roll < 45:
		return "choice"
	return "haunt" if roll < 72 else _local_kind(roll)

static func _local_kind(roll: int) -> String:
	return "choice" if roll % 2 == 0 else "rest"

static func _set_local_reward(node: Dictionary, biome: String, roller: RandomNumberGenerator) -> void:
	if node.kind == "choice":
		node.coins = roller.randi_range(3, 5)
	else:
		node.item = "ether" if biome in ["swamp", "ruins", "desert"] else "salve"

static func replace_legacy_clues(nodes: Dictionary, tiles: Dictionary, seed_value: int) -> void:
	_load_events()
	var roller = RandomNumberGenerator.new()
	for cell in nodes:
		if nodes[cell].kind != "clue":
			continue
		roller.seed = hash("replace-clue:%d:%s" % [seed_value, cell])
		var biome: String = tiles[cell].base_terrain
		var kind = _local_kind(roller.randi_range(0, 99))
		var candidates: Array = pools[kind + ":" + biome]
		var node = {"kind": kind, "event": candidates[roller.randi_range(0, candidates.size() - 1)], "result": ""}
		_set_local_reward(node, biome, roller)
		nodes[cell] = node

static func generate(tiles: Dictionary, seed_value: int, relic_sites: Dictionary, rewards: Dictionary, relic_checks: Dictionary) -> Dictionary:
	_load_events()
	var nodes = {}
	var use_counts = {}
	var cells = tiles.keys()
	cells.sort()
	var roller = RandomNumberGenerator.new()
	var nearby_haunts: Array = []
	for cell in cells:
		if tiles[cell].site == "start":
			nearby_haunts = Hex.neighbors(cell, tiles).filter(func(next): return Hex.is_land(tiles, next) and tiles[next].site.is_empty())
			nearby_haunts.sort_custom(func(a, b): return hash("clue:%s:%s" % [seed_value, a]) < hash("clue:%s:%s" % [seed_value, b]))
			nearby_haunts = nearby_haunts.slice(0, 3)
			break
	for cell in cells:
		if not Hex.is_land(tiles, cell):
			continue
		roller.seed = hash("node:%d:%s" % [seed_value, cell])
		var tile = tiles[cell]
		var defeated = rewards.has(cell + ":")
		var forced_haunt = cell in nearby_haunts
		var roll = 0 if forced_haunt else roller.randi_range(0, 99)
		var kind = "haunt" if forced_haunt else _kind(tile, relic_sites.has(cell), defeated, roll)
		var node = {"kind": kind, "event": "", "result": ""}
		nodes[cell] = node
		if kind == "story":
			continue
		var biome: String = tile.base_terrain
		var candidates: Array = pools.get(kind + ":" + biome, [])
		if kind == "haunt":
			var unseen = candidates.filter(func(id): return not use_counts.has(id))
			if unseen.is_empty():
				kind = _local_kind(roll)
				node.kind = kind
				candidates = pools.get(kind + ":" + biome, [])
			else:
				candidates = unseen
		if not candidates.is_empty():
			var fewest = candidates.map(func(id): return int(use_counts.get(id, 0))).min()
			var least_used = candidates.filter(func(id): return int(use_counts.get(id, 0)) == fewest)
			node.event = least_used[roller.randi_range(0, least_used.size() - 1)]
			use_counts[node.event] = int(fewest) + 1
		if kind == "trade":
			var stock = {"salve": 1, "ether": 1, "trail_food": 1}
			var local_supply = "ether" if biome in ["swamp", "ruins", "desert"] else "salve"
			stock[local_supply] += roller.randi_range(0, 1)
			stock[GEAR[roller.randi_range(0, GEAR.size() - 1)]] = 1
			node.stock = stock
		elif kind in ["rest", "choice"]:
			_set_local_reward(node, biome, roller)
		elif kind == "cache":
			var items = GEAR + ["salve", "ether"]
			node.item = items[roller.randi_range(0, items.size() - 1)]
			if relic_checks.has("site:" + cell):
				node.result = "search"
		elif kind in ["battle", "elite"]:
			node.coins = battle_coins(seed_value, cell, kind == "elite")
	return nodes
