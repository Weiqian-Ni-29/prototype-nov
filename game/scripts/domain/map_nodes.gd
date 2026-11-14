extends RefCounted
## Node placement uses a separate seed stream from terrain, combat and weather.
const Hex = preload("res://scripts/domain/hex_map.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const STARTING_COINS = 8
const PRICES = {"trail_food": 3, "trail_blade": 12, "padded_coat": 15, "lamp_charm": 18}
const GEAR = ["trail_blade", "padded_coat", "lamp_charm"]
const RETIRED_KINDS = ["choice", "haunt"]
const LABELS = {
	"story": "地点", "supply": "补给",
	"cache": "寻宝", "battle": "遭遇", "elite": "险地",
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
	# Retain the old seeded allocation without loading the retired story text.
	for terrain in ["plains", "forest", "mountain", "ruins", "desert", "swamp"]:
		for kind in RETIRED_KINDS:
			pools[kind + ":" + terrain] = legacy_event_ids(kind, terrain)

static func legacy_event_ids(kind: String, terrain: String) -> Array:
	return ["%s_%s_1" % [terrain, kind], "%s_%s_2" % [terrain, kind]]

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

static func battle_coins(seed_value: int, cell: String, elite: bool, finale: bool = false) -> int:
	var roller = RandomNumberGenerator.new()
	roller.seed = hash("battle-coins:%d:%s" % [seed_value, cell])
	if finale:
		return roller.randi_range(16, 20)
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
		return "story" if tile.site == "boss" else "battle"
	if roll < 19:
		return "rest"
	if roll < 27:
		return "cache"
	if roll < 45:
		return "choice"
	return "haunt" if roll < 72 else _local_kind(roll)

static func _local_kind(roll: int) -> String:
	return "choice" if roll % 2 == 0 else "rest"

static func _set_local_reward(node: Dictionary, roller: RandomNumberGenerator) -> void:
	if node.kind == "choice":
		node.coins = roller.randi_range(3, 5)
	else:
		node.item = "trail_food"

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
		_set_local_reward(node, roller)
		nodes[cell] = node

static func generate(tiles: Dictionary, seed_value: int, relic_sites: Dictionary, rewards: Dictionary, relic_checks: Dictionary) -> Dictionary:
	_load_events()
	var nodes = {}
	var use_counts = {}
	var cells = tiles.keys()
	cells.sort()
	var roller = RandomNumberGenerator.new()
	var start := ""
	var nearby_haunts: Array = []
	for cell in cells:
		if tiles[cell].site == "start":
			start = cell
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
		if kind in ["rest", "choice"]:
			_set_local_reward(node, roller)
		elif kind == "cache":
			var items = GEAR + ["trail_food", "trail_food"]
			node.item = items[roller.randi_range(0, items.size() - 1)]
			if relic_checks.has("site:" + cell):
				node.result = "search"
		elif kind in ["battle", "elite"]:
			node.coins = battle_coins(seed_value, cell, kind == "elite")
			if kind == "battle" and tile.enemies.is_empty() and not defeated:
				var near_start := not start.is_empty() and Hex.distance(Hex.coord(cell), Hex.coord(start)) <= 2
				_place_enemy(tile, roller, false, near_start, false, false)
	return nodes

static func replace_retired_nodes(data: Dictionary) -> void:
	# Keep the old placement and story caps so only the retired cells change.
	_load_events()
	var roller := RandomNumberGenerator.new()
	for cell in data.nodes:
		var previous: Dictionary = data.nodes[cell]
		if previous.kind not in RETIRED_KINDS:
			continue
		if cell == data.boss:
			data.nodes[cell] = {"kind": "story", "event": "", "result": ""}
			continue
		roller.seed = hash("replacement-battle:%s:%s" % [data.seed, cell])
		var opening := Hex.distance(Hex.coord(cell), Hex.coord(data.start)) <= 2
		var elite := not opening and roller.randi_range(0, 4) == 0
		var cleared: bool = not previous.result.is_empty() or data.peace.has(cell)
		_replace_with_battle(data, cell, roller, elite, opening, cleared)

static func merge_supplies(data: Dictionary) -> void:
	var roller := RandomNumberGenerator.new()
	for cell in data.nodes:
		var previous: Dictionary = data.nodes[cell]
		if previous.kind not in ["rest", "supply"] or (previous.kind == "supply" and previous.has("coins")):
			continue
		var tile: Dictionary = data.tiles[cell]
		var claimed: bool = not previous.result.is_empty() or (previous.kind == "supply" and tile.quantity <= 0)
		roller.seed = hash("supply-reward:%s:%s" % [data.seed, cell])
		var node := {"kind": "supply", "event": previous.event, "result": "collect" if claimed else "",
			"coins": roller.randi_range(1, 3)}
		var roll := roller.randi_range(0, 99)
		if roll < 10:
			node.gear_definition = Gear.roll_definition(tile.base_terrain, roller)
			node.gear_quality = Gear.roll_quality(roller)
		elif roll < 35:
			node.item = "trail_food"
		data.nodes[cell] = node
		tile.resource = ""
		tile.quantity = 0

static func raise_elite_share(data: Dictionary) -> void:
	var target := roundi(data.nodes.size() * 0.20)
	var current := 0
	var candidates: Array[String] = []
	var priority := {}
	var start := Hex.coord(data.start)
	for cell in data.nodes:
		var node: Dictionary = data.nodes[cell]
		if cell == data.boss:
			continue
		if node.kind == "elite":
			current += 1
		elif (node.kind == "supply" and node.result.is_empty()
				and Hex.distance(Hex.coord(cell), start) > 2 and cell != data.actors.hero.position):
			candidates.append(cell)
			priority[cell] = hash("elite-from-supply:%s:%s" % [data.seed, cell])
	candidates.sort_custom(func(a, b): return a < b if priority[a] == priority[b] else priority[a] < priority[b])
	var roller := RandomNumberGenerator.new()
	for index in mini(maxi(0, target - current), candidates.size()):
		var cell := candidates[index]
		roller.seed = priority[cell]
		_replace_with_battle(data, cell, roller, true, false, false)

static func _replace_with_battle(data: Dictionary, cell: String, roller: RandomNumberGenerator, elite: bool, opening: bool, cleared: bool) -> void:
	var tile: Dictionary = data.tiles[cell]
	var kind := "elite" if elite else "battle"
	var biome: String = tile.base_terrain
	var candidates: Array = pools[kind + ":" + biome]
	var event: String = candidates[roller.randi_range(0, candidates.size() - 1)]
	data.nodes[cell] = {"kind": kind, "event": event, "result": "cleared" if cleared else "",
		"coins": battle_coins(int(data.seed), cell, elite)}
	_place_enemy(tile, roller, elite, opening, cleared, data.get("visited", {}).has(cell))

static func _place_enemy(tile: Dictionary, roller: RandomNumberGenerator, elite: bool, opening: bool, cleared: bool, visited: bool) -> void:
	var biome: String = tile.base_terrain
	tile.resource = ""
	tile.quantity = 0
	tile.hidden = false
	if cleared:
		tile.enemies = []
	elif elite:
		tile.enemies = ["furnace_elite" if biome in ["mountain", "ruins", "desert"] else "hunter_elite"]
	else:
		tile.enemies = ["boar"] if opening else Hex._composition(biome, roller, true)
	tile.discovered_enemy = not cleared and visited

static func replace_shop_nodes(data: Dictionary) -> void:
	_load_events()
	var roller := RandomNumberGenerator.new()
	for cell in data.nodes:
		var node: Dictionary = data.nodes[cell]
		if node.kind != "trade":
			continue
		if cell == data.boss:
			data.nodes[cell] = {"kind": "story", "event": "", "result": ""}
			continue
		roller.seed = hash("shop-to-battle:%s:%s" % [data.seed, cell])
		var opening := Hex.distance(Hex.coord(cell), Hex.coord(data.start)) <= 2
		_replace_with_battle(data, cell, roller, false, opening, data.rewards.has(cell + ":"))
	for uid in data.gear_instances.keys():
		if data.gear_instances[uid].owner.kind == "shop":
			data.gear_instances.erase(uid)

static func place_opening_battles(data: Dictionary, relic_sites: Dictionary) -> void:
	var start: String = data.start
	var tiles: Dictionary = data.tiles
	var neighbors := Hex.neighbors(start, tiles)
	var roller := RandomNumberGenerator.new()
	roller.seed = hash("opening-battles:%s" % data.seed)
	var candidates: Array = []
	var best := -10
	for battle in neighbors:
		if not Hex.is_land(tiles, battle) or not tiles[battle].npc.is_empty():
			continue
		for next in Hex.neighbors(battle, tiles):
			if Hex.distance(Hex.coord(start), Hex.coord(next)) != 2 or not Hex.is_land(tiles, next):
				continue
			var tile: Dictionary = tiles[next]
			if tile.site.is_empty() and tile.npc.is_empty():
				var priority := 4 * int(tile.enemies.is_empty()) + 2 * int(data.nodes[battle].kind == "battle")
				if relic_sites.has(battle) or relic_sites.has(next):
					priority -= 8
				if priority > best:
					candidates.clear()
					best = priority
				if priority == best:
					candidates.append([battle, next])
	if candidates.is_empty():
		return
	var pair: Array = candidates[roller.randi_range(0, candidates.size() - 1)]
	_replace_with_battle(data, pair[0], roller, false, true, false)
	data.nodes[pair[0]].intro_duel = true
	_replace_with_battle(data, pair[1], roller, false, true, false)
	data.nodes[pair[1]].intro_duel = true

static func shop_supplies(roller: RandomNumberGenerator) -> Dictionary:
	return {"trail_food": roller.randi_range(1, 2)}
