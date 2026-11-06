extends SceneTree
## Unit-level story fixtures visit actual anchor cells; full UI journeys are tested separately.
const Run = preload("res://scripts/domain/expedition.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Combat = preload("res://scripts/domain/battle.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
var checks = 0
var failures: Array[String] = []
var r: RefCounted
var s: RefCounted
var personal_seen = {}
var main_seen = {}

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func fresh() -> void:
	r = Run.new()
	r.save_path = "user://test-story.json"
	r.new_run(20261104, "wayfarer")
	s = Story.new(r)

func location(subject: String) -> String:
	if r.data.actors.has(subject):
		return r.actor(subject).position
	for k in r.data.tiles:
		if r.data.tiles[k].site == subject:
			return k
	return ""

func visit(subject: String) -> void:
	r.actor("hero").position = location(subject)
	r.reveal(r.actor("hero").position)
	var result = s.dialogue("hero", subject)
	expect(result.ok, "Can visit " + subject)

func choose(subject: String, option: String) -> Dictionary:
	var before = r.actor("hero").ap
	var result = s.choose("hero", subject, option)
	expect(result.ok, "Choice " + subject + ":" + option + " " + str(result))
	if option not in ["take_record", "water_rubbing", "water_maintenance"]:
		expect(r.actor("hero").ap == before, "Story choice has no generic AP fee: " + option)
	return result

func expect_personal(id: String, result: String) -> void:
	var actual = s.character_ending(id).personal
	expect(actual == result, "Personal result " + id + ": " + result + " got " + actual)
	personal_seen[id + ":" + result] = true

func finish(expected: String) -> void:
	visit("exit")
	expect(r.extract().ok, "Explicit extraction in story fixture")
	var actual = s.main_ending().code
	expect(actual == expected, "Main ending " + expected + " got " + actual)
	main_seen[actual] = true

func execute() -> void:
	for id in Catalog.COMPANIONS:
		fresh()
		visit(id)
		expect_personal(id, "E0")
	main_paths()
	personal_paths()
	cross_paths()
	remote_endings()
	expect(main_seen.size() == 7, "All seven main endings exercised")
	expect(personal_seen.size() == 24, "All 24 personal result IDs exercised")
	print("STORY TESTS: %d checks, %d failures; %d main endings, %d personal results, 24 remote epilogue bases" % [checks, failures.size(), main_seen.size(), personal_seen.size()])
	quit(0 if failures.is_empty() else 1)

func main_paths() -> void:
	fresh()
	visit("exit")
	choose("exit", "register")
	expect(r.actor("hero").inventory.get("Q-T", 0) == 0 and r.actor("hero").inventory.get("Q-TR", 0) == 1, "QT is exchanged for one physical QTR")
	expect(not s.choose("hero", "exit", "register").ok, "Registration cannot duplicate receipts")
	choose("exit", "wait")
	expect(r.data.status == "exploring", "Waiting does not end expedition")
	finish("CH-00")
	fresh()
	visit("exit")
	choose("exit", "roads")
	finish("CH-01")
	fresh()
	visit("inn")
	choose("inn", "read")
	finish("CH-02")
	expect("尚未送达" in s.main_ending().text, "CH02 distinguishes undelivered investigation")
	for scope in ["public", "sealed"]:
		fresh()
		visit("inn")
		choose("inn", "read")
		visit("record")
		choose("record", "take_record")
		visit("home")
		choose("home", scope)
		visit("exit")
		choose("exit", "submit")
		expect(r.data.submitted.has_all(["Q-A", "Q-B", "Q-C"]), "Actual historical originals reach station")
		expect(r.actor("hero").inventory.get("Q-B", 0) == 0, "Submitted original no longer in inventory")
		finish("CH-03" if scope == "public" else "CH-04")
	fresh()
	visit("home")
	choose("home", "terms")
	visit("exit")
	choose("exit", "submit_terms")
	finish("CH-05")
	fresh()
	visit("record")
	choose("record", "take_record")
	visit("exit")
	choose("exit", "keep")
	finish("CH-06")

func personal_paths() -> void:
	fresh()
	visit("cen")
	choose("cen", "help")
	choose("cen", "decline")
	expect(not r.actor("cen").joined, "Helping does not force companionship")
	choose("cen", "boundary")
	visit("exit")
	choose("exit", "submit_boundary")
	visit("cen")
	choose("cen", "report")
	expect_personal("cen", "E1")
	fresh()
	visit("cen")
	choose("cen", "straight")
	expect_personal("cen", "E2")
	expect(not s.choose("hero", "cen", "boundary").ok, "Boundary conflict is not silently overwritten")
	for route in ["delivered", "sealed", "opened"]:
		fresh()
		visit("lorne")
		choose("lorne", "letter")
		visit("home")
		choose("home", "deliver_letter" if route == "delivered" else "seal_letter" if route == "sealed" else "open_letter")
		if route == "opened":
			choose("home", "deliver_letter")
		visit("lorne")
		choose("lorne", "letter_report")
		expect_personal("lorne", "E1" if route == "delivered" else "E2" if route == "sealed" else "E3")
		if route == "sealed":
			expect(r.actor("lorne").inventory.get("Q-L", 0) == 1 and r.actor("hero").inventory.get("Q-L", 0) == 0, "Sealed original truly returned")
	for route in ["whole", "emergency", "conceal"]:
		fresh()
		visit("eve")
		choose("eve", "medicine")
		if route != "whole":
			choose("eve", route)
		visit("home")
		choose("home", "deliver_medicine")
		visit("eve")
		choose("eve", "medicine_report")
		expect_personal("eve", "E1" if route == "whole" else "E2" if route == "emergency" else "E3")
		expect(not s.choose("hero", "eve", "medicine").ok, "No second medicine box after delivery")
	for route in ["new_path", "stay", "uncertain"]:
		fresh()
		visit("grit")
		if route != "uncertain":
			visit("inn")
			choose("inn", "diagnosis")
			visit("grit")
		choose("grit", route)
		expect_personal("grit", "E1" if route == "new_path" else "E2" if route == "stay" else "E3")
	for route in ["annotate", "limited", "forge"]:
		fresh()
		visit("tide")
		choose("tide", "water_draft")
		choose("tide", "water_observe")
		choose("tide", "water_rubbing")
		if route == "annotate":
			choose("tide", "water_maintenance")
		choose("tide", route)
		expect_personal("tide", "E1" if route == "annotate" else "E2" if route == "limited" else "E3")
	# Generate a real domain battle settlement for the conservation report.
	fresh()
	var p = r.data.start
	r.data.tiles[p].terrain = "forest"
	r.data.tiles[p].enemies = ["boar"]
	var b = Combat.new()
	expect(b.begin(r, {"position": p, "ambush": false, "origin": p, "movers": [], "npc": ""}, ["hero"]).ok, "Conservation report battle begins")
	b.enemies.enemy_0.hp = 1
	expect(b.act("attack", "enemy_0").ok and b.outcome == "victory", "Conservation report follows actual battle victory")
	visit("ember")
	choose("ember", "preserve")
	expect_personal("ember", "E1")
	for route in ["admit", "falsify"]:
		fresh()
		var point = r.data.start
		r.data.tiles[point].terrain = "forest"
		r.actor("hero").skill = "ember"
		expect(r.environmental_skill("hero", "ignite").ok, "Actual map ignition for report")
		visit("ember")
		choose("ember", route)
		expect_personal("ember", "E2" if route == "admit" else "E3")
	# Ordinary NPC combat: no automatic opponent 1HP and no invitation while wounded.
	fresh()
	visit("ember")
	var previous_ap = r.actor("hero").ap
	r.actor("hero").ap = Catalog.BATTLE_AP - 1
	expect(not s.choose("hero", "ember", "duel").ok and r.data.pending_battle.is_empty(),
		"An unaffordable duel cannot trap the player in formation")
	r.actor("hero").ap = previous_ap
	choose("ember", "duel")
	b = Combat.new()
	expect(b.begin(r, r.data.pending_battle, ["hero"]).ok, "Ordinary NPC combat begins")
	b.enemies.enemy_0.hp = 1
	expect(b.act("attack", "enemy_0").ok and b.outcome == "victory", "Ordinary NPC victory")
	expect(r.actor("ember").hp == 0, "Opponent NPC does not inherit friendly victory 1HP")
	expect_personal("ember", "E4")
	expect(not s.choose("hero", "ember", "join").ok, "Cannot invite unconscious opponent")
	var supplies_before = r.actor("hero").inventory.salve
	expect(r.use_item("hero", "ember", "salve").ok, "Actual physical NPC rescue")
	expect(r.actor("hero").inventory.salve == supplies_before - 1, "NPC rescue consumes actual item")
	visit("ember")
	choose("ember", "join")
	expect(r.actor("ember").joined and r.actor("ember").hp == 45, "Rescued companion joins without free full heal")

func cross_paths() -> void:
	fresh()
	visit("record")
	choose("record", "take_record")
	var evidence_position = r.actor("hero").position
	r.actor("lorne").joined = true
	r.data.story.lorne.met = true
	r.data.story.lorne.relation = "joined"
	r.actor("lorne").position = evidence_position
	expect(r.transfer("hero", "lorne", "Q-B", 1).ok, "Physical evidence transfer")
	visit("exit")
	expect(not s.choose("hero", "exit", "submit").ok, "Remote evidence cannot be submitted")
	choose("exit", "keep") if r.actor("hero").inventory.get("Q-B", 0) > 0 else expect(true, "No remote keep action")
	finish("CH-02")
	expect(s.character_ending("lorne").code.begins_with("LOR-U-"), "Evidence holder remains unextracted")
	# Once Tide moves, the site remains investigable by an unrelated character.
	fresh()
	var water_position = location("tide")
	r.actor("tide").joined = true
	r.actor("tide").position = r.data.start
	r.actor("hero").position = water_position
	choose("water", "water_observe")
	choose("water", "water_maintenance")
	expect(r.actor("hero").inventory.get("Q-WC", 0) == 1, "Water archive does not require Tide present")
	fresh()
	visit("cen")
	choose("cen", "help")
	var original_ap = r.actor("hero").ap
	choose("cen", "join")
	expect(r.actor("cen").ap == r.actor("cen").ap_max and r.actor("hero").ap == original_ap, "New companion initializes personal AP without recruitment fee")
	expect(not s.choose("hero", "cen", "join").ok, "Joined companion cannot initialize AP again")

func remote_endings() -> void:
	var seen = {}
	for id in Catalog.COMPANIONS:
		for injured in [false, true]:
			for resolved in [false, true]:
				fresh()
				r.actor(id).joined = true
				r.data.story[id].met = true
				r.data.story[id].relation = "joined"
				r.data.story[id].result = "E1" if resolved else "E0"
				r.actor(id).hp = 0 if injured else 15
				r.actor("hero").position = r.data.exit
				expect(r.extract().ok, "Extraction allows remote injured companion")
				var before_ending = JSON.stringify(r.data)
				var ending = s.character_ending(id)
				seen[ending.code] = true
				expect(ending.code.ends_with(("I" if injured else "H") + "-" + ("R" if resolved else "O")), "Correct injury/resolution base " + ending.code)
				expect(Story.PERSONAL[id]["E1" if resolved else "E0"] in ending.text and str(r.actor(id).position) in ending.text, "Remote ending includes actual personal result and location " + ending.code)
				expect(JSON.stringify(r.data) == before_ending, "Epilogue does not heal, move actors or change item ownership " + ending.code)
	expect(seen.size() == 24, "24 unique remote ending bases")
