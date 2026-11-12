extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("execute")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func fixture() -> RefCounted:
	var run := Run.new()
	run.save_path = "user://test-card-chess-domain.json"
	run.new_run(41, "wayfarer")
	var cell: String = run.actor("hero").position
	run.data.tiles[cell].enemies = ["boar"]
	var battle := Chess.new()
	expect(battle.begin(run, {"position": cell, "origin": cell, "npc": "", "ambush": false}, run.card_deck()).ok, "Battle fixture starts")
	return battle

func check_rules() -> void:
	var battle = fixture()
	expect(battle.board.size() == 12 and battle.board.filter(func(piece): return not piece.is_empty()).size() == 2,
		"Three-by-four board begins with just the commanders")
	expect(battle.board[1].side == Chess.ENEMY and battle.board[10].side == Chess.PLAYER,
		"Both commanders start in their center rear squares")
	expect(battle.hands.all(func(hand): return hand.size() == 3) and battle.piles.all(func(pile): return pile.size() == 9),
		"Both teams draw exactly three opening cards")
	expect(battle.moves(10).keys() == [6, 7, 8, 9, 11], "Commander can move one square horizontally, vertically or diagonally")
	battle.hands[Chess.PLAYER] = ["highdrake"]
	expect(not battle.play(0, 4) and not battle.play(0, 10) and battle.can_act(), "Cannot deploy onto enemy ground or an occupied square")
	expect(battle.play(0, 7) and battle.board[7].hp == 8 and battle.turn == Chess.ENEMY,
		"Partner deployment consumes the turn and uses the relic's life bonus")
	expect(not battle.move(7, 4), "A second action during the enemy turn is rejected")
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
	battle.turn = Chess.PLAYER
	expect(battle.move(7, 4) and battle.board[7].is_empty() and battle.board[4].name == "铅翼",
		"Only the lethal attack captures the square")
	battle.turn = Chess.PLAYER
	battle.board[4].hp = 3
	battle.hands[Chess.PLAYER] = ["eve"]
	expect(battle.play(0, 7) and battle.board[4].hp == 6, "Ivy heals the adjacent wounded ally on deployment")
	battle.turn = Chess.PLAYER
	battle.hands[Chess.PLAYER] = ["ward"]
	expect(battle.play(0, 7) and battle.board[7].armor == 2 and battle.board[4].armor == 3 and battle.board[10].armor == 3,
		"Column defense applies to every friendly piece in the column")
	battle.turn = Chess.PLAYER
	battle.hands[Chess.PLAYER] = ["pike"]
	expect(battle.play(0, 10) and battle.attack_power(battle.board[10]) == 5, "Weapon raises the attack of the chosen piece")
	battle.turn = Chess.PLAYER
	battle.hands[Chess.PLAYER] = ["rain"]
	expect(battle.play(0, -1) and battle.weather == "rain" and battle.attack_power(battle.board[7]) == 3,
		"Weather modifies elemental attacks and costs the same one action")
	battle.turn = Chess.PLAYER
	battle.commanders[Chess.ENEMY].hp = 1
	battle.commanders[Chess.ENEMY].armor = 0
	var spot: String = battle.position
	var before: int = battle.run.actor("hero").inventory.salve
	expect(battle.move(4, 1) and battle.outcome == "victory" and battle.run.data.pending_battle.is_empty()
		and battle.run.data.tiles[spot].enemies.is_empty(), "Capturing the enemy commander settles the actual encounter")
	expect(battle.run.actor("hero").inventory.salve == before + 1 and battle.run.data.has("pending_victory"),
		"Victory awards loot and creates a saved receipt")
	battle._finish("victory")
	expect(battle.run.actor("hero").inventory.salve == before + 1, "Settlement cannot grant twice")

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
	battle.player_has_played = true
	battle.weather = "rain"
	battle.weather_rounds = 1
	battle.hands[Chess.ENEMY] = [card_id]
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
	battle.enemy_turn()
	expect(battle.turn == Chess.PLAYER and battle.weather.is_empty() and battle.hands[Chess.ENEMY].is_empty()
		and battle.board[4].get("side") == Chess.ENEMY and not battle.moves(7).has(1) and battle.board[6].hp == 1,
		"The real turn commits the single blocking play and preserves the other pieces")

	battle = ranged_threat_fixture("coat")
	battle.enemy_turn()
	expect(battle.commanders[Chess.ENEMY].armor == 3 and battle.board[6].hp == 1
		and battle.moves(7).has(1) and battle.attack_power(battle.board[7]) == 3,
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

func click(node: Button) -> void:
	expect(node != null and not node.disabled, "Visible enabled button")
	if node != null and not node.disabled:
		var point := node.get_global_rect().get_center()
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
	expect(editor != null and editor.grid.get_child_count() >= 11, "Map opens the full illustrated collection")
	if editor == null:
		game.queue_free()
		return
	editor.search.text = "治疗"
	editor.search.text_changed.emit(editor.search.text)
	expect(editor.grid.get_child_count() == 1 and editor.selected == "eve", "Search finds the healing card by effect")
	editor.search.clear()
	editor.search.text_changed.emit("")
	await click(editor.find_child("Remove_pike", true, false))
	await click(editor.find_child("Collection_rain", true, false))
	await click(editor.find_child("AddDeckCard", true, false))
	await click(editor.find_child("ConfirmCardDeck", true, false))
	var saved := Run.new()
	expect(saved.load_game(game.run.save_path).ok and saved.card_deck().count("rain") == 2, "Edited deck persists in the expedition save")
	var cell: String = game.run.actor("hero").position
	game.run.data.tiles[cell].enemies = ["boar"]
	game._open_current_encounter(false)
	await process_frame
	var start := game.modal_layer.find_child("ConfirmCardDeck", true, false) as Button
	await click(start)
	var view = game.ui.find_child("ChessBattle", true, false)
	expect(view != null and not game.view.visible and not game.view.battle_mode, "Normal encounter opens only the chess presentation")
	if view != null:
		expect(root.get_visible_rect().encloses(view.get_global_rect()) and view.cells.size() == 12 and view.hand_buttons.size() == 3,
			"Board fits the viewport with twelve squares and a three-card opening hand")
		await click(view.find_child("ChessSquare10", true, false))
		await click(view.find_child("ChessSquare7", true, false))
		expect(game.combat.turn == Chess.ENEMY and view.cells[7].disabled, "Actual mouse move locks out extra actions")
		game.battle_timer = 0.0
		await process_frame
		await process_frame
		expect(game.combat.round_number == 2 and view.hand_buttons.size() == 4, "Enemy responds once and the next card animates into the hand")
		await create_timer(0.5).timeout
		await click(view.hand_buttons[-1])
		expect(view.selected_card == 3 and (not view._legal().is_empty() or view.find_child("CastChessSpell", true, false) != null),
			"Clicking the drawn card raises it and offers legal targets or a spell confirmation")
		game._to_menu()
		await process_frame
		await click(button_named(game.modal_layer, "确认"))
		game._continue_run()
		expect(game.modal_layer.has_node("StoryScreen") and not game.run.data.pending_battle.is_empty(),
			"Continuing resumes the saved encounter before the board")
	game.queue_free()
	await process_frame

func execute() -> void:
	check_rules()
	check_fatigue()
	check_enemy_strategy()
	await check_ui()
	print("CHESS BATTLE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
