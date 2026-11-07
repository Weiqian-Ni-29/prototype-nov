extends SceneTree
## Native wall-clock frames, no movie/headless. Deliberate full-map and maximal battle fixtures.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Hex = preload("res://scripts/domain/hex_map.gd")
var game: Node
var results: Array = []
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("execute")
func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",text)

func sample(name: String, battle: bool) -> void:
	await create_timer(1.0).timeout
	var frames: Array[float] = []
	var previous = Time.get_ticks_usec()
	for i in range(300):
		await process_frame
		var now = Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		previous = now
		if battle and i%30==0:
			for doll in game.view.battle_dolls.values(): doll.play_action("cast")
			var points: Array = []
			for id in game.combat.active: points.append(game.view.battle_dolls[id].position+Vector3.UP)
			game.view.effects.ultimate_start("tide_shelter",Vector3.ZERO,points)
			for point in points: game.view.effects.shield(point,Color("9bd9e1"))
	frames.sort()
	var total = 0.0
	var slow = 0
	for value in frames:
		total += value
		if value>33.34: slow += 1
	var result = {"scene":name,"window":str(root.size),"frames":frames.size(),"average_fps":1000.0/(total/frames.size()),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"worst_ms":frames[-1],"frames_over_33ms":slow,"renderer":"OpenGL Compatibility","gpu":RenderingServer.get_video_adapter_name(),"movie":false,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"cpu_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0}
	results.append(result)
	print("UPGRADE PERFORMANCE ",JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://upgrade-"+name+"-"+str(root.size.x)+".png")
	expect(root.get_texture().get_image().get_width()==root.size.x,"Actual requested resolution rendered")

func execute() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if "--throughput" in OS.get_cmdline_user_args(): Engine.max_fps = 0
	game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://benchmark-upgrade.json"
	for resolution in [Vector2i(1280,800),Vector2i(1440,900)]:
		root.size = resolution
		await process_frame
		game._start_new()
		game.set_process(false)
		var r = game.run
		for id in Catalog.COMPANIONS:
			r.actor(id).position = r.actor("hero").position
			r.join_companion(id)
		# Full map is an explicitly labelled rendering fixture, not normal fog behaviour.
		for id in r.data.tiles: r.data.explored[id] = true
		game.view.zoom_size = 30
		game.view.focus_cell("0,0")
		game._refresh()
		expect(r.data.tiles.size()==217 and not game.view.ocean.sea_cells.is_empty(),"217 land cells plus decorative ocean")
		for id in game.view.ocean.sea_cells:
			expect(not r.data.tiles.has(id) and Hex.closest(Hex.world(id),r.data.tiles)=="","Ocean cannot be walked or clicked as land")
		await sample("map-seven",false)
		var p = r.actor("hero").position
		r.data.tiles[p].terrain = "forest"
		r.data.tiles[p].burning = true
		r.data.weather = "rain" # combined render stress fixture, not a claim that rain ignites forest
		r.data.tiles[p].enemies = ["lamp_boss","furnace_elite","hunter_elite","swarm"]
		var b = Combat.new()
		expect(b.begin(r,{"position":p,"origin":p,"movers":[],"npc":"","ambush":false},["hero","grit","ember","tide"]).ok,"Maximal battle fixture begins")
		game.combat = b
		game.view.begin_battle(r,b)
		game._refresh()
		expect(game.view.battle_dolls.size()==8 and not game.view.ocean.visible,"Four allies plus four enemies, ocean absent from inland battle")
		await sample("battle-rain-fire",true)
		game.view.end_battle()
		game.combat = null
	var output = FileAccess.open("user://upgrade-performance.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(results,"  "))
	output.close()
	print("UPGRADE BENCHMARK: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await create_timer(1.0).timeout
	quit(0 if failures==0 else 1)
