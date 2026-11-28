extends SceneTree
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
	var r = fresh()
	var remote: String = r.actor("lorne").position
	fixture_ally(r, "lorne", remote)
	r.actor("lorne").inventory.trail_food = 1
	expect(not r.transfer("lorne", "hero", "trail_food", 1).ok, "No remote inventory transfer")
	r.actor("lorne").position = r.actor("hero").position
	r.actor("hero").hp = 1
	expect(r.equip("hero", r.actor("hero").equipment.accessory).ok, "Equipment outside combat")
	expect(r.save_game().ok and r.save_game().ok, "Repeated atomic save")
	var loaded = fresh(1)
	expect(loaded.load_game("user://test-run.json").ok, "Load stable checkpoint")
	# JSON numbers are parsed as floats and dictionary equality is type-strict,
	# so normalize both sides through the serialization contract before comparing.
	expect(JSON.parse_string(JSON.stringify(loaded.data)) == JSON.parse_string(JSON.stringify(r.data)),
		"State round-trip including RNG and inventory")
	expect(loaded.rng.state == r.rng.state, "RNG state survives save/load exactly")
	test_combat()
	test_legacy_terrain()
	print("RULE TESTS: %d checks, %d failures" % [checks, failures.size()])
	for error in failures:
		printerr(error)
	quit(0 if failures.is_empty() else 1)

func test_combat() -> void:
	var run = fresh()
	var position: String = run.data.start
	run.data.tiles[position].terrain = "forest"
	run.data.tiles[position].enemies = ["boar"]
	var encounter = {"position": position, "origin": position, "npc": "", "ambush": true}
	var battle := Chess.new()
	expect(battle.begin(run, encounter, run.card_deck()).ok, "Ambush starts a real chess encounter")
	expect(battle.turn == Chess.ENEMY, "An ambush starts on the enemy turn")
	var tiles_before: Dictionary = run.data.tiles.duplicate(true)
	battle.enemy_turn()
	expect(battle.retreat() and run.data.tiles == tiles_before,
		"Retreat leaves the terrain and enemies intact")
	battle = Chess.new()
	encounter.ambush = false
	expect(battle.begin(run, encounter, run.card_deck()).ok and battle.can_act(), "A normal rematch begins on the player's turn")
	battle.commanders[Chess.ENEMY].hp = 0
	battle._check_outcome()
	tiles_before[position].enemies = []
	expect(battle.outcome == "victory" and run.data.tiles == tiles_before,
		"Victory clears only the local encounter")

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
