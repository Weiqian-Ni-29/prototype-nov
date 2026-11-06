extends SceneTree
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Run = preload("res://scripts/domain/expedition.gd")
const Combat = preload("res://scripts/domain/battle.gd")
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func fresh(seed_value: int = 20261104) -> RefCounted:
	var r = Run.new()
	r.save_path = "user://test-run.json"
	r.new_run(seed_value, "wayfarer")
	return r

func fixture_ally(r: RefCounted, id: String, position: String) -> void:
	r.actor(id).position = position
	r.actor(id).joined = true
	r.data.story[id].relation = "joined"

func encounter(r: RefCounted, enemies: Array, ids: Array, ambush: bool = false) -> RefCounted:
	var p = r.actor(str(ids[0])).position
	r.data.tiles[p].enemies = enemies
	var b = Combat.new()
	var result = b.begin(r, {"position": p, "ambush": ambush, "origin": p, "movers": ids, "npc": ""}, ids)
	expect(result.ok, "Battle fixture begins: " + str(result))
	return b

func execute() -> void:
	var quick = "--quick" in OS.get_cmdline_user_args()
	var seed_count = 12 if quick else 200
	var early_locations = {}
	for seed_value in range(seed_count):
		var generated = Hex.generate(seed_value)
		var tiles = generated.tiles
		expect(tiles.size() == 217, "217 cells seed %d" % seed_value)
		expect(Hex.distance(Hex.coord(generated.start), Hex.coord(generated.exit)) >= 12, "Distant extraction seed %d" % seed_value)
		var route = Hex.path(tiles, generated.start, generated.exit, true)
		expect(not route.is_empty(), "Safe extraction route seed %d" % seed_value)
		var route_cost = 0
		for k in route.slice(1):
			route_cost += int(Catalog.TERRAIN[tiles[k].terrain].cost)
		expect(route_cost >= 12, "Extraction route cost seed %d" % seed_value)
		var counts = {}
		var terrains = {}
		var lake: Array[String] = []
		for k in tiles:
			expect(Hex.distance(Hex.coord(k), Vector2i.ZERO) <= 8, "Hex boundary " + k)
			terrains[tiles[k].terrain] = true
			if tiles[k].terrain == "lake":
				lake.append(k)
				expect(tiles[k].npc == "" and tiles[k].site == "" and tiles[k].enemies.is_empty() and tiles[k].quantity == 0,
					"No land encounters, sites or items on water " + k)
			if tiles[k].npc != "":
				var id = tiles[k].npc
				counts[id] = int(counts.get(id, 0)) + 1
				expect(tiles[k].terrain == Catalog.COMPANIONS[id].terrain, "NPC terrain " + id)
				expect(not Hex.path(tiles, generated.start, k, true).is_empty(), "NPC safely reachable " + id)
				if id == "lorne":
					early_locations[k] = true
					expect(Hex.path(tiles, generated.start, k, true).size() <= 4, "Early companion <=3 moves")
		for id in Catalog.COMPANIONS:
			expect(counts.get(id, 0) == 1, "Exactly one companion " + id)
		expect(terrains.size() == 7, "Six land biomes plus a lake seed %d" % seed_value)
		expect(lake.size() >= 5 and lake.size() <= 11, "Lake is a multi-tile feature seed %d" % seed_value)
		if not lake.is_empty():
			expect(Hex.path(tiles, generated.start, lake[0]).is_empty(), "No route into lake seed %d" % seed_value)
			var wet = {lake[0]: true}
			var frontier: Array[String] = [lake[0]]
			while not frontier.is_empty():
				for next in Hex.neighbors(frontier.pop_back(), tiles):
					if tiles[next].terrain == "lake" and not wet.has(next):
						wet[next] = true
						frontier.append(next)
			expect(wet.size() == lake.size(), "A single connected lake seed %d" % seed_value)
			expect(Hex._connected_land(tiles, generated.start, tiles.size() - lake.size()), "All land stays connected seed %d" % seed_value)
		if seed_value < 4:
			expect(JSON.stringify(generated) == JSON.stringify(Hex.generate(seed_value)), "Deterministic map seed %d" % seed_value)
	expect(early_locations.size() > 1, "Early companion placement varies with seed")
	var r = fresh()
	expect(r.data.explored.size() == 7, "Initial one-ring view")
	var destination = Hex.neighbors(r.actor("hero").position, r.data.tiles)[0]
	expect(r.has_visited(r.data.start) and not r.has_visited(destination), "Sight does not count as visiting a tile")
	var original_terrain = r.data.tiles[destination].terrain
	r.data.tiles[destination].terrain = "lake"
	var before_lake = JSON.stringify(r.data)
	var blocked = r.move(["hero"], destination)
	expect(not blocked.ok and "绕行" in blocked.message and JSON.stringify(r.data) == before_lake,
		"Attempting to enter lake water spends no AP and does not reveal tiles")
	r.data.tiles[destination].terrain = original_terrain
	var before_ap = int(r.actor("hero").ap)
	var before_energy = int(r.actor("hero").energy)
	var cost = r.move_cost("hero", destination)
	expect(r.move(["hero"], destination).ok, "Valid move")
	expect(r.has_visited(destination), "Successful movement records the destination as visited")
	expect(r.actor("hero").ap == before_ap - cost, "Individual movement charge")
	expect(r.actor("hero").energy == before_energy, "Exploration never charges ultimate")
	var explored = r.data.explored.size()
	r.actor("hero").ap = 0
	expect(not r.move(["hero"], r.data.start).ok, "Insufficient movement blocked")
	expect(r.data.explored.size() == explored, "Blocked move does not reveal")
	r.actor("hero").hp = 0
	fixture_ally(r, "lorne", r.data.start)
	expect(r.end_day().ok, "Advance day with rescuer")
	expect(r.actor("hero").hp == 0, "Daily healing cannot revive")
	expect(r.actor("lorne").ap == r.actor("lorne").ap_max, "Personal daily AP")
	expect(not r.transfer("lorne", "hero", "salve", 1).ok, "No remote inventory transfer")
	r.actor("lorne").position = r.actor("hero").position
	expect(r.use_item("lorne", "hero", "salve").ok, "Physical rescue")
	expect(r.actor("hero").hp > 0, "Rescued actor can act")
	var old_ap = r.actor("hero").ap
	expect(r.equip("hero", "lamp_charm").ok, "Equipment outside combat")
	expect(r.actor("hero").ap == old_ap, "Equipment does not refresh AP")
	expect(r.save_game().ok and r.save_game().ok, "Repeated atomic save")
	var loaded = fresh(1)
	expect(loaded.load_game("user://test-run.json").ok, "Load stable checkpoint")
	# JSON numbers are parsed as floats; compare the serialization contract, not native int tags.
	expect(loaded.data == JSON.parse_string(JSON.stringify(r.data)), "State round-trip including RNG and inventory")
	expect(loaded.rng.state == r.rng.state, "RNG state survives save/load exactly")
	expect(loaded.end_day().ok, "Loaded numeric state supports subsequent gameplay")
	for i in range(14):
		r.end_day()
	expect(r.data.day > 12 and r.data.status == "exploring", "No deadline")
	r.actor("hero").position = r.data.exit
	expect(r.data.status == "exploring", "Arriving at extraction never ends run")
	expect(r.extraction_preview().absent.has("lorne"), "Remote member in extraction warning")
	expect(r.extract().ok and r.data.status == "extracted", "Explicit extraction")
	test_combat()
	test_environment()
	print("RULE TESTS: %d checks, %d failures; %d map seeds" % [checks, failures.size(), seed_count])
	for error in failures:
		printerr(error)
	quit(0 if failures.is_empty() else 1)

func test_combat() -> void:
	var r = fresh()
	var b = encounter(r, ["boar"], ["hero"])
	expect(r.actor("hero").ap == r.actor("hero").ap_max - 2, "First deployment charge")
	var wrong_actor = "enemy_0" if b.current == "hero" else "hero"
	expect(b.current == "hero", "Fast hero acts before boar")
	var original_time = b.next_time.hero
	r.actor("hero").energy = 100
	expect(b.request_ultimate("hero").ok, "Ultimate queues at boundary")
	b.resolve_queued()
	expect(r.actor("hero").energy == 0 and b.next_time.hero == original_time, "Ultimate clears energy but preserves normal action")
	if b.outcome == "":
		var mp_before = r.actor("hero").mp
		b.act("trail_shot", "enemy_0")
		expect(r.actor("hero").mp == mp_before - 8, "Skill MP charge")
		expect(r.actor("hero").energy == 30, "Personal attack charge")
	r = fresh()
	fixture_ally(r, "lorne", r.data.start)
	fixture_ally(r, "eve", r.data.start)
	b = encounter(r, ["boar"], ["hero", "lorne"])
	while b.current != "hero" and b.outcome == "":
		if b.enemies.has(b.current):
			b.step_auto()
		else:
			b.act("guard")
	var first_ap = r.actor("hero").ap
	expect(b.swap("eve").ok, "Same-cell reserve swap")
	expect(r.actor("eve").ap == r.actor("eve").ap_max - 2, "Reserve first deploy pays")
	expect(b.paid.has("hero") and b.paid.has("eve") and r.actor("hero").ap == first_ap, "Paid collection persists across swap")
	r = fresh()
	r.actor("hero").ap = 0
	b = encounter(r, ["spider"], ["hero"], true)
	expect(r.actor("hero").ap == 0, "Ambush charge clamps at zero")
	expect(b.next_time.enemy_0 < 1000.0 / Catalog.ENEMIES.spider.speed, "Ambush initial action advanced")
	r = fresh()
	b = encounter(r, ["boar"], ["hero"])
	r.actor("hero").hp = 0
	b.enemies.enemy_0.hp = 0
	b.check_end()
	expect(b.outcome == "defeat" and r.data.status == "failed", "Simultaneous wipe is defeat")
	r = fresh()
	fixture_ally(r, "lorne", r.data.start)
	b = encounter(r, ["boar"], ["hero"])
	r.actor("hero").hp = 0
	b.check_end()
	expect(b.outcome == "" and b.active.has("lorne"), "Healthy same-cell reserve continues")
	for id in b.enemies:
		b.enemies[id].hp = 0
	b.check_end()
	expect(b.outcome == "victory" and r.actor("hero").hp == 1, "Victory revives this battle's downed allies")
	expect(r.actor("lorne").hp > 1, "Victory does not lower healed HP")
	r = fresh()
	var far = r.actor("lorne").position
	fixture_ally(r, "lorne", far)
	b = encounter(r, ["boar"], ["lorne"])
	r.actor("lorne").hp = 0
	b.check_end()
	expect(b.outcome == "defeat" and r.data.status == "exploring", "Remote nonprotagonist defeat does not end expedition")
	expect(r.actor("lorne").position == far and r.actor("lorne").hp == 0, "Defeated actors remain wounded at encounter")
	# These data make a friendly item usable during its own normal action.
	r = fresh()
	b = encounter(r, ["boar"], ["hero"])
	r.actor("hero").hp = 20
	var turn_before = b.current
	var time_before = b.next_time.hero
	expect(b.use_item("salve", "hero").ok and b.use_item("salve", "hero").ok, "Multiple items in one turn")
	expect(b.current == turn_before and b.next_time.hero == time_before, "Items do not consume normal action")

func test_environment() -> void:
	var r = fresh()
	var source = "0,0"
	var neighbor = "1,0"
	var further = "2,0"
	for k in [source, neighbor, further]:
		r.data.tiles[k].terrain = "forest"
		r.data.tiles[k].burning = false
		r.data.tiles[k].wet_until = 0
	expect(r.apply_environment(source, "ignite"), "Ignite dry forest")
	var fuel = r.data.tiles[source].fuel
	# Choose a deterministic sunny next day to inspect the propagation boundary.
	for seed_value in range(100):
		r.rng.seed = seed_value
		var probe = RandomNumberGenerator.new()
		probe.state = r.rng.state
		if probe.randf() >= 0.28:
			break
	r.end_day()
	expect(r.data.tiles[source].fuel == fuel - 1, "Fuel consumed once per day")
	expect(r.data.tiles[neighbor].burning, "Six-neighbor fire propagation")
	expect(not r.data.tiles[further].burning, "New ignition does not chain in same day")
	expect(r.apply_environment(neighbor, "wet"), "Water extinguishes current tile")
	expect(not r.data.tiles[neighbor].burning, "Extinguished tile persists")
	var before = r.data.tiles[neighbor].wet_until
	expect(not r.apply_environment(neighbor, "ignite"), "Wet tile cannot ignite")
	expect(r.data.tiles[neighbor].wet_until == before, "Rejected environment action has no mutation")
