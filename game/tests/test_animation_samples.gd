extends SceneTree
## Native rendered-frame gate for the four required samples; no battle resource changes.
const Main = preload("res://scenes/main.tscn")
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("execute")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",label)

func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.run.save_path = "user://animation-samples.json"
	game.chosen_profession = "guardian"
	game._start_new()
	game.set_process(false)
	var position = game.run.actor("hero").position
	for id in ["cen","eve","grit"]:
		game.run.actor(id).position = position
		game.run.join_companion(id)
	game._refresh()
	await create_timer(0.2).timeout
	var original = JSON.stringify(game.run.data)
	for id in ["hero","cen","eve","grit"]:
		var doll = game.view.dolls[id]
		var rig = doll.rigged
		var original_position = doll.position
		expect(rig != null and rig.animator != null,"Sample uses a real AnimationPlayer " + id)
		expect(rig.skeleton.get_bone_count() >= 23,"Complete skeleton " + id)
		for clip in ["idle","walk","run","attack_melee","cast","support","guard","hit","down"]:
			expect(rig.animator.has_animation(clip),"Required mapped clip " + id + "/" + clip)
		rig.play_action("walk")
		await create_timer(0.16).timeout
		var bone = rig.skeleton.find_bone("front humerus.L" if id=="grit" else "LeftUpperLeg")
		var before = rig.skeleton.get_bone_pose_rotation(bone)
		await create_timer(0.22).timeout
		expect(not before.is_equal_approx(rig.skeleton.get_bone_pose_rotation(bone)),"Locomotion changes skeletal pose over actual frames " + id)
		rig.play_action("idle")
		rig.set_down(true)
		await create_timer(1.6).timeout
		expect(rig.down and rig.holding_down and not rig.animator.is_playing(),"Down pose stays down " + id)
		rig.set_down(false)
		await create_timer(1.6).timeout
		expect(not rig.down and rig.action=="idle","Explicit recovery returns to idle " + id)
		expect(doll.position.is_equal_approx(original_position),"Animation does not relocate map actor " + id)
	expect(JSON.stringify(game.run.data)==original,"Presentation sample does not change any domain state")
	print("ANIMATION SAMPLES: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await create_timer(0.1).timeout
	quit(0 if failures==0 else 1)
