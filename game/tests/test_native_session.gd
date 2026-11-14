extends SceneTree
## Rendered card editor, chess turns and settlement, then NPC injury/rescue.
const Main = preload("res://scenes/main.tscn")
const Chess = preload("res://scripts/domain/chess_battle.gd")
var game: Node
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("execute")
func expect(value: bool,text: String) -> void:
	checks += 1
	if not value: failures+=1; printerr("FAIL: ",text)

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://native-session.json"
	game._start_new()
	var r = game.run
	var p = r.actor("hero").position
	for id in ["cen","eve","grit"]:
		r.actor(id).position = p
		r.join_companion(id)
	game._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://expedition-sidebar.png")
	r.data.tiles[p].enemies = ["boar", "archer", "boar"]
	game._open_current_encounter(false)
	game._deck_dialog(true)
	var editor = game.modal_layer.find_child("CardDeckEditor", true, false)
	expect(editor != null, "Encounter opens the native illustrated deck editor")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://chess-deck-editor.png")
	editor.find_child("ConfirmCardDeck", true, false).pressed.emit()
	var b = game.combat
	var chess = game.chess_view
	expect(b != null and chess != null, "Native session starts through the deck editor")
	await process_frame
	await process_frame
	expect(chess.animating.size() == 3, "Opening hand uses the native draw tween")
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://chess-opening.png")
	chess.cells[10].pressed.emit()
	chess.cells[7].pressed.emit()
	expect(b.turn == Chess.PLAYER and not b.can_move_piece(), "Moving leaves the player in control with their board action spent")
	b.hands[Chess.ENEMY] = ["brace", "brace"]
	b.mana[Chess.ENEMY] = 2
	b.mana_capacity[Chess.ENEMY] = 2
	b.commanders[Chess.ENEMY].move = 0
	b.commanders[Chess.ENEMY].diagonal = false
	b.commanders[Chess.ENEMY].range = 0
	b.mana_capacity[Chess.PLAYER] = 10
	b.mana[Chess.PLAYER] = 10
	chess.end_turn_button.pressed.emit()
	var reveal_deadline := Time.get_ticks_msec() + 2000
	while chess.reveal_card == null and Time.get_ticks_msec() < reveal_deadline:
		await process_frame
	var first_reveal = chess.reveal_card
	expect(first_reveal != null and b.turn == Chess.ENEMY and chess.cells[7].disabled
		and b.played_cards.size() == 1 and chess.card_history.shown_count == 0,
		"The enemy reveals its first card before landing it, with player input locked")
	if first_reveal != null:
		var center: Vector2 = first_reveal.position
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://chess-enemy-card-reveal.png")
		await create_timer(1.12).timeout
		game.battle_timer = 0.0
		game._process(0.0)
		expect(chess.reveal_card == first_reveal and first_reveal.position.is_equal_approx(center)
			and b.played_cards.size() == 1, "The next enemy play waits while the first card holds in the center")
		reveal_deadline = Time.get_ticks_msec() + 950
		while chess.card_history.shown_count < 1 and Time.get_ticks_msec() < reveal_deadline:
			await process_frame
		expect(chess.card_history.shown_count == 1 and chess.card_history.home.has_node("CardFace")
			and chess.card_history.recent.text.contains("护甲 +3"), "The first card flies to its recorded result")
	reveal_deadline = Time.get_ticks_msec() + 4000
	while b.turn != Chess.PLAYER and Time.get_ticks_msec() < reveal_deadline:
		await process_frame
	expect(b.round_number == 2 and b.turn == Chess.PLAYER and b.hands[Chess.PLAYER].size() == 4
		and chess.card_history.shown_count == 2 and chess.reveal_card == null,
		"Both identical enemy plays make it into the record before the next turn")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://chess-enemy-turn.png")
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://chess-round-two.png")

	# Make the enemy's only legal action a ranged attack and verify the native turn timer.
	var enemy_square: int = b.board.find(b.commanders[Chess.ENEMY])
	b.board[enemy_square] = {}
	b.board[0] = b.commanders[Chess.ENEMY]
	b.board[0].move = 0
	b.board[0].range = 0
	b.board[0].diagonal = false
	b.board[1] = b._piece(b.definition("foe:archer"), Chess.ENEMY)
	b.board[1].move = 0
	b.board[4] = {}
	b.board[7].hp = 8
	b.board[7].armor = 1
	b.hands[Chess.ENEMY] = []
	b.piles[Chess.ENEMY] = ["mend_spell"]
	b.end_turn()
	game.battle_timer = 0.0
	await process_frame
	await process_frame
	var shot = chess.attack_effect
	expect(shot != null and shot.ranged and shot.attack.distance == 2 and b.board_action_used[Chess.ENEMY],
		"The normal turn loop presents the real enemy archer's two-square attack")
	if shot != null:
		while not shot.contacted and shot.elapsed < 0.19:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://chess-enemy-projectile.png")
		if not shot.contacted:
			await shot.impact
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://chess-enemy-impact.png")
		game.battle_timer = 0.0
		game._process(0.0)
		expect(b.turn == Chess.ENEMY and b.round_number == 2 and shot.losses.get_child_count() > 0,
			"The enemy hit and loss numbers play before the next round")
		await shot.finished
	await create_timer(0.35).timeout
	expect(b.turn == Chess.PLAYER and b.round_number == 3, "The next round resumes when the enemy attack completes")

	# Stage the last attack after exercising the normal opening and turn loop.
	enemy_square = b.board.find(b.commanders[Chess.ENEMY])
	b.board[enemy_square] = {}
	b.board[1] = b.commanders[Chess.ENEMY]
	b.board[4] = b.board[7]
	b.board[7] = {}
	b.commanders[Chess.ENEMY].hp = 1
	b.commanders[Chess.ENEMY].armor = 0
	chess.render()
	chess.cells[4].pressed.emit()
	chess.cells[1].pressed.emit()
	var strike = chess.attack_effect
	expect(strike != null and not strike.ranged and b.outcome == "victory",
		"The lethal player move starts a melee attack as the combat resolves")
	if strike != null:
		await strike.impact
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://chess-player-impact.png")
		game.battle_timer = 0.0
		game._process(0.0)
		var destination: Vector2 = strike._tile_rect(chess.cells[1]).get_center()
		expect(game.combat == b and game.modal_layer.get_child_count() == 0
			and strike.defender.modulate.a > 0.0
			and not (strike.attacker.position + strike.attacker.size / 2.0).is_equal_approx(destination),
			"The victory screen waits for the melee hit and the occupation animation")
		await strike.finished
		expect(strike.defender.modulate.a == 0.0
			and (strike.attacker.position + strike.attacker.size / 2.0).is_equal_approx(destination),
			"The defender fades before the attacker settles into the captured square")
	await create_timer(0.3).timeout
	expect(game.combat == null and b.outcome == "victory" and game.modal_layer.find_child("ShopView", true, false) != null,
		"The last chess attack opens the post-battle shop")
	expect(r.data.tiles[p].enemies.is_empty() and not r.data.rewards.is_empty(),"Victory settles once with actual rewards")
	var checkpoint = JSON.parse_string(FileAccess.get_file_as_string(r.save_path))
	expect(checkpoint is Dictionary and checkpoint.get("pending_battle", {"missing": true}).is_empty()
		and checkpoint.get("tiles", {}).get(p, {}).get("enemies") == [] and checkpoint.get("rewards") == r.data.rewards
		and checkpoint.get("pending_victory", {}).get("coins", 0) > 0,
		"Battle settlement auto-saves the cleared encounter and the reward")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://battle-victory-result.png")
	game._continue_run()
	var victory_screen = game.modal_layer.find_child("ShopView", true, false)
	expect(victory_screen != null, "Continuing after victory restores the post-battle shop")
	if victory_screen != null:
		for button in victory_screen.find_children("*", "Button", true, false):
			if button.text == "返回地图":
				button.pressed.emit()
				break
	expect(game.combat == null and not r.data.has("pending_victory") and r.data.rewards == checkpoint.get("rewards"),
		"Acknowledging the settlement returns to exploration without re-awarding loot")
	# Recruitment gifts and a victory drop can each have multiple story pages.
	var page_budget: int = maxi(2, r.data.relic_intros.size() * 8)
	for page in page_budget:
		if r.relic_intro().is_empty() or not game.modal_layer.has_node("StoryScreen"):
			break
		for pressed in [true, false]:
			var event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = root.get_visible_rect().size * Vector2(0.76, 0.30)
			root.push_input(event, true)
		await process_frame
	expect(r.relic_intro().is_empty(), "Any victory relic introduction can be completed after the results")
	game.set_process(false)
	# A normal NPC conflict uses the same injury state, not a cosmetic non-lethal shortcut.
	r.actor("ember").position = p
	r.data.tiles[p].npc = "ember"
	r.data.story.ember.met = true
	r.actor("ember").hp = 0
	game._refresh()
	await create_timer(1.5).timeout
	expect(game.view.dolls.keys() == ["hero"] and r.actor("ember").hp == 0, "Injured NPC stays in domain state without a map figure")
	expect(r.save_game().ok and r.load_game().ok and r.actor("ember").hp == 0,
		"Continuing preserves an injured NPC")
	r.actor("ember").hp = r.actor("ember").hp_max
	game.view.reset()
	game._refresh()
	await process_frame
	expect(game.view.dolls.keys() == ["hero"], "Loading does not add extra map figures")
	r.data.lamp_coins = 52
	var cell: String = r.actor("hero").position
	r.data.tiles[cell].enemies.clear()
	r.data.tiles[cell].npc = "ember"
	r.data.pending_victory = {"enemies": 1, "members": ["hero"], "revived": [], "relic": ""}
	r.open_battle_shop()
	r.data.battles = 2
	game._shop_dialog("", {"category": "companion", "id": "ember"})
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://companion-recruitment.png")
	var recruit = game.modal_layer.find_child("ConfirmTrade", true, false)
	expect(recruit != null and not recruit.disabled, "The merchant offers the recovered companion")
	recruit.pressed.emit()
	expect(r.actor("ember").joined and r.data.lamp_coins == 44 and game.modal_layer.has_node("StoryRewards"),
		"Recruitment charges the wallet and opens the gift receipt")
	for button in game.modal_layer.find_children("*", "Button", true, false):
		if button.text.begins_with("返回商店"):
			button.pressed.emit()
			break
	game._leave_battle_shop()
	game._show_character_codex()
	var codex = game.modal_layer.get_node("CharacterCodex")
	codex._select_character("ember")
	codex._set_tab(2)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://companion-breakthrough.png")
	for index in [1, 2, 3]:
		codex.find_child("ConfirmCompanionBreakthrough", true, false).pressed.emit()
	expect(r.actor("ember").breakthrough == 3 and r.data.lamp_coins == 0, "All three breakthroughs can be purchased in the native UI")
	print("NATIVE SESSION: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await create_timer(1.0).timeout
	quit(0 if failures==0 else 1)
