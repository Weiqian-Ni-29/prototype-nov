extends SceneTree
const Run = preload("res://scripts/domain/expedition.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Opening = preload("res://scripts/domain/opening_story.gd")
const Nodes = preload("res://scripts/domain/map_nodes.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func unrelated_state(run: RefCounted) -> Dictionary:
	var state = run.data.duplicate(true)
	for field in ["story", "log", "transaction", "rng_state"]:
		state.erase(field)
	return state

func has_option(result: Dictionary, id: String) -> bool:
	return result.get("options", []).any(func(option): return option.id == id and option.get("enabled", true))

func check_personal_blocked(story: RefCounted, run: RefCounted, visitor: String, subject: String, reason: String) -> void:
	var before = unrelated_state(run)
	var original = run.data.story[subject].get("personal_choice", "")
	expect(not story.personal_quest(visitor, subject).ok, subject + " cannot open personal quest: " + reason)
	for option in ["quest", "personal_a", "personal_b"]:
		expect(not story.choose(visitor, subject, option).ok, subject + " rejects " + option + ": " + reason)
	expect(unrelated_state(run) == before and run.data.story[subject].get("personal_choice", "") == original,
		subject + " rejected personal interaction preserves state: " + reason)

func check_personal_choices() -> void:
	var responses = {}
	var endings = {}
	for id in Catalog.COMPANIONS:
		var definition: Dictionary = Story.PERSONAL_QUESTS.get(id, {})
		expect(definition.has_all(["title", "text", "personal_a", "personal_b", "pending"]), "Complete personal quest " + id)
		if not definition.has_all(["title", "text", "personal_a", "personal_b", "pending"]):
			continue
		var branch_responses: Array = []
		var branch_endings: Array = []
		var stored_choices: Array = []
		for branch in ["personal_a", "personal_b"]:
			var run = Run.new()
			run.save_path = "user://test-personal-quest.json"
			run.new_run(41, "wayfarer")
			var story = Story.new(run)
			var person = run.actor(id)
			var hero = run.actor("hero")
			hero.position = person.position
			run.data.tiles[person.position].enemies.clear()
			check_personal_blocked(story, run, "hero", id, "not recruited")
			expect(story.choose("hero", id, "join").ok, id + " joins before personal quest")
			expect(str(run.data.story[id].get("personal_choice", "")).is_empty(), id + " recruitment does not auto-select a branch")
			run.data.story[id].erase("personal_choice")
			expect(run.save_game().ok, id + " save old unchosen state")
			var old = Run.new()
			expect(old.load_game(run.save_path).ok and str(old.data.story[id].get("personal_choice", "")).is_empty(), id + " old save stays unchosen")
			var old_story = Story.new(old)
			expect(has_option(old_story.dialogue("hero", id), "quest") and old_story.personal_quest("hero", id).ok, id + " old save can start personal quest")
			old.data.status = "won"
			expect(str(old_story.character_ending(id).text).contains(definition.pending), id + " unchosen ending retains unfinished concerns")
			hero.position = run.data.start
			check_personal_blocked(story, run, "hero", id, "different tiles")
			hero.position = person.position
			hero.hp = 0
			check_personal_blocked(story, run, "hero", id, "visitor wounded")
			hero.hp = hero.hp_max
			person.hp = 0
			check_personal_blocked(story, run, "hero", id, "subject wounded")
			person.hp = person.hp_max
			var ally_id = "cen" if id == "lorne" else "lorne"
			var ally = run.actor(ally_id)
			ally.position = person.position
			check_personal_blocked(story, run, ally_id, id, "visitor not recruited")
			expect(story.choose("hero", ally_id, "join").ok, "Recruit local visitor for " + id)
			var visitor = "hero" if branch == "personal_a" else ally_id
			run.actor(visitor).ap = 0
			var before = unrelated_state(run)
			var dialogue = story.dialogue(visitor, id)
			expect(dialogue.ok and has_option(dialogue, "quest"), id + " joined dialogue offers personal quest")
			var open = story.choose(visitor, id, "quest")
			expect(open.ok and open.get("quest", false), id + " quest routes to its own full-text scene")
			var quest = story.personal_quest(visitor, id)
			expect(quest.ok and quest.has_all(["title", "text", "options", "pose"])
				and quest.get("title") == definition.title and quest.get("text") == definition.text
				and has_option(quest, "personal_a") and has_option(quest, "personal_b"), id + " both choices follow the complete personal story")
			expect(unrelated_state(run) == before and str(run.data.story[id].get("personal_choice", "")).is_empty(), id + " reading personal quest does not spend or select")
			var story_before = run.data.story.duplicate(true)
			var result = story.choose(visitor, id, branch)
			var response = str(result.get("response", ""))
			expect(result.ok and not response.is_empty() and response == definition[branch].response, id + " personalized response for " + branch)
			expect(unrelated_state(run) == before, id + " choice changes no AP, inventory, coins, position, map or battle state")
			var stored = run.data.story[id].get("personal_choice", "")
			expect(not str(stored).is_empty(), id + " records personal decision")
			story_before[id]["personal_choice"] = stored
			expect(run.data.story == story_before, id + " choice modifies only this companion's personal decision")
			stored_choices.append(stored)
			var recall = story.dialogue(visitor, id)
			expect(recall.ok and str(recall.text).contains(response) and not has_option(recall, "quest"), id + " normal dialogue recalls chosen response")
			for repeated in ["personal_a", "personal_b"]:
				expect(not story.choose(visitor, id, repeated).ok and run.data.story[id].get("personal_choice", "") == stored
					and unrelated_state(run) == before, id + " personal choice cannot be repeated or overwritten")
			run.data.status = "won"
			var ending = str(story.character_ending(id).text)
			expect(ending.contains(definition[branch].ending) and not ending.contains(definition.pending), id + " selected ending replaces pending concerns")
			run.data.status = "exploring"
			expect(run.save_game().ok, id + " save " + branch)
			var loaded = Run.new()
			expect(loaded.load_game(run.save_path).ok and loaded.data.story[id].get("personal_choice", "") == stored, id + " reload preserves opaque choice value")
			var continued = Story.new(loaded)
			expect(str(continued.dialogue(visitor, id).get("text", "")).contains(response), id + " reload keeps normal dialogue recall")
			var resumed_state = unrelated_state(loaded)
			for repeated in ["personal_a", "personal_b"]:
				expect(not continued.choose(visitor, id, repeated).ok and loaded.data.story[id].get("personal_choice", "") == stored
					and unrelated_state(loaded) == resumed_state, id + " reload cannot overwrite decision")
			loaded.data.status = "won"
			expect(continued.character_ending(id).text == ending, id + " reload keeps personalized ending")
			branch_responses.append(response)
			branch_endings.append(ending)
			responses[response] = true
			endings[ending] = true
		expect(branch_responses[0] != branch_responses[1] and branch_endings[0] != branch_endings[1]
			and stored_choices[0] != stored_choices[1], id + " two decisions have different responses and endings")
	expect(responses.size() == 50 and endings.size() == 50, "All 25 companions have two individualized outcomes")

func check_personal_boundaries() -> void:
	var run = Run.new()
	run.save_path = "user://test-personal-boundaries.json"
	run.new_run(41, "wayfarer")
	var story = Story.new(run)
	var person = run.actor("lorne")
	run.actor("hero").position = person.position
	run.data.tiles[person.position].enemies.clear()
	expect(story.choose("hero", "lorne", "join").ok, "Recruit boundary fixture companion")
	var before = run.data.duplicate(true)
	expect(story.choose("hero", "lorne", "leave").ok and run.data == before, "Cancel leaves no personal decision")
	expect(not story.choose("hero", "lorne", "personal_unknown").ok and run.data == before, "Unknown personal option cannot mutate the run")
	expect(story.personal_quest("hero", "lorne").ok, "Open personal choices before pending encounter")
	run.data.pending_battle = {"position": person.position}
	check_personal_blocked(story, run, "hero", "lorne", "encounter pending after opening choices")
	run.data.pending_battle.clear()
	run.data.tiles[person.position].enemies = ["bandit"]
	check_personal_blocked(story, run, "hero", "lorne", "danger appeared after opening choices")
	run.data.tiles[person.position].enemies.clear()
	expect(story.choose("hero", "lorne", "personal_a").ok and run.save_game().ok, "Save valid personal choice before corruption tests")
	var loaded = Run.new()
	expect(loaded.load_game(run.save_path).ok, "Load valid personal choice")
	var valid = run.data.duplicate(true)
	before = loaded.data.duplicate(true)
	for invalid in [0, true, "", "a", "personal_unknown", [], {}, null]:
		var corrupt = valid.duplicate(true)
		corrupt.story.lorne.personal_choice = invalid
		var file = FileAccess.open(run.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(corrupt))
		file.close()
		expect(not loaded.load_game(run.save_path).ok and loaded.data == before, "Invalid personal record cannot replace current run: " + str(invalid))

func check_hero_only_mystery() -> void:
	for id in Catalog.COMPANIONS:
		if Catalog.COMPANIONS[id].race in ["恶魔", "神"]:
			expect(Story.HERO_LINES.has(id), id + " retains its protagonist-only hint")
	for id in Story.HERO_LINES:
		var run = Run.new()
		run.new_run(41, "wayfarer")
		var story = Story.new(run)
		var person = run.actor(id)
		var hero = run.actor("hero")
		var companion = run.actor("lorne")
		hero.position = person.position
		companion.position = person.position
		run.data.tiles[person.position].enemies.clear()
		expect(run.join_companion("lorne").ok, "Recruit ordinary visitor")
		var ordinary = story.dialogue("lorne", id)
		var familiar = story.dialogue("hero", id)
		expect(ordinary.ok and str(ordinary.text).contains(Story.COMPANION_LINES[id])
			and not str(ordinary.text).contains(Story.HERO_LINES[id]), id + " ordinary visitor receives no protagonist familiarity")
		expect(familiar.ok and str(familiar.text).contains(Story.HERO_LINES[id])
			and not str(familiar.text).contains("伊文洛"), id + " hero receives the hint without identity reveal")
		hero.position = run.data.start
		expect(not story.dialogue("hero", id).ok, id + " distant hero cannot hear the hint")
		ordinary = story.dialogue("lorne", id)
		expect(ordinary.ok and not str(ordinary.text).contains(Story.HERO_LINES[id]), id + " local companion cannot borrow absent hero familiarity")

func execute() -> void:
	check_personal_choices()
	check_personal_boundaries()
	check_hero_only_mystery()
	var r = Run.new()
	r.save_path = "user://test-veylodan-story.json"
	r.new_run(41, "wayfarer")
	expect(not Opening.WORLD.contains("死亡之神") and not Opening.WORLD.contains("伊文洛"), "Opening preserves the identity reveal")
	expect(r.data.tiles.size() == 217 and Catalog.COMPANIONS.size() == 25, "Map and roster sizes")
	expect(r.actor("hero").name == "旅人" and r.actor("hero").skill == "gravity" and r.actor("hero").element == "none", "Fixed gravity protagonist")
	expect(r.actor("hero").inventory.salve == 3 and r.actor("hero").inventory.ether == 2 and r.actor("hero").inventory.trail_food == 2, "Village supplies")
	expect(r.data.tiles[r.data.boss].enemies.is_empty(), "Boss stays hidden until the fourth story scene")
	var positions = {}
	var story = Story.new(r)
	for id in Catalog.COMPANIONS:
		var person = r.actor(id)
		expect(not positions.has(person.position) and r.data.tiles[person.position].npc == id, "Unique encounter tile " + id)
		positions[person.position] = true
		expect(person.race in ["龙", "恶魔", "神", "人类", "矮人", "精灵"] and Catalog.SKILLS.has(person.skill) and Catalog.SKILLS.has(person.ultimate), "Complete character " + id)
		expect(Nodes.story(r.node_at(person.position)).size() > 0, "Character is placed in a real node " + id)
		r.actor("hero").position = person.position
		if not r.data.tiles[person.position].enemies.is_empty():
			expect(not story.dialogue("hero", id).ok, "The encounter has to be cleared first")
			r.data.tiles[person.position].enemies.clear()
		var dialogue = story.dialogue("hero", id)
		expect(dialogue.ok and dialogue.text.contains(Story.BACKGROUNDS[id]) and dialogue.text.contains(Story.COMPANION_LINES[id]), "Personal story and dialogue " + id)
		expect(story.choose("hero", id, "join").ok and person.squad_id == r.actor("hero").squad_id, "Actual recruitment " + id)

	var haunt: String = r.data.nodes.keys().filter(func(cell): return r.node_at(cell).kind == "haunt")[0]
	r.actor("lorne").position = haunt
	expect(not r.use_node("lorne", "settle").ok and not r.data.peace.has(haunt), "Remote squads cannot perform the hero’s unseen work")
	r.actor("hero").position = haunt
	expect(not r.use_node("hero", "settle").ok, "The hero must investigate before settlement")
	expect(r.use_node("hero", "inspect").ok and r.node_at(haunt).get("investigated", false)
		and r.node_at(haunt).result == "" and r.data.leads.has(haunt) and not r.data.peace.has(haunt),
		"Investigation supplies evidence but does not weaken the boss")
	expect(r.use_node("hero", "settle").ok and r.data.peace.has(haunt), "A settled haunting weakens the boss")
	var peace_count = r.data.peace.size()
	expect(not r.use_node("hero", "settle").ok and r.data.peace.size() == peace_count, "Repeated node cannot count twice")
	var cells = r.data.tiles.keys()
	r.data.explored.clear()
	r.data.visited.clear()
	for stage in range(1, 5):
		var needed = ceili(r.data.tiles.size() * stage * 0.2)
		while r.data.explored.size() < needed - 1:
			r.data.explored[cells[r.data.explored.size()]] = true
		expect(r.pending_chapter() == 0, "Chapter does not trigger before its threshold")
		r.data.explored[cells[r.data.explored.size()]] = true
		expect(r.pending_chapter() == stage, "Exploration triggers chapter %d" % stage)
		r.finish_chapter(stage)
		expect(r.pending_chapter() == 0 and r.actor("hero").name == "旅人", "Chapter acknowledges once and preserves the mystery")
	expect(r.boss_known() and r.data.tiles[r.data.boss].enemies == ["war_god"], "80 percent locates the actual boss")
	expect(r.actor("hero").ultimate == "gravity_wave", "A memory unlocks the upgraded gravity skill")
	r.actor("hero").position = r.data.boss
	var b = Combat.new()
	var encounter = {"position": r.data.boss, "origin": r.data.boss, "movers": [], "npc": "", "ambush": false}
	expect(b.begin(r, encounter, ["hero"]).ok, "Boss battle begins")
	expect(b.unit("enemy_0").attack < Catalog.ENEMIES.war_god.attack, "Earlier peace directly reduces Kadran's power")
	b.current = "hero"
	b.unit("enemy_0").hp = 1
	expect(b.act("gravity", "enemy_0").ok and b.reveal_pending and b.outcome.is_empty(), "Boss cannot be defeated before the replayed strike")
	expect(b.events[-1].skill_id == "old_strike", "The old strike precedes the reveal")
	b.awaken_death_power()
	expect(b.river and r.actor("hero").name == "伊文洛" and r.actor("hero").energy == 100, "Remembering precedes the river and full power")
	var hp = r.actor("hero").hp
	var attack = b.unit("enemy_0").attack
	b._hurt("hero", 999)
	expect(r.actor("hero").hp == hp, "Ivenlo is invulnerable while the river is present")
	b.current = "hero"
	b.act("guard")
	expect(b.unit("enemy_0").attack < attack, "The river strips Kadran's strength")
	b.current = "hero"
	b.request_ultimate("hero")
	b.resolve_queued()
	for i in range(5):
		if not b.outcome.is_empty():
			break
		b.current = "hero"
		b.act("gravity", "enemy_0")
	expect(r.data.status == "won" and story.main_ending().text.contains("卡德兰"), "Only beating Kadran completes the run")
	var loaded = Run.new()
	expect(loaded.load_game(r.save_path).ok and loaded.data.status == "won" and loaded.data.chapter == 4, "Victory and chapter state survive reload")
	print("STORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
