extends SceneTree
## Wall-clock native frame sample; run without movie mode or --headless.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")

func _initialize() -> void: call_deferred("execute")
func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://sample-performance.json"
	game._start_new()
	game.run.actor("hero").skill = "guard_all"
	game.set_process(false)
	var run = game.run
	var p = run.actor("hero").position
	for id in ["cen","eve","grit"]:
		run.actor(id).position = p
		run.join_companion(id)
	run.data.tiles[p].terrain = "forest"
	run.data.tiles[p].enemies = ["archer","furnace","spider","boar"]
	var b = Combat.new()
	b.begin(run,{"position":p,"origin":p,"ambush":false,"movers":[],"npc":""},["hero","cen","eve","grit"])
	game.combat = b
	game.view.begin_battle(run,b)
	game._refresh()
	await create_timer(2.0).timeout
	var times: Array[float] = []
	var previous = Time.get_ticks_usec()
	for i in range(240):
		await process_frame
		var now = Time.get_ticks_usec()
		times.append(float(now-previous)/1000.0)
		previous = now
		if i%40==0:
			for doll in game.view.battle_dolls.values(): doll.play_action("cast")
	times.sort()
	var total = 0.0
	for value in times: total += value
	var result = {"variant":"four-samples","frames":times.size(),"average_fps":1000.0/(total/times.size()),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*0.95)],"worst_ms":times[-1],"renderer":"OpenGL Compatibility","window":str(root.size),"movie":false}
	var file = FileAccess.open("user://animation-sample-performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("SAMPLE PERFORMANCE ",JSON.stringify(result))
	game.queue_free()
	await create_timer(0.1).timeout
	quit()
