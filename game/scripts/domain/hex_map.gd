class_name HexMap
extends RefCounted
const Catalog = preload("res://scripts/domain/catalog.gd")
const DIRECTIONS = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

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
	var costs = {start: 0}
	var previous = {}
	while not frontier.is_empty():
		var current = frontier[0]
		for candidate in frontier:
			if costs[candidate] < costs[current]:
				current = candidate
		frontier.erase(current)
		if current == goal:
			break
		for next in neighbors(current, tiles):
			if not is_land(tiles, next) or (avoid_enemies and not tiles[next].get("enemies", []).is_empty()):
				continue
			var cost = int(costs[current]) + int(Catalog.TERRAIN[tiles[next].terrain].cost)
			if not costs.has(next) or cost < costs[next]:
				costs[next] = cost
				previous[next] = current
				if next not in frontier:
					frontier.append(next)
	if not costs.has(goal):
		return []
	var result: Array[String] = [goal]
	while result[0] != start:
		result.push_front(previous[result[0]])
	return result

static func generate(seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var tiles = {}
	# Region centers produce coherent patches, with a tiny deterministic edge variation.
	var biomes = ["plains", "forest", "mountain", "ruins", "desert", "swamp"]
	var centers: Array[Vector2i] = []
	for i in range(6):
		centers.append(Vector2i(rng.randi_range(-6, 6), rng.randi_range(-4, 4)))
	for q in range(-8, 9):
		for r in range(-8, 9):
			var p = Vector2i(q, r)
			if distance(p, Vector2i.ZERO) > 8:
				continue
			var best = INF
			var terrain = "plains"
			for i in range(6):
				var score = distance(p, centers[i]) + rng.randf_range(0.0, 1.5)
				if score < best:
					best = score
					terrain = biomes[i]
			tiles[key(p)] = {"terrain": terrain, "base_terrain": terrain, "resource": "", "quantity": 0, "enemies": [], "hidden": false, "discovered_enemy": false, "site": "", "npc": "", "height": rng.randf_range(0.0, 0.08)}
	var starts: Array[String] = []
	for cell in tiles:
		if distance(coord(cell), Vector2i.ZERO) == 7 and tiles[cell].terrain != "ruins":
			starts.append(cell)
	var start = starts[rng.randi_range(0, starts.size() - 1)]
	var distant: Array[String] = []
	for cell in tiles:
		if distance(coord(start), coord(cell)) >= 11:
			distant.append(cell)
	var boss = distant[rng.randi_range(0, distant.size() - 1)]
	tiles[start].site = "start"
	tiles[boss].site = "boss"
	var occupied = {start: true, boss: true}
	for id in Catalog.COMPANIONS:
		var candidates: Array[String] = []
		for cell in tiles:
			if occupied.has(cell):
				continue
			var steps = distance(coord(start), coord(cell))
			if (id == "lorne" and steps <= 2) or (id != "lorne" and steps > 2 and tiles[cell].terrain == Catalog.COMPANIONS[id].terrain):
				candidates.append(cell)
		var cell = _pick_free(tiles, occupied, rng, 2) if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]
		tiles[cell].npc = id
		occupied[cell] = true
	# Ensure all six base biomes exist even when Voronoi seeds happen to overlap.
	for terrain in biomes:
		var exists = false
		for k in tiles:
			if tiles[k].terrain == terrain:
				exists = true
		if not exists:
			var k = _pick_free(tiles, occupied, rng, 2)
			tiles[k].terrain = terrain
			occupied[k] = true
	# Keep approaches to the village, companions and final battle open.
	_add_lake(tiles, occupied, seed_value, start)
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
			t.resource = "salve" if rng.randf() < 0.55 else "ether"
			t.quantity = rng.randi_range(1, 2)
	return {"tiles": tiles, "start": start, "boss": boss, "rng_state": rng.state}

static func _add_lake(tiles: Dictionary, occupied: Dictionary, seed_value: int, start: String) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x3a62f
	var candidates: Dictionary = {}
	var counts: Dictionary = {}
	for id in tiles:
		var terrain: String = tiles[id].terrain
		counts[terrain] = int(counts.get(terrain, 0)) + 1
		if not occupied.has(id) and distance(coord(id), Vector2i.ZERO) <= 6 and distance(coord(id), coord(start)) > 2:
			var basin = {"swamp": 0.8, "plains": 0.45, "mountain": -0.6}.get(terrain, 0.0)
			candidates[id] = rng.randf() + basin
	var centers = candidates.keys()
	centers.sort_custom(func(a, b): return candidates[a] > candidates[b])
	var target = rng.randi_range(7, 11)
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
		if changed.size() >= 5 and _connected_land(tiles, start, tiles.size() - changed.size()):
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

static func _pick_free(tiles: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, minimum: int) -> String:
	var candidates: Array[String] = []
	for k in tiles:
		if not occupied.has(k) and distance(coord(k), Vector2i(-7, 0)) >= minimum:
			candidates.append(k)
	assert(not candidates.is_empty(), "Map placement exhausted")
	return candidates[rng.randi_range(0, candidates.size() - 1)]

static func _composition(terrain: String, rng: RandomNumberGenerator) -> Array:
	var options = {
		"plains": [["archer", "boar"], ["swarm", "swarm", "swarm"]],
		"forest": [["spider", "swarm"], ["boar", "apothecary"], ["hunter_elite"]],
		"mountain": [["archer", "archer"], ["boar", "archer"]],
		"ruins": [["furnace", "apothecary"], ["canal", "furnace"], ["furnace_elite"]],
		"desert": [["furnace", "archer"], ["swarm", "swarm", "apothecary"]],
		"swamp": [["lurker", "spider"], ["lurker", "apothecary"]],
	}
	var choices = options.get(terrain, options.plains)
	return choices[rng.randi_range(0, choices.size() - 1)].duplicate()
