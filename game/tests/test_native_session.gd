extends SceneTree
## Rendered manual-to-auto session through Main._process, then a real victory and NPC injury/rescue.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
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
	r.data.tiles[p].enemies = ["boar", "archer", "boar"]
	var b = Combat.new()
	expect(b.begin(r,{"position":p,"origin":p,"npc":"","movers":[],"ambush":false},["hero","cen","eve","grit"]).ok,"Native session begins with real combat values")
	game.combat = b
	game.view.begin_battle(r,b)
	game._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://battle-enemy-cards.png")
	b.auto_mode = true
	var started = Time.get_ticks_msec()
	var observed_animation = false
	while game.combat!=null and Time.get_ticks_msec()-started<80000:
		await process_frame
		observed_animation = observed_animation or game.view.is_animating()
	expect(game.combat == null and b.outcome == "victory" and game.modal_layer.has_node("VictoryScreen"),
		"Auto victory drains visual events and opens the victory screen")
	expect(observed_animation and game.view.battle_mode and not game.view.is_animating(), "The completed battlefield remains behind the victory screen")
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
	expect(not game.view.battle_mode and not r.data.has("pending_victory") and r.data.rewards == checkpoint.get("rewards"),
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
	game.narrative.dialogue("hero","ember")
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
	print("NATIVE SESSION: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await create_timer(1.0).timeout
	quit(0 if failures==0 else 1)
