extends SceneTree
## Adversarial state fixtures; these are not claimed as full player journeys.
const Run = preload("res://scripts/domain/expedition.gd")
const Combat = preload("res://scripts/domain/battle.gd")
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

func battle(r: RefCounted, ids: Array) -> RefCounted:
	var p = r.actor("hero").position
	r.data.tiles[p].enemies = ["boar"]
	var b = Combat.new()
	expect(b.begin(r, {"position": p, "origin": p, "movers": [], "npc": "", "ambush": false}, ids).ok, "Edge encounter starts")
	return b

func sunny(r: RefCounted, rain: bool) -> void:
	for seed_value in range(100):
		r.rng.seed = seed_value
		if (r.next_weather() == "rain") == rain:
			return

func execute() -> void:
	checkpoint_edges()
	day_edges()
	combat_edges()
	story_modifiers()
	print("EDGE TESTS: %d checks, %d failures (invalid saves, checkpoint fees, weather, isolation, speed, policies, epilogue modifiers)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func checkpoint_edges() -> void:
	var r = fresh()
	expect(r.save_game().ok, "Valid edge checkpoint")
	var valid = JSON.parse_string(FileAccess.get_file_as_string(r.save_path))
	for issue in ["version", "old_version", "day", "name", "speed", "energy", "maximum", "fractional", "equipment", "choices", "explored"]:
		var broken = valid.duplicate(true)
		match issue:
			"version": broken.version = {}
			"old_version": broken.version = 1
			"day": broken.day = []
			"name": broken.actors.hero.erase("name")
			"speed": broken.actors.hero.speed = 0
			"energy": broken.actors.hero.energy = 101
			"maximum": broken.actors.hero.hp_max = "wrong"
			"fractional": broken.actors.hero.inventory.salve = 0.5
			"equipment": broken.actors.hero.inventory.trail_blade = 0
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
	var original_ap = r.actor("hero").ap
	var b = battle(r, ["hero"])
	expect(r.actor("hero").ap == original_ap - 2, "Live encounter pays fee")
	expect(not r.save_game().ok, "No partial battle checkpoint")
	var continued = fresh()
	expect(continued.load_game().ok, "Load prebattle checkpoint")
	expect(continued.actor("hero").ap == original_ap and not continued.data.pending_battle.is_empty(), "Checkpoint precedes deployment fee")
	var resumed = Combat.new()
	expect(resumed.begin(continued, continued.data.pending_battle, ["hero"]).ok, "Resume pending encounter")
	expect(continued.actor("hero").ap == original_ap - 2, "Resume charges exactly once from checkpoint")
	for id in resumed.enemies:
		resumed.enemies[id].hp = 0
	resumed.check_end()
	var loot = continued.actor("hero").inventory.salve
	resumed.check_end()
	expect(continued.actor("hero").inventory.salve == loot, "Repeated finish cannot duplicate victory reward")
	b.retreat()

func day_edges() -> void:
	var r = fresh()
	var state = r.rng.state
	var predicted = r.next_weather()
	expect(r.next_weather() == predicted and r.rng.state == state, "Forecast reads without consuming RNG")
	expect(r.end_day().ok and r.data.weather == predicted, "Next day matches forecast")
	r = fresh()
	ally(r, "eve")
	r.actor("hero").hp = 0
	r.actor("hero").ap = 0
	r.actor("hero").mp = 0
	r.actor("hero").energy = 71
	expect(r.end_day().ok, "Healthy partner keeps day progression available")
	expect(r.actor("hero").hp == 0 and r.actor("hero").mp == 0 and r.actor("hero").ap == r.actor("hero").ap_max and r.actor("hero").energy == 71, "Daily AP resets but injury is not cured and energy retained")
	var pos = r.actor("hero").position
	r.data.tiles[pos].terrain = "forest"
	var terrain_before = r.data.tiles.duplicate(true)
	sunny(r, true)
	expect(r.end_day().ok and r.data.weather == "rain" and r.data.tiles == terrain_before,
		"Rain advances weather with no map state changes")
	expect(r.heal_skill("eve", "hero").ok and r.actor("hero").hp == 38, "Same-cell medic can actually rescue")
	expect(r.actor("eve").energy == 0, "Map support never charges ultimate")
	var neighbor = Hex.neighbors(pos, r.data.tiles)[0]
	var before = JSON.stringify(r.data.actors)
	expect(not r.move(["hero", "hero"], neighbor).ok and JSON.stringify(r.data.actors) == before, "Duplicate group move is atomic and rejected")

func combat_edges() -> void:
	var r = fresh()
	ally(r, "lorne")
	var b = battle(r, ["hero", "lorne"])
	var simulated = b.timeline(60)
	var counts = {"hero": 0, "lorne": 0, "enemy_0": 0}
	for entry in simulated:
		counts[entry.id] += 1
	expect(counts.lorne > counts.enemy_0 and counts.hero > counts.enemy_0, "Fast units act more often over same continuous timeline")
	var untouched = "0,0"
	r.data.tiles[untouched].terrain = "forest"
	var remote = JSON.stringify(r.data.tiles[untouched])
	var day = r.data.day
	while b.enemies.has(b.current):
		b.step_auto()
	var hero_ap = r.actor("hero").ap
	var outgoing = b.current
	ally(r, "eve")
	expect(b.swap("eve").ok, "Reserve enters on normal action")
	for turn in range(20):
		if b.current == "eve":
			break
		if b.enemies.has(b.current): b.step_auto()
		else: b.act("guard")
	expect(b.swap(outgoing).ok and r.actor("hero").ap == hero_ap, "Previously deployed reserve is not recharged")
	expect(JSON.stringify(r.data.tiles[untouched]) == remote and r.data.day == day, "Battle leaves remote tiles and date unchanged")
	b.retreat()
	for skill_id in ["ember", "sunfall"]:
		for condition in ["dry", "rain", "wet"]:
			r = fresh()
			ally(r, "ember")
			var tile = r.data.tiles[r.actor("hero").position]
			tile.terrain = "forest"
			r.data.weather = "rain" if condition == "rain" else "sun"
			b = battle(r, ["ember"])
			if condition == "wet":
				b._apply_field_effect("wet")
			r.actor("ember").energy = 100 if skill_id == "sunfall" else 0
			b.auto_mode = true
			b.step_auto()
			expect(b.events.any(func(event): return event.get("skill_id") == skill_id),
				"Automatic battle casts %s in a %s forest" % [skill_id, condition])
			expect(b.field_view().burning == (condition == "dry") and tile.terrain == "forest",
				"Automatic %s follows battlefield ignition rules in a %s forest" % [skill_id, condition])
	r = fresh()
	ally(r, "grit")
	b = battle(r, ["hero", "grit"])
	r.actor("hero").hp = 30
	b._hurt("hero", 10)
	expect(r.actor("hero").hp == 22, "Present protector reduces damage to injured ally")
	r.actor("grit").hp = 0
	b._hurt("hero", 10)
	expect(r.actor("hero").hp == 12, "Downed protector does not grant protection")
	b.retreat()

func story_modifiers() -> void:
	var r = fresh()
	var story = Story.new(r)
	for id in Catalog.COMPANIONS:
		r.actor(id).joined = true
		r.actor(id).hp = 0
		expect(story.character_ending(id).text.contains(r.actor(id).name), "Injury is reflected in the ending " + id)
