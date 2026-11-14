extends SceneTree
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const LegacyOutcomes = preload("res://scripts/domain/legacy_companion_outcomes.gd")
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

func check_past(story: RefCounted, run: RefCounted, visitor: String, subject: String, reason: String) -> void:
	var before = run.data.duplicate(true)
	var dialogue = story.dialogue(visitor, subject)
	expect(dialogue.ok and has_option(dialogue, "past") and not str(dialogue.text).contains(Story.BACKGROUNDS[subject]),
		subject + " offers background separately: " + reason)
	for attempt in range(2):
		var past = story.choose(visitor, subject, "past")
		expect(past.ok and past.get("response", "") == Story.BACKGROUNDS[subject], subject + " recalls the complete background: " + reason)
	if visitor != "hero" or not Story.HERO_LINES.has(subject):
		expect(not has_option(dialogue, "echo") and not story.choose(visitor, subject, "echo").ok,
			subject + " cannot lend protagonist familiarity to this visitor: " + reason)
	expect(run.data == before, subject + " repeated background reading changes no resources, decisions or other state: " + reason)

func check_player_advice(subject: String, quest: Dictionary) -> void:
	var labels = {}
	for option in quest.get("options", []):
		labels[option.id] = str(option.text)
	for branch in ["personal_a", "personal_b"]:
		expect(labels.get(branch, "") == Story.PERSONAL_QUESTS[subject][branch].label, subject + " presents the player's advice for " + branch)
	var a: String = labels.get("personal_a", "")
	var b: String = labels.get("personal_b", "")
	if subject == "stone_guard":
		expect("陪你" in a and "主路" in a and "爆破料" in a and "一起拦住军官" in a,
			"Stone guard advice offers help with evacuation and explosives, not the guard's own specialist role")
		expect("帮你" in b and "借梁" in b and "旧出口" in b and not "我下第一段" in b,
			"Stone guard advice helps gather beams without claiming to take the guard's first support shift")
	elif subject == "granite":
		expect("旧门卫" in a and "士族优先" in a and "不会替你" in a and not "还给我" in a,
			"Granite advice acknowledges his old guards and privilege without claiming his command")
		expect("陪你" in b and "城南军官" in b and "谁守门" in b and not "钥匙不交" in b,
			"Granite advice accompanies negotiations without speaking as the keeper of the gate")

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
			expect(run.join_companion(id, "hero").ok, id + " joins before personal quest")
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
			expect(run.join_companion(ally_id, "hero").ok, "Recruit local visitor for " + id)
			var visitor = "hero" if branch == "personal_a" else ally_id
			var before = unrelated_state(run)
			var dialogue = story.dialogue(visitor, id)
			expect(dialogue.ok and has_option(dialogue, "quest"), id + " joined dialogue offers personal quest")
			var open = story.choose(visitor, id, "quest")
			expect(open.ok and open.get("quest", false), id + " quest routes to its own full-text scene")
			var quest = story.personal_quest(visitor, id)
			expect(quest.ok and quest.has_all(["title", "text", "options", "pose"])
				and quest.get("title") == definition.title and quest.get("text") == definition.text
				and has_option(quest, "personal_a") and has_option(quest, "personal_b"), id + " both choices follow the complete personal story")
			expect(quest.options.all(func(option): return option.spoken and not str(option.text).strip_edges().is_empty()),
				id + " every personal choice is a nonempty spoken reply")
			check_player_advice(id, quest)
			expect(unrelated_state(run) == before and str(run.data.story[id].get("personal_choice", "")).is_empty(), id + " reading personal quest does not spend or select")
			var story_before = run.data.story.duplicate(true)
			var result = story.choose(visitor, id, branch)
			var response = str(result.get("response", ""))
			expect(result.ok and not response.is_empty() and response == definition[branch].response, id + " personalized response for " + branch)
			expect(unrelated_state(run) == before, id + " choice changes no AP, inventory, coins, position, map or battle state")
			var stored = run.data.story[id].get("personal_choice", "")
			expect(stored == "journey_" + branch.right(1), id + " records the current journey decision version")
			story_before[id]["personal_choice"] = stored
			expect(run.data.story == story_before, id + " choice modifies only this companion's personal decision")
			stored_choices.append(stored)
			var recall = story.dialogue(visitor, id)
			expect(recall.ok and not str(recall.text).contains(response) and has_option(recall, "quest"), id + " normal dialogue offers a separate review without repeating the response")
			expect(story.personal_quest(visitor, id).get("text", "") == response, id + " deliberate review recalls the chosen response")
			check_past(story, run, visitor, id, "after journey choice")
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
			expect(not str(continued.dialogue(visitor, id).get("text", "")).contains(response)
				and continued.personal_quest(visitor, id).get("text", "") == response, id + " reload keeps the response in its own review")
			check_past(continued, loaded, visitor, id, "after journey reload")
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
	expect(run.join_companion("lorne", "hero").ok, "Recruit boundary fixture companion")
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
	for invalid in [0, true, "", "a", "personal_unknown", "journey_x", "god_a", [], {}, null]:
		var corrupt = valid.duplicate(true)
		corrupt.story.lorne.personal_choice = invalid
		var file = FileAccess.open(run.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(corrupt))
		file.close()
		expect(not loaded.load_game(run.save_path).ok and loaded.data == before, "Invalid personal record cannot replace current run: " + str(invalid))
	for old_choice in ["personal_a", "personal_b"]:
		run.data.story.lorne.personal_choice = old_choice
		expect(run.save_game().ok and loaded.load_game(run.save_path).ok, "Load completed choice from the first Veylodan campaign")
		var legacy_story = Story.new(loaded)
		var outcome = LegacyOutcomes.OUTCOMES.lorne[old_choice]
		var recall = legacy_story.personal_quest("hero", "lorne")
		expect(recall.ok and recall.title == LegacyOutcomes.OUTCOMES.lorne.title and spoken_from(outcome.response, recall.text),
			"Old choice keeps its original title and response")
		expect(not legacy_story.choose("hero", "lorne", "personal_a").ok and outcome.ending in legacy_story.character_ending("lorne").text,
			"Old choice cannot be replaced and keeps its original ending")
	var longroad = run.actor("longroad")
	longroad.position = run.actor("hero").position
	expect(run.join_companion("longroad", "hero").ok, "Recruit the companion for a saved preview choice")
	run.data.story.longroad.personal_choice = "war_b"
	expect(run.save_game().ok and loaded.load_game(run.save_path).ok, "Load a completed choice from the first war-story draft")
	var preview_story = Story.new(loaded)
	var preview = LegacyOutcomes.PREVIEW_OUTCOMES.longroad
	var recall = preview_story.personal_quest("hero", "longroad")
	expect(recall.ok and recall.title == preview.title and spoken_from(preview.personal_b.response, recall.text)
		and preview.personal_b.ending in preview_story.character_ending("longroad").text,
		"The betrayal rewrite does not retroactively change a choice saved on the first draft")
	for id in LegacyOutcomes.WAR_OUTCOMES:
		run.actor(id).position = run.actor("hero").position
		expect(run.join_companion(id, "hero").ok, "Recruit avatar for an existing god choice: " + id)
		run.data.story[id].personal_choice = "war_a" if id == "seasons" else "war2_a"
		expect(run.save_game().ok and loaded.load_game(run.save_path).ok, "Load a previous campaign choice for " + id)
		var old_story = Story.new(loaded)
		var prior = LegacyOutcomes.PREVIEW_OUTCOMES[id] if id == "seasons" else LegacyOutcomes.WAR_OUTCOMES[id]
		var old_scene = old_story.personal_quest("hero", id)
		expect(old_scene.ok and old_scene.title == prior.title and spoken_from(prior.personal_a.response, old_scene.text)
			and prior.personal_a.ending in old_story.character_ending(id).text,
			"The new god story preserves an earlier title, response and ending for " + id)

func spoken_from(record: String, dialogue: String) -> bool:
	if dialogue.is_empty():
		return false
	if not record.contains("「"):
		return dialogue == record
	var expected = PackedStringArray()
	for passage in record.split("「").slice(1):
		var line = passage.get_slice("」", 0)
		if line.ends_with("。") or line.ends_with("？") or line.ends_with("！"):
			expected.append(line)
	return dialogue == "\n\n".join(expected)

func check_spoken_from() -> void:
	expect(spoken_from("我会回来。", "我会回来。"), "Plain legacy responses must match exactly")
	expect(not spoken_from("我会回来。", "") and not spoken_from("", "")
		and not spoken_from("我会回来。", "别人会回来。") and not spoken_from("我会回来。", "我会回来。另有新话。"),
		"Plain response matching rejects empty, substituted or appended text")
	var record = "他点头。「先等一等。」他指向写着「北门」的路牌。「我会回来！」"
	expect(spoken_from(record, "先等一等。\n\n我会回来！"), "Quoted legacy responses retain all spoken sentences, not stage directions or names")
	expect(not spoken_from(record, "先等一等。") and not spoken_from(record, "我会回来！\n\n先等一等。")
		and not spoken_from(record, record) and not spoken_from(record, "别的新故事。"),
		"Quoted response matching rejects omissions, reordered lines, stage directions and new content")

func check_legacy_choice_matrix() -> void:
	expect(LegacyOutcomes.TRAVEL_OUTCOMES.size() == 25 and LegacyOutcomes.TRAVEL_OUTCOMES.has_all(Catalog.COMPANIONS.keys()),
		"Travel outcomes freeze the complete original 25-companion roster")
	var cases = 0
	var travel_cases = 0
	var preview_fallbacks = 0
	for id in Catalog.COMPANIONS:
		var run = Run.new()
		run.save_path = "user://test-legacy-story-matrix.json"
		run.new_run(41, "wayfarer")
		var story = Story.new(run)
		var person = run.actor(id)
		run.actor("hero").position = person.position
		run.data.tiles[person.position].enemies.clear()
		expect(run.join_companion(id, "hero").ok, "Recruit legacy matrix companion " + id)
		var routes = [
			{"prefix": "personal_", "table": LegacyOutcomes.OUTCOMES},
			{"prefix": "war_", "table": LegacyOutcomes.PREVIEW_OUTCOMES},
			{"prefix": "war2_", "table": LegacyOutcomes.WAR_OUTCOMES},
		]
		if Catalog.COMPANIONS[id].race == "神":
			routes.append({"prefix": "god_", "table": LegacyOutcomes.TRAVEL_OUTCOMES})
		for route in routes:
			var prior: Dictionary = route.table.get(id, LegacyOutcomes.TRAVEL_OUTCOMES[id])
			for branch in ["personal_a", "personal_b"]:
				var choice: String = route.prefix + branch.right(1)
				var label = id + " " + choice
				var outcome: Dictionary = prior[branch]
				run.data.story[id].personal_choice = choice
				expect(run.save_game().ok, label + " saves the historical decision")
				var loaded = Run.new()
				var load_result = loaded.load_game(run.save_path)
				expect(load_result.ok, label + " survives the save whitelist")
				if not load_result.ok:
					continue
				expect(loaded.data.story[id].get("personal_choice", "") == choice, label + " is not migrated to journey")
				var continued = Story.new(loaded)
				var before = loaded.data.duplicate(true)
				var dialogue = continued.dialogue("hero", id)
				expect(dialogue.ok and dialogue.text == Story.CHARACTER_BEHAVIOR[id][2] and has_option(dialogue, "quest")
					and not has_option(dialogue, "past"), label + " keeps chat separate and hides the rewritten past")
				expect(not continued.choose("hero", id, "past").ok, label + " cannot request the rewritten background directly")
				var open = continued.choose("hero", id, "quest")
				expect(open.ok and open.get("quest", false), label + " explicitly opens its historical review")
				var recall = continued.personal_quest("hero", id)
				expect(recall.ok and recall.get("title", "") == prior.title and spoken_from(outcome.response, recall.get("text", "")),
					label + " recalls the original table's title and complete response")
				expect(has_option(recall, "leave") and not has_option(recall, "personal_a") and not has_option(recall, "personal_b"),
					label + " review offers no replacement decision")
				expect(not spoken_from(Story.PERSONAL_QUESTS[id][branch].response, recall.get("text", "")),
					label + " review is not the new journey response")
				for repeated in ["personal_a", "personal_b", "journey_a", "journey_b"]:
					expect(not continued.choose("hero", id, repeated).ok, label + " cannot be overwritten by " + repeated)
				expect(loaded.data == before, label + " reading and rejected choices preserve the entire loaded state")
				for status in ["won", "failed"]:
					loaded.data.status = status
					var ending_before = loaded.data.duplicate(true)
					var ending = continued.character_ending(id).text
					expect(outcome.ending in ending and not Story.PERSONAL_QUESTS[id][branch].ending in ending,
						label + " retains its historical ending, not journey content, after " + status)
					expect(loaded.data == ending_before, label + " ending is read-only after " + status)
				cases += 1
				if route.prefix == "god_" or (route.prefix == "war2_" and Catalog.COMPANIONS[id].race != "神"):
					travel_cases += 1
				if route.prefix == "war_" and not route.table.has(id):
					preview_fallbacks += 1
	expect(cases == 156, "All personal, preview and war routes cover 25 companions twice, plus both god routes for three avatars")
	expect(travel_cases == 50, "Travel snapshot covers 22 ordinary war2 decisions and three god decisions on both branches")
	expect(preview_fallbacks == 16, "Both war branches fall back to travel for all eight companions absent from the preview table")

func check_topics_blocked(story: RefCounted, run: RefCounted, visitor: String, subject: String, reason: String) -> void:
	var before = run.data.duplicate(true)
	var dialogue = story.dialogue(visitor, subject)
	for option in ["past", "echo", "quest"]:
		expect(not has_option(dialogue, option) and not story.choose(visitor, subject, option).ok,
			subject + " hides and rejects " + option + " for " + visitor + ": " + reason)
	check_personal_blocked(story, run, visitor, subject, reason)
	expect(run.data == before, subject + " blocked topics preserve all resources, choices and state: " + reason)

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
		var stranger = run.actor("cen")
		hero.position = person.position
		companion.position = person.position
		stranger.position = person.position
		run.data.tiles[person.position].enemies.clear()
		expect(run.join_companion("lorne").ok, "Recruit ordinary visitor")
		var first_state = run.data.duplicate(true)
		for visitor in ["hero", "lorne"]:
			expect(not story.dialogue(visitor, id).ok, id + " first encounter is reserved for recruitment")
			check_topics_blocked(story, run, visitor, id, "subject not recruited")
		expect(run.data == first_state, id + " locked conversation does not change any state")
		expect(not str(Story.HERO_LINES[id]).contains("伊文洛"), id + " hint never reveals the protagonist's name")
		expect(run.join_companion(id, "hero").ok, id + " joins before any past or echo")
		if Catalog.COMPANIONS[id].race == "神":
			expect("化身" in story.dialogue("hero", id).title, id + " is described as an avatar")
		var ready = run.data.duplicate(true)
		for visitor in ["hero", "lorne"]:
			var chat = story.dialogue(visitor, id)
			expect(chat.ok and chat.text == Story.CHARACTER_BEHAVIOR[id][2] and not str(chat.text).contains(Story.HERO_LINES[id])
				and has_option(chat, "echo") == (visitor == "hero"), id + " joined chat requires a deliberate hero-only echo request")
			check_past(story, run, visitor, id, "joined with zero AP")
		for attempt in range(2):
			var echo = story.choose("hero", id, "echo")
			expect(echo.ok and echo.get("response", "") == Story.HERO_LINES[id] and not str(echo.get("response", "")).contains("伊文洛"),
				id + " hero may actively revisit the exact hint without an identity reveal")
		expect(run.data == ready and str(run.data.story[id].get("personal_choice", "")).is_empty(),
			id + " repeated past and echo consume no resources and make no decision")
		check_topics_blocked(story, run, "cen", id, "visitor not recruited")
		check_topics_blocked(story, run, id, id, "cannot talk to oneself")
		hero.position = run.data.start
		expect(not story.dialogue("hero", id).ok, id + " distant hero cannot hear the hint")
		check_topics_blocked(story, run, "hero", id, "different tiles")
		var ordinary = story.dialogue("lorne", id)
		expect(ordinary.ok and not str(ordinary.text).contains(Story.HERO_LINES[id]), id + " local companion cannot borrow absent hero familiarity")
		check_past(story, run, "lorne", id, "hero absent")
		hero.position = person.position
		companion.position = run.data.start
		check_topics_blocked(story, run, "lorne", id, "ordinary visitor on a different tile")
		companion.position = person.position
		for visitor in ["hero", "lorne"]:
			var member = run.actor(visitor)
			var hp = member.hp
			member.hp = 0
			check_topics_blocked(story, run, visitor, id, "visitor wounded")
			member.hp = hp
		var person_hp = person.hp
		person.hp = 0
		for visitor in ["hero", "lorne"]:
			check_topics_blocked(story, run, visitor, id, "subject wounded")
		person.hp = person_hp
		run.data.tiles[person.position].enemies = ["bandit"]
		for visitor in ["hero", "lorne"]:
			check_topics_blocked(story, run, visitor, id, "enemies appeared after opening dialogue")
		run.data.tiles[person.position].enemies.clear()
		run.data.pending_battle = {"position": person.position}
		for visitor in ["hero", "lorne"]:
			check_topics_blocked(story, run, visitor, id, "encounter pending after opening dialogue")
		run.data.pending_battle.clear()
		for status in ["battle", "won", "failed"]:
			run.data.status = status
			for visitor in ["hero", "lorne"]:
				check_topics_blocked(story, run, visitor, id, status)
		run.data.status = "exploring"
		check_past(story, run, "hero", id, "safe context restored")
		var restored_echo = story.choose("hero", id, "echo")
		expect(restored_echo.ok and restored_echo.get("response", "") == Story.HERO_LINES[id] and run.data == ready,
			id + " safe context restores voluntary topics without hidden state changes")

func execute() -> void:
	check_spoken_from()
	check_personal_choices()
	check_personal_boundaries()
	check_legacy_choice_matrix()
	check_hero_only_mystery()
	var r = Run.new()
	r.save_path = "user://test-veylodan-story.json"
	r.new_run(41, "wayfarer")
	expect(Opening.world_pages().all(func(page): return "死亡之神" not in page.text and "伊文洛" not in page.text),
		"Opening preserves the identity reveal")
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
		expect(person.race in ["龙", "恶魔", "神", "人类", "矮人", "精灵"] and Catalog.SAVE_SKILL_IDS.has(person.skill) and Catalog.SAVE_SKILL_IDS.has(person.ultimate), "Complete character " + id)
		expect(Nodes.story(r.node_at(person.position)).size() > 0, "Character is placed in a real node " + id)
		r.retreat_party(person.position)
		if not r.data.tiles[person.position].enemies.is_empty():
			expect(not story.dialogue("hero", id).ok, "The encounter has to be cleared first")
			r.data.tiles[person.position].enemies.clear()
		expect(not story.dialogue("hero", id).ok, "First meeting opens no story for " + id)
		check_topics_blocked(story, r, "hero", id, "before recruitment")
		r.data.lamp_coins = 8
		var store := ""
		for candidate in r.data.nodes:
			if r.data.nodes[candidate].get("kind", "") == "trade" and not r.data.nodes[candidate].get("starter_shop", false) \
					and id in r.recruit_shop_offers(candidate):
				store = candidate
				break
		expect(not store.is_empty(), id + " is stocked at a regular shop")
		r.retreat_party(store)
		expect(r.recruit_companion(id).ok and person.position == r.actor("hero").position and r.data.lamp_coins == 0,
			"Paid recruitment " + id)
		r.data.erase("pending_story_rewards")
		check_past(story, r, "hero", id, "immediately after first meeting and recruitment")
		expect(str(r.data.story[id].get("personal_choice", "")).is_empty(), id + " learning the background never selects a personal branch")

	var full_power := Chess.enemy_definition(r, "war_god", true)
	for cell in positions.keys().slice(0, 8):
		r.data.peace[cell] = true

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
	r.retreat_party(r.data.boss)
	var b := Chess.new()
	var encounter = {"position": r.data.boss, "origin": r.data.boss, "npc": "", "ambush": false}
	expect(b.begin(r, encounter, r.card_deck()).ok, "Boss battle begins")
	var enemy := b.commanders[Chess.ENEMY]
	var hero := b.commanders[Chess.PLAYER]
	expect(enemy.attack < full_power.attack and enemy.hp_max < full_power.hp,
		"Earlier peace directly reduces Kadran's power")
	b.board[4] = hero
	b.board[10] = {}
	enemy.hp = 1
	enemy.armor = 0
	expect(b.move(4, 1) and enemy.hp == 1 and b.reveal_pending and b.outcome.is_empty() and not b.can_act(),
		"A lethal blow pauses the battle for the memory instead of completing the run")
	hero.hp = 1
	var attack := b.attack_power(enemy)
	b.awaken_death_power()
	expect(b.river and b.weather == "river" and r.actor("hero").name == "伊文洛"
		and hero.hp == hero.hp_max, "Remembering restores Ivenlo and summons the river")
	expect(b.attack_power(enemy) < attack and not b.retreat(), "The river strips Kadran's strength and prevents retreat")
	b.enemy_turn()
	if b.can_act() and b.moves(4).has(1):
		b.move(4, 1)
	expect(r.data.status == "won" and story.main_ending().text.contains("卡德兰"), "Only beating Kadran completes the run")
	var loaded = Run.new()
	expect(loaded.load_game(r.save_path).ok and loaded.data.status == "won" and loaded.data.chapter == 4, "Victory and chapter state survive reload")
	print("STORY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
