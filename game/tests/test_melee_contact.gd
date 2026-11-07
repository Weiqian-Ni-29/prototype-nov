extends SceneTree
## Real rendered attack events: approach, blade contact, feedback, return. Explicit battle fixture.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
var checks = 0
var failures = 0
var game: Node

func _initialize() -> void: call_deferred("execute")
func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",text)

func replay(capture: bool = false) -> void:
	var state = JSON.stringify(game.run.data)
	var contact_count = game.view.presenter.contact_records.size()
	game._after_combat_step()
	var started = Time.get_ticks_msec()
	var saved = false
	while game.view.is_animating() and Time.get_ticks_msec()-started<10000:
		await process_frame
		if capture and not saved and game.view.presenter.contact_records.size()>contact_count:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://melee-contact.png")
			saved = true
	expect(not game.view.is_animating(),"Presentation queue drains")
	expect(JSON.stringify(game.run.data)==state,"Visual replay never changes any domain state")

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.chosen_profession = "guardian"
	game.run.save_path = "user://test-melee-contact.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var p = run.actor("hero").position
	run.data.tiles[p].enemies = ["boar","boar"]
	var battle = Combat.new()
	expect(battle.begin(run,{"position":p,"origin":p,"movers":[],"npc":"","ambush":false},["hero"]).ok,"Melee fixture starts")
	game.combat = battle
	game.battle_timer = 0
	game.view.begin_battle(run,battle)
	game._refresh()
	var source = game.view.battle_dolls.hero
	var home = source.position
	var world_position = run.actor("hero").position
	for target in ["enemy_0","enemy_1"]:
		while battle.current!="hero" and battle.outcome=="":
			battle.step_auto()
			await replay()
		expect(battle.act("attack",target).ok,"Legal sword attack " + target)
		await replay(true)
		var record = game.view.presenter.contact_records[-1]
		print("CONTACT ",record)
		expect(record.actor=="hero" and record.target==target,"Blade samples the actual selected target")
		expect(record.error<=0.25,"Blade reaches target hit surface: "+str(record.error))
		expect(record.home.distance_to(record.contact_body)>2.0,"Melee visibly approaches instead of swinging across the field")
		expect(source.position.is_equal_approx(home) and source.body.position.is_equal_approx(Vector3.ZERO),"Attacker returns to original formation slot")
		expect(run.actor("hero").position==world_position,"Presentation lunge never changes the hex position")
	game.combat = null
	game.view.end_battle()
	await create_timer(1.0).timeout
	game.queue_free()
	await create_timer(0.1).timeout
	print("MELEE CONTACT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
