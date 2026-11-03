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

static func world(id: String) -> Vector3:
	var p = coord(id)
	return Vector3(sqrt(3.0) * (p.x + p.y * 0.5), 0, 1.5 * p.y)

static func closest(point: Vector3, tiles: Dictionary) -> String:
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
	var k = key(Vector2i(cx, cz))
	return k if tiles.has(k) else ""

static func path(tiles: Dictionary, start: String, goal: String, avoid_enemies: bool = false) -> Array[String]:
	if not tiles.has(start) or not tiles.has(goal):
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
			if avoid_enemies and not tiles[next].get("enemies", []).is_empty():
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
			tiles[key(p)] = {"terrain": terrain, "base_terrain": terrain, "burning": false, "fuel": 3, "wet_until": 0, "resource": "", "quantity": 0, "enemies": [], "hidden": false, "discovered_enemy": false, "site": "", "npc": "", "camp": false, "height": rng.randf_range(0.0, 0.08)}
	var start = "-7,0"
	# Pick the exit from far boundary cells, never relaxing geometric distance.
	var exits: Array[String] = []
	for k in tiles:
		if distance(coord(start), coord(k)) >= 12 and distance(coord(k), Vector2i.ZERO) >= 7:
			exits.append(k)
	var exit_id = exits[rng.randi_range(0, exits.size() - 1)]
	tiles[start].terrain = "plains"
	tiles[start].site = "start"
	tiles[exit_id].terrain = "plains"
	tiles[exit_id].site = "exit"
	# Early companion has a safe route within two moves, not two AP.
	var early_candidates: Array[String] = []
	for k in tiles:
		var d = distance(coord(start), coord(k))
		if d > 0 and d <= 2:
			early_candidates.append(k)
	var early = early_candidates[rng.randi_range(0, early_candidates.size() - 1)]
	tiles[early].terrain = "mountain"
	tiles[early].npc = "lorne"
	tiles[early].site = "sign"
	var occupied = {start: true, exit_id: true, early: true}
	var sites = {"inn": "ruins", "home": "forest", "record": "ruins"}
	for site in sites:
		var k = _pick_free(tiles, occupied, rng, 3)
		tiles[k].terrain = sites[site]
		tiles[k].site = site
		occupied[k] = true
	var npc_sites = {"cen": "forest", "eve": "herb", "grit": "track", "ember": "clear", "tide": "water"}
	for id in npc_sites:
		var k = _pick_free(tiles, occupied, rng, 2)
		tiles[k].terrain = Catalog.COMPANIONS[id].terrain
		tiles[k].npc = id
		tiles[k].site = npc_sites[id]
		occupied[k] = true
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
	# Reserve a completely safe extraction path and safe approaches to every story anchor.
	var safe = {}
	for destination in occupied:
		for k in path(tiles, start, destination):
			safe[k] = true
	for k in tiles:
		var t = tiles[k]
		t.base_terrain = t.terrain
		if not occupied.has(k) and not safe.has(k) and distance(coord(k), coord(start)) > 2 and rng.randf() < 0.19:
			t.enemies = _composition(t.terrain, rng)
			t.hidden = t.terrain in ["forest", "swamp"]
			t.discovered_enemy = not t.hidden
		elif not occupied.has(k) and rng.randf() < 0.38:
			t.resource = "salve" if rng.randf() < 0.55 else "ether"
			t.quantity = rng.randi_range(1, 2)
	tiles[start].resource = "salve"
	tiles[start].quantity = 2
	# A separate optional boss cannot occupy story or extraction corridors.
	for k in tiles:
		if not occupied.has(k) and not safe.has(k) and distance(coord(start), coord(k)) > 8:
			tiles[k].enemies = ["lamp_boss", "canal"]
			tiles[k].hidden = false
			tiles[k].discovered_enemy = true
			break
	return {"tiles": tiles, "start": start, "exit": exit_id, "rng_state": rng.state}

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
