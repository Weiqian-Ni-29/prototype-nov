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
	var previous_log: String = chess.log_text.text
	await create_timer(0.65).timeout
	expect(b.enemy_action_resolved and b.turn == Chess.ENEMY and chess.log_text.text != previous_log,
		"The enemy action updates the battle log while input is locked")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://chess-enemy-turn.png")
	await create_timer(0.85).timeout
	expect(b.round_number == 2 and b.turn == Chess.PLAYER and b.hands[Chess.PLAYER].size() == 4,
		"Native move lets the opponent respond and draws the next card")
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://chess-round-two.png")
	# Stage the last attack after exercising the normal opening and turn loop.
	var enemy_square: int = b.board.find(b.commanders[Chess.ENEMY])
	b.board[enemy_square] = {}
	b.board[1] = b.commanders[Chess.ENEMY]
	b.board[4] = b.board[7]
	b.board[7] = {}
	b.commanders[Chess.ENEMY].hp = 1
	b.commanders[Chess.ENEMY].armor = 0
	chess.render()
	chess.cells[4].pressed.emit()
	chess.cells[1].pressed.emit()
	await create_timer(0.65).timeout
	expect(game.combat == null and b.outcome == "victory" and game.modal_layer.has_node("VictoryScreen"),
		"The last chess attack opens the victory screen")
	expect(r.data.tiles[p].enemies.is_empty() and not r.data.rewards.is_empty(),"Victory settles once with actual rewards")
	var checkpoint = JSON.parse_string(FileAccess.get_file_as_string(r.save_path))
	expect(checkpoint is Dictionary and checkpoint.get("pending_battle", {"missing": true}).is_empty()
		and checkpoint.get("tiles", {}).get(p, {}).get("enemies") == [] and checkpoint.get("rewards") == r.data.rewards
		and checkpoint.get("pending_victory", {}).get("salve_receiver") == "hero",
		"Battle settlement auto-saves the cleared encounter and the reward")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://battle-victory-result.png")
	game._continue_run()
	var victory_screen = game.modal_layer.get_node_or_null("VictoryScreen")
	expect(victory_screen != null, "Continuing after victory restores the pending settlement")
	if victory_screen != null:
		for button in victory_screen.find_children("*", "Button", true, false):
			if button.text == "继续远征":
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
	var salves = r.actor("hero").inventory.get("salve",0)
	expect(salves>0 and r.use_item("hero","ember","salve").ok,"Same-cell actual item rescues the NPC")
	game._refresh()
	await create_timer(1.5).timeout
	expect(r.actor("ember").hp > 0, "Rescue restores the NPC")
	expect(r.save_game().ok,"Updated run saves")
	var hp = r.actor("ember").hp
	expect(r.load_game().ok and r.actor("ember").hp==hp,"Continue preserves actual rescue state")
	game.view.reset()
	game._refresh()
	await process_frame
	expect(game.view.dolls.keys() == ["hero"], "Loading does not add extra map figures")
	r.data.lamp_coins = 52
	var stores: Array = r.data.nodes.keys().filter(func(cell): return "ember" in r.recruit_shop_offers(cell))
	expect(not stores.is_empty(), "A merchant stocks Ember in this session")
	if stores.is_empty():
		quit(1)
		return
	r.retreat_party(stores[0])
	r.data.tiles[stores[0]].enemies.clear()
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
		if button.text.begins_with("返回地图"):
			button.pressed.emit()
			break
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
