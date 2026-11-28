extends SceneTree
## Adversarial state fixtures; these are not claimed as full player journeys.
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Story = preload("res://scripts/domain/narrative.gd")
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

func execute() -> void:
	checkpoint_edges()
	story_modifiers()
	print("EDGE TESTS: %d checks, %d failures (invalid saves, encounter checkpoints and epilogue modifiers)" % [checks, failures])
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
			"fractional": broken.actors.hero.inventory.trail_food = 0.5
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
	var position: String = r.actor("hero").position
	r.data.tiles[position].enemies = ["boar"]
	var b := Chess.new()
	expect(b.begin(r, {"position": position, "origin": position, "npc": "", "ambush": false}, r.card_deck()).ok,
		"Edge encounter starts")
	expect(not r.save_game().ok, "No partial battle checkpoint")
	var continued = fresh()
	expect(continued.load_game().ok, "Load prebattle checkpoint")
	expect(not continued.data.pending_battle.is_empty(), "Checkpoint preserves the pending battle")
	var resumed := Chess.new()
	expect(resumed.begin(continued, continued.data.pending_battle, continued.card_deck()).ok, "Resume pending encounter")
	resumed.commanders[Chess.ENEMY].hp = 0
	resumed._check_outcome()
	var inventory: Dictionary = continued.actor("hero").inventory.duplicate()
	var coins: int = continued.data.lamp_coins
	resumed._check_outcome()
	expect(resumed.outcome == "victory" and continued.actor("hero").inventory == inventory
		and continued.data.lamp_coins == coins, "Repeated finish cannot duplicate victory rewards")

func story_modifiers() -> void:
	var r = fresh()
	var story = Story.new(r)
	for id in Catalog.COMPANIONS:
		r.actor(id).joined = true
		r.actor(id).hp = 0
		expect(story.character_ending(id).text.contains(r.actor(id).name), "Injury is reflected in the ending " + id)
