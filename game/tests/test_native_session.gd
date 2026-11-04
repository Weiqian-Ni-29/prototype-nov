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
	game.chosen_profession = "guardian"
	game.run.save_path = "user://native-session.json"
	game._start_new()
	var r = game.run
	var p = r.actor("hero").position
	for id in ["cen","eve","grit"]:
		r.actor(id).position = p
		r.join_companion(id)
	r.data.tiles[p].enemies = ["boar","archer"]
	var b = Combat.new()
	expect(b.begin(r,{"position":p,"origin":p,"npc":"","movers":[],"ambush":false},["hero","cen","eve","grit"]).ok,"Native session begins with real combat values")
	game.combat = b
	game.view.begin_battle(r,b)
	game._refresh()
	b.auto_mode = true
	var started = Time.get_ticks_msec()
	var observed_animation = false
	while game.combat!=null and Time.get_ticks_msec()-started<80000:
		await process_frame
		observed_animation = observed_animation or game.view.is_animating()
	expect(game.combat==null and b.outcome=="victory","Main loop drains visuals and actually returns to map after auto victory")
	expect(observed_animation and not game.view.battle_mode,"Native auto session rendered the sequential visual queue")
	expect(r.data.tiles[p].enemies.is_empty() and not r.data.rewards.is_empty(),"Victory settles once with actual rewards")
	game.set_process(false)
	# A normal NPC conflict uses the same injury state, not a cosmetic non-lethal shortcut.
	r.actor("ember").position = p
	r.data.tiles[p].npc = "ember"
	game.narrative.dialogue("hero","ember")
	r.actor("ember").hp = 0
	game._refresh()
	await create_timer(1.5).timeout
	expect(game.view.dolls.ember.rigged.holding_down,"Down NPC stays visibly injured")
	var salves = r.actor("hero").inventory.get("salve",0)
	expect(salves>0 and r.use_item("hero","ember","salve").ok,"Same-cell actual item rescues the NPC")
	game._refresh()
	await create_timer(1.5).timeout
	expect(r.actor("ember").hp>0 and not game.view.dolls.ember.rigged.holding_down,"Rescue state makes the same NPC stand up")
	expect(r.save_game().ok,"Updated run saves")
	var hp = r.actor("ember").hp
	expect(r.load_game().ok and r.actor("ember").hp==hp,"Continue preserves actual rescue state")
	game.view.reset()
	game._refresh()
	await process_frame
	expect(not game.view.dolls.ember.down,"Recreated exploration actor reflects loaded HP")
	print("NATIVE SESSION: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await create_timer(1.0).timeout
	quit(0 if failures==0 else 1)
