extends SceneTree
## End-to-end domain journeys: no teleports, resource grants, forced victories or fixture HP edits.
const Run = preload("res://scripts/domain/expedition.gd")
const Story = preload("res://scripts/domain/narrative.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Combat = preload("res://scripts/domain/battle.gd")
var r: RefCounted
var s: RefCounted
var group: Array = []
var checks = 0
var failures: Array[String] = []
var moves = 0

func _initialize() -> void:
	call_deferred("execute")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func location(subject: String) -> String:
	if r.data.actors.has(subject):
		return r.actor(subject).position
	for k in r.data.tiles:
		if r.data.tiles[k].site == subject:
			return k
	return ""

func travel(ids: Array, destination: String) -> bool:
	var route = Hex.path(r.data.tiles, r.actor(ids[0]).position, destination, true)
	expect(not route.is_empty(), "Safe legal path exists to " + destination)
	if route.is_empty():
		return false
	for next in route.slice(1):
		var need_day = false
		for id in ids:
			if r.actor(id).ap < r.move_cost(id, next):
				need_day = true
		if need_day:
			expect(r.end_day().ok, "End day to replenish independent AP")
		var result = r.move(ids, next)
		expect(result.ok and not result.get("battle", false), "Each safe travel step is accepted")
		if not result.ok or result.get("battle", false):
			return false
		moves += 1
	return true

func visit(subject: String) -> void:
	travel(group, location(subject))
	expect(s.dialogue("hero", subject).ok, "Hero actually present at " + subject)

func choose(subject: String, choice: String, visitor: String = "hero") -> void:
	var result = s.choose(visitor, subject, choice)
	expect(result.ok, "Journey choice " + subject + ":" + choice + " " + str(result))

func recruit(id: String) -> void:
	choose(id, "join")
	expect(r.actor(id).joined and r.actor(id).hp > 0, "Companion joined through actual story: " + id)
	if id not in group:
		group.append(id)

func execute() -> void:
	for setting in [[20261104, "wayfarer"], [41, "guardian"], [918, "arcanist"]]:
		journey(int(setting[0]), str(setting[1]))
	failure_journey()
	print("FULL JOURNEYS: %d checks, %d failures; 3 success journeys + 1 real defeat, %d legal movement steps" % [checks, failures.size(), moves])
	quit(0 if failures.is_empty() else 1)

func journey(seed_value: int, profession: String) -> void:
	r = Run.new()
	r.save_path = "user://test-journey.json"
	r.new_run(seed_value, profession)
	s = Story.new(r)
	group = ["hero"]
	visit("lorne")
	choose("lorne", "letter")
	recruit("lorne")
	group.erase("lorne")
	travel(["lorne"], location("record"))
	choose("record", "take_record", "lorne")
	expect(r.actor("lorne").inventory.get("Q-B", 0) == 1, "Separated courier owns original evidence")
	visit("inn")
	choose("inn", "read")
	visit("cen")
	choose("cen", "help")
	choose("cen", "boundary")
	recruit("cen")
	visit("grit")
	choose("grit", "share_food")
	choose("grit", "uncertain")
	recruit("grit")
	visit("ember")
	choose("ember", "explain")
	recruit("ember")
	visit("tide")
	choose("tide", "water_draft")
	choose("tide", "water_observe")
	if r.actor("hero").ap < 2:
		r.end_day()
	choose("tide", "water_rubbing")
	choose("tide", "water_maintenance")
	choose("tide", "limited")
	recruit("tide")
	visit("eve")
	choose("eve", "medicine")
	visit("home")
	choose("home", "deliver_letter")
	choose("home", "deliver_medicine")
	choose("home", "public")
	choose("home", "terms")
	visit("eve")
	choose("eve", "medicine_report")
	recruit("eve")
	# The courier physically delivers the original before the main group arrives.
	travel(["lorne"], r.data.exit)
	choose("exit", "submit", "lorne")
	expect(r.data.submitted.get("Q-B", {}).get("by", "") == "lorne", "Courier truly submitted original while separated")
	visit("exit")
	expect(r.data.status == "exploring", "First arrival leaves expedition active")
	choose("exit", "register")
	choose("exit", "submit")
	choose("exit", "submit_terms")
	choose("exit", "submit_boundary")
	choose("lorne", "letter_report")
	choose("cen", "report")
	group.append("lorne")
	expect(r.joined_ids().size() == 7, "All six companions plus protagonist recruited through real branches")
	forest_battle()
	if r.data.status != "exploring":
		expect(false, "Expedition survived intended full-party forest encounter")
		return
	choose("ember", "preserve")
	visit("exit")
	choose("exit", "wait")
	var checkpoint_explored = r.data.explored.size()
	expect(r.save_game().ok, "Full journey stable save")
	var restored = Run.new()
	restored.save_path = r.save_path
	expect(restored.load_game().ok, "Full journey continues after save")
	r = restored
	s = Story.new(r)
	expect(r.data.explored.size() == checkpoint_explored and r.joined_ids().size() == 7, "Full journey restored team and exploration")
	# The letter and evidence arrived; their courier can still remain outside the station.
	var away = ""
	for k in Hex.neighbors(r.data.exit, r.data.tiles):
		if r.data.tiles[k].enemies.is_empty():
			away = k
			break
	expect(away != "", "At least one legal station approach")
	if away != "":
		travel(["lorne"], away)
	expect(r.extract().ok, "Final explicit extraction with remote companion")
	expect(s.main_ending().code == "CH-03", "Full journey earns authorized public verification ending")
	expect(s.character_ending("lorne").code == "LOR-U-H-R", "Actual remote courier gets resolved healthy unextracted epilogue")
	expect(r.data.submitted.has("Q-B") and r.actor("lorne").position != r.data.exit, "Delivered evidence is preserved independently of courier extraction")
	print("JOURNEY COMPLETE seed=%d profession=%s days=%d battles=%d explored=%d" % [seed_value, profession, r.data.day, r.data.battles, r.data.explored.size()])

func forest_battle() -> void:
	var goal = ""
	var approach = ""
	var best = 10000
	for k in r.data.tiles:
		var tile = r.data.tiles[k]
		if tile.terrain != "forest" or tile.enemies.is_empty() or "lamp_boss" in tile.enemies:
			continue
		for neighbor in Hex.neighbors(k, r.data.tiles):
			if not r.data.tiles[neighbor].enemies.is_empty():
				continue
			var route = Hex.path(r.data.tiles, r.actor("hero").position, neighbor, true)
			if not route.is_empty() and route.size() < best:
				best = route.size()
				goal = k
				approach = neighbor
	expect(goal != "", "A forest combat and preservation route exists")
	if goal == "":
		return
	travel(group, approach)
	var formation = ["hero", "cen", "grit", "eve"]
	var need_day = false
	for id in formation:
		if r.actor(id).ap < r.move_cost(id, goal) + 2:
			need_day = true
	if need_day:
		r.end_day()
	var movement = r.move(group, goal)
	expect(movement.ok and movement.get("battle", false), "Actual movement triggers encounter")
	if not movement.ok:
		return
	var b = Combat.new()
	expect(b.begin(r, r.data.pending_battle, formation).ok, "Select four from seven same-cell characters")
	b.auto_mode = true
	var steps = 0
	while b.outcome == "" and steps < 500:
		b.step_auto()
		steps += 1
	expect(b.outcome == "victory", "Unmodified full-party combat wins through normal combat rules")
	expect(b.paid.size() == 4 and r.data.tiles[goal].enemies.is_empty(), "Exactly four deployed, encounter cleared once")
	expect(r.data.tiles[goal].terrain == "forest" and not r.data.tiles[goal].burning, "Actual strategy preserved forest")

func failure_journey() -> void:
	r = Run.new()
	r.save_path = "user://test-journey-defeat.json"
	r.new_run(77, "wayfarer")
	s = Story.new(r)
	group = ["hero"]
	var boss = ""
	var approach = ""
	for k in r.data.tiles:
		if "lamp_boss" in r.data.tiles[k].enemies:
			boss = k
			break
	for k in Hex.neighbors(boss, r.data.tiles):
		if r.data.tiles[k].enemies.is_empty() and not Hex.path(r.data.tiles, r.data.start, k, true).is_empty():
			approach = k
			break
	expect(boss != "" and approach != "", "Optional boss has a reachable approach")
	if approach == "":
		return
	travel(group, approach)
	if r.actor("hero").ap < r.move_cost("hero", boss) + 2:
		r.end_day()
	var entered = r.move(group, boss)
	expect(entered.ok and entered.battle, "Lone character voluntarily enters fixed-strength boss")
	var b = Combat.new()
	expect(b.begin(r, r.data.pending_battle, ["hero"]).ok, "Real boss defeat battle starts")
	b.auto_mode = true
	var steps = 0
	while b.outcome == "" and steps < 500:
		b.step_auto()
		steps += 1
	expect(b.outcome == "defeat" and r.data.status == "failed", "Unmodified combat can end in protagonist expedition failure")
	expect(s.main_ending().code == "FAIL", "Failure never plays successful extraction ending")
	print("DEFEAT JOURNEY COMPLETE seed=77 days=%d combat_actions=%d" % [r.data.day, steps])
