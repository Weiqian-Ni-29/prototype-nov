extends SceneTree
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Run = preload("res://scripts/domain/expedition.gd")
const Combat = preload("res://tests/legacy/realtime_battle.gd")
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
	expect(not r.transfer("lorne", "hero", "salve", 1).ok, "No remote inventory transfer")
	r.actor("lorne").position = r.actor("hero").position
	expect(r.use_item("lorne", "hero", "salve").ok, "Physical rescue")
	expect(r.actor("hero").hp > 0, "Rescued actor can act")
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
	test_environment()
	test_elemental_heroes()
	print("RULE TESTS: %d checks, %d failures; %d map seeds" % [checks, failures.size(), seed_count])
	for error in failures:
		printerr(error)
	quit(0 if failures.is_empty() else 1)

func test_combat() -> void:
	var r = fresh()
	var b = encounter(r, ["boar"], ["hero"])
	expect(r.remaining_steps() == Run.STEPS_PER_DAY and b.deployed.has("hero"), "Battle deployment does not spend steps")
	var wrong_actor = "enemy_0" if b.current == "hero" else "hero"
	expect(b.current == "hero", "Fast hero acts before boar")
	var original_time = b.next_time.hero
	r.actor("hero").energy = 100
	expect(b.request_ultimate("hero").ok, "Ultimate queues at boundary")
	b.resolve_queued()
	expect(r.actor("hero").energy == 0 and b.next_time.hero == original_time, "Ultimate clears energy but preserves normal action")
	if b.outcome == "":
		var mp_before = r.actor("hero").mp
		b.act("gravity", "enemy_0")
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
	expect(b.swap("eve").ok, "Same-cell reserve swap")
	expect(r.remaining_steps() == Run.STEPS_PER_DAY, "Reserve deployment does not spend steps")
	expect(b.deployed.has("hero") and b.deployed.has("eve"), "Participants tracked across swaps")
	r = fresh()
	b = encounter(r, ["spider"], ["hero"], true)
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
	var position = r.data.start
	r.data.weather = "sun"
	r.data.tiles[position].terrain = "forest"
	r.actor("hero").skill = "ember"
	fixture_ally(r, "tide", position)
	var b = encounter(r, ["lamp_boss"], ["hero", "tide"])
	var tiles_before = r.data.tiles.duplicate(true)
	b.current = "hero"
	expect(b.act("ember", "enemy_0").ok and b.field_view().burning, "Fire skill ignites the current forest battle")
	expect(is_equal_approx(b.environment_multiplier("fire", "normal"), 1.1), "Burning boosts fire skills")
	b.current = "tide"
	expect(b.act("torrent", "enemy_0").ok and b.field_view().wet and b.field_view().burning,
		"Water wets the battlefield without extinguishing an active fire")
	expect(is_equal_approx(b.environment_multiplier("fire", "normal"), 1.1 * 0.8), "Wet field weakens fire skills")
	var ally_hp: int = r.actor("hero").hp
	var enemy_hp: int = b.unit("enemy_0").hp
	b.clock = b.fire_tick
	b._settle_fire()
	expect(r.actor("hero").hp == ally_hp - ceili(r.actor("hero").hp_max * 0.08)
		and b.unit("enemy_0").hp == enemy_hp - ceili(b.unit("enemy_0").hp_max * 0.08),
		"Fire still ticks on both sides of the wet battlefield")
	var checkpoint = Run.new()
	var loaded = checkpoint.load_game(r.save_path)
	expect(loaded.ok, "The battle checkpoint still loads: " + str(loaded))
	var saved_tile: Dictionary = checkpoint.data.get("tiles", {}).get(position, {})
	expect(saved_tile.get("terrain") == "forest" and not saved_tile.has("burning") and not saved_tile.has("wet_until"),
		"The battle checkpoint has no field effects")
	expect(b.retreat().ok and r.data.tiles == tiles_before, "Retreat leaves the entire map intact")
	expect(b.begin(r, {"position": position, "origin": position, "movers": [], "npc": "", "ambush": false}, ["hero", "tide"]).ok
		and not b.field_view().burning and not b.field_view().wet, "A rematch starts with a fresh battlefield")
	b.current = "hero"
	expect(b.act("ember", "enemy_0").ok and b.field_view().burning, "The forest can ignite again within a new battle")
	b.unit("enemy_0").hp = 0
	b.check_end()
	var cleared_tile = tiles_before[position].duplicate(true)
	cleared_tile.enemies = []
	tiles_before[position] = cleared_tile
	expect(b.outcome == "victory" and r.data.tiles == tiles_before, "Victory only clears the encounter on the map")
	var hp_after: int = r.actor("hero").hp
	r._advance_day()
	expect(r.data.tiles == tiles_before and r.actor("hero").hp == hp_after,
		"No post-battle fire damage, spreading or terrain changes during day settlement")

	var legacy = r.data.tiles[position]
	legacy.base_terrain = "forest"
	legacy.terrain = "scorched"
	legacy.burning = false
	legacy.fuel = 0
	legacy.wet_until = r.data.day + 1
	r.data.flags.player_ignitions = {position: "hero"}
	r.data.knowledge.hero.ignitions = [position]
	expect(r.save_game().ok and checkpoint.load_game(r.save_path).ok, "Old save with a burned forest still loads")
	var restored = checkpoint.data.tiles[position]
	expect(restored.terrain == "forest" and not restored.has("burning") and not restored.has("fuel") and not restored.has("wet_until"),
		"Loading an old save restores the terrain and strips map fire state")
	expect(not checkpoint.data.flags.has("player_ignitions") and not checkpoint.data.knowledge.hero.has("ignitions"),
		"Old map ignition records are removed")

func test_elemental_heroes() -> void:
	for profession in ["frost_archer", "storm_caller", "wind_runner", "stone_guard"]:
		var r = fresh()
		var position = r.data.start
		fixture_ally(r, profession, position)
		var hero = r.actor(profession)
		var definition = Catalog.COMPANIONS[profession]
		expect(hero.name == definition.name and hero.element == definition.element, "Selected hero joins the expedition with the right element")
		fixture_ally(r, "tide", hero.position)
		var b = encounter(r, ["lamp_boss", "furnace_elite"], [profession, "tide"])
		var initial_damage = b.damage_preview(profession, "enemy_0", hero.skill)
		b.current = "tide"
		expect(b.act("torrent", "enemy_1").ok and b.wet, "Water skill supplies the battlefield interaction")
		b.current = profession
		var mp: int = hero.mp
		var initial_hp: int = b.unit("enemy_0").hp
		var second_hp: int = b.unit("enemy_1").hp
		expect(b.act(hero.skill, "enemy_0").ok and hero.mp == mp - Catalog.SKILLS[hero.skill].mp,
			"Hero's primary skill is usable and pays its magic cost: " + profession)
		match hero.element:
			"ice":
				expect(b.unit("enemy_0").slow == 3 and b.unit("enemy_1").slow == 0, "Wet ice attack slows its chosen target")
			"lightning":
				expect(initial_hp - b.unit("enemy_0").hp > initial_damage, "Wet lightning actually deals bonus damage")
			"wind":
				expect(b.unit("enemy_0").hp < initial_hp and b.unit("enemy_1").hp < second_hp, "Windblade strikes every enemy")
			"earth":
				expect(b.unit("enemy_0").hp < initial_hp and b.unit("enemy_1").hp == second_hp, "Stone spike strikes one enemy")
		hero.energy = 100
		expect(b.request_ultimate(profession).ok, "Hero can queue a fully charged ultimate: " + profession)
		b.resolve_queued()
		expect(hero.energy == 0 and b.events[-1].skill_id == hero.ultimate, "Ultimate releases through the normal queue")
		match hero.element:
			"ice":
				expect(b.unit("enemy_1").slow == 3, "Ice ultimate slows all surviving enemies")
			"lightning":
				expect(b.unit("enemy_1").hp < second_hp, "Thunderstorm reaches the second enemy")
			"wind":
				expect(b.haste_turns.get(profession) == 2 and b.haste_turns.get("tide") == 2, "Wind ultimate hastens all active allies")
				var interval: float = 1000.0 / r.stat(profession, "speed")
				for remaining in [1, 0]:
					b.current = profession
					var action_clock: float = b.clock
					expect(b.act("guard").ok and is_equal_approx(b.next_time[profession], action_clock + interval / 1.25)
						and b.haste_turns.get(profession, 0) == remaining, "Haste shortens exactly two scheduled intervals")
				b.current = profession
				var action_clock: float = b.clock
				expect(b.act("guard").ok and is_equal_approx(b.next_time[profession], action_clock + interval), "Haste expires")
			"earth":
				expect(hero.shield == 42 and r.actor("tide").shield == 42, "Stonewall shields all active allies")
		expect(b.retreat().ok, "Hero leaves the encounter")
		var loaded = fresh(1)
		expect(loaded.load_game(r.save_path).ok and loaded.actor(profession).joined
			and loaded.actor(profession).name == definition.name, "Elemental hero survives a normal save and continue")
