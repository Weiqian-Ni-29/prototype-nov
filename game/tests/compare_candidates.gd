extends SceneTree
## Optional licensed comparison, loaded from a supplied local archive extraction, never shipped.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/domain/battle.gd")
var source = ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
	call_deferred("execute")

func execute() -> void:
	if source=="":
		printerr("FAIL: Supply --source pointing to the reviewed KayKit 1.0 extraction")
		quit(1)
		return
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game._start_new()
	game.run.actor("hero").skill = "guard_all"
	game.set_process(false)
	var r = game.run
	var p = r.actor("hero").position
	for id in ["cen","eve","grit"]:
		r.actor(id).position = p
		r.join_companion(id)
	r.data.tiles[p].terrain = "forest"
	r.data.tiles[p].enemies = ["boar","archer","spider","swarm"]
	var b = Combat.new()
	b.begin(r,{"position":p,"origin":p,"movers":[],"npc":"","ambush":false},["hero","cen","eve","grit"])
	game.combat = b
	game.view.begin_battle(r,b)
	game._refresh()
	var animators: Array[AnimationPlayer] = []
	for pair in [["hero","Knight"],["cen","Rogue"],["eve","Mage"]]:
		var doc = GLTFDocument.new()
		var state = GLTFState.new()
		if doc.append_from_file(source.path_join(pair[1]+".glb"),state)!=OK:
			printerr("FAIL: Failed to load reviewed candidate ",pair[1]); quit(1); return
		var node = doc.generate_scene(state)
		var doll = game.view.battle_dolls[pair[0]]
		doll.rigged.visible = false
		doll.add_child(node)
		var animator = node.find_children("*","AnimationPlayer",true,false)[0]
		animators.append(animator)
		print("CANDIDATE ",pair[1]," clips=",animator.get_animation_list().size())
	for clip in ["Idle","Walking_A","1H_Melee_Attack_Slice_Diagonal","2H_Ranged_Shoot","Spellcast_Raise","Hit_A","Death_A","Lie_StandUp"]:
		for animator in animators: animator.play(clip)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://candidate-1.0-"+clip+".png")
		await create_timer(0.6).timeout
	print("CANDIDATE COMPARISON COMPLETE: three old human rigs, eight played clips, same battle camera/light")
	game.queue_free()
	await create_timer(0.2).timeout
	quit()
