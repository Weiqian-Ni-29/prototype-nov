extends SceneTree
const ExpeditionModel = preload("res://scripts/domain/expedition.gd")
var checks = 0
var failures = 0
func _initialize():
	call_deferred("execute")
func expect(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func execute():
	var run = ExpeditionModel.new()
	run.new_run(20261104, "wayfarer")
	run.save_path = "user://test-squads.json"
	expect(run.save_game().ok, "Fixture checkpoint saves")
	var legacy: Dictionary = run.data.duplicate(true)
	legacy.version = 4
	legacy.erase("steps_today")
	legacy.day = 7
	legacy.squad_colors = {"squad_0": 0, "squad_1": 1}
	legacy.next_squad_id = 2
	legacy.actors.hero.squad_id = "squad_0"
	legacy.actors.lorne.joined = true
	legacy.actors.lorne.squad_id = "squad_1"
	legacy.actors.lorne.hp = 9
	legacy.actors.hero.ap = 0
	legacy.relic_seen.trail_boots = true
	legacy.relic_inventory.trail_boots = 1
	legacy.relic_attunement = ["trail_boots"]
	var origin: String = legacy.actors.hero.position
	var destination: String = legacy.actors.lorne.position
	expect(destination != origin, "Legacy party is split across two cells")
	for resume_encounter in [false, true]:
		if resume_encounter:
			legacy.pending_battle = {"position": destination, "origin": origin, "npc": "", "ambush": false, "movers": ["lorne"]}
		var file = FileAccess.open(run.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(legacy))
		file.close()
		var loaded = ExpeditionModel.new()
		expect(loaded.load_game(run.save_path).ok, "Load old multi-squad checkpoint")
		var cell = destination if resume_encounter else origin
		expect(loaded.actor("hero").position == cell and loaded.actor("lorne").position == cell
			and loaded.actor("lorne").hp == 9 and loaded.data.day == 7 and loaded.remaining_steps() == 5,
			"Travel migration reunites the party and preserves injuries and date")
		expect(not loaded.actor("hero").has("ap") and not loaded.data.has("squad_colors"), "Old travel state is removed")
		expect(loaded.data.relic_inventory.trail_boots == 1 and not loaded.has_relic("trail_boots"),
			"Retired relic is kept in the bag and no longer active")
		expect(loaded.data.pending_battle.is_empty() != resume_encounter, "Pending encounter survives migration")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(run.save_path + suffix)
	print("TRAVEL MIGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
