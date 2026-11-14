extends SceneTree

const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("execute")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func execute() -> void:
	var run := Run.new()
	run.save_path = "user://test-chess-loadout.json"
	run.new_run(81, "wayfarer")
	var deck := run.card_deck()
	var start: String = run.actor("hero").position
	var owned := Cards.collection(run.data.actors, run.data)
	expect(deck.size() == 12 and deck.count("ember_spell") == 2 and deck.count("sun") == 1
		and deck.filter(func(id): return id.begins_with("gear:")).size() == 4
		and "ice_spell" not in owned and not owned.any(func(id): return Cards.definition(id).get("kind") == "partner"), "New game owns four real equipment cards, solo defense and spells")
	var blade_id: String = deck[0]
	var uid := blade_id.trim_prefix("gear:")
	var original := Cards.owned_definition(blade_id, run.data.actors, run.data)
	run.data.lamp_coins = 100
	var quote: Dictionary = run.enhancement_quote("hero", uid)
	expect(run.save_card_deck(deck).ok and run.enhance_card("hero", uid).ok
		and run.data.lamp_coins == 100 - quote.price, "Enhancement charges lamps and saves the same card instance")
	var upgraded := Cards.owned_definition(blade_id, run.data.actors, run.data)
	expect(upgraded.level == 1 and upgraded.equip_guard == 1 and run.card_deck() == deck and original.level == 0,
		"Upgrading a gear instance updates the card without editing its deck slot")
	var store: String = run.data.start
	run.data.pending_victory = {"enemies": 1, "members": ["hero"], "revived": [], "relic": ""}
	run.open_battle_shop()
	var offer: String = run.spell_shop_offers(store)[0]
	var balance: int = run.data.lamp_coins
	expect(run.buy_spell("hero", offer).ok and run.data.lamp_coins == balance - 8
		and offer in Cards.collection(run.data.actors, run.data) and run.spell_shop_offers(store).is_empty(),
		"A paid spell becomes a collection card and takes the store's current blueprint slot")
	expect(not run.buy_spell("hero", offer).ok and run.shop_refresh_cost(store) == 1, "A spell purchase cannot repeat or alter refresh costs")
	run.retreat_party(start)
	run.data.tiles[start].enemies = ["boar"]
	var encounter := {"position": start, "origin": start, "npc": "", "ambush": false}
	run.close_battle_shop()
	run.data.erase("pending_victory")
	var battle := Chess.new()
	expect(battle.begin(run, encounter, deck).ok and battle.hands[0].size() == 3
		and battle.hands[1].size() == 3 and battle.piles[0].size() == 9, "Both sides draw exactly three from shuffled decks")
	battle.hands[0] = [blade_id]
	expect(battle.play(0, 10) and battle.board[10].armor == 2 and battle.attack_power(battle.board[10]) == 6
		and battle.board[10].weapon == blade_id and battle.can_move_piece(), "The enhanced card equips the commander without using the board action")
	battle.retreat() # The next encounter below starts from a separate expedition.
	run.new_run(81, "wayfarer")
	start = run.actor("hero").position
	run.grant_relic("dry_ink_seal", "hero", start)
	run.grant_relic("banked_ember_box", "hero", start)
	run.grant_relic("rime_thimble", "hero", start)
	run.grant_relic("clear_air_reed", "hero", start)
	run.prepared_weather = "clear_air_reed"
	run.data.tiles[start].enemies = ["boar"]
	battle = Chess.new()
	expect(battle.begin(run, encounter, run.card_deck()).ok and battle.weather == "sun"
		and battle.piles[0].size() == 9 and battle.hands[0].has("temp:ember_spell") and battle.hands[0].size() == 5,
		"A temporary spell enters hand without drawing or changing deck size")
	var spell_index: int = battle.hands[0].find("temp:ember_spell")
	var enemy := battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
	enemy.armor = 2
	var old_hp: int = enemy.hp
	battle.board[4] = enemy
	battle.board[7] = battle._piece(battle.definition("foe:archer"), Chess.ENEMY)
	expect(4 not in battle.card_targets(0, spell_index), "A blocker stops a two-square spell")
	battle.board[7] = {}
	expect(battle.play(spell_index, 4) and enemy.armor == 0 and enemy.hp == old_hp - 2
		and battle.board[10].leader and battle.can_move_piece(), "Fire, weather, relic damage and armor resolve together without moving a piece")
	var loaded := Run.new()
	expect(loaded.load_game(run.save_path).ok and "ice_spell" in Cards.collection(loaded.data.actors, loaded.data),
		"A relic spell unlock survives reloading")
	check_progression()
	check_legacy_loadout()
	print("CHESS LOADOUT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check_progression() -> void:
	var run := Run.new()
	run.save_path = "user://test-chess-progression.json"
	var earlier_hp := 0
	for tier in 5:
		run.new_run(41, "wayfarer")
		var cell: String = run.actor("hero").position
		run.data.tiles[cell].enemies = ["boar"]
		run.data.explored.clear()
		for key in run.data.tiles.keys().slice(0, ceili(run.data.tiles.size() * tier / 5.0)):
			run.data.explored[key] = true
		var battle := Chess.new()
		var result := battle.begin(run, {"position": cell, "origin": cell, "npc": "", "ambush": false}, run.card_deck())
		expect(result.ok and battle.difficulty == tier and battle.commanders[Chess.ENEMY].hp > earlier_hp,
			"Each new exploration band increases enemy strength")
		var enemy_deck: Array = battle.hands[Chess.ENEMY] + battle.piles[Chess.ENEMY]
		expect(enemy_deck.size() == 12 and enemy_deck.filter(func(card): return card.begins_with("foe:")).size() == tier,
			"Enemy deck retains the same size and gains a reinforcement at each band")
		expect(enemy_deck.all(func(card): return not battle.definition(card).is_empty() and enemy_deck.count(card) <= 2),
			"Generated enemy decks use playable cards and obey the copy limits")
		earlier_hp = battle.commanders[Chess.ENEMY].hp
		expect(battle.hands[Chess.PLAYER].any(func(card):
			var entry := battle.definition(card)
			return entry.has("damage") or entry.get("slot") == "weapon"), "First battle guarantees an attack option")
	expect(Chess.difficulty_tier(0, true, false) == 1 and Chess.difficulty_tier(80, true, false) == 4,
		"Elite encounters use the next band, capped at the maximum")

	var battle := Chess.new()
	var roller := RandomNumberGenerator.new()
	var boar_deck := battle._enemy_deck(["boar"], "boar", roller)
	var spiders := battle._enemy_deck(["spider"], "spider", roller)
	expect(boar_deck.count("brace") == 2 and "fog_spell" in spiders and "fog_spell" not in boar_deck,
		"Facing a different commander changes the enemy deck even in the first difficulty band")
	battle.difficulty = 2
	var squad := battle._enemy_deck(["boar", "swarm", "swarm"], "boar", roller)
	expect(squad.count("foe:swarm") == 1 and "foe:archer" in squad,
		"The enemy recruits from its encounter first, with at most one copy of each reinforcement")

	for seed in 24:
		run.new_run(seed, "wayfarer")
		var guards: Array = run.data.nodes.keys().filter(func(cell): return run.node_at(cell).get("intro_duel", false))
		var route: bool = guards.size() == 2 and Hex.distance(Hex.coord(guards[0]), Hex.coord(guards[1])) == 1
		expect(route and guards.all(func(cell): return run.data.tiles[cell].enemies == ["boar"]),
			"Seed %d has two opening duels" % seed)


func check_legacy_loadout() -> void:
	var run := Run.new()
	run.save_path = "user://test-chess-v8-migration.json"
	run.new_run(18, "wayfarer")
	var hero_cell: String = run.actor("hero").position
	run.actor("eve").position = hero_cell
	run.join_companion("eve")
	run.data.version = 8
	run.data.spell_collection = []
	var equipment := run.card_deck().slice(0, 4)
	run.data.card_deck = ["support_vanguard", "support_archer", "support_medic", "support_guard",
		"eve", "ward", "rain", "sun"] + equipment
	expect(run.save_game().ok and run.load_game().ok and Cards.valid_deck(run.card_deck(), run.data.actors, true, run.data)
		and "eve" in run.card_deck() and run.actor("eve").joined and "support_vanguard" not in run.card_deck(),
		"Version 8 saves retain recruited cards and replace former free support without shrinking the deck")
