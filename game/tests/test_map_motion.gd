extends SceneTree
## Real legal movement with queued presentation; fixture joins only for crowded-layout checks.
const Main = preload("res://scenes/main.tscn")
const Hex = preload("res://scripts/domain/hex_map.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
var checks = 0
var failures = 0
func _initialize() -> void: call_deferred("execute")
func expect(value: bool,text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",text)
func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://test-map-motion.json"
	game._start_new()
	game.set_process(false)
	var run = game.run
	var start = run.actor("hero").position
	var next = Hex.neighbors(start,run.data.tiles)[0]
	var doll = game.view.dolls.hero
	expect(run.move(["hero"],next).ok,"First legal movement")
	game._refresh()
	var waypoint = doll.movement_target
	var next2 = Hex.neighbors(next,run.data.tiles)[0]
	if next2==start: next2 = Hex.neighbors(next,run.data.tiles)[1]
	expect(run.move(["hero"],next2).ok,"Second legal movement while the first is animating")
	game._refresh()
	var destination = doll.movement_queue[-1]
	var state = JSON.stringify(run.data)
	var visited_waypoint = false
	var started = Time.get_ticks_msec()
	while doll.is_moving() and Time.get_ticks_msec()-started<5000:
		if doll.position.distance_to(waypoint)<0.15: visited_waypoint = true
		game._refresh()
		await process_frame
	expect(visited_waypoint,"Continuous clicks preserve the intermediate hex visually")
	expect(doll.position.distance_to(destination)<0.02 and not doll.is_moving(),"Movement queue reaches the real final position")
	expect(JSON.stringify(run.data)==state,"Animation and repeated interface refreshes do not charge resources again")
	for id in Catalog.COMPANIONS:
		run.actor(id).position = run.actor("hero").position
		run.join_companion(id)
	game._refresh()
	await create_timer(0.2).timeout
	var ids = run.joined_ids()
	for i in range(ids.size()):
		for j in range(i+1,ids.size()):
			expect(game.view.dolls[ids[i]].position.distance_to(game.view.dolls[ids[j]].position)>0.45,"Crowded cell separates actor bases")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://map-seven-actors.png")
	game.queue_free()
	await create_timer(0.1).timeout
	print("MAP MOTION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
