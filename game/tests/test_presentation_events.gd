extends SceneTree
## Explicit native fixtures use real domain skills; replay must leave all settled data unchanged.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
var game: Node
var checks = 0
var failures = 0
var observed_cues: Array = []
var captured = false
var capture_name = ""

func _initialize() -> void: call_deferred("execute")
func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",text)

func fixture(profession: String, members: Array) -> RefCounted:
	game.chosen_profession = profession
	game._start_new()
	game.set_process(false)
	var r = game.run
	var p = r.actor("hero").position
	for id in Catalog.COMPANIONS:
		r.actor(id).position = p
		r.join_companion(id)
	r.data.tiles[p].terrain = "forest"
	r.data.tiles[p].enemies = ["boar","furnace","archer","swarm"]
	r.data.tiles[p].site = ""
	var b = Combat.new()
	expect(b.begin(r,{"position":p,"origin":p,"ambush":false,"movers":[],"npc":""},members).ok,"Native fixture starts")
	for enemy in b.enemies.values():
		enemy.hp = 5000
		enemy.hp_max = 5000
	game.combat = b
	game.view.begin_battle(r,b)
	game._refresh()
	return b

func replay(events: Array, name: String, positive: bool = false) -> void:
	var state = JSON.stringify(game.run.data)
	var enemy_state = JSON.stringify(game.combat.enemies)
	var nodes = {}
	for id in game.view.battle_dolls: nodes[id] = game.view.battle_dolls[id].get_instance_id()
	var count = game.view.presenter.event_order.size()
	game.view.animate_events(events)
	game.view.animate_events(events) # stable IDs must not replay the same settlement twice
	game._refresh()
	var started = Time.get_ticks_msec()
	var captured_event = false
	while game.view.is_animating() and Time.get_ticks_msec()-started<12000:
		await process_frame
		if not captured_event and not game.view.display_results.is_empty():
			captured_event = true
			if positive:
				for result in events[0].get("results",[]):
					var target = game.view.battle_dolls[result.target]
					expect(target.rigged.action!="hit","Healing/protection never makes target flinch "+name)
	expect(not game.view.is_animating(),"Queue drains "+name)
	expect(JSON.stringify(game.run.data)==state and JSON.stringify(game.combat.enemies)==enemy_state,"Replay changes no settled friendly or enemy state "+name)
	expect(game.view.presenter.event_order.size()==count+events.size(),"Events play once in FIFO order "+name)
	for id in nodes: expect(game.view.battle_dolls[id].get_instance_id()==nodes[id],"Environment preserves actor instance "+id)
	await create_timer(0.16).timeout
	expect(is_zero_approx(game.view.camera.v_offset),"Impact camera returns to original framing")
	game.view.display_results.clear()

func feedback() -> void:
	if capture_name=="" or captured: return
	captured = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://ultimate-"+capture_name+".png")

func execute() -> void:
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://presentation-events.json"
	game.view.sound_cue.connect(func(kind: String): observed_cues.append(kind))
	game.view.presenter.feedback_changed.connect(feedback)
	for specification in [["guardian",["hero","cen","eve","grit"]],["wayfarer",["hero","lorne","ember","tide"]],["arcanist",["hero","eve","ember","tide"]]]:
		var b = fixture(specification[0],specification[1])
		for id in specification[1]:
			var a = b.unit(id)
			a.mp = a.mp_max
			for ally in b.active:
				b.unit(ally).hp = maxi(1,int(b.unit(ally).hp_max)-40)
				b.unit(ally).shield = 0
			b.current = id
			var skill = Catalog.SKILLS[a.skill]
			var target = "enemy_0" if skill.target=="enemy" else id
			expect(b.act(a.skill,target).ok,"Actual ordinary skill "+a.skill)
			var events = b.events.duplicate(true)
			b.events.clear()
			expect(events[0].skill_id==a.skill and events[0].has("results"),"Explicit skill ID and settled results")
			await replay(events,a.skill,skill.get("healing",false) or skill.has("shield"))
			a.energy = 100
			b.current = id
			var next_normal = b.next_time[id]
			expect(b.request_ultimate(id,"enemy_0").ok,"Actual ultimate request "+a.ultimate)
			b.resolve_queued()
			expect(a.energy==0 and b.next_time[id]==next_normal,"Ultimate remains an extra action")
			events = b.events.duplicate(true)
			b.events.clear()
			capture_name = a.ultimate
			captured = false
			var ultimate = Catalog.SKILLS[a.ultimate]
			await replay(events,a.ultimate,ultimate.get("healing",false) or ultimate.has("shield"))
			expect(captured,"Native impact frame captured "+a.ultimate)
			capture_name = ""
		game.view.end_battle()
	# Cancellation must remove effects and restore camera before another scene.
	var b = fixture("guardian",["hero","cen","eve","grit"])
	b.current = "hero"
	b.act("attack","enemy_0")
	game.view.animate_events(b.events)
	await create_timer(0.15).timeout
	game.view.end_battle()
	await create_timer(0.6).timeout
	expect(not game.view.is_animating() and game.view.effects.get_child_count()==0,"Early exit cancels queue and cleans all effects")
	expect(is_zero_approx(game.view.camera.v_offset),"Early exit resets camera")
	expect("bow" in observed_cues and "heal" in observed_cues and "water" in observed_cues and "howl" in observed_cues and "fire" in observed_cues,"Distinct original audio cues are emitted")
	print("PRESENTATION EVENTS: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await create_timer(1.0).timeout
	quit(0 if failures==0 else 1)
