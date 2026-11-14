extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
const Items = preload("res://scripts/domain/expedition_items.gd")
const ChessView = preload("res://scripts/presentation/chess_battle_view.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func fixture(enemy: String = "boar", ambush: bool = false) -> RefCounted:
	var run := Run.new()
	run.save_path = "user://test-card-chess-domain.json"
	run.new_run(41, "wayfarer")
	var cell: String = run.actor("hero").position
	run.data.tiles[cell].enemies = [enemy]
	var battle := Chess.new()
	expect(battle.begin(run, {"position": cell, "origin": cell, "npc": "", "ambush": ambush}, run.card_deck()).ok, "Battle fixture starts")
	return battle

func check_mana() -> void:
	var battle = fixture()
	expect(battle.mana == [1, 1] and battle.mana_capacity == [1, 1], "Each side opens with one full crystal")
	battle.hands[Chess.PLAYER] = ["brace", "pike"]
	battle.hands[Chess.ENEMY] = ["ward"]
	expect(battle.card_targets(Chess.PLAYER, 1).is_empty() and not battle.play(1, 10)
		and battle.mana[Chess.PLAYER] == 1 and battle.hands[Chess.PLAYER].size() == 2,
		"An unaffordable play does not spend mana or the card")
	expect(not battle.play(0, 1) and battle.mana[Chess.PLAYER] == 1, "An illegal target does not spend mana")
	expect(battle.play(0, 10) and battle.mana[Chess.PLAYER] == 0 and battle.can_move_piece(),
		"A valid play spends mana and leaves the board action available")
	expect(battle.end_turn() and not battle.end_turn(), "The turn can be ended manually exactly once")
	battle.enemy_turn()
	expect(battle.mana[Chess.PLAYER] == 2 and battle.mana_capacity[Chess.PLAYER] == 2
		and battle.hands[Chess.ENEMY] == ["ward"] and battle.mana[Chess.ENEMY] == 1,
		"Turn two refills the player and the enemy cannot play an unaffordable card on its first turn")
	expect(battle.move(10, 7) and battle.mana[Chess.PLAYER] == 2, "Movement does not cost mana")
	expect(battle.end_turn(), "The player can end with unspent mana")
	battle.enemy_turn()
	expect(battle.mana[Chess.PLAYER] == 3 and battle.mana_capacity[Chess.ENEMY] == 2,
		"Each side gains capacity at the start of its own turn")
	battle.hands[Chess.PLAYER] = ["brace", "pike"]
	battle.board[9] = battle._piece(Cards.definition("eve"), Chess.PLAYER)
	battle.board[4] = battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
	expect(battle.play(0, 7) and battle.mana[Chess.PLAYER] == 2, "The player can play a card before moving")
	expect(battle.move(7, 4) and battle.mana[Chess.PLAYER] == 2 and battle.can_act(),
		"A basic attack uses the free board action and leaves the turn active")
	expect(not battle.move(9, 6) and not battle.can_move_piece(), "Another unit cannot move after the team's attack")
	var hero_square: int = battle.board.find(battle.commanders[Chess.PLAYER])
	expect(battle.play(0, hero_square) and battle.mana[Chess.PLAYER] == 0 and battle.can_act(),
		"The player can spend the remaining mana after their board action")
	battle.mana_capacity[Chess.PLAYER] = Chess.MANA_LIMIT
	battle._start_turn(Chess.PLAYER)
	expect(battle.mana[Chess.PLAYER] == 10 and battle.mana_capacity[Chess.PLAYER] == 10,
		"At the cap, spent crystals still refill")
	var ambushed = fixture("boar", true)
	ambushed.hands[Chess.ENEMY] = []
	ambushed.enemy_turn()
	expect(ambushed.turn == Chess.PLAYER and ambushed.round_number == 1 and ambushed.mana[Chess.PLAYER] == 1,
		"The player's first turn starts at one even when the enemy goes first")

func check_enemy_turn_budget() -> void:
	var battle = fixture()
	battle.hands[Chess.ENEMY] = ["brace", "brace"]
	expect(not battle.play(0, 1, Chess.ENEMY) and not battle.move(1, 4, Chess.ENEMY),
		"The enemy cannot use its cards or pieces during the player's turn")
	battle.mana_capacity[Chess.ENEMY] = 2
	battle.mana[Chess.ENEMY] = 2
	var first_pile: Array = battle.piles[Chess.ENEMY].duplicate()
	battle.end_turn()
	var moves_taken := 0
	var cards_played := 0
	for step in 4:
		if battle.turn != Chess.ENEMY:
			break
		var previous_mana: int = battle.mana[Chess.ENEMY]
		battle.enemy_turn(true)
		if battle.turn == Chess.ENEMY:
			if battle.mana[Chess.ENEMY] < previous_mana:
				cards_played += 1
			elif battle.last_enemy_action.has("from"):
				moves_taken += 1
	expect(moves_taken == 1 and cards_played == 2 and battle.turn == Chess.PLAYER
		and battle.round_number == 2 and battle.mana[Chess.ENEMY] == 0,
		"The enemy can play several cards and uses at most one board action per turn")
	expect(battle.piles[Chess.ENEMY] == first_pile and battle.turns_started == [2, 1],
		"The first enemy turn uses the opening hand without an extra draw")
	battle.piles[Chess.ENEMY] = ["ward", "pike"]
	battle.end_turn()
	battle.enemy_turn(true)
	expect(battle.turn == Chess.ENEMY and battle.piles[Chess.ENEMY] == ["pike"]
		and battle.mana_capacity[Chess.ENEMY] == 3 and battle.turns_started == [2, 2],
		"The second enemy turn gains one crystal and draws from its own pile")
	var enemy_square: int = battle.board.find(battle.commanders[Chess.ENEMY])
	expect(not battle.play(0, battle.board.find(battle.commanders[Chess.PLAYER]), Chess.ENEMY)
		and not battle.move(battle.board.find(battle.commanders[Chess.PLAYER]), enemy_square, Chess.ENEMY),
		"Enemy card targets and moving pieces obey the same ownership rules as player actions")
	battle.enemy_turn()
	expect(battle.turn == Chess.PLAYER and battle.piles[Chess.ENEMY] == ["pike"],
		"Resolving further enemy actions does not draw again")

func check_rules() -> void:
	var battle = fixture()
	expect(battle.board.size() == 12 and battle.board.filter(func(piece): return not piece.is_empty()).size() == 2,
		"Three-by-four board begins with just the commanders")
	expect(battle.board[1].side == Chess.ENEMY and battle.board[10].side == Chess.PLAYER,
		"Both commanders start in their center rear squares")
	expect(battle.board[10].element == "ice" and battle.board[1].element == "",
		"The traveler is an ice unit and the boar is untyped")
	expect(battle.hands.all(func(hand): return hand.size() == 3) and battle.piles.all(func(pile): return pile.size() == 9),
		"Both teams draw exactly three opening cards")
	expect(battle.moves(10).keys() == [6, 7, 8, 9, 11], "Commander can move one square horizontally, vertically or diagonally")
	battle.hands[Chess.PLAYER] = ["highdrake"]
	battle.mana_capacity[Chess.PLAYER] = 2
	battle.mana[Chess.PLAYER] = 2
	expect(not battle.play(0, 4) and not battle.play(0, 10) and battle.can_act(), "Cannot deploy onto enemy ground or an occupied square")
	expect(battle.play(0, 7) and battle.board[7].hp == 8 and battle.can_move_piece(),
		"Partner deployment uses the relic's life bonus and leaves the board action available")
	battle.end_turn()
	expect(not battle.move(7, 4), "The player cannot move during the enemy turn")
	battle.enemy_turn()
	expect(battle.round_number == 2 and battle.hands[Chess.PLAYER].size() == 1 and battle.piles[Chess.ENEMY].size() == 9,
		"Next friendly turn draws once and the enemy opening turn uses its three opening cards")

	battle.board[4] = battle._piece(battle.definition("foe:furnace"), Chess.ENEMY)
	battle.board[4].hp = 6
	battle.board[4].armor = 1
	expect(battle.moves(7).get(4) == "attack" and not battle.moves(7).has(1),
		"Enemy blocks the two-square move behind it")
	expect(battle.move(7, 4) and battle.board[4].hp == 2 and battle.board[4].armor == 0
		and battle.board[7].name == "铅翼", "Nonlethal attack consumes armor first and leaves both pieces in place")
	var hit: Dictionary = battle.take_attack()
	expect(hit.from == 7 and hit.target == 4 and hit.defender.hp == 6 and hit.defender.armor == 1
		and hit.hp == 2 and hit.armor == 0 and hit.hp_loss == 4 and hit.armor_loss == 1
		and not hit.lethal and battle.take_attack().is_empty(), "Attack presentation receives pre-hit cards and actual losses once")
	expect(hit.retaliation.armor_loss == 1 and hit.retaliation.hp_loss == 2 and battle.board[7].hp == 6,
		"The defender's attack damages the initiator in the same exchange, armor first")
	battle._start_turn(Chess.PLAYER)
	expect(battle.move(7, 4) and battle.board[7].is_empty() and battle.board[4].name == "铅翼",
		"Only the lethal attack captures the square")
	hit = battle.take_attack()
	expect(hit.lethal and hit.hp_loss == 2 and hit.hp == 0 and hit.retaliation.hp_loss == 3
		and battle.board[4].hp == 3, "A defeated unit still returns its full damage before the survivor occupies its square")
	battle.board[4].hp = 3
	battle.hands[Chess.PLAYER] = ["eve"]
	expect(battle.play(0, 7) and battle.board[4].hp == 6, "Ivy heals the adjacent wounded ally on deployment")
	battle.hands[Chess.PLAYER] = ["ward"]
	battle.mana[Chess.PLAYER] = 2
	expect(battle.play(0, 7) and battle.board[7].armor == 2 and battle.board[4].armor == 2 and battle.board[10].armor == 3,
		"Column defense applies to every friendly piece in the column")
	battle.hands[Chess.PLAYER] = ["pike"]
	battle.mana[Chess.PLAYER] = 2
	expect(battle.play(0, 10) and battle.attack_power(battle.board[10]) == 5, "Weapon raises the attack of the chosen piece")
	var wayfarer_gear := Gear.card({"definition_id": "grave_wayfarer_weapon", "enhance_level": 0, "quality": Gear.QUALITIES[0]})
	var armor_before: int = battle.board[10].armor
	battle._apply_card(Chess.PLAYER, "gear:wayfarer", wayfarer_gear, 10)
	expect(wayfarer_gear.element == "ice" and battle.board[10].armor == armor_before + 1,
		"Wayfarer gear preserves its affinity guard on the ice commander")
	battle.hands[Chess.PLAYER] = ["rain"]
	battle.mana[Chess.PLAYER] = 1
	expect(battle.play(0, -1) and battle.weather == "rain" and battle.attack_power(battle.board[7]) == 3,
		"Weather modifies elemental attacks after the board action")
	expect(battle.take_attack().is_empty(), "Playing a weather card does not create an attack animation")
	battle._start_turn(Chess.PLAYER)
	battle.commanders[Chess.ENEMY].hp = 1
	battle.commanders[Chess.ENEMY].armor = 0
	battle.board[battle.board.find(battle.commanders[Chess.ENEMY])] = {}
	battle.board[1] = battle.commanders[Chess.ENEMY]
	var spot: String = battle.position
	var before: Dictionary = battle.run.actor("hero").inventory.duplicate()
	expect(battle.move(4, 1) and battle.outcome == "victory" and battle.run.data.pending_battle.is_empty()
		and battle.run.data.tiles[spot].enemies.is_empty(), "Capturing the enemy commander settles the actual encounter")
	expect(battle.run.actor("hero").inventory == before and battle.run.data.has("pending_victory")
		and battle.run.data.peace.has(spot) and battle.run.data.pending_victory.coins >= 4,
		"Victory awards loot and creates a saved receipt")
	battle._finish("victory")
	expect(battle.run.actor("hero").inventory == before, "Settlement cannot grant twice")

func check_equipment_replacement() -> void:
	var battle = fixture()
	var unit: Dictionary = battle.board[10]
	battle.mana[Chess.PLAYER] = 10
	battle.hands[Chess.PLAYER] = ["temp:pike", "blade"]
	var base_attack: int = battle.attack_power(unit)
	expect(battle.play(0, 10) and battle.attack_power(unit) == base_attack + 1 and battle._attack_range(unit) == 2,
		"The temporary pike grants its attack and range")
	expect(not battle.play(0, 1) and battle.hands[Chess.PLAYER] == ["blade"] and unit.weapon == "temp:pike",
		"A replacement cannot target an enemy")
	expect(battle.play(0, 10) and battle.hands[Chess.PLAYER] == ["temp:pike"] and unit.weapon == "blade"
		and battle.attack_power(unit) == base_attack + 2 and battle._attack_range(unit) == 1
		and battle.mana[Chess.PLAYER] == 7 and battle.can_move_piece(),
		"Swapping the weapon charges only the new card, returns the exact ID, and replaces attack and range")

	var armor_uid := Items.add_gear(battle.run.data, "padded_coat", "common", "actor", "hero")
	var other_armor_uid := Items.add_gear(battle.run.data, "padded_coat", "common", "actor", "hero")
	battle.run.data.gear_instances[armor_uid].enhance_level = 2
	var armor := "gear:" + armor_uid
	var other_armor := "gear:" + other_armor_uid
	var base_armor: int = unit.armor
	battle.hands[Chess.PLAYER] = [armor, other_armor, "brace"]
	expect(battle.play(0, 10) and unit.armor == base_armor + 5, "The upgraded coat grants five armor")
	battle._damage(unit, 2)
	expect(battle.play(1, 10) and battle.play(0, 10) and unit.armor == base_armor + 6
		and battle.hands[Chess.PLAYER] == [armor] and battle.definition(armor).level == 2 and unit.weapon == "blade",
		"An armor swap removes remaining armor from the old coat and preserves defense buffs and card upgrades")

	var charm_uid := Items.add_gear(battle.run.data, "lamp_charm", "common", "actor", "hero")
	var stronger_charm_uid := Items.add_gear(battle.run.data, "lamp_charm", "common", "actor", "hero")
	battle.run.data.gear_instances[stronger_charm_uid].enhance_level = 2
	var charm := "gear:" + charm_uid
	var stronger_charm := "gear:" + stronger_charm_uid
	var base_hp_max: int = unit.hp_max
	battle.hands[Chess.PLAYER] = [stronger_charm, charm]
	battle.mana[Chess.PLAYER] = 6
	expect(battle.play(0, 10) and unit.hp_max == base_hp_max + 2, "The stronger charm raises maximum health")
	unit.hp = 1
	expect(battle.play(0, 10) and unit.hp_max == base_hp_max + 1 and unit.hp == 1
		and battle.hands[Chess.PLAYER] == [stronger_charm],
		"Swapping to a weaker charm removes its previous HP bonus without defeating the wearer")
	expect(not battle.play(0, 10) and unit.hp_max == base_hp_max + 1 and battle.hands[Chess.PLAYER] == [stronger_charm],
		"An unaffordable replacement leaves the equipment and hand intact")

func check_retaliation() -> void:
	var battle = fixture()
	var attacker: Dictionary = battle._piece(Cards.definition("support_archer"), Chess.PLAYER)
	var defender: Dictionary = battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
	battle.board[7] = attacker
	battle.board[1] = defender
	battle.board[0] = battle.commanders[Chess.ENEMY]
	attacker.hp = 2
	defender.hp = 2
	defender.armor = 0
	expect(not battle.moves(1).has(7) and battle.move(7, 1), "A ranged attack can reach a melee defender")
	var hit: Dictionary = battle.take_attack()
	expect(hit.lethal and hit.retaliation.lethal and battle.board[7].is_empty() and battle.board[1].is_empty(),
		"The lethal counter hits regardless of reach and leaves both squares empty when both pieces fall")
	expect(battle.ally_losses == 1 and battle.enemy_losses == 1 and not battle.can_move_piece(),
		"Both deaths are recorded and the exchange spends only the initiating team's board action")

	battle = fixture()
	battle.board[4] = battle.board[1]
	battle.board[1] = {}
	battle.board[7] = battle.board[10]
	battle.board[10] = {}
	battle.commanders[Chess.PLAYER].hp = 1
	battle.commanders[Chess.PLAYER].armor = 0
	battle.commanders[Chess.ENEMY].hp = 1
	battle.commanders[Chess.ENEMY].armor = 0
	expect(battle.move(7, 4) and battle.commanders[Chess.ENEMY].hp == 0 and battle.outcome == "defeat",
		"Losing the traveler ends the expedition even when the exchange also defeats the rival commander")

	battle = fixture()
	battle.board[4] = battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
	battle.board[4].hp = 1
	battle.board[4].armor = 0
	battle.hands[Chess.PLAYER] = ["ember_spell"]
	var hp_before: int = battle.board[10].hp
	var armor_before: int = battle.board[10].armor
	expect(battle.play(0, 4) and battle.board[4].is_empty() and battle.board[10].hp == hp_before
		and battle.board[10].armor == armor_before and battle.take_attack().is_empty(),
		"A targeted damage spell resolves without retaliation")

func check_attack_feedback() -> void:
	var battle = fixture("archer")
	var enemy: Dictionary = battle.board[1]
	battle.board[4] = enemy
	battle.board[1] = {}
	expect(enemy.range == 1 and enemy.attack_delivery == "ranged" and enemy.attack_projectile == "arrow"
		and Cards.definition("support_vanguard").get("attack_delivery", "melee") == "melee",
		"Attack delivery is independent of legal reach for archers and melee vanguards")
	battle.board[7] = battle.board[10]
	battle.board[10] = {}
	battle.board[7].armor = 10
	var view := ChessView.new()
	root.add_child(view)
	view.setup(battle, null)
	await process_frame
	await process_frame
	var target_rect := view.cells[7].get_global_rect()
	var round_before: int = battle.round_number
	# Force the board action to be the archer shooting the neighboring commander.
	enemy.move = 0
	enemy.diagonal = false
	battle.hands[Chess.ENEMY] = []
	battle.turn = Chess.ENEMY
	battle.enemy_turn(true)
	view.present_action()
	var effect := view.attack_effect
	expect(effect != null and effect.ranged and effect.arrow and effect.attack.from == 4 and effect.attack.target == 7
		and battle.round_number == round_before and not view.turn_banner.visible and view.menu.disabled,
		"The real enemy action animates an adjacent ranged attack before returning player input")
	if effect != null:
		var before := effect.attacker.position
		await effect.impact
		expect(effect.attacker.position.is_equal_approx(before) and effect.losses.get_child_count() == 1
			and effect.losses.get_child(0).get_child(0).text.begins_with("护甲")
			and effect.defender.get_node("Armor").get_child(0).text == str(battle.board[7].armor)
			and view.cells[7].get_global_rect() == target_rect,
			"An armor-only projectile leaves the attacker and grid in place and updates only armor")
		expect(effect.retaliation_losses.visible and effect.retaliation_losses.get_child_count() == 2
			and effect.retaliation_losses.get_child(1).get_child(0).text.begins_with("生命")
			and effect.attacker.get_node("Health").get_child(0).text == str(enemy.hp),
			"The counter damage appears on the attacking archer on the same frame")
		await effect.finished
	expect(not view.is_attack_playing() and not view.menu.disabled, "The attack overlay releases its input lock")

	battle.turn = Chess.PLAYER
	battle.board[7].attack = 0
	view.render()
	view.cells[7].pressed.emit()
	view.cells[4].pressed.emit()
	effect = view.attack_effect
	expect(effect != null and not effect.ranged, "Normal player input triggers the melee presentation")
	if effect != null:
		await effect.impact
		expect(effect.losses.get_child_count() == 1 and effect.losses.get_child(0).get_child(0).text == "未造成伤害",
			"A zero-damage hit shows no armor or health loss")
		await effect.finished
	view.queue_free()
	await process_frame

func check_fatigue() -> void:
	var battle = fixture()
	battle.board[7] = battle._piece(Cards.definition("eve"), Chess.PLAYER)
	battle.board[4] = battle._piece(battle.definition("foe:furnace"), Chess.ENEMY)
	battle.piles = [[], []]
	var hero: Dictionary = battle.commanders[Chess.PLAYER]
	var enemy: Dictionary = battle.commanders[Chess.ENEMY]
	var hero_hp: int = hero.hp
	var enemy_hp: int = enemy.hp
	battle._draw(Chess.PLAYER)
	expect(battle.fatigue == [1, 0] and hero.hp == hero_hp and hero.armor == 0 and battle.board[7].hp == 6,
		"First empty draw hits the entire team, shield first, without changing the opponent's fatigue")
	battle._draw(Chess.PLAYER)
	battle._draw(Chess.ENEMY)
	expect(battle.fatigue == [2, 1] and hero.hp == hero_hp - 2 and battle.board[7].hp == 4
		and enemy.hp == enemy_hp and battle.board[4].armor == 0, "Fatigue increases separately and damages all living pieces")
	hero.hp = 2
	battle._draw(Chess.PLAYER)
	battle._check_outcome()
	expect(battle.outcome == "defeat" and battle.run.data.status == "failed", "Fatigue can defeat the commander before another action")

func ranged_threat_fixture(card_id: String) -> RefCounted:
	var battle = fixture()
	battle.commanders[Chess.ENEMY].hp = 3
	battle.commanders[Chess.ENEMY].armor = 0
	battle.board[7] = battle._piece(Cards.definition("lorne"), Chess.PLAYER)
	battle.board[7].element = "fire"
	battle.board[6] = battle._piece(Cards.definition("eve"), Chess.PLAYER)
	battle.board[6].hp = 1
	for square in [0, 2, 3, 5]:
		battle.board[square] = battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
		battle.board[square].move = 0
	battle.turn = Chess.ENEMY
	battle.weather = "rain"
	battle.weather_rounds = 1
	battle.hands[Chess.ENEMY] = [card_id]
	battle.mana_capacity[Chess.ENEMY] = 2
	battle.mana[Chess.ENEMY] = 2
	return battle

func check_enemy_strategy() -> void:
	var battle = ranged_threat_fixture("foe:boar")
	var board_before := JSON.stringify(battle.board)
	var run_before := JSON.stringify(battle.run.data)
	var save_before := FileAccess.get_file_as_string(battle.run.save_path)
	var action: Dictionary = battle._choose_enemy_action()
	expect(action.get("card_index") == 0 and action.get("target") == 4,
		"Enemy deploys into the firing lane instead of taking a kill when rain is about to expire")
	expect(JSON.stringify(battle.board) == board_before and JSON.stringify(battle.run.data) == run_before
		and FileAccess.get_file_as_string(battle.run.save_path) == save_before and battle.hands[Chess.ENEMY] == ["foe:boar"],
		"Trial actions leave the real board, cards, expedition and save untouched")
	battle.hands[Chess.PLAYER] = ["sun", "blade", "pike"]
	battle.piles[Chess.PLAYER].reverse()
	expect(battle._choose_enemy_action() == action, "The same public position produces the same action with different hidden cards")
	battle.enemy_turn(true)
	expect(battle.turn == Chess.ENEMY and battle.weather == "rain" and battle.hands[Chess.ENEMY].is_empty()
		and battle.board[4].get("side") == Chess.ENEMY and not battle.moves(7).has(1) and battle.board[6].hp == 1,
		"The enemy first uses its hand to block the lane and preserves its free board action")
	battle.enemy_turn()
	expect(battle.turn == Chess.PLAYER and battle.weather.is_empty() and not battle.moves(7).has(1),
		"The lane stays blocked when the full turn ends and rain expires")

	battle = ranged_threat_fixture("coat")
	battle.enemy_turn(true)
	expect(battle.commanders[Chess.ENEMY].armor == 3 and battle.board[6].hp == 1
		and battle.moves(7).has(1) and battle.attack_power(battle.board[7]) == 2,
		"Enemy equips armor when it must survive an open firing lane")

	battle = fixture()
	battle.board[4] = battle._piece(Cards.definition("eve"), Chess.PLAYER)
	battle.board[4].hp = 1
	battle.board[4].attack = 1
	battle.board[11] = battle.board[10]
	battle.board[10] = battle._piece(Cards.definition("lorne"), Chess.PLAYER)
	battle.commanders[Chess.ENEMY].hp = 2
	battle.commanders[Chess.ENEMY].armor = 0
	battle.hands[Chess.ENEMY] = []
	battle.turn = Chess.ENEMY
	battle.enemy_turn()
	expect(battle.board[4].get("name") == "伊芙" and battle.board.find(battle.commanders[Chess.ENEMY]) != 4,
		"Commander declines the capture that would step into a lethal two-square attack")

	battle = fixture()
	battle.board[4] = battle.board[1]
	battle.board[1] = {}
	battle.board[7] = battle.board[10]
	battle.board[10] = {}
	battle.commanders[Chess.PLAYER].hp = 3
	battle.commanders[Chess.PLAYER].armor = 0
	battle.board[3] = battle._piece(Cards.definition("eve"), Chess.PLAYER)
	battle.board[3].hp = 1
	battle.board[0] = battle._piece(battle.definition("foe:furnace"), Chess.ENEMY)
	battle.board[0].attack = 20
	battle.turn = Chess.ENEMY
	battle.enemy_turn()
	expect(battle.outcome == "defeat" and battle.board[7].get("leader", false) and battle.board[3].hp == 1,
		"Enemy takes the immediate commander win over a higher-damage attack on a partner")

func check_companion_growth() -> void:
	var run := Run.new()
	run.save_path = "user://test-companion-growth.json"
	run.new_run(41, "wayfarer")
	expect(not "lorne" in Cards.collection(run.data.actors) and Cards.valid_deck(run.card_deck(), run.data.actors, true, run.data),
		"The solo starter deck is complete and named cards require recruitment")
	expect(not run.recruit_companion("lorne").ok and run.data.lamp_coins == 8, "Recruitment requires a post-battle shop")
	var cell: String = run.data.start
	run.data.battles = 1
	run.data.pending_victory = {"enemies": 1, "members": ["hero"], "revived": [], "relic": ""}
	run.open_battle_shop()
	run.data.tiles[cell].enemies = ["boar"]
	expect(not run.recruit_companion("lorne").ok, "Enemies block recruitment")
	run.data.tiles[cell].enemies.clear()
	run.data.lamp_coins = 5
	expect(not run.recruit_companion("lorne").ok and run.data.lamp_coins == 5, "Recruitment requires the full price")
	run.data.lamp_coins = 6
	expect(run.recruit_companion("lorne").ok and run.data.lamp_coins == 0 and "lorne" in Cards.collection(run.data.actors)
		and not run.recruit_companion("lorne").ok, "Recruitment charges once and unlocks the companion card")
	expect(not run.breakthrough_companion("lorne", 0).ok, "Breakthrough requires funds")
	run.data.lamp_coins = 44
	var normal_path: String = run.save_path
	run.save_path = "user://missing-growth-%d/save.json" % OS.get_process_id()
	expect(not run.breakthrough_companion("lorne", 0).ok and run.data.lamp_coins == 44
		and run.actor("lorne").get("breakthrough", 0) == 0, "Write failure rolls back rank and coins")
	run.save_path = normal_path
	var base := Cards.definition("lorne")
	expect(run.breakthrough_companion("lorne", 0).ok and not run.breakthrough_companion("lorne", 0).ok
		and Cards.owned_definition("lorne", run.data.actors).hp == base.hp + 2 and run.data.lamp_coins == 36,
		"The first breakthrough raises health and a stale confirmation cannot buy the next rank")
	expect(run.breakthrough_companion("lorne", 1).ok and Cards.owned_definition("lorne", run.data.actors).armor == base.armor + 1,
		"The second breakthrough raises starting armor")
	expect(run.breakthrough_companion("lorne", 2).ok and run.data.lamp_coins == 0 and not run.breakthrough_companion("lorne", 3).ok,
		"The third breakthrough unlocks the talent and caps progression")
	var saved := Run.new()
	saved.save_path = normal_path
	expect(saved.load_game(normal_path).ok and saved.actor("lorne").breakthrough == 3,
		"Paid recruitment and breakthroughs survive loading")
	var deck: Array = saved.card_deck()
	deck[1] = "lorne"
	saved.data.tiles[cell].enemies = ["boar"]
	saved.close_battle_shop()
	saved.data.erase("pending_victory")
	var battle := Chess.new()
	expect(battle.begin(saved, {"position": cell, "origin": cell, "npc": "", "ambush": false}, deck).ok,
		"Recruited cards enter a real battle")
	battle.board[9] = battle.board[10]
	battle.board[10] = {}
	battle.hands[Chess.PLAYER] = ["lorne"]
	battle.mana_capacity[Chess.PLAYER] = 2
	battle.mana[Chess.PLAYER] = 2
	expect(battle.play(0, 10) and battle.board[10].attack == base.attack + 1 and battle.board[10].hp == base.hp + 3
		and battle.moves(10).get(1) == "attack", "The breakthrough card deploys with its improved stats and three-square range")
	battle.board[4] = battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
	expect(not battle.moves(10).has(1), "A blocker still stops a three-square shot")

func check_battle_income() -> void:
	for reward in [["furnace_elite", 8, 12], ["war_god", 16, 20]]:
		var battle = fixture(reward[0])
		var before: int = battle.run.data.lamp_coins
		battle._finish("victory")
		var coins: int = battle.run.data.pending_victory.coins
		expect(coins >= reward[1] and coins <= reward[2] and battle.run.data.lamp_coins == before + coins,
			"Victory pays its battle-tier coin reward and records it on the receipt")
		battle._finish("victory")
		expect(battle.run.data.lamp_coins == before + coins, "Reopening settlement does not pay twice")

func click(node: Button, point_in_button: Vector2 = Vector2(0.5, 0.5)) -> void:
	expect(node != null and not node.disabled, "Visible enabled button: " + (str(node.name) if node != null else "<missing>"))
	if node != null and not node.disabled:
		var parent := node.get_parent()
		while parent != null:
			if parent is ScrollContainer:
				parent.ensure_control_visible(node)
			parent = parent.get_parent()
		await process_frame
		var rect := node.get_global_rect()
		var point := rect.position + rect.size * point_in_button
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event, true)
	await process_frame

func button_named(parent: Node, title: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == title and node.is_visible_in_tree():
			return node as Button
	return null

func check_ui() -> void:
	var game := Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-card-chess-ui.json"
	game._start_new()
	await process_frame
	await click(button_named(game.ui, "卡组"))
	var editor = game.modal_layer.find_child("CardDeckEditor", true, false)
	expect(editor != null and editor.grid.get_child_count() >= 10, "Map opens the full illustrated collection")
	if editor == null:
		game.queue_free()
		return
	editor.search.text = "回复 2 点生命"
	editor.search.text_changed.emit(editor.search.text)
	expect(editor.grid.get_child_count() == 1 and editor.selected == "mend_spell", "Search finds the starter healing card by effect")
	editor.search.clear()
	editor.search.text_changed.emit("")
	var water_index := Cards.ELEMENTS.keys().find("water") + 1
	expect(editor.attribute.item_count == 7 and editor.attribute.get_item_text(water_index).is_empty()
		and editor.attribute.get_item_icon(water_index).resource_path.ends_with("/water.svg"),
		"The collection filters offer exactly the six element icons")
	editor.attribute.select(water_index)
	editor.attribute.item_selected.emit(water_index)
	expect(editor.grid.get_child_count() > 0 and editor.grid.get_children().all(
		func(button): return button.name in ["Collection_rain", "Collection_mend_spell"]),
		"The water icon filters the collection to water cards")
	editor.attribute.select(0)
	editor.attribute.item_selected.emit(0)
	editor.search.text = "唤雨"
	editor.search.text_changed.emit(editor.search.text)
	await process_frame
	await click(editor.find_child("Collection_rain", true, false))
	await click(editor.find_child("AddDeckCard", true, false))
	await click(editor.find_child("AddDeckCard", true, false))
	var capped := editor.find_child("AddDeckCard", true, false) as Button
	expect(editor.total.text == "14 张" and capped != null and capped.disabled,
		"The editor adds cards beyond twelve and still enforces the per-card limit")
	await click(editor.find_child("Remove_rain", true, false))
	await click(editor.find_child("ConfirmCardDeck", true, false))
	var saved := Run.new()
	expect(saved.load_game(game.run.save_path).ok and saved.card_deck().size() == 13 and saved.card_deck().count("rain") == 1,
		"The thirteen-card deck persists in the expedition save")
	var cell: String = game.run.actor("hero").position
	game.run.data.tiles[cell].enemies = ["boar"]
	game._open_current_encounter(false)
	await process_frame
	var start := game.modal_layer.find_child("ConfirmCardDeck", true, false) as Button
	await click(start)
	var view = game.ui.find_child("ChessBattle", true, false)
	expect(view != null and not game.view.visible, "Normal encounter shows the chess board and hides the map")
	if view != null:
		expect(root.get_visible_rect().encloses(view.get_global_rect()) and view.cells.size() == 12 and view.hand_buttons.size() == 3,
			"Board fits the viewport with twelve squares and a three-card opening hand")
		expect(game.combat.piles[Chess.PLAYER].size() == 10 and game.combat.piles[Chess.ENEMY].size() == 9,
			"The battle uses all thirteen player cards and the usual twelve enemy cards")
		expect(view.enemy_cards.text == "手牌 3\n牌库 9" and view.enemy_mana_ratio.text == "1/1"
			and view.enemy_deck_back.visible, "The rail shows the opponent's opening resources without showing card faces")
		var grid := view.find_child("ChessGrid", true, false) as GridContainer
		expect(grid != null and grid.columns == Chess.COLS and grid.get_child_count() == view.cells.size(),
			"The chess grid contains only the twelve squares")
		var grid_rect := grid.get_global_rect()
		var view_rect: Rect2 = view.get_global_rect()
		var rail := view.find_child("ChessMana", true, false) as Control
		expect(is_equal_approx(grid_rect.position.x - view_rect.position.x, 24.0)
			and rail != null and rail.get_global_rect().position.x > grid_rect.end.x
			and is_equal_approx(rail.get_global_rect().end.x, view_rect.end.x - 15.0),
			"The board expands up to its right-side mana column")
		var board_labels: Array[Node] = view.find_children("*", "Label", true, false)
		expect(not board_labels.any(func(label): return label.text in ["左路", "中路", "右路", "敌方\n后排", "敌方\n前排",
			"己方\n前排", "己方\n后排", "共鸣遗器", "战斗记录"]), "Board headings and the sidebar are absent")
		var menu := view.find_child("ChessMainMenu", true, false) as Button
		var retreat_rect: Rect2 = view.retreat.get_global_rect()
		var menu_rect := menu.get_global_rect() if menu != null else Rect2()
		var menu_top_right := Vector2(menu_rect.end.x, menu_rect.position.y)
		var view_top_right := Vector2(view_rect.end.x, view_rect.position.y)
		expect(menu != null and menu_top_right.distance_to(view_top_right) <= 22
			and retreat_rect.size == Vector2(48, 40) and menu_rect.size == Vector2(48, 40)
			and is_equal_approx(menu_rect.position.y, retreat_rect.position.y)
			and is_equal_approx(menu_rect.position.x - retreat_rect.end.x, 4.0),
			"Retreat and Main Menu sit side by side in a compact top-right row")
		expect(menu != null and menu.text.is_empty() and menu.accessibility_name == "主菜单"
			and menu.icon != null and menu.icon.resource_path.ends_with("/story-main-menu.svg")
			and view.retreat.text.is_empty() and view.retreat.accessibility_name == "撤退"
			and view.retreat.icon != null and view.retreat.icon.resource_path.ends_with("/chess-retreat.svg"),
			"The navigation buttons show only their icons and expose accessible names")
		for square in [1, 10]:
			var tile: Button = view.cells[square]
			var labels := tile.find_children("*", "Label", true, false)
			var textures := tile.find_children("*", "TextureRect", true, false)
			expect(not labels.any(func(label): return "主战者" in label.text),
				"Commander square %d omits the visible role label" % square)
			var has_crown := textures.any(func(rect):
				return rect.is_visible_in_tree() and rect.texture != null and rect.texture.resource_path.ends_with("/crown-badge.svg"))
			expect(has_crown, "Commander square %d still shows its crown" % square)
			expect("主战者" in tile.accessibility_name, "Commander square %d announces the role to screen readers" % square)
		await click(view.retreat)
		await click(button_named(game.modal_layer, "取消，继续远征"))
		await click(view.find_child("ChessSquare10", true, false))
		await click(view.find_child("ChessSquare7", true, false))
		expect(game.combat.turn == Chess.PLAYER and not game.combat.can_move_piece()
			and not view.end_turn_button.disabled, "A mouse move spends the board action and leaves End Turn available")
		game.combat.piles[Chess.PLAYER][0] = "ward"
		game.combat.hands[Chess.ENEMY] = []
		await click(view.end_turn_button)
		expect(view.end_turn_button.disabled and view.end_turn_button.text == "敌方回合", "End Turn hands off to the enemy")
		game.battle_timer = 0.0
		await process_frame
		await process_frame
		expect(game.combat.turn == Chess.ENEMY and game.combat.board_action_used[Chess.ENEMY]
			and view.turn_banner_text.text == "敌方回合" and not game.combat.last_enemy_action.is_empty(),
			"The enemy resolves its action before the player gets another turn")
		game.battle_timer = 0.0
		await process_frame
		await process_frame
		expect(game.combat.round_number == 2 and view.hand_buttons.size() == 4, "Enemy responds once and the next card animates into the hand")
		await create_timer(0.5).timeout
		await click(view.hand_buttons[-1])
		expect(view.selected_card == 3 and (not view._legal().is_empty() or view.cast_button.visible),
			"Clicking the drawn card raises it and offers legal targets or a spell confirmation")
		expect(is_zero_approx(view.hand_buttons[-1].rotation)
			and view.hand_buttons[-1].position.y < view.hand_buttons[0].position.y,
			"The selected hand card straightens and rises above the fan")
		await click(menu)
		await click(button_named(game.modal_layer, "确认"))
		game._continue_run()
		expect(game.modal_layer.find_child("CardDeckEditor", true, false) != null and not game.run.data.pending_battle.is_empty(),
			"Continuing resumes the saved encounter before the board")
	game.queue_free()
	await process_frame

func check_hand_layout() -> void:
	var battle = fixture()
	var large_hand: Array = Cards.DEFAULT_DECK + Cards.DEFAULT_DECK + ["rain", "sun"]
	battle.hands[Chess.PLAYER] = large_hand
	battle.draw_count = 0
	var view := ChessView.new()
	root.add_child(view)
	view.setup(battle, null)
	await process_frame
	await process_frame
	var hand_bounds := Rect2(Vector2.ZERO, view.hand.size).grow(0.1)
	var all_inside := true
	for button in view.hand_buttons:
		var card_transform := view.hand.get_global_transform().affine_inverse() * button.get_global_transform()
		for corner in [Vector2.ZERO, Vector2(button.size.x, 0), button.size, Vector2(0, button.size.y)]:
			all_inside = all_inside and hand_bounds.has_point(card_transform * corner)
	expect(view.hand_buttons.size() == large_hand.size() and all_inside, "A large hand fits inside its panel")
	expect(view.hand_buttons.all(func(button): return is_equal_approx(button.size.aspect(), 5.0 / 7.0)),
		"Every hand card has a five-by-seven portrait aspect ratio")
	view._hover_card(0)
	expect(view.hand_buttons[0].z_index > view.hand_buttons[-1].z_index,
		"A raised card appears above the entire large hand")
	view.queue_free()
	await process_frame

func check_mana_display() -> void:
	var battle = fixture()
	battle.hands[Chess.PLAYER] = ["ember_spell", "pike", "temp:mend_spell"]
	battle.draw_count = 0
	var view := ChessView.new()
	root.add_child(view)
	view.setup(battle, null)
	await process_frame
	await process_frame
	var bottom := view.mana_crystals[0]
	var bottom_y := bottom.global_position.y
	var ratio_y := view.mana_ratio.global_position.y
	expect(view.mana_row.get_child_count() == 1 and view.mana_ratio.text == "1/1"
		and bottom.get_global_rect().end.y <= ratio_y, "The first turn has one crystal and the ratio below it")
	expect(view.end_turn_button.get_global_rect().position.y >= view.mana_ratio.get_global_rect().end.y,
		"End Turn sits at the bottom of the rail below the player's mana")
	var pike := view.hand_buttons[1]
	var badge := pike.find_child("ManaCost", true, false) as TextureRect
	expect(badge != null and badge.get_child(0).text == "2"
		and badge.position.x < pike.size.x * 0.5 and badge.position.y < pike.size.y * 0.5,
		"Hand cards show their cost in the top left")
	await click(pike)
	expect(view.selected_card == -1 and "法力不足" in view.hint.text, "Clicking an unaffordable card explains the shortfall")
	battle.mana_capacity[Chess.PLAYER] = 3
	battle.mana[Chess.PLAYER] = 1
	battle.hands[Chess.ENEMY] = ["brace"]
	battle.piles[Chess.ENEMY] = []
	battle.mana_capacity[Chess.ENEMY] = 2
	battle.mana[Chess.ENEMY] = 0
	view.render()
	await process_frame
	await process_frame
	expect(view.mana_row.get_child_count() == 3 and view.mana_ratio.text == "1/3"
		and is_equal_approx(bottom.global_position.y, bottom_y)
		and is_equal_approx(view.mana_ratio.global_position.y, ratio_y)
		and view.mana_crystals[2].global_position.y < view.mana_crystals[1].global_position.y
		and view.mana_crystals[1].global_position.y < bottom_y
		and bottom.self_modulate == Color.WHITE and view.mana_crystals[2].self_modulate != Color.WHITE,
		"Crystals grow upwards from a fixed baseline, with spent crystals dimmed")
	expect(view.enemy_cards.text == "手牌 1\n牌库 0" and view.enemy_mana_ratio.text == "0/2"
		and not view.enemy_deck_back.visible, "Enemy resources update separately and an exhausted deck loses its card back")
	view.queue_free()
	await process_frame

func check_deck_draw() -> void:
	var battle = fixture()
	battle.hands[Chess.PLAYER] = ["brace", "ward", "ember_spell"]
	battle.piles[Chess.PLAYER] = ["rain"]
	battle.draw_count = 0
	var view := ChessView.new()
	root.add_child(view)
	view.setup(battle, null)
	await process_frame
	await process_frame
	var top := view.deck_layers[0]
	expect(top.visible and top.global_position.x >= view.hand.get_global_rect().end.x
		and not view.deck_layers[1].visible and view.pile.text == "牌库 1 张",
		"The last card sits in the right-hand deck")
	var first_position := view.hand_buttons[0].position
	battle._draw(Chess.PLAYER)
	view.render()
	var drawn := view.hand_buttons[-1]
	expect(view.pile.text == "牌库 1 张" and view.hand_label.text == "手牌  3 张" and drawn.disabled,
		"A queued draw keeps the displayed counts and cannot be selected")
	var saw_lift := false
	var saw_departure := false
	var saw_reveal := false
	var saw_fan_expand := false
	var timeout := Time.get_ticks_msec() + 2000
	while drawn.disabled and Time.get_ticks_msec() < timeout:
		await process_frame
		var back := drawn.get_node_or_null("DrawCardBack") as TextureRect
		if back == null or not drawn.disabled or not drawn.visible:
			continue
		if back.visible and view.pile.text == "牌库 1 张":
			var center := drawn.get_global_transform() * (drawn.size * 0.5)
			saw_lift = saw_lift or center.distance_to(top.get_global_rect().get_center()) < 15.0
		if back.visible and view.pile.text.begins_with("牌库 0 张"):
			saw_departure = saw_departure or view.empty_deck.visible and not top.visible
		if not back.visible and drawn.get_child(0).visible:
			saw_reveal = true
			saw_fan_expand = saw_fan_expand or not view.hand_buttons[0].position.is_equal_approx(first_position)
	expect(saw_lift and saw_departure and saw_reveal and saw_fan_expand,
		"The card lifts from the deck, decrements it, flips, and makes space in the hand")
	expect(view.animating.is_empty() and view.hand_label.text == "手牌  4 张" and drawn.scale.is_equal_approx(Vector2.ONE),
		"The last draw settles and increases the hand count")
	await click(drawn)
	expect(view.selected_card == 3, "The drawn card becomes selectable after landing")
	view.queue_free()
	await process_frame

func check_board_badges() -> void:
	var battle = fixture()
	battle.board[11] = battle._piece(Cards.definition("eve"), Chess.PLAYER)
	var view := ChessView.new()
	root.add_child(view)
	view.setup(battle, null)
	await process_frame
	await process_frame
	var flush := true
	for square in view.cells.size():
		var rect := view.cells[square].get_global_rect()
		if square % Chess.COLS < Chess.COLS - 1:
			flush = flush and is_equal_approx(rect.end.x, view.cells[square + 1].get_global_rect().position.x)
		if square + Chess.COLS < view.cells.size():
			flush = flush and is_equal_approx(rect.end.y, view.cells[square + Chess.COLS].get_global_rect().position.y)
	expect(flush, "All twelve square buttons share edges with their neighbors")
	for square in [1, 10, 11]:
		var tile := view.cells[square]
		var unit: Dictionary = battle.board[square]
		var rect := tile.get_global_rect()
		for stat in [["Attack", battle.attack_power(unit), Vector2(-1, 1)],
				["Health", unit.hp, Vector2(1, 1)], ["Armor", unit.armor, Vector2(1, -1)]]:
			var badge := tile.get_node_or_null(stat[0]) as TextureRect
			var number := badge.get_child(0) as Label if badge != null else null
			var badge_rect := badge.get_global_rect() if badge != null else Rect2()
			var quadrant := (badge_rect.get_center() - rect.get_center()).sign()
			expect(number != null and number.text == str(stat[1]) and badge.texture != null
				and rect.grow(-1).encloses(badge_rect) and quadrant == stat[2],
				"%s shows the correct %s badge fully inside its corner" % [unit.name, stat[0]])
	var left := view.cells[10]
	var right := view.cells[11]
	var health := left.get_node("Health") as TextureRect
	await click(left, (health.get_global_rect().get_center() - left.global_position) / left.size)
	expect(view.selected_square == 10, "Clicking the health badge selects its unit")
	var armor := right.get_node("Armor") as TextureRect
	await click(right, (armor.get_global_rect().get_center() - right.global_position) / right.size)
	expect(view.selected_square == 11, "Clicking the adjacent armor badge selects the neighboring unit")
	battle.board[11].hp -= 1
	battle.board[11].armor = 0
	view.render()
	expect(right.get_node("Health").get_child(0).text == str(battle.board[11].hp)
		and right.get_node("Armor").get_child(0).text == "0", "Re-rendering shows the latest health and armor")
	battle.hands[Chess.PLAYER] = ["rain"]
	view.render()
	await click(view.hand_buttons[0])
	expect(view.cast_button.visible and view.cast_button.tooltip_text == "打出唤雨", "Selecting a weather card offers confirmation in the right column")
	await click(view.cast_button)
	expect(battle.weather == "rain" and not view.cast_button.visible, "Confirming plays the weather card")
	expect(battle.can_move_piece() and not view.end_turn_button.disabled, "Playing a card leaves the board action and End Turn available")
	await click(view.end_turn_button)
	expect(battle.turn == Chess.ENEMY and view.end_turn_button.disabled, "The player can end even with legal moves")
	var traveler_icon := view.cells[10].find_child("ElementIcon", true, false) as TextureRect
	expect(traveler_icon != null and traveler_icon.texture.resource_path.ends_with("/ice.svg")
		and view.cells[1].find_child("ElementIcon", true, false) == null,
		"The real traveler shows the ice badge and the untyped boar has no badge")
	var elements := ["earth", "fire", "water", "ice", "wind", "lightning"]
	expect(Cards.ELEMENTS.keys() == elements, "The chess catalog defines only the six elements")
	for square in elements.size():
		var piece: Dictionary = battle._piece(battle.definition("foe:boar"), Chess.ENEMY)
		piece.element = elements[square]
		battle.board[square] = piece
	view.render()
	await process_frame
	for square in elements.size():
		var tile := view.cells[square]
		var icon := tile.find_child("ElementIcon", true, false) as TextureRect
		var attribute_name: String = Cards.ELEMENTS[elements[square]]
		expect(icon != null and icon.texture != null and icon.texture.resource_path.ends_with("/%s.svg" % elements[square])
			and tile.get_global_rect().encloses(icon.get_global_rect()) and attribute_name in tile.accessibility_name
			and not tile.find_children("*", "Label", true, false).any(func(label): return label.text == attribute_name),
			"Each attribute has its own visible icon and accessible name: " + attribute_name)
	view.queue_free()
	await process_frame

func _detail_text(view: Node) -> String:
	var parts: Array[String] = []
	if view.hover_detail_body != null:
		for node in view.hover_detail_body.find_children("*", "Label", true, false):
			parts.append(node.text)
	return "\n".join(parts)

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await process_frame
	await process_frame

func check_hover_details() -> void:
	var game := Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-hover-details.json"
	game._start_new()
	await process_frame
	var cell: String = game.run.actor("hero").position
	game.run.data.tiles[cell].enemies = ["boar"]
	game._open_current_encounter(false)
	await process_frame
	await click(game.modal_layer.find_child("ConfirmCardDeck", true, false))
	var view = game.ui.find_child("ChessBattle", true, false)
	expect(view != null, "Hover fixture reaches the chess board")
	if view == null:
		game.queue_free()
		await process_frame
		return
	view._hover_tile(10)
	await process_frame
	await process_frame
	var text := _detail_text(view)
	expect(view.hover_detail.visible and view.hover_detail.size.y > 90, "Hovering the commander opens a sized detail popup")
	var icon := view.hover_detail_body.find_child("ElementIcon", true, false) as TextureRect
	expect(icon != null and icon.texture.resource_path.ends_with("/ice.svg") and not "冰属性" in text,
		"The traveler detail shows only the ice icon")
	expect("移动 · " in text and "攻击 · " in text, "Commander popup lists movement and attack")
	expect(root.get_visible_rect().encloses(view.hover_detail.get_global_rect()), "The popup stays inside the viewport")
	game.combat.revealed_enemy = ["rain"]
	view._hover_tile(1)
	await process_frame
	await process_frame
	text = _detail_text(view)
	expect("敌方主战者" in text and "已知敌方手牌" in text and "唤雨" in text,
		"Enemy commander popup shows its side and known enemy cards")
	view._unhover_tile(1)
	view._hover_tile(7)
	await process_frame
	expect(not view.hover_detail.visible, "Leaving a piece or hovering an empty square closes the popup")
	game.combat.hands[Chess.PLAYER] = ["pike"]
	view.render()
	await process_frame
	view._hover_card(0)
	await process_frame
	await process_frame
	text = _detail_text(view)
	expect(view.hover_detail.visible and "技能说明" in text and "护沿短戟" in text, "Hand card popup shows the card's skill text")
	expect("攻击 + 1" in text and "直线射程 2 格" in text, "Hand weapon popup summarizes its stats")
	expect("费用 2 · 法力不足" in text, "Unaffordable cards can still be inspected")
	game.combat.mana_capacity[Chess.PLAYER] = 2
	game.combat.mana[Chess.PLAYER] = 2
	expect(game.combat.play(0, 10), "Pike equips the commander for the equipment check")
	view.render()
	await process_frame
	view._hover_tile(10)
	await process_frame
	await process_frame
	text = _detail_text(view)
	expect("当前装备" in text and "护沿短戟" in text, "Equipped popup lists the carried weapon")
	var tile := view.cells[10] as Button
	var rack := tile.get_node("PieceFace/EquipmentSlots")
	var occupied := rack.get_node("weapon") as Control
	var empty := rack.get_node("armor") as Control
	await move_mouse(occupied.get_global_rect().get_center())
	text = _detail_text(view)
	expect("武器 · 已装备" in text and "护沿短戟" in text and "攻击 +1" in text and "移动与攻击" not in text,
		"Moving over the weapon slot shows only that equipment and its effects")
	await move_mouse(empty.get_global_rect().get_center())
	text = _detail_text(view)
	expect("护甲" in text and "空槽" in text and "护沿短戟" not in text, "Moving across slots switches to the empty armor tooltip")
	var identity := tile.get_node("PieceFace/Identity") as Control
	await move_mouse(identity.get_global_rect().get_center())
	expect("移动与攻击" in _detail_text(view), "Moving back to the portrait restores the unit tooltip")

	game.combat.hands[Chess.PLAYER] = ["blade"]
	game.combat.mana[Chess.PLAYER] = 1
	view.render()
	await click(view.hand_buttons[0])
	occupied = tile.get_node("PieceFace/EquipmentSlots/weapon") as Control
	var point := occupied.get_global_rect().get_center()
	await move_mouse(point)
	expect("点击替换" in _detail_text(view), "An occupied target explains where its old card goes")
	var attack := int(tile.get_node("Attack").get_child(0).text)
	await click(tile, (point - tile.global_position) / tile.size)
	expect(view.hand_ids == ["pike"] and tile.get_node("Attack").get_child(0).text == str(attack + 1),
		"Clicking through a slot replaces the weapon, puts the old card in the hand, and updates the attack badge")
	expect("巡路短刃" in _detail_text(view) and "护沿短戟" not in _detail_text(view),
		"A pointer held over the swapped slot sees the new weapon immediately")
	await move_mouse(view.cells[7].get_global_rect().get_center())
	expect(not view.hover_detail.visible, "Leaving the piece closes its equipment tooltip")
	game.combat.turn = Chess.PLAYER
	game.combat.run.data.actors["eve"] = {"breakthrough": 3}
	game.combat.hands[Chess.PLAYER] = ["eve"]
	view.render()
	await process_frame
	view._hover_card(0)
	await process_frame
	await process_frame
	text = _detail_text(view)
	expect("角色天赋" in text and "援护" in text, "Breakthrough talent appears in the hand card popup")
	expect("移动 · " in text, "Partner card popup lists its movement")
	view._unhover_card(0)
	expect(not view.hover_detail.visible, "Leaving the hand card closes the popup")
	game.queue_free()
	await process_frame

func execute() -> void:
	check_mana()
	check_enemy_turn_budget()
	check_rules()
	check_equipment_replacement()
	check_retaliation()
	check_fatigue()
	check_enemy_strategy()
	check_companion_growth()
	check_battle_income()
	await check_attack_feedback()
	await check_ui()
	await check_hand_layout()
	await check_mana_display()
	await check_deck_draw()
	await check_board_badges()
	await check_hover_details()
	print("CHESS BATTLE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
