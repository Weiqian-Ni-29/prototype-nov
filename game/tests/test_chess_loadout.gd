extends SceneTree

const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
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
	expect(deck.size() == 12 and deck.count("rain") == 1 and deck.count("sun") == 1
		and deck.filter(func(id): return id.begins_with("gear:")).size() == 4
		and "ember_spell" not in owned, "New game owns four real equipment cards and two weather spells")
	var blade_id: String = deck[5]
	var uid := blade_id.trim_prefix("gear:")
	var original := Cards.owned_definition(blade_id, run.data.actors, run.data)
	run.data.lamp_coins = 100
	var quote: Dictionary = run.enhancement_quote("hero", uid)
	expect(run.save_card_deck(deck).ok and run.enhance_card("hero", uid).ok
		and run.data.lamp_coins == 100 - quote.price, "Enhancement charges lamps and saves the same card instance")
	var upgraded := Cards.owned_definition(blade_id, run.data.actors, run.data)
	expect(upgraded.level == 1 and upgraded.equip_guard == 1 and run.card_deck() == deck and original.level == 0,
		"Upgrading a gear instance updates the card without editing its deck slot")
	var store := ""
	for pos in run.data.nodes:
		if run.node_at(pos).kind == "trade":
			store = pos
			break
	expect(not store.is_empty(), "Fixture has a store")
	run.retreat_party(store)
	run.data.tiles[store].enemies.clear()
	var offer: String = run.spell_shop_offers(store)[0]
	var balance: int = run.data.lamp_coins
	expect(run.buy_spell("hero", offer).ok and run.data.lamp_coins == balance - 8
		and offer in Cards.collection(run.data.actors, run.data) and run.spell_shop_offers(store).is_empty(),
		"A paid spell becomes a collection card and takes the store's current blueprint slot")
	expect(not run.buy_spell("hero", offer).ok and run.shop_refresh_cost(store) == 1, "A spell purchase cannot repeat or alter refresh costs")
	run.retreat_party(start)
	run.data.tiles[start].enemies = ["boar"]
	var encounter := {"position": start, "origin": start, "npc": "", "ambush": false}
	var battle := Chess.new()
	expect(battle.begin(run, encounter, deck).ok and battle.hands[0].size() == 3
		and battle.hands[1].size() == 3 and battle.piles[0].size() == 9, "Both sides draw exactly three from shuffled decks")
	battle.hands[0] = [blade_id]
	expect(battle.play(0, 10) and battle.board[10].armor == 2 and battle.attack_power(battle.board[10]) == 6
		and battle.board[10].weapon == blade_id and not battle.can_act(), "The enhanced card equips the commander and uses the turn")
	battle.retreat() # The next encounter below starts from a separate expedition.
	run.new_run(81, "wayfarer")
	start = run.actor("hero").position
	run.grant_relic("dry_ink_seal", "hero", start)
	run.grant_relic("banked_ember_box", "hero", start)
	run.grant_relic("clear_air_reed", "hero", start)
	run.prepared_weather = "clear_air_reed"
	run.data.tiles[start].enemies = ["boar"]
	battle = Chess.new()
	expect(battle.begin(run, encounter, run.card_deck()).ok and battle.weather == "sun"
		and battle.piles[0].size() == 9 and battle.hands[0].has("temp:ember_spell") and battle.hands[0].size() == 4,
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
		and battle.board[10].leader and not battle.can_act(), "Fire, weather, relic damage and armor resolve together without moving a piece")
	var loaded := Run.new()
	expect(loaded.load_game(run.save_path).ok and "ember_spell" in Cards.collection(loaded.data.actors, loaded.data),
		"A relic spell unlock survives reloading")
	print("CHESS LOADOUT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
