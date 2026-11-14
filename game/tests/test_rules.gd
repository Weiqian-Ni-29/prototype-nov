extends SceneTree
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
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

func execute() -> void:
	var quick = "--quick" in OS.get_cmdline_user_args()
	var seed_count = 12 if quick else 200
	var early_locations = {}
	for seed_value in range(seed_count):
		var generated = Hex.generate(seed_value)
		var tiles = generated.tiles
		expect(tiles.size() == 217, "217 cells seed %d" % seed_value)
		expect(Hex.distance(Hex.coord(generated.start), Hex.coord(generated.boss)) >= 11, "Distant boss seed %d" % seed_value)
		var route = Hex.path(tiles, generated.start, generated.boss, true)
		expect(not route.is_empty(), "Safe boss approach seed %d" % seed_value)
		expect(route.size() - 1 >= 11, "Boss route distance seed %d" % seed_value)
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
				var approachable = not Hex.path(tiles, generated.start, k, true).is_empty() if tiles[k].enemies.is_empty() else Hex.neighbors(k, tiles).any(func(cell): return not Hex.path(tiles, generated.start, cell, true).is_empty())
				expect(approachable, "NPC location has a reachable approach " + id)
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
	r.data.tiles[destination].enemies.clear()
	expect(r.has_visited(r.data.start) and not r.has_visited(destination), "Sight does not count as visiting a tile")
	var original_terrain = r.data.tiles[destination].terrain
	r.data.tiles[destination].terrain = "lake"
	var before_lake = JSON.stringify(r.data)
	var blocked = r.move(destination)
	expect(not blocked.ok and "绕行" in blocked.message and JSON.stringify(r.data) == before_lake,
		"Attempting to enter lake water spends no steps and does not reveal tiles")
	r.data.tiles[destination].terrain = original_terrain
	var before_steps = r.remaining_steps()
	var before_energy = int(r.actor("hero").energy)
	expect(r.move(destination).ok, "Valid move")
	expect(r.has_visited(destination), "Successful movement records the destination as visited")
	expect(r.remaining_steps() == before_steps - 1, "One tile uses one step")
	expect(r.actor("hero").energy == before_energy, "Exploration never charges ultimate")
	var explored = r.data.explored.size()
	r.actor("hero").hp = 0
	expect(not r.move(r.data.start).ok, "A wounded leader cannot move")
	expect(r.data.explored.size() == explored, "Blocked move does not reveal")
	fixture_ally(r, "lorne", r.data.start)
	r.actor("lorne").inventory.trail_food = 1
	expect(not r.transfer("lorne", "hero", "trail_food", 1).ok, "No remote inventory transfer")
	r.actor("lorne").position = r.actor("hero").position
	r.actor("hero").hp = 1
	var steps = r.remaining_steps()
	expect(r.equip("hero", r.actor("hero").equipment.accessory).ok, "Equipment outside combat")
	expect(r.remaining_steps() == steps, "Equipment does not spend movement")
	expect(r.save_game().ok and r.save_game().ok, "Repeated atomic save")
	var loaded = fresh(1)
	expect(loaded.load_game("user://test-run.json").ok, "Load stable checkpoint")
	# JSON numbers are parsed as floats and dictionary equality is type-strict,
	# so normalize both sides through the serialization contract before comparing.
	expect(JSON.parse_string(JSON.stringify(loaded.data)) == JSON.parse_string(JSON.stringify(r.data)),
		"State round-trip including RNG and inventory")
	expect(loaded.rng.state == r.rng.state, "RNG state survives save/load exactly")
	expect(loaded.move(r.data.start).ok, "Loaded numeric state supports subsequent gameplay")
	for i in range(70):
		var next = r.data.start if r.actor("hero").position == destination else destination
		r.move(next)
	expect(r.data.day > 12 and r.data.status == "exploring", "No deadline")
	r.actor("hero").position = r.data.boss
	expect(r.data.status == "exploring" and not r.boss_known(), "Arriving early does not reveal the boss")
	test_combat()
	test_legacy_terrain()
	print("RULE TESTS: %d checks, %d failures; %d map seeds" % [checks, failures.size(), seed_count])
	for error in failures:
		printerr(error)
	quit(0 if failures.is_empty() else 1)

func test_combat() -> void:
	var run = fresh()
	var position: String = run.data.start
	run.data.tiles[position].terrain = "forest"
	run.data.tiles[position].enemies = ["boar"]
	run.data.weather = "rain"
	var encounter = {"position": position, "origin": position, "npc": "", "ambush": true}
	var battle := Chess.new()
	expect(battle.begin(run, encounter, run.card_deck()).ok, "Ambush starts a real chess encounter")
	expect(battle.turn == Chess.ENEMY and battle.weather == "rain" and run.remaining_steps() == Run.STEPS_PER_DAY,
		"An ambush starts on the enemy turn, with expedition weather and no movement cost")
	var tiles_before: Dictionary = run.data.tiles.duplicate(true)
	battle.enemy_turn()
	expect(battle.retreat() and run.data.tiles == tiles_before and run.data.weather == "rain",
		"Retreat leaves the terrain, enemies and weather intact")
	battle = Chess.new()
	encounter.ambush = false
	expect(battle.begin(run, encounter, run.card_deck()).ok and battle.can_act(), "A normal rematch begins on the player's turn")
	battle.commanders[Chess.ENEMY].hp = 0
	battle._check_outcome()
	tiles_before[position].enemies = []
	expect(battle.outcome == "victory" and run.data.tiles == tiles_before,
		"Victory clears only the local encounter")
	var hp_after: int = run.actor("hero").hp
	run._advance_day()
	expect(run.data.tiles == tiles_before and run.actor("hero").hp == hp_after,
		"Battle effects do not spill into day settlement")

func test_legacy_terrain() -> void:
	var r = fresh()
	var position: String = r.data.start
	var checkpoint = Run.new()
	var legacy = r.data.tiles[position]
	legacy.base_terrain = "forest"
	legacy.terrain = "scorched"
	legacy.burning = false
	legacy.fuel = 0
	legacy.wet_until = r.data.day + 1
	r.data.flags.player_ignitions = {position: "hero"}
	r.data.knowledge.hero = {"ignitions": [position]}
	expect(r.save_game().ok and checkpoint.load_game(r.save_path).ok, "Old save with a burned forest still loads")
	var restored = checkpoint.data.tiles[position]
	expect(restored.terrain == "forest" and not restored.has("burning") and not restored.has("fuel") and not restored.has("wet_until"),
		"Loading an old save restores the terrain and strips map fire state")
	expect(not checkpoint.data.flags.has("player_ignitions") and not checkpoint.data.knowledge.hero.has("ignitions"),
		"Old map ignition records are removed")
