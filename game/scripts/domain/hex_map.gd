class_name HexMap
extends RefCounted
const Catalog = preload("res://scripts/domain/catalog.gd")
const Relics = preload("res://scripts/domain/relic_catalog.gd")
const DIRECTIONS = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func cell_count(radius: int) -> int:
	return 1 + 3 * radius * (radius + 1)

static func key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

static func coord(id: String) -> Vector2i:
	var parts = id.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

static func distance(a: Vector2i, b: Vector2i) -> int:
	var d = a - b
	return maxi(abs(d.x), maxi(abs(d.y), abs(d.x + d.y)))

static func neighbors(id: String, tiles: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for d in DIRECTIONS:
		var k = key(coord(id) + d)
		if tiles.has(k):
			result.append(k)
	return result

static func is_land(tiles: Dictionary, id: String) -> bool:
	return tiles.has(id) and tiles[id].terrain != "lake"

static func world(id: String) -> Vector3:
	var p = coord(id)
	return Vector3(sqrt(3.0) * (p.x + p.y * 0.5), 0, 1.5 * p.y)

static func closest(point: Vector3, tiles: Dictionary) -> String:
	var id = cell_at(point)
	return id if tiles.has(id) else ""

static func cell_at(point: Vector3) -> String:
	var r = point.z / 1.5
	var q = point.x / sqrt(3.0) - r * 0.5
	var cx = roundi(q)
	var cz = roundi(r)
	var cy = roundi(-q - r)
	var dx = absf(cx - q)
	var dz = absf(cz - r)
	var dy = absf(cy + q + r)
	if dx > dy and dx > dz:
		cx = -cy - cz
	elif dz > dy:
		cz = -cx - cy
	return key(Vector2i(cx, cz))

static func path(tiles: Dictionary, start: String, goal: String, avoid_enemies: bool = false) -> Array[String]:
	if not is_land(tiles, start) or not is_land(tiles, goal):
		return []
	var frontier: Array[String] = [start]
	var previous = {start: ""}
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		if current == goal:
			break
		for next in neighbors(current, tiles):
			if previous.has(next) or not is_land(tiles, next) or (avoid_enemies and not tiles[next].get("enemies", []).is_empty()):
				continue
			previous[next] = current
			frontier.append(next)
	if not previous.has(goal):
		return []
	var result: Array[String] = [goal]
	while result[0] != start:
		result.push_front(previous[result[0]])
	return result

static func generate(seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var tiles = {}
	var radius := Catalog.RADIUS
	# Region centers produce coherent patches, with a tiny deterministic edge variation.
	var biomes = ["plains", "forest", "mountain", "ruins", "desert", "swamp"]
	var available_centers: Array[Vector2i] = []
	for q in range(1 - radius, radius):
		for r in range(1 - radius, radius):
			var center := Vector2i(q, r)
			if distance(center, Vector2i.ZERO) < radius:
				available_centers.append(center)
	var centers: Array[Vector2i] = []
	for _biome in biomes:
		centers.append(available_centers.pop_at(rng.randi_range(0, available_centers.size() - 1)))
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var p = Vector2i(q, r)
			if distance(p, Vector2i.ZERO) > radius:
				continue
			var best = INF
			var terrain = "plains"
			for i in range(6):
				var score = distance(p, centers[i]) + rng.randf()
				if score < best:
					best = score
					terrain = biomes[i]
			tiles[key(p)] = {"terrain": terrain, "base_terrain": terrain, "resource": "", "quantity": 0, "enemies": [], "hidden": false, "discovered_enemy": false, "site": "", "npc": "", "height": rng.randf_range(0.0, 0.08)}
	var starts: Array[String] = []
	for cell in tiles:
		if distance(coord(cell), Vector2i.ZERO) == radius - 1:
			starts.append(cell)
	var preferred := starts.filter(func(cell): return tiles[cell].terrain != "ruins")
	var start: String = _pick(preferred if not preferred.is_empty() else starts, rng)
	var distant: Array[String] = []
	for cell in tiles:
		if distance(coord(start), coord(cell)) >= radius + 1:
			distant.append(cell)
	var boss: String = _pick(distant, rng)
	tiles[start].site = "start"
	tiles[boss].site = "boss"
	var occupied = {start: true, boss: true}
	# Reserve the village route before the 25 companions fill the small island.
	var routes: Array = []
	for first in neighbors(start, tiles):
		for second in neighbors(first, tiles):
			if distance(coord(start), coord(second)) == 2:
				routes.append([first, second])
	var opening_route: Array = _pick(routes, rng)
	for cell in opening_route:
		occupied[cell] = true
	var early: Array[String] = neighbors(start, tiles).filter(func(cell): return not occupied.has(cell))
	var lorne: String = _pick(early, rng)
	tiles[lorne].npc = "lorne"
	occupied[lorne] = true
	early.erase(lorne)
	var opening_supply: String = _pick(early, rng)
	occupied[opening_supply] = true
	_add_lake(tiles, occupied, seed_value, start)
	_reserve_relic_sites(tiles, occupied, rng)
	var free := tiles.keys().filter(func(cell): return not occupied.has(cell) and is_land(tiles, cell))
	for id in Catalog.COMPANIONS:
		if id == "lorne":
			continue
		var candidates := free.filter(func(cell): return tiles[cell].terrain == Catalog.COMPANIONS[id].terrain)
		var cell: String = _pick(candidates if not candidates.is_empty() else free, rng)
		tiles[cell].npc = id
		occupied[cell] = true
		free.erase(cell)
	var safe = {}
	for destination in occupied:
		for k in path(tiles, start, destination):
			safe[k] = int(safe.get(k, 0)) + 1
	for k in tiles:
		var t = tiles[k]
		t.base_terrain = t.terrain
		if not is_land(tiles, k):
			continue
		var companion_in_danger = not t.npc.is_empty() and t.npc != "lorne" and safe.get(k, 0) == 1 and rng.randf() < 0.22
		if companion_in_danger or (not occupied.has(k) and not safe.has(k) and distance(coord(k), coord(start)) > 2 and rng.randf() < 0.19):
			t.enemies = _composition(t.terrain, rng)
			t.hidden = t.terrain in ["forest", "swamp"]
		elif not occupied.has(k) and rng.randf() < 0.38:
			# Keep the RNG draw so later terrain resources stay in their seeded locations.
			rng.randf()
			t.resource = "trail_food"
			t.quantity = rng.randi_range(1, 2)
	return {"tiles": tiles, "start": start, "boss": boss, "opening_route": opening_route,
		"opening_supply": opening_supply, "rng_state": rng.state}

static func _reserve_relic_sites(tiles: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator) -> void:
	var terrain_counts := {}
	for tile in tiles.values():
		terrain_counts[tile.terrain] = int(terrain_counts.get(tile.terrain, 0)) + 1
	var free := tiles.keys().filter(func(cell): return not occupied.has(cell) and is_land(tiles, cell))
	for site in Relics.SITES.values():
		var terrain: String = site[1]
		var matching := free.filter(func(cell): return tiles[cell].terrain == terrain)
		# Keep one tile of every biome when a cache has to claim a different terrain.
		var candidates := matching if not matching.is_empty() else free.filter(
			func(cell): return terrain_counts[tiles[cell].terrain] > 1)
		var cell: String = _pick(candidates, rng)
		terrain_counts[tiles[cell].terrain] -= 1
		terrain_counts[terrain] += 1
		tiles[cell].terrain = terrain
		occupied[cell] = true
		free.erase(cell)

static func _add_lake(tiles: Dictionary, occupied: Dictionary, seed_value: int, start: String) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x3a62f
	var candidates: Dictionary = {}
	var counts: Dictionary = {}
	for id in tiles:
		var terrain: String = tiles[id].terrain
		counts[terrain] = int(counts.get(terrain, 0)) + 1
		if not occupied.has(id) and distance(coord(id), Vector2i.ZERO) < Catalog.RADIUS and distance(coord(id), coord(start)) > 1:
			var basin = {"swamp": 0.8, "plains": 0.45, "mountain": -0.6}.get(terrain, 0.0)
			candidates[id] = rng.randf() + basin
	var centers = candidates.keys()
	centers.sort_custom(func(a, b): return candidates[a] > candidates[b])
	var target = rng.randi_range(2, 3)
	for center in centers:
		var shore: Array[String] = [center]
		var changed: Dictionary = {}
		while not shore.is_empty() and changed.size() < target:
			shore.sort_custom(func(a, b): return candidates[a] > candidates[b])
			var id: String = shore.pop_front()
			var terrain: String = tiles[id].terrain
			if counts[terrain] <= 1:
				continue
			changed[id] = terrain
			counts[terrain] -= 1
			tiles[id].terrain = "lake"
			for next in neighbors(id, tiles):
				if candidates.has(next) and is_land(tiles, next) and next not in shore and distance(coord(next), coord(center)) <= 2:
					shore.append(next)
		if changed.size() >= 2 and _connected_land(tiles, start, tiles.size() - changed.size()):
			return
		for id in changed:
			tiles[id].terrain = changed[id]
			counts[changed[id]] += 1

static func _connected_land(tiles: Dictionary, start: String, expected: int) -> bool:
	var frontier: Array[String] = [start]
	var visited = {start: true}
	while not frontier.is_empty():
		for next in neighbors(frontier.pop_back(), tiles):
			if is_land(tiles, next) and not visited.has(next):
				visited[next] = true
				frontier.append(next)
	return visited.size() == expected

static func _pick(candidates: Array, rng: RandomNumberGenerator) -> Variant:
	assert(not candidates.is_empty(), "Map placement exhausted")
	return candidates[rng.randi_range(0, candidates.size() - 1)]

static func _composition(terrain: String, rng: RandomNumberGenerator, ordinary_only: bool = false) -> Array:
	var options = {
		"plains": [["archer", "boar"], ["swarm", "swarm", "swarm"]],
		"forest": [["spider", "swarm"], ["boar", "apothecary"], ["hunter_elite"]],
		"mountain": [["archer", "archer"], ["boar", "archer"]],
		"ruins": [["furnace", "apothecary"], ["canal", "furnace"], ["furnace_elite"]],
		"desert": [["furnace", "archer"], ["swarm", "swarm", "apothecary"]],
		"swamp": [["lurker", "spider"], ["lurker", "apothecary"]],
	}
	var choices = options.get(terrain, options.plains)
	if ordinary_only and terrain in ["forest", "ruins"]:
		choices = choices.slice(0, 2)
	return choices[rng.randi_range(0, choices.size() - 1)].duplicate()
