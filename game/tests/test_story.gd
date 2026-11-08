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

func execute() -> void:
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
