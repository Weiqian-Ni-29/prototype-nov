extends SceneTree

const Run = preload("res://scripts/domain/expedition.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Opening = preload("res://scripts/domain/opening_story.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Journey = preload("res://scripts/domain/journey.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		print("FAIL: ", label)
		failures += 1

func execute() -> void:
	expect(Opening.DEPARTURE.length() <= 35 and "酒馆被鲸吞了" in Opening.DEPARTURE
		and "找出口" in Opening.DEPARTURE, "The opening states the predicament and goal in one line")
	var run := Run.new()
	run.save_path = "user://test-whale-story.json"
	run.new_run(41, "wayfarer", true)
	var narrative := Story.new(run)
	for id in Catalog.COMPANIONS:
		expect(narrative.character_records(id).is_empty(), "Unknown profile stays hidden: " + id)
		run.data.story[id].met = true
		var records := narrative.character_records(id)
		expect(records.size() == 1 and not records[0].body.is_empty() and records[0].body.length() <= 40,
			"Each known companion gets one short story line: " + id)
	run.data.status = "won"
	expect("刚才那杯" in narrative.main_ending().text, "The ending returns to the opening joke")
	run.data.status = "exploring"
	check_saved_story_migration(run)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(run.save_path + suffix)
	print("STORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_saved_story_migration(run: RefCounted) -> void:
	run.data.version = 14
	run.actor("hero").name = "旧主角名"
	run.data.flags.hero_identity_revealed = true
	run.data.story.seasons.personal_choice = "god_a"
	run.data.pending_story_rewards = {"kind": "starter_deck", "source": "旧序章", "items": []}
	run.data.lamp_coins = 24
	var route: Array = run.data.journey.route.duplicate()
	var deck: Array = run.card_deck()
	expect(run.save_game().ok, "The old campaign checkpoint is writable")
	var continued := Run.new()
	expect(continued.load_game(run.save_path).ok, "The old campaign still loads")
	expect(continued.data.journey.route == route and continued.data.lamp_coins == 24 and continued.card_deck() == deck,
		"Story migration keeps route, wallet and deck")
	expect(continued.actor("hero").name == "旅人" and not continued.data.flags.has("hero_identity_revealed")
		and not continued.data.story.seasons.has("personal_choice") and continued.data.pending_story_rewards.source == "酒馆老板",
		"Old identity and story choices are no longer surfaced")
	expect(Journey.encounter(continued.data).scene in ["tavern", "belly"], "Resuming opens the matching scene in the whale")
