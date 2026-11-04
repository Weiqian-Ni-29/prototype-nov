extends SceneTree
## Render all 20 definitions and verify actual skinned vertices, loops, down and recovery.
const Main = preload("res://scenes/main.tscn")
const Doll = preload("res://scripts/presentation/doll.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Run = preload("res://scripts/domain/expedition.gd")
var checks = 0
var failures = 0
var actors: Array = []
var samples: Array = []

func _initialize() -> void: call_deferred("execute")
func expect(value: bool,text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",text)

func skin_sample(doll: Node3D) -> Dictionary:
	var bone_name = "LeftLowerLeg" if doll.family=="humanoid" else "front metacarpals.L" if doll.definition.get("id","")=="grit" else "Lower0" if doll.family=="quadruped" else "Lower-1_0" if doll.family=="spider" else "Wing0_-1"
	var wanted = doll.skeleton.find_bone(bone_name)
	for mesh in doll.find_children("*","MeshInstance3D",true,false):
		if mesh.skin==null: continue
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays = mesh.mesh.surface_get_arrays(surface)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var joints = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if joints==null or weights==null: continue
			for vertex in range(vertices.size()):
				for j in range(4):
					var bind = int(joints[vertex*4+j])
					var name = mesh.skin.get_bind_name(bind)
					var bone = doll.skeleton.find_bone(name) if name!="" else mesh.skin.get_bind_bone(bind)
					if bone==wanted and weights[vertex*4+j]>0.2:
						return {"mesh":mesh,"vertex":vertices[vertex],"joints":joints.slice(vertex*4,vertex*4+4),"weights":weights.slice(vertex*4,vertex*4+4),"skeleton":doll.skeleton}
	return {}

func skin_point(sample: Dictionary) -> Vector3:
	var result = Vector3.ZERO
	var skin = sample.mesh.skin
	for j in range(4):
		var bind = int(sample.joints[j])
		var name = skin.get_bind_name(bind)
		var bone = sample.skeleton.find_bone(name) if name!="" else skin.get_bind_bone(bind)
		if bone>=0:
			result += (sample.skeleton.get_bone_global_pose(bone)*skin.get_bind_pose(bind)*sample.vertex)*sample.weights[j]
	return sample.skeleton.global_transform*result

func snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://actors-"+name+".png")

func execute() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.ui.visible = false
	game.view.map_root.visible = false
	game.view.actor_root.visible = false
	game.view.selection_ring.visible = false
	var definitions: Array = []
	for profession in Catalog.PROFESSIONS:
		var run = Run.new()
		run.new_run(20261104,profession)
		var definition = run.actor("hero").duplicate(true)
		definition.name = Catalog.PROFESSIONS[profession].name
		definitions.append(definition)
	for id in Catalog.COMPANIONS:
		var definition = Catalog.COMPANIONS[id].duplicate(true)
		definition.id = id
		definitions.append(definition)
	for id in Catalog.ENEMIES:
		var definition = Catalog.ENEMIES[id].duplicate(true)
		definition.id = id
		definition.type = id
		definitions.append(definition)
	var gallery = Node3D.new()
	game.view.add_child(gallery)
	for index in range(definitions.size()):
		var doll = Doll.new()
		gallery.add_child(doll)
		doll.configure(definitions[index])
		doll.position = Vector3((index%5)*3.0,0,(index/5)*3.0)
		actors.append(doll)
		var label = Label3D.new()
		label.font = preload("res://assets/fonts/NotoSansSC.ttf")
		label.text = definitions[index].name
		label.font_size = 36
		label.pixel_size = 0.007
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		gallery.add_child(label)
		label.position = doll.position+Vector3(0,0.1,1.25)
	game.view.camera.position = Vector3(14,19,24)
	game.view.camera.look_at(Vector3(6,0.8,4.5))
	game.view.camera.size = 17.5
	game.view.camera.h_offset = 0
	await create_timer(0.3).timeout
	await snapshot("idle")
	for doll in actors:
		var rig = doll.rigged
		var expected = ["Root","Head","LeftLowerLeg","RightLowerArm"] if doll.family=="humanoid" else ["Root","Bee0","Bee1","Bee2","Wing0_-1","Wing2_1"] if doll.family=="swarm" else ["Root","Head","Upper-1_0","Lower1_3"] if doll.family=="spider" else ["Root","Head","front humerus.L","femur.R"] if doll.definition.get("id","")=="grit" else ["Root","Head","Upper0","Lower3"]
		var mapped = true
		for bone in expected: mapped = mapped and rig.skeleton.find_bone(bone)>=0
		expect(rig.animator!=null and mapped,"Complete family-specific rig "+doll.definition.name)
		var sample = skin_sample(doll)
		expect(not sample.is_empty(),"Moving limb has a real skin binding "+doll.definition.name)
		samples.append(sample)
		doll.play_action("walk")
	await create_timer(0.12).timeout
	var before: Array = []
	for sample in samples: before.append(skin_point(sample) if not sample.is_empty() else Vector3.ZERO)
	await create_timer(0.25).timeout
	for i in range(actors.size()):
		if samples[i].is_empty(): continue
		expect(skin_point(samples[i]).distance_to(before[i])>0.001,"Weighted mesh vertex moves over real rendered frames "+actors[i].definition.name)
	for action in ["attack","cast","heal","guard","hit","ultimate"]:
		for doll in actors: doll.play_action(action)
		await create_timer(0.25).timeout
	for i in range(actors.size()):
		var rig = actors[i].rigged
		if samples[i].is_empty(): continue
		rig.animator.play("walk",0)
		rig.animator.seek(0,true)
		var first = skin_point(samples[i])
		rig.animator.seek(rig.animator.get_animation("walk").length-0.001,true)
		expect(first.distance_to(skin_point(samples[i]))<0.04,"Walk loop seam is continuous "+actors[i].definition.name)
		actors[i].play_action("idle")
		actors[i].set_down(true)
	await create_timer(1.7).timeout
	await snapshot("down")
	for doll in actors:
		expect(doll.rigged.holding_down and not doll.rigged.animator.is_playing(),"Down remains still "+doll.definition.name)
		doll.set_down(false)
	await create_timer(1.7).timeout
	for doll in actors: expect(doll.rigged.action=="idle","Recovered actor returns to idle "+doll.definition.name)
	var cold = Doll.new()
	gallery.add_child(cold)
	var definition = definitions[0].duplicate(true)
	definition.hp = 0
	cold.configure(definition)
	expect(cold.rigged.holding_down and not cold.rigged.animator.is_playing(),"Loading an injured actor directly restores the down pose")
	print("ACTOR ASSETS: %d checks, %d failures; %d definitions" % [checks,failures,actors.size()])
	game.queue_free()
	await create_timer(0.1).timeout
	quit(0 if failures==0 else 1)
