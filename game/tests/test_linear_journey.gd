extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/domain/expedition.gd")
const Journey = preload("res://scripts/domain/journey.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")

var checks := 0
var failures := 0
var save_path := "user://linear-journey-%d.json" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("execute")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func seed_for(kind: String, stake: int, step: int = 0, event_roll: int = -1) -> int:
	for seed_value in range(1, 2000):
		var roller := Journey._roller(str(seed_value), "result:%d:%d" % [step, stake])
		if Journey._draw(stake, roller) == kind and (event_roll < 0 or roller.randi_range(0, 3) == event_roll):
			return seed_value
	assert(false, "No seed matches the requested test encounter.")
	return 0

func new_run(seed_value: int, journey: bool = true) -> RefCounted:
	var run := Run.new()
	run.save_path = save_path
	run.new_run(seed_value, "wayfarer", journey)
	return run

func check_pools() -> void:
	var seen := {}
	for stake in Journey.POOLS.size():
		var counts := {}
		var roller := Journey._roller("20261126", "distribution:%d" % stake)
		for i in 10000:
			var kind := Journey._draw(stake, roller)
			counts[kind] = int(counts.get(kind, 0)) + 1
		for kind in Journey.POOLS[stake]:
			expect(absi(counts.get(kind, 0) - Journey.POOLS[stake][kind] * 100) < 180, "Stake weights match the PRD.")
			seen[kind] = true
	expect(seen.size() == 6 and not seen.has("boss"), "All six intermediate encounters are possible, with no early boss.")

func check_checkpoints() -> void:
	var seed_value := seed_for("chest", 2)
	var run := new_run(seed_value)
	var initial: int = int(run.data.lamp_coins)
	var unwritable: String = run.save_path + "/missing"
	run.save_path = unwritable
	expect(not Journey.choose(run, 0, 2).ok and Journey.current(run.data).is_empty() and run.data.lamp_coins == initial,
		"Failed save rolls back the choice and its rewards.")
	run.save_path = save_path
	expect(Journey.choose(run, 0, 2).ok, "A valid choice reveals and saves a chest.")
	var entry := Journey.current(run.data)
	expect(entry.kind == "chest" and entry.settled and entry.coins_change >= 11 and entry.coins_change <= 18,
		"High stakes scale the chest reward.")
	var reload := Run.new()
	expect(reload.load_game(save_path).ok, "The resolved journey file is readable.")
	var restored := Journey.current(reload.data)
	expect(restored.get("kind") == entry.kind and restored.get("text") == entry.text and restored.get("settled", false)
		and int(restored.get("coins_change", 0)) == entry.coins_change and reload.data.lamp_coins == run.data.lamp_coins,
		"Reopening a resolved checkpoint preserves the result and resources.")
	expect(not Journey.choose(run, 0, 0).ok and Journey.advance(run, 0).ok and not Journey.advance(run, 0).ok
		and not Journey.choose(run, 0, 2).ok, "Settled choices and previously used step tokens cannot be repeated.")
	var rest := new_run(seed_for("rest", 0))
	rest.actor("hero").hp = 1
	var base := roundi(rest.actor("hero").hp_max * 0.25)
	expect(Journey.choose(rest, 0, 0).ok and Journey.current(rest.data).hp_change == roundi(base * 0.6), "Rest heals at the selected stake scale.")

func check_shop_and_companion() -> void:
	var run := new_run(seed_for("shop", 0))
	expect(Journey.choose(run, 0, 0).ok and Journey.shop_active(run.data) and not Journey.advance(run, 0).ok,
		"A revealed shop opens independently and must be settled before advancing.")
	var reload := Run.new()
	reload.save_path = save_path
	expect(reload.load_game().ok, "The open shop checkpoint is readable.")
	var before: Dictionary = run.data.battle_shop
	var after: Dictionary = reload.data.battle_shop
	expect(after.cell == before.cell and after.stock.keys() == before.stock.keys()
		and after.stock.keys().all(func(id): return int(after.stock[id]) == before.stock[id])
		and after.relic_stock.keys() == before.relic_stock.keys(), "Shop inventory survives reloading.")
	var offers: Array = reload.recruit_shop_offers(reload.actor("hero").position)
	expect(not offers.is_empty() and offers == run.recruit_shop_offers(run.actor("hero").position),
		"The revealed companion offers survive reloading.")
	var recruit: String = offers[0]
	expect(reload.recruit_companion(recruit).ok and recruit in reload.card_deck(), "Existing recruitment adds the card to the deck.")
	reload.data.erase("pending_story_rewards")
	expect(Journey.close_shop(reload).ok and Journey.current(reload.data).coins_change == -6 and not reload.data.has("battle_shop"),
		"The shop settlement reports spending and clears temporary stock.")
	expect(reload.load_game().ok and reload.actor(recruit).joined and not Journey.close_shop(reload).ok,
		"Shop purchases and closure cannot be repeated after reloading.")
	run = new_run(seed_for("event", 0, 0, 0))
	expect(Journey.choose(run, 0, 0).ok and run.joined_ids().size() == 2 and run.joined_ids()[1] in run.card_deck(),
		"A roadside companion event joins the party through the existing system.")

func check_migration_and_failure() -> void:
	var old := new_run(42, false)
	old.data.version = 13
	DirAccess.remove_absolute(save_path + ".legacy-map.bak")
	old.data.lamp_coins = 17
	old.data.chapter = 3
	old.actor("hero").hp = 22
	old.data.pending_battle = {"position": old.data.start, "origin": old.data.start, "npc": "", "ambush": false}
	var deck: Array = old.card_deck()
	expect(old.save_game().ok, "The old map save is written.")
	var migrated := Run.new()
	migrated.save_path = save_path
	expect(migrated.load_game().ok and migrated.migrate_to_journey().ok and migrated.load_game().ok,
		"The old save migrates and remains readable.")
	var original: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path + ".legacy-map.bak"))
	expect(original is Dictionary and original.get("version") == 13 and not original.has("journey"),
		"Migration keeps a separate copy of the original map save.")
	expect(migrated.data.journey.step == 0 and Journey.current(migrated.data).is_empty() and migrated.data.pending_battle.is_empty()
		and migrated.data.lamp_coins == 17 and migrated.actor("hero").hp == 22 and migrated.card_deck() == deck,
		"Migration starts the new route while keeping the party's earned resources and cards.")
	var fatal := new_run(seed_for("event", 0, 0, 1))
	fatal.actor("hero").hp = 1
	expect(Journey.choose(fatal, 0, 0).ok and fatal.data.status == "failed" and fatal.actor("hero").hp == 0
		and not Journey.advance(fatal, 0).ok and fatal.load_game().ok, "A fatal journey event persists as a finished run.")
	var abandoned := new_run(seed_for("shop", 0))
	expect(Journey.choose(abandoned, 0, 0).ok and Journey.abandon(abandoned).ok and abandoned.load_game().ok
		and abandoned.data.status == "failed" and not abandoned.data.has("battle_shop"), "Abandoning an open shop creates a readable final save.")

func check_battle_exit() -> void:
	var run := new_run(seed_for("battle", 1))
	expect(Journey.choose(run, 0, 1).ok, "The fixture reveals a standard battle.")
	var model := Chess.new()
	expect(model.begin(run, run.data.pending_battle, run.card_deck()).ok and model.retreat(),
		"A player can retreat from an intermediate battle.")
	var result := Journey.current(run.data)
	expect(result.settled and result.hp_change < 0 and not run.data.has("pending_victory")
		and run.load_game().ok and Journey.advance(run, 0).ok, "Retreat leaves a wound and advances the same route.")
	run = new_run(seed_for("elite", 2))
	expect(Journey.choose(run, 0, 2).ok, "The fixture reveals an elite battle.")
	model = Chess.new()
	if not model.begin(run, run.data.pending_battle, run.card_deck()).ok:
		expect(false, "The elite battle starts.")
		return
	model.commanders[Chess.PLAYER].hp = 0
	expect(model._check_outcome() and run.data.status == "failed" and run.actor("hero").hp == 0
		and run.load_game().ok and Journey.current(run.data).settled, "A card battle defeat ends and saves the journey.")

func press_named(host: Node, button_name: String) -> bool:
	var button := host.find_child(button_name, true, false) as Button
	if button == null or button.disabled or not button.is_visible_in_tree():
		expect(false, "Visible, enabled button: " + button_name)
		return false
	button.pressed.emit()
	return true

func press_text(host: Node, prefix: String) -> bool:
	for child in host.find_children("*", "Button", true, false):
		if child.text.begins_with(prefix) and child.is_visible_in_tree() and not child.disabled:
			child.pressed.emit()
			return true
	expect(false, "Visible, enabled button: " + prefix)
	return false

func check_playable_route(game: Node) -> void:
	game._start_new()
	var run: RefCounted = game.run
	var battle_count := 0
	var boss_count := 0
	for i in Journey.STOPS:
		var screen: Node = game.ui.get_node_or_null("JourneyScreen")
		expect(screen != null and not game.view.visible and not game.view.is_processing_unhandled_input(),
			"The default exploration surface is the journey, with map input disabled.")
		if screen == null:
			return
		expect(screen.find_children("JourneyChoice*", "Button", true, false).size() == (1 if i == Journey.STOPS - 1 else 3),
			"Only actions and stake labels appear before reveal.")
		if not press_named(screen, "JourneyChoice0" if i == 1 or i == Journey.STOPS - 1 else "JourneyChoice2"):
			return
		var entry := Journey.current(run.data)
		var kind: String = entry.kind
		expect(not Journey.choose(run, i, 1).ok, "Another route option is locked after reveal.")
		if kind in Journey.BATTLES:
			var pending: Dictionary = run.data.pending_battle.duplicate(true)
			var enemies := Journey.battle_enemies(run.data, pending)
			game._continue_run()
			expect(int(run.data.pending_battle.get("journey_step", -1)) == int(pending.journey_step)
				and Journey.battle_enemies(run.data, run.data.pending_battle) == enemies,
				"Reload keeps the revealed encounter and opponents.")
			if not press_named(game.ui, "JourneyEnter"):
				return
			if kind == "boss":
				boss_count += 1
				game._deck_dialog(true)
			else:
				battle_count += 1
			if not press_text(game.modal_layer, "开始战斗") or game.combat == null:
				return
			expect(game.combat.final_battle == (kind == "boss") and not game.view.visible, "The selected node enters the real card battle.")
			if kind == "boss":
				expect(not game.combat.can_retreat(), "The final battle is terminal.")
				game.combat.commanders[Chess.ENEMY].hp = 1
				expect(game.combat._check_outcome() and game.combat.reveal_pending, "The boss triggers the existing identity reveal.")
				game.combat.awaken_death_power()
			game.combat.commanders[Chess.ENEMY].hp = 0
			game.combat._check_outcome()
			game._finish_battle()
			expect(run.data.has("pending_victory") and not run.data.has("battle_shop"), "Battles show loot without opening an unrelated merchant.")
			game._continue_run()
			expect(press_text(game.modal_layer, "查看结局" if kind == "boss" else "返回旅途"), "Victory receipt reopens after loading.")
		elif kind == "shop":
			if not press_named(game.ui, "JourneyEnter") or not press_text(game.modal_layer, "离开商店"):
				return
		var settled := Journey.current(run.data)
		expect(settled.get("settled", false), "The revealed node records its settlement.")
		if i < Journey.STOPS - 1 and not press_named(game.ui, "JourneyAdvance"):
			return
	expect(battle_count > 0 and boss_count == 1 and run.data.status == "won" and run.data.journey.history.size() == Journey.STOPS,
		"All seven stops can complete through the game's normal entry points.")

func execute() -> void:
	check_pools()
	check_checkpoints()
	check_shop_and_companion()
	check_migration_and_failure()
	check_battle_exit()
	var game := Main.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.run.save_path = save_path
	game.chosen_seed = str(seed_for("elite", 2))
	check_playable_route(game)
	game.queue_free()
	await process_frame
	await process_frame
	for suffix in ["", ".bak", ".legacy-map.bak", ".tmp"]:
		DirAccess.remove_absolute(save_path + suffix)
	print("Linear journey checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
