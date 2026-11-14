extends SceneTree
## Adversarial state fixtures; these are not claimed as full player journeys.
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func fresh(profession: String = "wayfarer") -> RefCounted:
	var r = Run.new()
	r.save_path = "user://test-edges.json"
	r.new_run(20261104, profession)
	return r

func ally(r: RefCounted, id: String) -> void:
	r.actor(id).position = r.actor("hero").position
	r.join_companion(id)

func execute() -> void:
	checkpoint_edges()
	day_edges()
	story_modifiers()
	print("EDGE TESTS: %d checks, %d failures (invalid saves, encounter checkpoints, weather and epilogue modifiers)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func checkpoint_edges() -> void:
	var r = fresh()
	expect(r.save_game().ok, "Valid edge checkpoint")
	var valid = JSON.parse_string(FileAccess.get_file_as_string(r.save_path))
	for issue in ["version", "old_version", "day", "steps", "name", "speed", "energy", "maximum", "fractional", "equipment", "choices", "explored"]:
		var broken = valid.duplicate(true)
		match issue:
			"version": broken.version = {}
			"old_version": broken.version = 1
			"day": broken.day = []
			"steps": broken.steps_today = 5
			"name": broken.actors.hero.erase("name")
			"speed": broken.actors.hero.speed = 0
			"energy": broken.actors.hero.energy = 101
			"maximum": broken.actors.hero.hp_max = "wrong"
			"fractional": broken.actors.hero.inventory.salve = 0.5
			"equipment": broken.actors.hero.equipment.weapon = "999999"
			"choices": broken.choices = {}
			"explored": broken.explored["99,99"] = true
		var path = "user://test-invalid.json"
		var file = FileAccess.open(path, FileAccess.WRITE)
		var raw = JSON.stringify(broken)
		file.store_string(raw)
		file.close()
		var before = JSON.stringify(r.data)
		expect(not r.load_game(path).ok, "Reject corrupt field " + issue)
		expect(JSON.stringify(r.data) == before and FileAccess.get_file_as_string(path) == raw, "Rejected load leaves memory and source intact " + issue)
	var original_steps = r.remaining_steps()
	var position: String = r.actor("hero").position
	r.data.tiles[position].enemies = ["boar"]
	var b := Chess.new()
	expect(b.begin(r, {"position": position, "origin": position, "npc": "", "ambush": false}, r.card_deck()).ok,
		"Edge encounter starts")
	expect(r.remaining_steps() == original_steps, "Live encounter does not spend movement")
	expect(not r.save_game().ok, "No partial battle checkpoint")
	var continued = fresh()
	expect(continued.load_game().ok, "Load prebattle checkpoint")
	expect(continued.remaining_steps() == original_steps and not continued.data.pending_battle.is_empty(), "Checkpoint preserves pending battle and steps")
	var resumed := Chess.new()
	expect(resumed.begin(continued, continued.data.pending_battle, continued.card_deck()).ok, "Resume pending encounter")
	expect(continued.remaining_steps() == original_steps, "Resume leaves movement unchanged")
	resumed.commanders[Chess.ENEMY].hp = 0
	resumed._check_outcome()
	var loot: int = continued.actor("hero").inventory.salve
	var coins: int = continued.data.lamp_coins
	resumed._check_outcome()
	expect(resumed.outcome == "victory" and continued.actor("hero").inventory.salve == loot
		and continued.data.lamp_coins == coins, "Repeated finish cannot duplicate victory rewards")

func day_edges() -> void:
	var r = fresh()
	var state = r.rng.state
	var predicted = r.next_weather()
	expect(r.next_weather() == predicted and r.rng.state == state, "Forecast reads without consuming RNG")
	var pos = r.actor("hero").position
	var neighbor = Hex.neighbors(pos, r.data.tiles).filter(func(cell): return Hex.is_land(r.data.tiles, cell))[0]
	r.data.tiles[neighbor].enemies.clear()
	r.data.tiles[neighbor].terrain = "mountain"
	ally(r, "eve")
	var hero = r.actor("hero")
	hero.hp = 21
	hero.mp = 0
	hero.energy = 71
	for step in range(1, 5):
		var destination = neighbor if step % 2 == 1 else pos
		expect(r.move(destination).ok and r.remaining_steps() == 5 - step and r.data.day == 1,
			"Each land move, including mountains and return trips, takes one step")
	r.data.tiles[neighbor].enemies = ["boar"]
	expect(r.move(neighbor).battle and r.data.day == 2 and r.remaining_steps() == 5 and r.data.weather == predicted,
		"Fifth step advances weather before the encounter")
	expect(hero.hp == 21 and hero.mp == 0 and hero.energy == 71 and r.actor("eve").position == neighbor,
		"Day rollover preserves resources and companions follow the traveler")
	expect(not r.move(pos).ok and r.remaining_steps() == 5, "An unresolved battle blocks travel without spending a step")
	r.data.pending_battle.clear()
	r.data.tiles[neighbor].enemies.clear()
	hero.hp = 0
	expect(not r.move(pos).ok and r.actor("eve").position == neighbor, "A healthy companion cannot move independently")
	expect(r.use_item("eve", "hero", "salve").ok and hero.hp > 0, "A companion can spend a salve to rescue the traveler")
	expect(r.actor("eve").energy == 0, "Map support never charges ultimate")

func story_modifiers() -> void:
	var r = fresh()
	var story = Story.new(r)
	for id in Catalog.COMPANIONS:
		r.actor(id).joined = true
		r.actor(id).hp = 0
		expect(story.character_ending(id).text.contains(r.actor(id).name), "Injury is reflected in the ending " + id)
