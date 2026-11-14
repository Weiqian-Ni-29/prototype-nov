extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/domain/expedition.gd")
const Chess = preload("res://scripts/domain/chess_battle.gd")
const Cards = preload("res://scripts/domain/card_catalog.gd")
const Gear = preload("res://scripts/domain/gear_catalog.gd")
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

func fixture(enemy: String = "boar") -> RefCounted:
	var run := Run.new()
	run.save_path = "user://test-card-chess-domain.json"
	run.new_run(41, "wayfarer")
	var cell: String = run.actor("hero").position
	run.data.tiles[cell].enemies = [enemy]
	var battle := Chess.new()
	expect(battle.begin(run, {"position": cell, "origin": cell, "npc": "", "ambush": false}, run.card_deck()).ok, "Battle fixture starts")
	return battle

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
	var wayfarer_gear := Gear.card({"definition_id": "grave_wayfarer_weapon", "enhance_level": 0, "quality": Gear.QUALITIES[0]})
	var armor_before: int = battle.board[10].armor
	battle._apply_card(Chess.PLAYER, "gear:wayfarer", wayfarer_gear, 10)
	expect(wayfarer_gear.element == "ice" and battle.board[10].armor == armor_before + 1,
		"Wayfarer gear preserves its affinity guard on the ice commander")
	battle.turn = Chess.PLAYER
	battle.hands[Chess.PLAYER] = ["rain"]
	expect(battle.play(0, -1) and battle.weather == "rain" and battle.attack_power(battle.board[7]) == 3,
		"Weather modifies elemental attacks and costs the same one action")
	battle.turn = Chess.PLAYER
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
	var equipment: String = game.run.card_deck().filter(func(id): return id.begins_with("gear:"))[0]
	await click(editor.find_child("Remove_" + equipment.replace(":", "_"), true, false))
	editor.search.text = "唤雨"
	editor.search.text_changed.emit(editor.search.text)
	await process_frame
	await click(editor.find_child("Collection_rain", true, false))
	await click(editor.find_child("AddDeckCard", true, false))
	await click(editor.find_child("ConfirmCardDeck", true, false))
	var saved := Run.new()
	expect(saved.load_game(game.run.save_path).ok and saved.card_deck().count("rain") == 1, "Edited deck persists in the expedition save")
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
		var grid := view.find_child("ChessGrid", true, false) as GridContainer
		expect(grid != null and grid.columns == Chess.COLS and grid.get_child_count() == view.cells.size(),
			"The chess grid contains only the twelve squares")
		var grid_rect := grid.get_global_rect()
		var view_rect: Rect2 = view.get_global_rect()
		expect(is_equal_approx(grid_rect.position.x - view_rect.position.x, 24.0)
			and is_equal_approx(view_rect.end.x - grid_rect.end.x, 24.0),
			"The board fills the width between the panel margins")
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
		expect(game.combat.turn == Chess.ENEMY and view.cells[7].disabled, "Actual mouse move locks out extra actions")
		game.combat.piles[Chess.PLAYER][0] = "ward"
		game.battle_timer = 0.0
		await process_frame
		await process_frame
		expect(game.combat.turn == Chess.ENEMY and game.combat.enemy_action_resolved
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
		await click(menu)
		await click(button_named(game.modal_layer, "确认"))
		game._continue_run()
		expect(game.modal_layer.find_child("CardDeckEditor", true, false) != null and not game.run.data.pending_battle.is_empty(),
			"Continuing resumes the saved encounter before the board")
	game.queue_free()
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
	expect(view.cast_button.visible and view.cast_button.text == "打出唤雨", "Selecting a weather card offers confirmation above the board")
	await click(view.cast_button)
	expect(battle.weather == "rain" and not view.cast_button.visible, "Confirming plays the weather card")
	battle.turn = Chess.PLAYER
	battle.board[10].move = 0
	battle.board[10].diagonal = false
	battle.board[10].range = 0
	battle.board[11].move = 0
	battle.board[11].diagonal = false
	battle.board[11].range = 0
	view.render()
	expect(view.wait_button.visible, "A blocked player can pass from above the board")
	await click(view.wait_button)
	expect(battle.turn == Chess.ENEMY and not view.wait_button.visible, "Passing hands the turn to the enemy")
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
	expect(game.combat.play(0, 10), "Pike equips the commander for the equipment check")
	view.render()
	await process_frame
	view._hover_tile(10)
	await process_frame
	await process_frame
	text = _detail_text(view)
	expect("当前装备" in text and "护沿短戟" in text, "Equipped popup lists the carried weapon")
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
	check_rules()
	check_fatigue()
	check_enemy_strategy()
	check_companion_growth()
	check_battle_income()
	await check_ui()
	await check_board_badges()
	await check_hover_details()
	print("CHESS BATTLE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
